#!/usr/bin/env node
/**
 * Копирует изображения из внешних URL (Appwrite Storage и т.п.) в Firebase Storage
 * и обновляет поля в Firestore: presets (previewImageUrl, thumbnailUrl),
 * user_generations (userImageUrl, resultImageUrl, referenceImageUrl).
 *
 * URL уже на firebasestorage.googleapis.com пропускаются.
 * Локальные пути (/data/...) пропускаются с предупреждением.
 *
 * Запуск из корня репозитория:
 *   cd scripts && npm install && node migrate_remote_images_to_firebase_storage.mjs
 *
 * По умолчанию dry-run. Запись: --execute
 *   --presets-only | --generations-only
 *   --limit=50
 */

import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import admin from 'firebase-admin';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

function parseArgs(argv) {
  const dryRun = !argv.includes('--execute');
  let presetsOnly = argv.includes('--presets-only');
  let generationsOnly = argv.includes('--generations-only');
  let limit = 0;
  for (const a of argv) {
    if (a.startsWith('--limit=')) {
      const n = parseInt(a.slice('--limit='.length), 10);
      if (Number.isFinite(n) && n > 0) limit = n;
    }
  }
  if (presetsOnly && generationsOnly) generationsOnly = false;
  return { dryRun, presetsOnly, generationsOnly, limit };
}

async function loadEnv() {
  const envPath = path.join(PROJECT_ROOT, '.env');
  const raw = await fs.promises.readFile(envPath, 'utf8');
  const env = {};
  for (const line of raw.split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq <= 0) continue;
    const key = t.slice(0, eq).trim();
    let val = t.slice(eq + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    env[key] = val;
  }
  return env;
}

function tryFile(p) {
  if (!p) return null;
  const resolved = path.isAbsolute(p) ? p : path.join(PROJECT_ROOT, p);
  return fs.existsSync(resolved) ? resolved : null;
}

function resolveServiceAccountPath(env) {
  const fromEnv = [
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH?.trim(),
    process.env.GOOGLE_APPLICATION_CREDENTIALS?.trim(),
    env.FIREBASE_SERVICE_ACCOUNT_PATH?.trim(),
    env.GOOGLE_APPLICATION_CREDENTIALS?.trim(),
  ];
  for (const raw of fromEnv) {
    const hit = tryFile(raw);
    if (hit) return hit;
  }
  const fixedCandidates = [
    'firebase-service-account.json',
    path.join('tool', 'firebase-service-account.json'),
    path.join('secrets', 'firebase-service-account.json'),
  ];
  for (const rel of fixedCandidates) {
    const hit = tryFile(rel);
    if (hit) return hit;
  }
  const adminSdkRe = /^[a-z0-9-]+-firebase-adminsdk-[a-z0-9]+\.json$/i;
  for (const dirRel of ['secrets', '.']) {
    const dir = path.join(PROJECT_ROOT, dirRel);
    if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) continue;
    let names;
    try {
      names = fs.readdirSync(dir);
    } catch {
      continue;
    }
    const match = names.find((n) => adminSdkRe.test(n));
    if (match) {
      const hit = path.join(dir, match);
      if (fs.existsSync(hit)) return hit;
    }
  }
  return null;
}

function appwriteStorageHint(url, env) {
  if (!url || typeof url !== 'string') return false;
  if (url.includes('/v1/storage/buckets/')) return true;
  const ep = (env.APPWRITE_ENDPOINT || '').trim();
  if (!ep) return false;
  try {
    const host = new URL(ep).hostname;
    return host && url.includes(host);
  } catch {
    return false;
  }
}

function isFirebaseStorageDownloadUrl(url) {
  if (!url || typeof url !== 'string') return false;
  return url.includes('firebasestorage.googleapis.com');
}

function shouldMigrateHttpUrl(url, env) {
  const u = url.trim();
  if (!u.startsWith('http://') && !u.startsWith('https://')) return false;
  if (isFirebaseStorageDownloadUrl(u)) return false;
  return appwriteStorageHint(u, env);
}

