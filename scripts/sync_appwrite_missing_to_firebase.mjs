#!/usr/bin/env node
/**
 * Копирует в Firestore документы, которые есть в Appwrite, но отсутствуют в Firebase.
 * Сохраняет deviceId, ownerId, likedBy, likesCount — тот же «ключ пользователя», что в приложении.
 *
 * Требуется сервисный аккаунт Firebase (обход правил Firestore):
 *   export FIREBASE_SERVICE_ACCOUNT_PATH=/path/to/serviceAccount.json
 * или GOOGLE_APPLICATION_CREDENTIALS
 *
 * Запуск из корня репозитория:
 *   cd scripts && npm install && node sync_appwrite_missing_to_firebase.mjs
 *
 * По умолчанию dry-run. Запись: добавьте --execute
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import admin from 'firebase-admin';
import { Client, Databases, Query } from 'node-appwrite';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

function parseArgs(argv) {
  const dryRun = !argv.includes('--execute');
  const presetsOnly = argv.includes('--presets-only');
  const generationsOnly = argv.includes('--generations-only');
  return { dryRun, presetsOnly, generationsOnly };
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

function stripAppwriteMeta(doc) {
  const {
    $id,
    $sequence,
    $permissions,
    $createdAt,
    $updatedAt,
    $databaseId,
    $collectionId,
    ...data
  } = doc;
  return { id: $id, $createdAt, ...data };
}

function presetForFirestore(doc) {
  const d = stripAppwriteMeta(doc);
  const createdAt =
    d.createdAt || d.$createdAt || new Date().toISOString();
  const likedBy = Array.isArray(d.likedBy)
    ? d.likedBy.filter((x) => typeof x === 'string')
    : [];
  const tags = Array.isArray(d.tags)
    ? d.tags.filter((x) => typeof x === 'string')
    : [];
  let likesCount =
    typeof d.likesCount === 'number'
      ? d.likesCount
      : parseInt(String(d.likesCount ?? ''), 10);
  if (!Number.isFinite(likesCount)) likesCount = 0;
  if (likesCount === 0 && likedBy.length) likesCount = likedBy.length;

  const out = {
    prompt: String(d.prompt ?? ''),
    previewImageUrl: String(d.previewImageUrl ?? ''),
    title: d.title != null && String(d.title).length > 0 ? String(d.title) : null,
    tags,
    createdAt: String(createdAt),
    ownerId: d.ownerId != null && String(d.ownerId).length > 0 ? String(d.ownerId) : null,
    isPublic: Boolean(d.isPublic),
    likesCount,
    likedBy,
    accountKeyDeviceId:
      d.ownerId != null && String(d.ownerId).length > 0 ? String(d.ownerId) : null,
    _syncSource: 'appwrite',
    _appwriteId: String(d.id ?? ''),
    migratedFromAppwriteAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (d.thumbnailUrl != null && String(d.thumbnailUrl).length > 0) {
    out.thumbnailUrl = String(d.thumbnailUrl);
  }
  return out;
}

function generationForFirestore(doc) {
  const d = stripAppwriteMeta(doc);
  const createdAt =
    d.createdAt || d.$createdAt || new Date().toISOString();
  const out = {
    presetId: String(d.presetId ?? ''),
    userImageUrl: String(d.userImageUrl ?? ''),
    resultImageUrl: String(d.resultImageUrl ?? ''),
    deviceId: String(d.deviceId ?? ''),
    createdAt: String(createdAt),
    accountKeyDeviceId: String(d.deviceId ?? ''),
    _syncSource: 'appwrite',
    _appwriteId: String(d.id ?? ''),
    migratedFromAppwriteAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (d.referenceImageUrl != null && String(d.referenceImageUrl).length > 0) {
    out.referenceImageUrl = String(d.referenceImageUrl);
  }
  return out;
}

async function fetchAllAppwriteDocuments(databases, databaseId, collectionId) {
  const out = [];
  let lastId = null;
  for (;;) {
    const queries = [Query.orderAsc('$id'), Query.limit(100)];
    if (lastId) queries.push(Query.cursorAfter(lastId));
    const res = await databases.listDocuments(databaseId, collectionId, queries);
    if (!res.documents.length) break;
    for (const doc of res.documents) out.push(doc);
    lastId = res.documents[res.documents.length - 1].$id;
    if (res.documents.length < 100) break;
  }
  return out;
}

async function loadFirebaseIds(db, collectionName) {
  const snap = await db.collection(collectionName).get();
  return new Set(snap.docs.map((d) => d.id));
}

function tryFile(p) {
  if (!p) return null;
  const resolved = path.isAbsolute(p) ? p : path.join(PROJECT_ROOT, p);
  return fs.existsSync(resolved) ? resolved : null;
}

/**
 * Ищет JSON ключа сервисного аккаунта без обязательного .env:
 * 1) FIREBASE_SERVICE_ACCOUNT_PATH / GOOGLE_APPLICATION_CREDENTIALS (env или .env)
 * 2) ./firebase-service-account.json в корне репозитория (уже в .gitignore)
 * 3) ./tool/firebase-service-account.json
 * 4) ./secrets/firebase-service-account.json
 * 5) любой *-firebase-adminsdk-*.json в ./secrets или в корне
 */
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

