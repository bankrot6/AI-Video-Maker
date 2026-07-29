import { Client, Databases, Query } from 'node-appwrite';

const DATABASE_ID = process.env.APPWRITE_DATABASE_ID ?? 'main';
const PRESETS_COLLECTION = 'presets';

function buildClient() {
  return new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);
}

export default async ({ req, res, log, error }) => {
  let body;
  try {
    body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body ?? {});
  } catch {
    return res.json({ error: 'invalid_json' }, 400);
  }

  const { action, presetId, ownerId } = body;

  if (!presetId || typeof presetId !== 'string') {
    return res.json({ error: 'presetId обязателен' }, 400);
  }
  if (!ownerId || typeof ownerId !== 'string' || ownerId.length < 16) {
    return res.json({ error: 'ownerId обязателен' }, 400);
  }

  const db = new Databases(buildClient());

  // ── MAKE_PUBLIC ─────────────────────────────────────────────────────────────
  if (action === 'make_public') {
    try {
      const doc = await db.getDocument(DATABASE_ID, PRESETS_COLLECTION, presetId);
      
      if (doc.ownerId !== ownerId) {
        log(`make_public denied: preset=${presetId} owner=${doc.ownerId} caller=${ownerId}`);
        return res.json({ error: 'Вы не владелец этого пресета' }, 403);
      }

      await db.updateDocument(DATABASE_ID, PRESETS_COLLECTION, presetId, {
        isPublic: true,
      });

      log(`make_public: preset=${presetId} owner=${ownerId}`);
      return res.json({ success: true, isPublic: true });
    } catch (e) {
      error(`make_public error: ${e.message}`);
      return res.json({ error: e.message }, 500);
    }
  }

  // ── MAKE_PRIVATE ────────────────────────────────────────────────────────────
  if (action === 'make_private') {
    try {
      const doc = await db.getDocument(DATABASE_ID, PRESETS_COLLECTION, presetId);
      
      if (doc.ownerId !== ownerId) {
        log(`make_private denied: preset=${presetId} owner=${doc.ownerId} caller=${ownerId}`);
        return res.json({ error: 'Вы не владелец этого пресета' }, 403);
      }

      await db.updateDocument(DATABASE_ID, PRESETS_COLLECTION, presetId, {
        isPublic: false,
      });

      log(`make_private: preset=${presetId} owner=${ownerId}`);
      return res.json({ success: true, isPublic: false });
    } catch (e) {
      error(`make_private error: ${e.message}`);
      return res.json({ error: e.message }, 500);
    }
  }

  // ── DELETE_PRESET ───────────────────────────────────────────────────────────
  if (action === 'delete_preset') {
    try {
      const doc = await db.getDocument(DATABASE_ID, PRESETS_COLLECTION, presetId);
      
      if (doc.ownerId !== ownerId) {
        log(`delete_preset denied: preset=${presetId} owner=${doc.ownerId} caller=${ownerId}`);
        return res.json({ error: 'Вы не владелец этого пресета' }, 403);
      }

      await db.deleteDocument(DATABASE_ID, PRESETS_COLLECTION, presetId);

      log(`delete_preset: preset=${presetId} owner=${ownerId}`);
      return res.json({ success: true });
    } catch (e) {
      error(`delete_preset error: ${e.message}`);
      return res.json({ error: e.message }, 500);
    }
  }

  // ── UPDATE_TAGS ─────────────────────────────────────────────────────────────
  if (action === 'update_tags') {
    const { tags } = body;
    if (!Array.isArray(tags)) {
      return res.json({ error: 'tags должен быть массивом' }, 400);
    }

    try {
      const doc = await db.getDocument(DATABASE_ID, PRESETS_COLLECTION, presetId);
      
      if (doc.ownerId !== ownerId) {
        log(`update_tags denied: preset=${presetId} owner=${doc.ownerId} caller=${ownerId}`);
        return res.json({ error: 'Вы не владелец этого пресета' }, 403);
      }

      await db.updateDocument(DATABASE_ID, PRESETS_COLLECTION, presetId, {
        tags,
      });

      log(`update_tags: preset=${presetId} owner=${ownerId} tags=${tags.length}`);
      return res.json({ success: true, tags });
    } catch (e) {
      error(`update_tags error: ${e.message}`);
      return res.json({ error: e.message }, 500);
    }
  }

  return res.json({ error: 'unknown_action' }, 400);
};
