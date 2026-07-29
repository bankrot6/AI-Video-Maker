import { Client, Databases, Permission, Query, Role } from 'node-appwrite';

const ENDPOINT = (process.env.APPWRITE_ENDPOINT ?? '').trim();
const PROJECT_ID = (process.env.APPWRITE_PROJECT_ID ?? '').trim();
const API_KEY = (process.env.APPWRITE_API_KEY ?? '').trim();
const DATABASE_ID = (process.env.APPWRITE_DATABASE_ID ?? 'main').trim();
const PRESETS_COLL = (process.env.APPWRITE_PRESETS_COLLECTION_ID ?? 'presets').trim();
const GENERATIONS_COLL = (
  process.env.APPWRITE_GENERATIONS_COLLECTION_ID ?? 'user_generations'
).trim();
const PAGE_SIZE = Math.max(
  1,
  Math.min(100, parseInt(process.env.REPAIR_PRESET_PERMISSIONS_PAGE_SIZE ?? '50', 10) || 50),
);

function makeClient() {
  return new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
}

function parseBody(req) {
  try {
    return req.bodyJson ?? (typeof req.body === 'string' ? JSON.parse(req.body) : req.body) ?? {};
  } catch {
    return {};
  }
}

function readString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function getField(doc, key) {
  if (!doc || typeof doc !== 'object') return undefined;
  if (key in doc) return doc[key];
  if (doc.data && typeof doc.data === 'object' && key in doc.data) {
    return doc.data[key];
  }
  return undefined;
}

function expectedPermissions(userId) {
  return [
    Permission.read(Role.any()),
    Permission.update(Role.user(userId)),
    Permission.delete(Role.user(userId)),
  ];
}

function hasExpectedPermissions(doc, userId) {
  const permissions = Array.isArray(doc?.$permissions) ? doc.$permissions : [];
  if (permissions.length === 0) return false;
  const expected = new Set(expectedPermissions(userId));
  return Array.from(expected).every((permission) => permissions.includes(permission));
}

function extractPayloadDoc(body) {
  if (body && typeof body === 'object' && readString(body.$id)) {
    return body;
  }
  if (body && typeof body.payload === 'object' && readString(body.payload.$id)) {
    return body.payload;
  }
  return null;
}

async function resolveUserIdForPreset(databases, preset, log) {
  const presetId = readString(preset?.$id);
  const ownerId = readString(getField(preset, 'ownerId'));
  const existingUserId = readString(getField(preset, 'appwriteUserId'));
  if (existingUserId) return existingUserId;
  if (!ownerId) return '';

  const generationQueries = [];
  if (presetId) {
    generationQueries.push([
      Query.equal('presetId', presetId),
      Query.orderDesc('$createdAt'),
      Query.limit(20),
    ]);
  }
  generationQueries.push([
    Query.equal('deviceId', ownerId),
    Query.orderDesc('$createdAt'),
    Query.limit(100),
  ]);

  for (const queries of generationQueries) {
    try {
      const result = await databases.listDocuments(
        DATABASE_ID,
        GENERATIONS_COLL,
        queries,
      );
      for (const finalDoc of result.documents) {
        const userId = readString(getField(finalDoc, 'appwriteUserId'));
        if (userId) {
          log(`Resolved owner ${ownerId} -> ${userId} for preset ${presetId || '<unknown>'}`);
          return userId;
        }
      }
    } catch (err) {
      log(
        `resolveUserId failed for preset=${presetId || '<unknown>'} owner=${ownerId}: ${err.message}`,
      );
    }
  }

  return '';
}

async function repairPreset(databases, preset, log) {
  const presetId = readString(preset?.$id);
  if (!presetId) return { ok: false, reason: 'missing_preset_id' };

  let fullDoc = preset;
  if (!Array.isArray(fullDoc?.$permissions)) {
    try {
      fullDoc = await databases.getDocument(DATABASE_ID, PRESETS_COLL, presetId);
    } catch (err) {
      return { ok: false, reason: `get_failed:${err.message}` };
    }
  }

  const ownerId = readString(getField(fullDoc, 'ownerId'));
  if (!ownerId) return { ok: false, reason: 'missing_owner_id' };

  const userId = await resolveUserIdForPreset(databases, fullDoc, log);
  if (!userId) return { ok: false, reason: 'user_id_not_found' };

  const currentUserId = readString(getField(fullDoc, 'appwriteUserId'));
  if (currentUserId === userId && hasExpectedPermissions(fullDoc, userId)) {
    return { ok: true, updated: false, presetId, userId };
  }

  await databases.updateDocument(
    DATABASE_ID,
    PRESETS_COLL,
    presetId,
    { appwriteUserId: userId },
    expectedPermissions(userId),
  );

  return { ok: true, updated: true, presetId, userId };
}

async function backfillPresets(databases, limit, log) {
  const results = [];
  let cursor = null;
  let scanned = 0;

  while (results.length < limit) {
    const queries = [Query.limit(PAGE_SIZE), Query.orderAsc('$id')];
    if (cursor) queries.push(Query.cursorAfter(cursor));

    const page = await databases.listDocuments(DATABASE_ID, PRESETS_COLL, queries);
    if (page.documents.length === 0) break;

    for (const doc of page.documents) {
      scanned++;
      const ownerId = readString(getField(doc, 'ownerId'));
      if (!ownerId) continue;

      const candidate = {
        ...(doc.data && typeof doc.data === 'object' ? doc.data : {}),
        ...doc,
        $id: doc.$id,
        $permissions: doc.$permissions,
      };
      const result = await repairPreset(databases, candidate, log);
      results.push(result);
      if (results.length >= limit) break;
    }

    if (page.documents.length < PAGE_SIZE) break;
    cursor = page.documents[page.documents.length - 1].$id;
  }

  return { scanned, results };
}

export default async ({ req, res, log, error }) => {
  if (!ENDPOINT || !PROJECT_ID || !API_KEY) {
    return res.json({ ok: false, error: 'Appwrite env is not configured' }, 500);
  }

  const client = makeClient();
  const databases = new Databases(client);
  const body = parseBody(req);
  const payloadDoc = extractPayloadDoc(body);

  try {
    if (payloadDoc != null) {
      const result = await repairPreset(databases, payloadDoc, log);
      return res.json({ ok: result.ok, mode: 'single', ...result });
    }

    const limit = Math.max(
      1,
      Math.min(500, parseInt(String(body.limit ?? PAGE_SIZE), 10) || PAGE_SIZE),
    );
    const { scanned, results } = await backfillPresets(databases, limit, log);
    const updated = results.filter((item) => item.updated).length;
    const unresolved = results.filter((item) => item.reason === 'user_id_not_found').length;
    return res.json({
      ok: true,
      mode: 'backfill',
      scanned,
      processed: results.length,
      updated,
      unresolved,
      results,
    });
  } catch (err) {
    error(`repair-preset-permissions failed: ${err.message}`);
    return res.json({ ok: false, error: err.message }, 500);
  }
};