function printServiceAccountHelp() {
  console.error(`
Не найден JSON ключ сервисного аккаунта Firebase (Admin SDK).

Сделайте один раз:
  1) Откройте https://console.firebase.google.com/
  2) Ваш проект → шестерёнка «Project settings»
  3) Вкладка «Service accounts» → «Generate new private key»
  4) Сохраните файл в КОРЕНЬ этого репозитория (рядом с pubspec.yaml) под именем:

       firebase-service-account.json

     Это имя уже в .gitignore — в git ключ не попадёт.

  Альтернатива: положите тот же JSON в папку secrets/ или назовите как скачал Firebase
  (…-firebase-adminsdk-….json) — скрипт подхватит автоматически.

  Или в .env добавьте одну строку (путь от корня репо):
       FIREBASE_SERVICE_ACCOUNT_PATH=./secrets/мой-ключ.json
`);
}

async function main() {
  const { dryRun, presetsOnly, generationsOnly } = parseArgs(process.argv.slice(2));
  const env = await loadEnv();

  const appwriteEndpoint = (env.APPWRITE_ENDPOINT || '').trim();
  const appwriteProject = (env.APPWRITE_PROJECT_ID || '').trim();
  const appwriteKey = (env.APPWRITE_API_KEY || '').trim();
  const appwriteDatabase =
    (env.APPWRITE_DATABASE_ID || '').trim() || 'main';
  const presetsCollection =
    (env.APPWRITE_PRESETS_COLLECTION_ID || '').trim() || 'presets';
  const generationsCollection =
    (env.APPWRITE_GENERATIONS_COLLECTION_ID || '').trim() || 'user_generations';

  const saPath = resolveServiceAccountPath(env);
  if (!saPath) {
    printServiceAccountHelp();
    process.exit(1);
  }
  console.log('Используется ключ:', saPath);

  if (!appwriteEndpoint || !appwriteProject || !appwriteKey) {
    console.error('Нужны APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY в .env');
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }
  const db = admin.firestore();

  const client = new Client()
    .setEndpoint(appwriteEndpoint)
    .setProject(appwriteProject)
    .setKey(appwriteKey);
  const databases = new Databases(client);

  console.log(
    dryRun
      ? '\n[DRY-RUN] Запись отключена. Для копирования добавьте --execute\n'
      : '\n[EXECUTE] Запись в Firestore включена\n',
  );

  let presetsCopied = 0;
  let gensCopied = 0;

  if (!generationsOnly) {
    console.log('Загрузка пресетов из Appwrite…');
    const awPresets = await fetchAllAppwriteDocuments(
      databases,
      appwriteDatabase,
      presetsCollection,
    );
    const fbIds = await loadFirebaseIds(db, 'presets');
    const missing = awPresets.filter((d) => !fbIds.has(d.$id));
    console.log(
      `  Appwrite: ${awPresets.length}, Firebase: ${fbIds.size}, отсутствуют в Firebase: ${missing.length}`,
    );
    for (const doc of missing) {
      const payload = presetForFirestore(doc);
      if (dryRun) {
        console.log(`  [dry-run] preset ${doc.$id}`);
      } else {
        await db.collection('presets').doc(doc.$id).set(payload, { merge: false });
        presetsCopied += 1;
      }
    }
  }

  if (!presetsOnly) {
    console.log('Загрузка генераций из Appwrite…');
    const awGens = await fetchAllAppwriteDocuments(
      databases,
      appwriteDatabase,
      generationsCollection,
    );
    const fbGenIds = await loadFirebaseIds(db, 'user_generations');
    const missingG = awGens.filter((d) => !fbGenIds.has(d.$id));
    console.log(
      `  Appwrite: ${awGens.length}, Firebase: ${fbGenIds.size}, отсутствуют в Firebase: ${missingG.length}`,
    );
    for (const doc of missingG) {
      const payload = generationForFirestore(doc);
      if (!payload.deviceId) {
        console.warn(`  пропуск ${doc.$id}: нет deviceId`);
        continue;
      }
      if (dryRun) {
        console.log(`  [dry-run] generation ${doc.$id} deviceId=${payload.deviceId.slice(0, 12)}…`);
      } else {
        await db
          .collection('user_generations')
          .doc(doc.$id)
          .set(payload, { merge: false });
        gensCopied += 1;
      }
    }
  }

  console.log('\nИтог:');
  if (dryRun) {
    console.log('  Dry-run завершён. Повторите с --execute для записи.');
  } else {
    console.log(`  Скопировано пресетов: ${presetsCopied}`);
    console.log(`  Скопировано генераций: ${gensCopied}`);
  }
  console.log(
    '\nКлиент ищет генерации по полю deviceId (как и раньше). Новые записи также получают firebaseUid.',
  );
  console.log(
    'Задеплойте обновлённые firestore.rules (проверка firebaseUid на update/delete).\n',
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
