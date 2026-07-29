import { Client, Databases, Storage, Query } from 'node-appwrite';
import { InputFile } from 'node-appwrite/file';
import { runPresetPipeline } from './pipeline_runner.js';

// .trim() защищает от trailing \n, которые deploy-скрипт добавляет через JSON-escape
const ENDPOINT      = (process.env.APPWRITE_ENDPOINT              ?? '').trim();
const PROJECT_ID    = (process.env.APPWRITE_PROJECT_ID            ?? '').trim();
const API_KEY       = (process.env.APPWRITE_API_KEY               ?? '').trim();
const DATABASE_ID   = (process.env.APPWRITE_DATABASE_ID           ?? 'main').trim();
const PRESETS_COLL  = (process.env.APPWRITE_PRESETS_COLLECTION_ID ?? 'presets').trim();
const BUCKET_ID     = (process.env.APPWRITE_STORAGE_BUCKET_ID     ?? 'user-photos').trim();
const API_BOST_KEY  = (process.env.API_BOST_API_KEY               ?? '').trim();
const DEEPSEEK_KEY  = (process.env.DEEPSEEK_API_KEY               ?? '').trim();
const ADMIN_KEY     = (process.env.ADMIN_API_KEY || 'photosession_admin_key_2026_secure_secret').trim();

const BACKFILL_CONCURRENCY = 5;
const THUMBNAIL_WIDTH      = 400;
const THUMBNAIL_QUALITY    = 80;
const BASE_URL             = ENDPOINT.replace(/\/v1\/?$/, '');

function makeClient() {
  return new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin':  '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Admin-API-Key',
  };
}

function titleSlug(title) {
  const base = (title || 'preset').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '_').replace(/^_|_$/g, '');
  return (base || 'preset').slice(0, 15);
}

function makePresetDocId(title) {
  const ts  = Date.now().toString(36);
  const rnd = Math.random().toString(36).slice(2, 7);
  return `p_${ts}_${titleSlug(title)}_${rnd}`.slice(0, 36).replace(/[^a-zA-Z0-9._-]/g, '-');
}

