const functions = require('firebase-functions');
const admin = require('firebase-admin');
const sharp = require('sharp');
const crypto = require('crypto');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret, defineString } = require('firebase-functions/params');

admin.initializeApp();

const appwriteApiKeySecret = defineSecret('APPWRITE_API_KEY');
const syncFromAppwriteSchedule = defineString('SYNC_FROM_APPWRITE_SCHEDULE', {
  default: '0 */12 * * *',
});

const ADMIN_API_KEY = 'photosession_admin_key_2026_secure_secret';

const THUMBNAIL_WIDTH = 400;
const THUMBNAIL_QUALITY = 80;

async function createThumbnailForPreset(presetId, previewImageUrl) {
  const response = await fetch(previewImageUrl);
  if (!response.ok) {
    throw new Error(`Download failed: ${response.status} ${response.statusText}`);
  }

  const imageBuffer = Buffer.from(await response.arrayBuffer());

  const thumbnail = await sharp(imageBuffer)
    .resize(THUMBNAIL_WIDTH, null, { withoutEnlargement: true })
    .webp({ quality: THUMBNAIL_QUALITY })
    .toBuffer();

  const bucket = admin.storage().bucket();
  const storagePath = `thumbnails/${presetId}.webp`;
  const file = bucket.file(storagePath);
  const token = crypto.randomUUID();

  await file.save(thumbnail, {
    contentType: 'image/webp',
    metadata: {
      metadata: {
        firebaseStorageDownloadTokens: token,
      },
    },
  });

  const encodedPath = encodeURIComponent(storagePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${token}`;
}

exports.createPreset = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  
  if (req.method === 'OPTIONS') {
    res.set('Access-Control-Allow-Methods', 'POST');
    res.set('Access-Control-Allow-Headers', 'Content-Type, X-Admin-API-Key');
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const apiKey = req.get('X-Admin-API-Key');
  if (apiKey !== ADMIN_API_KEY) {
    console.warn('Unauthorized access attempt');
    res.status(403).json({ error: 'Unauthorized' });
    return;
  }

  try {
    const { title, prompt, previewImageUrl, tags, createdAt } = req.body;

    if (!prompt || !previewImageUrl) {
      res.status(400).json({ error: 'Missing required fields: prompt, previewImageUrl' });
      return;
    }

    const db = admin.firestore();
    const timestamp = Date.now();
    const titleSlug = (title || 'preset').toLowerCase().replace(/[^a-z0-9]+/g, '_');
    const docId = `preset_${timestamp}_${titleSlug}`;

    const docData = {
      title: title || null,
      prompt: prompt,
      previewImageUrl: previewImageUrl,
      tags: Array.isArray(tags) ? tags : [],
      createdAt: createdAt || new Date().toISOString(),
      likesCount: 0,
      likedBy: [],
    };

    await db.collection('presets').doc(docId).set(docData);

    console.log(`Preset created: ${docId}`);
    res.status(200).json({ 
      success: true, 
      id: docId,
      message: 'Preset created successfully'
    });
  } catch (error) {
    console.error('Error creating preset:', error);
    res.status(500).json({ 
      error: 'Internal server error',
      details: error.message 
    });
  }
});

exports.createPresetsBatch = functions.https.onRequest(async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  
  if (req.method === 'OPTIONS') {
    res.set('Access-Control-Allow-Methods', 'POST');
    res.set('Access-Control-Allow-Headers', 'Content-Type, X-Admin-API-Key');
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const apiKey = req.get('X-Admin-API-Key');
  if (apiKey !== ADMIN_API_KEY) {
    console.warn('Unauthorized batch access attempt');
    res.status(403).json({ error: 'Unauthorized' });
    return;
  }

  try {
    const { presets } = req.body;

    if (!Array.isArray(presets) || presets.length === 0) {
      res.status(400).json({ error: 'Invalid request: presets array required' });
      return;
    }

    const db = admin.firestore();
    const batch = db.batch();
    const results = [];

    for (const preset of presets) {
      if (!preset.prompt || !preset.previewImageUrl) {
        results.push({ 
          title: preset.title || 'unknown', 
          success: false, 
          error: 'Missing required fields' 
        });
        continue;
      }

      const timestamp = Date.now();
      const titleSlug = (preset.title || 'preset').toLowerCase().replace(/[^a-z0-9]+/g, '_');
      const docId = `preset_${timestamp}_${titleSlug}_${Math.random().toString(36).substr(2, 9)}`;

      const docRef = db.collection('presets').doc(docId);
      const docData = {
        title: preset.title || null,
        prompt: preset.prompt,
        previewImageUrl: preset.previewImageUrl,
        tags: Array.isArray(preset.tags) ? preset.tags : [],
        createdAt: preset.createdAt || new Date().toISOString(),
        likesCount: 0,
        likedBy: [],
      };

      batch.set(docRef, docData);
      results.push({ 
        title: preset.title || docId, 
        success: true, 
        id: docId 
      });
    }

    await batch.commit();

    const successCount = results.filter(r => r.success).length;
    console.log(`Batch created: ${successCount}/${presets.length} presets`);

    res.status(200).json({ 
      success: true,
      total: presets.length,
      successful: successCount,
      results: results
    });
  } catch (error) {
    console.error('Error creating presets batch:', error);
    res.status(500).json({ 
      error: 'Internal server error',
      details: error.message 
    });
  }
});

exports.generateThumbnail = functions
  .runWith({ memory: '512MB', timeoutSeconds: 120 })
  .firestore
  .document('presets/{presetId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;

    const presetId = context.params.presetId;
    const after = change.after.data();
    const before = change.before.exists ? change.before.data() : null;

    if (!after.previewImageUrl) return null;

    if (after.thumbnailUrl &&
        (!before || before.previewImageUrl === after.previewImageUrl)) {
      return null;
    }

    console.log(`Generating thumbnail for preset: ${presetId}`);

    try {
      const thumbnailUrl = await createThumbnailForPreset(presetId, after.previewImageUrl);
      await change.after.ref.update({ thumbnailUrl });
      console.log(`Thumbnail generated for preset: ${presetId}`);
    } catch (error) {
      console.error(`Failed to generate thumbnail for ${presetId}:`, error);
    }

    return null;
  });

exports.backfillThumbnails = functions
  .runWith({ memory: '1GB', timeoutSeconds: 540 })
  .https.onRequest(async (req, res) => {
    res.set('Access-Control-Allow-Origin', '*');

    if (req.method === 'OPTIONS') {
      res.set('Access-Control-Allow-Methods', 'POST');
      res.set('Access-Control-Allow-Headers', 'Content-Type, X-Admin-API-Key');
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const apiKey = req.get('X-Admin-API-Key');
    if (apiKey !== ADMIN_API_KEY) {
      console.warn('Unauthorized backfill access attempt');
      res.status(403).json({ error: 'Unauthorized' });
      return;
    }

    try {
      const db = admin.firestore();
      const snapshot = await db.collection('presets').get();

      const presetsToProcess = snapshot.docs.filter(doc => {
        const data = doc.data();
        return data.previewImageUrl && !data.thumbnailUrl;
      });

      console.log(`Backfill: found ${presetsToProcess.length} presets without thumbnails`);

      const results = [];
      const CONCURRENCY = 5;

      for (let i = 0; i < presetsToProcess.length; i += CONCURRENCY) {
        const batch = presetsToProcess.slice(i, i + CONCURRENCY);
        const promises = batch.map(async (doc) => {
          try {
            const thumbnailUrl = await createThumbnailForPreset(
              doc.id, doc.data().previewImageUrl
            );
            await doc.ref.update({ thumbnailUrl });
            console.log(`Backfill: thumbnail created for ${doc.id}`);
            return { id: doc.id, title: doc.data().title || doc.id, success: true };
          } catch (error) {
            console.error(`Backfill: failed for ${doc.id}:`, error.message);
            return { id: doc.id, title: doc.data().title || doc.id, success: false, error: error.message };
          }
        });

        const batchResults = await Promise.all(promises);
        results.push(...batchResults);
      }

      const successCount = results.filter(r => r.success).length;
      console.log(`Backfill complete: ${successCount}/${presetsToProcess.length}`);

      res.status(200).json({
        success: true,
        total: presetsToProcess.length,
        processed: successCount,
        failed: presetsToProcess.length - successCount,
        results,
      });
    } catch (error) {
      console.error('Backfill error:', error);
      res.status(500).json({
        error: 'Internal server error',
        details: error.message,
      });
    }
  });

exports.processPresetRewards = functions
  .runWith({
    timeoutSeconds: 60,
    memory: '256MB',
  })
  .firestore
  .document('presets/{presetId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    
    const presetId = context.params.presetId;
    const ownerId = after.ownerId;
    const isPublic = after.isPublic;
    
    if (!ownerId || !isPublic) {
      console.log(`Reward skipped for ${presetId}: no owner or not public`);
      return null;
    }
    
    const oldLikes = before.likesCount || 0;
    const newLikes = after.likesCount || 0;
    
    if (newLikes <= oldLikes) {
      return null;
    }
    
    const MIN_LIKES = 3;
    const MAX_CREDITS_PER_PRESET = 50;
    const CREDITS_PER_LIKE = 1;
    
    if (newLikes < MIN_LIKES) {
      console.log(`Reward skipped for ${presetId}: ${newLikes} likes < ${MIN_LIKES} minimum`);
      return null;
    }
    
    const db = admin.firestore();
    const earningsRef = db.collection('preset_earnings').doc(presetId);
    const earningsDoc = await earningsRef.get();
    
    let creditsEarned = 0;
    let lastProcessedLikes = 0;
    
    if (earningsDoc.exists) {
      const data = earningsDoc.data();
      creditsEarned = data.creditsEarned || 0;
      lastProcessedLikes = data.lastProcessedLikes || 0;
    }
    
    if (creditsEarned >= MAX_CREDITS_PER_PRESET) {
      console.log(`Reward skipped for ${presetId}: max credits reached (${creditsEarned})`);
      return null;
    }
    
    const delta = newLikes - lastProcessedLikes;
    if (delta <= 0) {
      return null;
    }
    
    let newCredits = delta * CREDITS_PER_LIKE;
    
    if (creditsEarned + newCredits > MAX_CREDITS_PER_PRESET) {
      newCredits = Math.max(0, MAX_CREDITS_PER_PRESET - creditsEarned);
    }
    
    if (newCredits === 0) {
      return null;
    }
    
    await earningsRef.set({
      presetId: presetId,
      ownerId: ownerId,
      totalLikes: newLikes,
      creditsEarned: creditsEarned + newCredits,
      lastProcessedLikes: newLikes,
      lastProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: earningsDoc.exists ? 
        earningsDoc.data().createdAt : 
        admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    
    console.log(`✅ Reward: preset ${presetId} earned ${newCredits} credits (${newLikes} likes, owner: ${ownerId})`);
    
    return null;
  });

// ═══════════════════════════════════════════════════════════════════════
// BIDIRECTIONAL SYNC  Firebase Firestore ↔ Appwrite
//
// Strategy:
//   Firebase → Appwrite : Firestore onWrite trigger (push, near-realtime)
//   Appwrite → Firebase : scheduled pull every 5 minutes
//
// Images:
//   Preset preview/thumbnail images are mirrored to each side's own
//   Storage so that users never load images from the opposite region.
//   Firebase Storage → Appwrite Storage  (Russian users stay on VPS)
//   Appwrite Storage → Firebase Storage  (global users stay on GCP)
//   File IDs are deterministic (MD5) — re-upload is safe (409 = skip).
//
// Loop prevention:
//   • Writes FROM Appwrite land in Firestore with _syncSource='appwrite'.
//     The Firestore trigger checks this field and skips such documents.
//   • When Firebase pushes to Appwrite it records the timestamp in the
//     internal _appwriteSyncLog collection. The pull sync skips any
//     Appwrite document whose $updatedAt is within 60 s of that stamp.
//
// What is synced:  presets (all fields, images mirrored to both sides)
// What is NOT synced: user_generations (private/device-local),
//                     preset_earnings (Firebase-only business logic)
// ═══════════════════════════════════════════════════════════════════════

function _appwriteEndpoint() {
  const ep = process.env.APPWRITE_ENDPOINT || '';
  return ep.endsWith('/') ? ep : `${ep}/`;
}

function _appwriteCollUrl() {
  return (
    `${_appwriteEndpoint()}databases/` +
    `${process.env.APPWRITE_DATABASE_ID || 'main'}/collections/` +
    `${process.env.APPWRITE_PRESETS_COLLECTION_ID || 'presets'}/documents`
  );
}

function _appwriteHeaders(apiKey) {
  return {
    'Content-Type': 'application/json',
    'X-Appwrite-Project': process.env.APPWRITE_PROJECT_ID || '',
    'X-Appwrite-Key': apiKey,
  };
}

function _appwritePresetImagesBucketId() {
  return process.env.APPWRITE_PRESET_IMAGES_BUCKET_ID || 'preset-images';
}

/** Returns true if url belongs to Appwrite Storage on the VPS. */
function _isAppwriteStorageUrl(url) {
  if (!url) return false;
  try {
    const awHost = new URL(process.env.APPWRITE_ENDPOINT || 'http://localhost').hostname;
    return url.includes(awHost);
  } catch (_) { return false; }
}

/** Returns true if url belongs to Firebase Storage. */
function _isFirebaseStorageUrl(url) {
  return Boolean(url && url.includes('firebasestorage.googleapis.com'));
}

/**
 * Returns true if the URL is external and should be mirrored to Appwrite.
 * Mirrors anything that is NOT already on Appwrite Storage and is a real URL.
 */
function _shouldMirrorToAppwrite(url) {
  if (!url) return false;
  if (!url.startsWith('http://') && !url.startsWith('https://')) return false;
  return !_isAppwriteStorageUrl(url);
}

/**
 * Download image from any URL → upload to Appwrite Storage.
 * fileId must be ≤ 36 chars and deterministic (use MD5).
 * Returns the Appwrite view URL. On 409 (already exists) returns computed URL.
 */
async function _mirrorImageToAppwriteStorage(sourceUrl, fileId, apiKey) {
  const endpoint = process.env.APPWRITE_ENDPOINT || '';
  const projectId = process.env.APPWRITE_PROJECT_ID || '';
  const bucketId = _appwritePresetImagesBucketId();

  const dlRes = await fetch(sourceUrl, { signal: AbortSignal.timeout(45000) });
  if (!dlRes.ok) throw new Error(`Download failed: ${dlRes.status} ${sourceUrl}`);

  const buffer = Buffer.from(await dlRes.arrayBuffer());
  const contentType = dlRes.headers.get('content-type') || 'image/jpeg';
  const ext = contentType.includes('webp') ? 'webp' : contentType.includes('png') ? 'png' : 'jpg';

  const uploadUrl = `${endpoint}/storage/buckets/${bucketId}/files`;
  const formData = new FormData();
  formData.append('fileId', fileId);
  formData.append('file', new Blob([buffer], { type: contentType }), `${fileId}.${ext}`);
  formData.append('permissions[]', 'read("any")');

  const upRes = await fetch(uploadUrl, {
    method: 'POST',
    headers: { 'X-Appwrite-Project': projectId, 'X-Appwrite-Key': apiKey },
    body: formData,
    signal: AbortSignal.timeout(60000),
  });

  if (upRes.status === 409 || upRes.ok) {
    return `${endpoint}/storage/buckets/${bucketId}/files/${fileId}/view?project=${projectId}`;
  }
  throw new Error(`Appwrite upload: ${upRes.status} ${await upRes.text()}`);
}

/**
 * Download image from any URL → upload to Firebase Storage.
 * Returns a public Firebase Storage download URL.
 */
async function _mirrorImageToFirebaseStorage(sourceUrl, fileId) {
  const dlRes = await fetch(sourceUrl, { signal: AbortSignal.timeout(45000) });
  if (!dlRes.ok) throw new Error(`Download failed: ${dlRes.status} ${sourceUrl}`);

  const buffer = Buffer.from(await dlRes.arrayBuffer());
  const contentType = dlRes.headers.get('content-type') || 'image/jpeg';
  const ext = contentType.includes('webp') ? 'webp' : contentType.includes('png') ? 'png' : 'jpg';

  const bucket = admin.storage().bucket();
  const storagePath = `preset-images/${fileId}.${ext}`;
  const file = bucket.file(storagePath);

  const [exists] = await file.exists();
  if (!exists) {
    const token = crypto.randomUUID();
    await file.save(buffer, {
      contentType,
      metadata: { metadata: { firebaseStorageDownloadTokens: token } },
    });
    const encodedPath = encodeURIComponent(storagePath);
    return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${token}`;
  }
  // Already exists — get existing metadata for the token
  const [meta] = await file.getMetadata();
  const token = meta.metadata?.firebaseStorageDownloadTokens;
  const encodedPath = encodeURIComponent(storagePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${token}`;
}

/**
 * For Firebase → Appwrite direction:
 * Mirror ALL external images to Appwrite Storage (not just Firebase Storage).
 */
async function _mirrorImagesToAppwrite(fields, appwriteId, apiKey) {
  const out = { ...fields };

  if (_shouldMirrorToAppwrite(fields.previewImageUrl)) {
    try {
      const fid = crypto.createHash('md5').update(`preview_${appwriteId}`).digest('hex');
      out.previewImageUrl = await _mirrorImageToAppwriteStorage(fields.previewImageUrl, fid, apiKey);
      console.log(`[img→aw] preview (${new URL(fields.previewImageUrl).hostname}): ${appwriteId}`);
    } catch (e) {
      console.error(`[img→aw] preview failed (${appwriteId}): ${e.message}`);
    }
  }

  if (_shouldMirrorToAppwrite(fields.thumbnailUrl)) {
    try {
      const fid = crypto.createHash('md5').update(`thumb_${appwriteId}`).digest('hex');
      out.thumbnailUrl = await _mirrorImageToAppwriteStorage(fields.thumbnailUrl, fid, apiKey);
      console.log(`[img→aw] thumbnail (${new URL(fields.thumbnailUrl).hostname}): ${appwriteId}`);
    } catch (e) {
      console.error(`[img→aw] thumbnail failed (${appwriteId}): ${e.message}`);
    }
  }

  return out;
}

/**
 * For Appwrite → Firebase direction:
 * Replace Appwrite Storage URLs with Firebase Storage URLs.
 */
async function _mirrorImagesToFirebase(fields, appwriteId) {
  const out = { ...fields };

  if (_isAppwriteStorageUrl(fields.previewImageUrl)) {
    try {
      const fid = crypto.createHash('md5').update(`fbprev_${appwriteId}`).digest('hex');
      out.previewImageUrl = await _mirrorImageToFirebaseStorage(fields.previewImageUrl, fid);
      console.log(`[img←aw] preview: ${appwriteId}`);
    } catch (e) {
      console.error(`[img←aw] preview failed (${appwriteId}): ${e.message}`);
    }
  }

  if (_isAppwriteStorageUrl(fields.thumbnailUrl)) {
    try {
      const fid = crypto.createHash('md5').update(`fbthumb_${appwriteId}`).digest('hex');
      out.thumbnailUrl = await _mirrorImageToFirebaseStorage(fields.thumbnailUrl, fid);
      console.log(`[img←aw] thumbnail: ${appwriteId}`);
    } catch (e) {
      console.error(`[img←aw] thumbnail failed (${appwriteId}): ${e.message}`);
    }
  }

  return out;
}

/** Firebase doc IDs can exceed Appwrite's 36-char limit — hash them. */
function _toAppwriteId(firebaseId) {
  if (firebaseId.length <= 36 && /^[a-zA-Z0-9._-]+$/.test(firebaseId)) {
    return firebaseId;
  }
  return crypto.createHash('md5').update(firebaseId).digest('hex');
}

/** PATCH existing doc, POST if 404. */
async function _appwriteUpsert(appwriteId, data, apiKey) {
  const url = _appwriteCollUrl();
  const headers = _appwriteHeaders(apiKey);

  const patchRes = await fetch(`${url}/${appwriteId}`, {
    method: 'PATCH',
    headers,
    body: JSON.stringify({ data }),
  });

  if (patchRes.status === 404) {
    const createRes = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        documentId: appwriteId,
        data,
        permissions: ['read("any")'],
      }),
    });
    if (!createRes.ok) {
      throw new Error(
        `Appwrite create ${appwriteId}: ${createRes.status} ${await createRes.text()}`
      );
    }
    console.log(`[sync→aw] created ${appwriteId}`);
  } else if (patchRes.ok) {
    console.log(`[sync→aw] updated ${appwriteId}`);
  } else {
    throw new Error(
      `Appwrite patch ${appwriteId}: ${patchRes.status} ${await patchRes.text()}`
    );
  }
}

async function _appwriteDelete(appwriteId, apiKey) {
  const res = await fetch(`${_appwriteCollUrl()}/${appwriteId}`, {
    method: 'DELETE',
    headers: _appwriteHeaders(apiKey),
  });
  if (res.ok || res.status === 404) {
    console.log(`[sync→aw] deleted ${appwriteId}`);
  } else {
    console.error(`[sync→aw] delete failed ${appwriteId}: ${res.status}`);
  }
}

/**
 * Fetch Appwrite presets modified after isoTimestamp, all pages.
 * Query format mirrors the existing Dart HTTP queries in the repo.
 */
async function _fetchAppwriteModifiedSince(isoTimestamp, apiKey) {
  const url = _appwriteCollUrl();
  const headers = _appwriteHeaders(apiKey);
  const all = [];
  let offset = 0;
  const pageSize = 100;

  while (true) {
    const q = [
      `queries[]=${encodeURIComponent(
        JSON.stringify({
          method: 'greaterThan',
          attribute: '$updatedAt',
          values: [isoTimestamp],
        })
      )}`,
      `queries[]=${encodeURIComponent(
        JSON.stringify({ method: 'orderAsc', attribute: '$updatedAt' })
      )}`,
      `queries[]=${encodeURIComponent(
        JSON.stringify({ method: 'limit', values: [pageSize] })
      )}`,
      `queries[]=${encodeURIComponent(
        JSON.stringify({ method: 'offset', values: [offset] })
      )}`,
    ];
    const res = await fetch(`${url}?${q.join('&')}`, { headers });
    if (!res.ok) {
      console.error(`[sync←aw] fetch error: ${res.status} ${await res.text()}`);
      break;
    }
    const json = await res.json();
    const docs = json.documents || [];
    all.push(...docs);
    if (docs.length < pageSize) break;
    offset += pageSize;
  }
  return all;
}

/** Normalise preset fields from either Firestore data or Appwrite document. */
function _presetFields(src) {
  const fields = {
    prompt: src.prompt || '',
    previewImageUrl: src.previewImageUrl || '',
    thumbnailUrl: src.thumbnailUrl || null,
    title: src.title || null,
    tags: Array.isArray(src.tags) ? src.tags : [],
    createdAt: src.createdAt || new Date().toISOString(),
    ownerId: src.ownerId || null,
    isPublic: src.isPublic ?? false,
    likesCount: src.likesCount || 0,
    likedBy: Array.isArray(src.likedBy) ? src.likedBy : [],
  };
  if (src.sourceChannel) fields.sourceChannel = src.sourceChannel;
  if (src.sourcePostId != null) fields.sourcePostId = String(src.sourcePostId);
  return fields;
}

// ─── Firebase → Appwrite (push on every Firestore preset write) ─────────────
exports.syncPresetToAppwrite = functions
  .runWith({ timeoutSeconds: 300, memory: '512MB', secrets: ['APPWRITE_API_KEY'] })
  .firestore
  .document('presets/{presetId}')
  .onWrite(async (change, context) => {
    const apiKey = process.env.APPWRITE_API_KEY || '';
    if (!apiKey || !process.env.APPWRITE_ENDPOINT || !process.env.APPWRITE_PROJECT_ID) {
      return null;
    }

    const after = change.after.exists ? change.after.data() : null;

    // Loop guard — this write came from the Appwrite pull sync; skip it.
    if (after?._syncSource === 'appwrite') {
      return null;
    }

    const firebaseId = context.params.presetId;
    const appwriteId = _toAppwriteId(firebaseId);

    try {
      if (!after) {
        await _appwriteDelete(appwriteId, apiKey);
        await admin.firestore().collection('_appwriteSyncLog').doc(appwriteId).delete();
        return null;
      }

      // Mirror images to Appwrite Storage so Russian users load from VPS
      const fields = await _mirrorImagesToAppwrite(_presetFields(after), appwriteId, apiKey);
      await _appwriteUpsert(appwriteId, fields, apiKey);

      // Record sync timestamp so the pull sync can detect our own writes.
      await admin.firestore().collection('_appwriteSyncLog').doc(appwriteId).set(
        { syncedAt: admin.firestore.FieldValue.serverTimestamp(), firebaseDocId: firebaseId },
        { merge: true }
      );
    } catch (err) {
      console.error(`[sync→aw] ${firebaseId}:`, err.message);
    }

    return null;
  });

// ─── Appwrite → Firebase (scheduled pull; SYNC_FROM_APPWRITE_SCHEDULE in functions/.env) ───────
exports.syncFromAppwrite = onSchedule(
  {
    schedule: syncFromAppwriteSchedule,
    timeZone: 'UTC',
    timeoutSeconds: 540,
    memory: '512MiB',
    secrets: [appwriteApiKeySecret],
  },
  async () => {
    const apiKey = appwriteApiKeySecret.value();
    if (!apiKey || !process.env.APPWRITE_ENDPOINT || !process.env.APPWRITE_PROJECT_ID) {
      console.warn('[sync←aw] Appwrite config missing — set APPWRITE_* env vars');
      return;
    }

    const db = admin.firestore();
    const stateRef = db.collection('_syncState').doc('appwriteToFirebase');
    const stateSnap = await stateRef.get();
    const lastSyncAt = stateSnap.exists
      ? (stateSnap.data().lastSyncAt?.toDate() ?? new Date(0))
      : new Date(0);

    console.log(`[sync←aw] pulling docs modified since ${lastSyncAt.toISOString()}`);

    const docs = await _fetchAppwriteModifiedSince(lastSyncAt.toISOString(), apiKey);
    console.log(`[sync←aw] ${docs.length} docs to process`);

    let synced = 0;
    let skipped = 0;

    for (const doc of docs) {
      const appwriteId = doc.$id;
      if (!appwriteId || !doc.prompt || !doc.previewImageUrl) continue;

      // Loop guard — check if $updatedAt ≈ our last Firebase→Appwrite write.
      const logSnap = await db.collection('_appwriteSyncLog').doc(appwriteId).get();
      if (logSnap.exists) {
        const syncedAt = logSnap.data().syncedAt?.toDate();
        const awUpdatedAt = new Date(doc.$updatedAt);
        if (syncedAt && Math.abs(awUpdatedAt.getTime() - syncedAt.getTime()) < 60_000) {
          skipped++;
          continue;
        }
      }

      const firestoreDocId = logSnap.exists
        ? (logSnap.data().firebaseDocId || appwriteId)
        : appwriteId;

      // Mirror images to Firebase Storage so global users load from GCP
      const fields = await _mirrorImagesToFirebase(_presetFields(doc), appwriteId);
      await db.collection('presets').doc(firestoreDocId).set(
        { ...fields, _syncSource: 'appwrite', _appwriteId: appwriteId },
        { merge: true }
      );
      synced++;
    }

    await stateRef.set(
      { lastSyncAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    console.log(`[sync←aw] done: synced=${synced} skipped=${skipped}`);
  }
);

