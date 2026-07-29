const admin = require('firebase-admin');
const sharp = require('sharp');
const crypto = require('crypto');
const path = require('path');

const THUMBNAIL_WIDTH = 400;
const THUMBNAIL_QUALITY = 80;

const serviceAccountPath = path.join(__dirname, 'service-account.json');

try {
  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    storageBucket: `${serviceAccount.project_id}.firebasestorage.app`,
  });
} catch (e) {
  console.error(`\n  Не найден файл: ${serviceAccountPath}`);
  console.error('  Скачайте его из Firebase Console:');
  console.error('  Project Settings → Service accounts → Generate new private key\n');
  process.exit(1);
}

const db = admin.firestore();
const bucket = admin.storage().bucket();

async function createThumbnail(presetId, previewImageUrl) {
  const response = await fetch(previewImageUrl);
  if (!response.ok) {
    throw new Error(`Download failed: ${response.status} ${response.statusText}`);
  }

  const imageBuffer = Buffer.from(await response.arrayBuffer());

  const thumbnail = await sharp(imageBuffer)
    .resize(THUMBNAIL_WIDTH, null, { withoutEnlargement: true })
    .webp({ quality: THUMBNAIL_QUALITY })
    .toBuffer();

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

async function main() {
  console.log('Backfill Thumbnails — старт\n');

  const snapshot = await db.collection('presets').get();
  console.log(`Всего пресетов в БД: ${snapshot.docs.length}`);

  const toProcess = snapshot.docs.filter(doc => {
    const data = doc.data();
    return data.previewImageUrl && !data.thumbnailUrl;
  });

  console.log(`Без thumbnail: ${toProcess.length}\n`);

  if (toProcess.length === 0) {
    console.log('Все пресеты уже имеют thumbnail. Готово!');
    process.exit(0);
  }

  let success = 0;
  let failed = 0;
  const CONCURRENCY = 5;

  for (let i = 0; i < toProcess.length; i += CONCURRENCY) {
    const batch = toProcess.slice(i, i + CONCURRENCY);
    const promises = batch.map(async (doc) => {
      const data = doc.data();
      const label = data.title || doc.id;
      try {
        const thumbnailUrl = await createThumbnail(doc.id, data.previewImageUrl);
        await doc.ref.update({ thumbnailUrl });
        console.log(`  ✓ ${label}`);
        return true;
      } catch (error) {
        console.error(`  ✗ ${label}: ${error.message}`);
        return false;
      }
    });

    const results = await Promise.all(promises);
    success += results.filter(Boolean).length;
    failed += results.filter(r => !r).length;

    console.log(`  [${Math.min(i + CONCURRENCY, toProcess.length)}/${toProcess.length}]`);
  }

  console.log(`\nГотово! Обработано: ${success}, ошибок: ${failed}`);
  process.exit(0);
}

main().catch(err => {
  console.error('Критическая ошибка:', err);
  process.exit(1);
});