async function generateThumbnailBuffer(imageUrl) {
  const { default: sharp } = await import('sharp').catch(() => ({ default: null }));
  const res = await fetch(imageUrl, {
    headers: { 'User-Agent': 'Mozilla/5.0 (compatible; AppwriteFunction/1.0)' },
    signal: AbortSignal.timeout(45_000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} ${imageUrl}`);
  const buf = Buffer.from(await res.arrayBuffer());
  if (!sharp) return buf;
  return sharp(buf).resize(THUMBNAIL_WIDTH, null, { withoutEnlargement: true }).webp({ quality: THUMBNAIL_QUALITY }).toBuffer();
}

async function uploadThumbnail(storage, presetId, thumbBuf) {
  const fileId = `th-${presetId.replace(/[^a-zA-Z0-9._-]/g,'-').slice(0,29)}`;
  try { await storage.deleteFile(BUCKET_ID, fileId); } catch { /* ok */ }
  await storage.createFile(BUCKET_ID, fileId, InputFile.fromBuffer(thumbBuf, `${fileId}.webp`), ['read("any")']);
  return `${BASE_URL}/v1/storage/buckets/${BUCKET_ID}/files/${fileId}/view?project=${PROJECT_ID}`;
}

function isAuthorized(req) {
  // Appwrite Execution API strips custom headers — accept key from header OR body OR query
  const fromHeader = req.headers['x-admin-api-key'];
  // req.body may be a raw JSON string when called via Execution API
  let parsedBody = req.bodyJson ?? req.body;
  if (typeof parsedBody === 'string') {
    try { parsedBody = JSON.parse(parsedBody); } catch { parsedBody = {}; }
  }
  const fromBody  = parsedBody?.adminKey ?? parsedBody?.admin_key;
  const fromQuery = req.query?.key;
  const provided  = (fromHeader || fromBody || fromQuery || '').trim();
  return provided === ADMIN_KEY;
}

async function handleCreatePreset(body, databases, storage) {
  const { title, prompt, previewImageUrl, tags, createdAt } = body;
  if (!prompt || !previewImageUrl) {
    return { status: 400, body: { error: 'Missing required fields: prompt, previewImageUrl' } };
  }
  const docId = makePresetDocId(title);

  let thumbnailUrl       = null;
  let thumbnailSourceUrl = null;
  try {
    const thumbBuf     = await generateThumbnailBuffer(previewImageUrl);
    thumbnailUrl       = await uploadThumbnail(storage, docId, thumbBuf);
    thumbnailSourceUrl = previewImageUrl;
  } catch { /* generate-thumbnail trigger will retry on create event */ }

  await databases.createDocument(DATABASE_ID, PRESETS_COLL, docId, {
    title:          title ?? null,
    prompt,
    previewImageUrl,
    tags:           Array.isArray(tags) ? tags : [],
    createdAt:      createdAt ?? new Date().toISOString(),
    likesCount:     0,
    likedBy:        [],
    ...(thumbnailUrl ? { thumbnailUrl, thumbnailSourceUrl } : {}),
  }, ['read("any")']);
  return { status: 200, body: { success: true, id: docId, thumbnailGenerated: thumbnailUrl !== null } };
}

async function handleCreatePresetsBatch(body, databases, storage) {
  const { presets } = body;
  if (!Array.isArray(presets) || !presets.length) {
    return { status: 400, body: { error: 'Invalid request: presets array required' } };
  }
  const results = [];
  for (const preset of presets) {
    if (!preset.prompt || !preset.previewImageUrl) {
      results.push({ title: preset.title || 'unknown', success: false, error: 'Missing required fields' });
      continue;
    }
    const docId = makePresetDocId(preset.title);

    let thumbnailUrl       = null;
    let thumbnailSourceUrl = null;
    try {
      const thumbBuf     = await generateThumbnailBuffer(preset.previewImageUrl);
      thumbnailUrl       = await uploadThumbnail(storage, docId, thumbBuf);
      thumbnailSourceUrl = preset.previewImageUrl;
    } catch { /* ok, trigger will retry */ }

    await databases.createDocument(DATABASE_ID, PRESETS_COLL, docId, {
      title:           preset.title ?? null,
      prompt:          preset.prompt,
      previewImageUrl: preset.previewImageUrl,
      tags:            Array.isArray(preset.tags) ? preset.tags : [],
      createdAt:       preset.createdAt ?? new Date().toISOString(),
      likesCount:      0,
      likedBy:         [],
      ...(thumbnailUrl ? { thumbnailUrl, thumbnailSourceUrl } : {}),
    }, ['read("any")']);
    results.push({ title: preset.title || docId, success: true, id: docId, thumbnailGenerated: thumbnailUrl !== null });
  }
  const successCount = results.filter(r => r.success).length;
  return { status: 200, body: { success: true, total: presets.length, successful: successCount, results } };
}

async function handleBackfillThumbnails(databases, storage) {
  const toProcess = [];
  let offset = 0;
  while (true) {
    const res = await databases.listDocuments(DATABASE_ID, PRESETS_COLL, [
      Query.limit(100), Query.offset(offset),
    ]);
    for (const doc of res.documents) {
      if (doc.previewImageUrl && !doc.thumbnailUrl) toProcess.push(doc);
    }
    if (res.documents.length < 100) break;
    offset += 100;
  }

  const results = [];
  for (let i = 0; i < toProcess.length; i += BACKFILL_CONCURRENCY) {
    const chunk   = toProcess.slice(i, i + BACKFILL_CONCURRENCY);
    const settled = await Promise.allSettled(chunk.map(async doc => {
      const thumbBuf    = await generateThumbnailBuffer(doc.previewImageUrl);
      const thumbnailUrl = await uploadThumbnail(storage, doc.$id, thumbBuf);
      await databases.updateDocument(DATABASE_ID, PRESETS_COLL, doc.$id, {
        thumbnailUrl,
        thumbnailSourceUrl: doc.previewImageUrl,
      });
      return { id: doc.$id, title: doc.title || doc.$id, success: true };
    }));
    for (let j = 0; j < settled.length; j++) {
      if (settled[j].status === 'fulfilled') {
        results.push(settled[j].value);
      } else {
        results.push({ id: chunk[j].$id, title: chunk[j].title || chunk[j].$id, success: false, error: settled[j].reason?.message });
      }
    }
  }

  const successCount = results.filter(r => r.success).length;
  return {
    status: 200,
    body: { success: true, total: toProcess.length, processed: successCount,
            failed: toProcess.length - successCount, results },
  };
}

async function handleRunPipeline(body, databases, storage) {
  if (!API_BOST_KEY || !DEEPSEEK_KEY) {
    return { status: 500, body: { error: 'Missing API_BOST_API_KEY or DEEPSEEK_API_KEY' } };
  }
  let limit = 1;
  if (body?.limit != null) {
    const n = parseInt(String(body.limit), 10);
    if (!Number.isNaN(n)) limit = Math.min(Math.max(1, n), 20);
  }
  const summary = await runPresetPipeline({
    databases, storage,
    apiBostKey:  API_BOST_KEY,
    deepseekKey: DEEPSEEK_KEY,
    limit,
    databaseId:  DATABASE_ID,
    presetsColl: PRESETS_COLL,
    bucketId:    BUCKET_ID,
    endpoint:    ENDPOINT,
    projectId:   PROJECT_ID,
  });
  return { status: 200, body: summary };
}

export default async ({ req, res, log, error }) => {
  const headers = corsHeaders();

  if (req.method === 'OPTIONS') {
    return res.send('', 204, headers);
  }

  if (!isAuthorized(req)) {
    return res.json({ error: 'Unauthorized' }, 403, headers);
  }

  if (req.method !== 'POST') {
    return res.json({ error: 'Method not allowed' }, 405, headers);
  }

  let body;
  try {
    body = req.bodyJson ?? (typeof req.body === 'string' ? JSON.parse(req.body) : req.body) ?? {};
  } catch {
    body = {};
  }

  const client    = makeClient();
  const databases = new Databases(client);
  const storage   = new Storage(client);

  const path = req.path ?? '/';

  try {
    let result;

    if (path === '/' || path === '') {
      log('createPreset');
      result = await handleCreatePreset(body, databases, storage);
    } else if (path === '/batch') {
      log('createPresetsBatch');
      result = await handleCreatePresetsBatch(body, databases, storage);
    } else if (path === '/backfill') {
      log('backfillThumbnails');
      result = await handleBackfillThumbnails(databases, storage);
    } else if (path === '/pipeline') {
      log(`runPresetPipeline limit=${body?.limit ?? 1}`);
      result = await handleRunPipeline(body, databases, storage);
    } else {
      result = { status: 404, body: { error: `Unknown path: ${path}` } };
    }

    return res.json(result.body, result.status, headers);
  } catch (err) {
    error(`Error on ${path}: ${err.message}`);
    return res.json({ error: 'Internal server error', details: err.message }, 500, headers);
  }
};