async function downloadBytes(url) {
  const res = await fetch(url, {
    redirect: 'follow',
    headers: { Accept: 'image/*,*/*' },
  });
  if (!res.ok) {
    throw new Error(`GET ${url.slice(0, 80)}… → ${res.status}`);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  if (!buf.length) throw new Error('empty body');
  return buf;
}

function guessContentType(url) {
  const lower = url.toLowerCase();
  if (lower.includes('.png')) return 'image/png';
  if (lower.includes('.webp')) return 'image/webp';
  return 'image/jpeg';
}

async function uploadWithDownloadToken(bucket, storagePath, buffer, contentType) {
  const file = bucket.file(storagePath);
  const token = crypto.randomBytes(32).toString('hex');
  await file.save(buffer, {
    resumable: false,
    metadata: {
      contentType,
      metadata: {
        firebaseStorageDownloadTokens: token,
      },
    },
  });
  const encoded = encodeURIComponent(storagePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token}`;
}

const DRY_RUN_SENTINEL = Symbol('dryRun');

async function migrateUrlField(
  env,
  bucket,
  docId,
  collection,
  field,
  currentUrl,
  dryRun,
) {
  if (!currentUrl || typeof currentUrl !== 'string') return null;
  if (currentUrl.startsWith('/')) {
    console.warn(`  [skip] ${collection}/${docId} ${field}: локальный путь`);
    return null;
  }
  if (!shouldMigrateHttpUrl(currentUrl, env)) return null;

  if (dryRun) {
    console.log(`  [dry-run] ${collection}/${docId} ${field}`);
    return DRY_RUN_SENTINEL;
  }

  const bytes = await downloadBytes(currentUrl);
  const safeId = String(docId).replace(/[^\w-]+/g, '_').slice(0, 80);
  const dest = `user-photos/migrated_${collection}_${safeId}_${field}_${Date.now()}.jpg`;
  const ct = guessContentType(currentUrl);
  const newUrl = await uploadWithDownloadToken(bucket, dest, bytes, ct);
  console.log(`  [ok] ${collection}/${docId} ${field} (${bytes.length} B)`);
  return newUrl;
}

async function main() {
  const { dryRun, presetsOnly, generationsOnly, limit } = parseArgs(
    process.argv.slice(2),
  );
  const env = await loadEnv();
  const saPath = resolveServiceAccountPath(env);
  if (!saPath) {
    console.error('Нет ключа Firebase Admin (см. sync_appwrite_missing_to_firebase.mjs).');
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  const projectId = serviceAccount.project_id;
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }

  const bucketNameRaw =
    (env.FIREBASE_STORAGE_BUCKET || '').trim() || `${projectId}.appspot.com`;
  const bucketName = bucketNameRaw.replace(/^gs:\/\//, '');
  const bucket = admin.storage().bucket(bucketName);
  const db = admin.firestore();

  console.log(
    dryRun
      ? '\n[DRY-RUN] Без загрузок и без записи в Storage/Firestore\n'
      : '\n[EXECUTE] Загрузка в Firebase Storage и merge в Firestore\n',
  );
  console.log(`Bucket: ${bucket.name}`);

  let fieldsTouched = 0;

  const runPresets = !generationsOnly;
  const runGens = !presetsOnly;

  async function processCollection(collectionId, fields) {
    const snap = await db.collection(collectionId).get();
    let docsDone = 0;
    for (const doc of snap.docs) {
      if (limit > 0 && docsDone >= limit) break;
      const data = doc.data() || {};
      const patch = {};
      let anyWouldMigrate = false;
      for (const field of fields) {
        const cur = data[field];
        if (!cur || typeof cur !== 'string') continue;
        if (cur.startsWith('/')) {
          console.warn(
            `  [skip] ${collectionId}/${doc.id} ${field}: локальный путь`,
          );
          continue;
        }
        if (!shouldMigrateHttpUrl(cur, env)) continue;
        anyWouldMigrate = true;
        try {
          const next = await migrateUrlField(
            env,
            bucket,
            doc.id,
            collectionId,
            field,
            cur,
            dryRun,
          );
          if (next === DRY_RUN_SENTINEL) {
            fieldsTouched += 1;
          } else if (next != null && typeof next === 'string' && next !== cur) {
            patch[field] = next;
            fieldsTouched += 1;
          }
        } catch (e) {
          console.warn(`  ${collectionId}/${doc.id} ${field}: ${e.message || e}`);
        }
      }
      if (!anyWouldMigrate) continue;
      docsDone += 1;
      if (Object.keys(patch).length && !dryRun) {
        patch.migratedImagesToFirebaseAt =
          admin.firestore.FieldValue.serverTimestamp();
        await doc.ref.set(patch, { merge: true });
      }
    }
  }

  if (runPresets) {
    console.log('\n=== presets ===');
    await processCollection('presets', ['previewImageUrl', 'thumbnailUrl']);
  }

  if (runGens) {
    console.log('\n=== user_generations ===');
    await processCollection('user_generations', [
      'userImageUrl',
      'resultImageUrl',
      'referenceImageUrl',
    ]);
  }

  console.log(
    dryRun
      ? `\nDry-run: полей к миграции (оценка): ${fieldsTouched}. Запись: добавьте --execute`
      : `\nГотово. Обновлено полей изображений: ${fieldsTouched}`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
