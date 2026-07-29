const admin = require('firebase-admin');
const sharp = require('sharp');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

const PIAPI_TASK_URL = 'https://api.piapi.ai/api/v1/task';
const PIAPI_MODEL = 'Qubico/qwen-image';
const IMAGE_WIDTH = 768;
const IMAGE_HEIGHT = 1024;
const THUMBNAIL_WIDTH = 400;
const THUMBNAIL_QUALITY = 80;
const POLL_INTERVAL_MS = 4000;
const POLL_TIMEOUT_MS = 5 * 60 * 1000;

function loadEnv() {
  const envPath = path.join(__dirname, '..', '.env');
  if (!fs.existsSync(envPath)) {
    console.error(`Файл .env не найден: ${envPath}`);
    process.exit(1);
  }
  const content = fs.readFileSync(envPath, 'utf-8');
  const env = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx < 0) continue;
    env[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim();
  }
  return env;
}

const env = loadEnv();
const PIAPI_API_KEY = env['PIAPI_API_KEY'];
if (!PIAPI_API_KEY) {
  console.error('PIAPI_API_KEY не найден в .env');
  process.exit(1);
}

const serviceAccountPath = path.join(__dirname, 'service-account.json');
try {
  const sa = require(serviceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    storageBucket: `${sa.project_id}.firebasestorage.app`,
  });
} catch {
  console.error(`service-account.json не найден: ${serviceAccountPath}`);
  process.exit(1);
}

const db = admin.firestore();
const bucket = admin.storage().bucket();

async function createPiApiTask(prompt) {
  const response = await fetch(PIAPI_TASK_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-API-Key': PIAPI_API_KEY,
    },
    body: JSON.stringify({
      model: PIAPI_MODEL,
      task_type: 'txt2img',
      input: {
        prompt: prompt.slice(0, 2000),
        width: IMAGE_WIDTH,
        height: IMAGE_HEIGHT,
      },
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Create task failed: ${response.status} ${text}`);
  }

  const json = await response.json();
  const taskId = json?.data?.task_id || json?.task_id;
  if (!taskId) throw new Error(`No task_id in response: ${JSON.stringify(json)}`);
  return taskId;
}

async function pollTask(taskId) {
  const start = Date.now();
  while (Date.now() - start < POLL_TIMEOUT_MS) {
    await new Promise(r => setTimeout(r, POLL_INTERVAL_MS));

    const response = await fetch(`${PIAPI_TASK_URL}/${taskId}`, {
      headers: { 'X-API-Key': PIAPI_API_KEY },
    });

    if (!response.ok) continue;

    const json = await response.json();
    const data = json?.data || json;
    const status = (data?.status || '').toLowerCase();

    if (status === 'completed') {
      const output = data?.output;
      const url = output?.image_url || (output?.image_urls && output.image_urls[0]);
      if (url) return url;
      throw new Error('Completed but no image URL');
    }

    if (status === 'failed') {
      const errMsg = data?.error?.message || 'Generation failed';
      throw new Error(errMsg);
    }

    process.stdout.write('.');
  }
  throw new Error('Poll timeout');
}

async function downloadImage(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download failed: ${response.status}`);
  return Buffer.from(await response.arrayBuffer());
}

async function uploadToStorage(presetId, imageBuffer, suffix = '') {
  const storagePath = suffix
    ? `thumbnails/${presetId}.webp`
    : `preset-previews/${presetId}.jpg`;
  const file = bucket.file(storagePath);
  const token = crypto.randomUUID();

  const contentType = suffix ? 'image/webp' : 'image/jpeg';
  await file.save(imageBuffer, {
    contentType,
    metadata: { metadata: { firebaseStorageDownloadTokens: token } },
  });

  const encoded = encodeURIComponent(storagePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token}`;
}

async function processPreset(doc) {
  const data = doc.data();
  const title = data.title || doc.id;
  const prompt = data.prompt;

  if (!prompt) {
    console.log(`  ✗ ${title}: нет промпта`);
    return false;
  }

  try {
    process.stdout.write(`  ⏳ ${title}: генерация`);
    const taskId = await createPiApiTask(prompt);
    const imageUrl = await pollTask(taskId);
    console.log(' скачивание...');

    const imageBuffer = await downloadImage(imageUrl);

    const jpegBuffer = await sharp(imageBuffer)
      .jpeg({ quality: 90 })
      .toBuffer();

    const thumbnailBuffer = await sharp(imageBuffer)
      .resize(THUMBNAIL_WIDTH, null, { withoutEnlargement: true })
      .webp({ quality: THUMBNAIL_QUALITY })
      .toBuffer();

    const previewUrl = await uploadToStorage(doc.id, jpegBuffer);
    const thumbnailUrl = await uploadToStorage(doc.id, thumbnailBuffer, 'thumb');

    await doc.ref.update({ previewImageUrl: previewUrl, thumbnailUrl });

    console.log(`  ✓ ${title}`);
    return true;
  } catch (error) {
    console.log(`\n  ✗ ${title}: ${error.message}`);
    return false;
  }
}

async function main() {
  console.log('Regenerate Broken Presets — старт\n');

  const snapshot = await db.collection('presets').get();
  const broken = [];

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!data.previewImageUrl || data.thumbnailUrl) continue;

    try {
      const resp = await fetch(data.previewImageUrl, { method: 'HEAD' });
      if (!resp.ok) broken.push(doc);
    } catch {
      broken.push(doc);
    }
  }

  console.log(`Найдено сломанных пресетов: ${broken.length}\n`);

  if (broken.length === 0) {
    console.log('Все пресеты в порядке!');
    process.exit(0);
  }

  broken.forEach((doc, i) => {
    console.log(`  ${i + 1}. ${doc.data().title || doc.id}`);
  });
  console.log('');

  let success = 0;
  let failed = 0;

  for (const doc of broken) {
    const ok = await processPreset(doc);
    if (ok) success++;
    else failed++;
  }

  console.log(`\nГотово! Успешно: ${success}, ошибок: ${failed}`);
  process.exit(0);
}

main().catch(err => {
  console.error('Критическая ошибка:', err);
  process.exit(1);
});
