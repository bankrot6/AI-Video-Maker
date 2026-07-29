#!/usr/bin/env node
/**
 * Сравнение количества документов: Firestore (Firebase) vs Appwrite.
 * Запуск из корня репозитория: node scripts/compare_db_counts.mjs
 */

import { initializeApp } from 'firebase/app';
import {
  getFirestore,
  collection,
  getCountFromServer,
  getDocs,
  limit,
  query,
  startAfter,
} from 'firebase/firestore';
import { Client, Databases, Query } from 'node-appwrite';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

async function loadEnv() {
  const envPath = path.join(PROJECT_ROOT, '.env');
  const envContent = await fs.readFile(envPath, 'utf8');
  const env = {};
  for (const line of envContent.split('\n')) {
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

async function countFirestoreAggregate(firestore, name) {
  const snap = await getCountFromServer(collection(firestore, name));
  return snap.data().count;
}

/** Падение агрегата → постраничный обход (те же правила; иногда помогает другой путь). */
async function countFirestorePaged(firestore, name, pageSize = 500) {
  const col = collection(firestore, name);
  let total = 0;
  let lastDoc = null;
  for (;;) {
    const q = lastDoc
      ? query(col, startAfter(lastDoc), limit(pageSize))
      : query(col, limit(pageSize));
    const snap = await getDocs(q);
    total += snap.size;
    if (snap.size < pageSize) break;
    lastDoc = snap.docs[snap.docs.length - 1];
  }
  return total;
}

async function countFirestore(firestore, name) {
  try {
    return { ok: true, count: await countFirestoreAggregate(firestore, name) };
  } catch (e1) {
    const code = e1?.code || '';
    if (code === 'permission-denied' || String(e1).includes('PERMISSION_DENIED')) {
      try {
        const n = await countFirestorePaged(firestore, name);
        return { ok: true, count: n, note: 'через getDocs (агрегат запрещён правилами)' };
      } catch (e2) {
        return {
          ok: false,
          count: null,
          error: `${e1?.message || e1} | fallback: ${e2?.message || e2}`,
        };
      }
    }
    return { ok: false, count: null, error: e1?.message || String(e1) };
  }
}

async function countAppwrite(databases, databaseId, collectionId) {
  try {
    const res = await databases.listDocuments(databaseId, collectionId, [
      Query.limit(1),
    ]);
    return { ok: true, total: res.total, error: null };
  } catch (e) {
    return { ok: false, total: null, error: e?.message || String(e) };
  }
}

async function main() {
  const env = await loadEnv();

  const firebaseConfig = {
    apiKey: env.FIREBASE_API_KEY,
    authDomain: env.FIREBASE_AUTH_DOMAIN,
    projectId: env.FIREBASE_PROJECT_ID,
    storageBucket: env.FIREBASE_STORAGE_BUCKET,
    messagingSenderId: env.FIREBASE_MESSAGING_SENDER_ID,
    appId: env.FIREBASE_APP_ID,
  };

  const appwriteEndpoint = (env.APPWRITE_ENDPOINT || '').trim();
  const appwriteProject = (env.APPWRITE_PROJECT_ID || '').trim();
  const appwriteKey = (env.APPWRITE_API_KEY || '').trim();
  const appwriteDatabase =
    (env.APPWRITE_DATABASE_ID || '').trim() || 'photosession_db';
  const presetsCollection =
    (env.APPWRITE_PRESETS_COLLECTION_ID || '').trim() || 'presets';
  const generationsCollection =
    (env.APPWRITE_GENERATIONS_COLLECTION_ID || '').trim() || 'user_generations';

  const missingFb = Object.entries(firebaseConfig)
    .filter(([, v]) => !v)
    .map(([k]) => k);
  if (missingFb.length) {
    console.error('Не хватает переменных Firebase в .env:', missingFb.join(', '));
    process.exit(1);
  }

  if (!appwriteEndpoint || !appwriteProject || !appwriteKey) {
    console.error(
      'Для Appwrite нужны APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY в .env',
    );
    process.exit(1);
  }

  const firebaseApp = initializeApp(firebaseConfig);
  const firestore = getFirestore(firebaseApp);

  const client = new Client()
    .setEndpoint(appwriteEndpoint)
    .setProject(appwriteProject)
    .setKey(appwriteKey);
  const databases = new Databases(client);

  const fbPresets = await countFirestore(firestore, 'presets');
  const fbGens = await countFirestore(firestore, 'user_generations');

  const awPresets = await countAppwrite(
    databases,
    appwriteDatabase,
    presetsCollection,
  );
  const awGens = await countAppwrite(
    databases,
    appwriteDatabase,
    generationsCollection,
  );

  const fbP = fbPresets.ok ? String(fbPresets.count) : `ОШИБКА: ${fbPresets.error}`;
  const fbG = fbGens.ok ? String(fbGens.count) : `ОШИБКА: ${fbGens.error}`;
  const awP = awPresets.ok ? String(awPresets.total) : `ОШИБКА: ${awPresets.error}`;
  const awG = awGens.ok ? String(awGens.total) : `ОШИБКА: ${awGens.error}`;

  console.log('');
  console.log('Коллекция          | Firebase (Firestore) | Appwrite');
  console.log('-------------------|----------------------|----------');
  console.log(`presets            | ${fbP.padEnd(20)} | ${awP}`);
  console.log(`user_generations   | ${fbG.padEnd(20)} | ${awG}`);
  console.log('');
  if (fbPresets.note) console.log('Firebase presets:', fbPresets.note);
  if (fbGens.note) console.log('Firebase user_generations:', fbGens.note);
  console.log('Appwrite DB:', appwriteDatabase);
  console.log('Appwrite presets collection:', presetsCollection);
  console.log('Appwrite generations collection:', generationsCollection);
  console.log('Firebase project:', env.FIREBASE_PROJECT_ID);
  console.log('');

  if (!awPresets.ok || !awGens.ok) {
    console.log('Appwrite: не удалось получить total по одной из коллекций.');
    process.exit(1);
  }

  if (!fbPresets.ok || !fbGens.ok) {
    console.log(
      'Firestore: часть запросов отклонена правилами (read). Для полного сравнения откройте чтение коллекций или используйте Admin SDK.',
    );
  }

  if (fbPresets.ok && awPresets.ok) {
    const dPresets = fbPresets.count - awPresets.total;
    if (dPresets === 0) {
      console.log('presets: количество совпадает.');
    } else {
      console.log(
        `presets: разница ${Math.abs(dPresets)} — ${dPresets > 0 ? 'в Firebase больше' : 'в Appwrite больше'} (Firebase ${fbPresets.count}, Appwrite ${awPresets.total}).`,
      );
    }
  }

  if (fbGens.ok && awGens.ok) {
    const dGens = fbGens.count - awGens.total;
    if (dGens === 0) {
      console.log('user_generations: количество совпадает.');
    } else {
      console.log(
        `user_generations: разница ${Math.abs(dGens)} — ${dGens > 0 ? 'в Firebase больше' : 'в Appwrite больше'} (Firebase ${fbGens.count}, Appwrite ${awGens.total}).`,
      );
    }
  }

  if (fbPresets.ok && fbGens.ok && awPresets.ok && awGens.ok) {
    const dP = fbPresets.count - awPresets.total;
    const dG = fbGens.count - awGens.total;
    if (dP === 0 && dG === 0) {
      console.log('\nИтог: обе коллекции совпадают по количеству.');
    }
  }

  console.log(
    '\nПримечание: сверяется только total; дубликаты по ID между БД скрипт не ищет.',
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
