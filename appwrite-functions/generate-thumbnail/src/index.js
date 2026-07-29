import { Client, Databases, Storage } from 'node-appwrite';
import { InputFile } from 'node-appwrite/file';
import sharp from 'sharp';

const ENDPOINT     = (process.env.APPWRITE_ENDPOINT              ?? '').trim();
const PROJECT_ID   = (process.env.APPWRITE_PROJECT_ID            ?? '').trim();
const API_KEY      = (process.env.APPWRITE_API_KEY               ?? '').trim();
const DATABASE_ID  = (process.env.APPWRITE_DATABASE_ID           ?? 'main').trim();
const PRESETS_COLL = (process.env.APPWRITE_PRESETS_COLLECTION_ID ?? 'presets').trim();
const BUCKET_ID    = (process.env.APPWRITE_STORAGE_BUCKET_ID     ?? 'user-photos').trim();

const BASE_URL         = ENDPOINT.replace(/\/v1\/?$/, '');
const THUMBNAIL_WIDTH  = 400;
const THUMBNAIL_QUALITY = 80;

function makeClient() {
  return new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
}

function thumbFileId(presetId) {
  const safe = presetId.replace(/[^a-zA-Z0-9._-]/g, '-').slice(0, 29);
  return `th-${safe}`;
}

export default async ({ req, res, log, error }) => {
  let doc;
  try {
    doc = req.bodyJson ?? (typeof req.body === 'string' ? JSON.parse(req.body) : req.body);
  } catch {
    error('Invalid JSON body');
    return res.json({ ok: false, message: 'Invalid JSON body' }, 400);
  }

  const presetId        = doc?.$id;
  const previewImageUrl = doc?.previewImageUrl;
  const existingThumb   = doc?.thumbnailUrl ?? null;
  const thumbSource     = doc?.thumbnailSourceUrl ?? null;

  if (!presetId || !previewImageUrl) {
    log('Skipping: missing presetId or previewImageUrl');
    return res.json({ ok: false, message: 'Missing presetId or previewImageUrl' });
  }

  if (existingThumb && thumbSource === previewImageUrl) {
    log(`Already up-to-date: ${presetId}`);
    return res.json({ ok: true, message: 'Already up-to-date' });
  }

  const client    = makeClient();
  const databases = new Databases(client);
  const storage   = new Storage(client);

  try {
    log(`Downloading preview: ${previewImageUrl}`);
    const imgRes = await fetch(previewImageUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; AppwriteFunction/1.0)' },
      signal: AbortSignal.timeout(45_000),
    });
    if (!imgRes.ok) throw new Error(`HTTP ${imgRes.status} ${previewImageUrl}`);

    const imageBuffer = Buffer.from(await imgRes.arrayBuffer());

    log('Generating WebP thumbnail…');
    const thumb = await sharp(imageBuffer)
      .resize(THUMBNAIL_WIDTH, null, { withoutEnlargement: true })
      .webp({ quality: THUMBNAIL_QUALITY })
      .toBuffer();

    const fileId = thumbFileId(presetId);

    try { await storage.deleteFile(BUCKET_ID, fileId); } catch { /* not found — ok */ }

    log(`Uploading thumbnail (bucket=${BUCKET_ID}, id=${fileId})`);
    await storage.createFile(
      BUCKET_ID,
      fileId,
      InputFile.fromBuffer(thumb, `${fileId}.webp`),
      ['read("any")'],
    );

    const thumbUrl = `${BASE_URL}/v1/storage/buckets/${BUCKET_ID}/files/${fileId}/view?project=${PROJECT_ID}`;

    await databases.updateDocument(DATABASE_ID, PRESETS_COLL, presetId, {
      thumbnailUrl: thumbUrl,
      thumbnailSourceUrl: previewImageUrl,
    });

    log(`Done: ${thumbUrl}`);
    return res.json({ ok: true, thumbnailUrl: thumbUrl });
  } catch (err) {
    error(`Failed for ${presetId}: ${err.message}`);
    return res.json({ ok: false, error: err.message }, 500);
  }
};
