#!/usr/bin/env node
/**
 * Приводит Firestore к набору id как в Appwrite (1:1 по ключам):
 *  - presets: удаляет документы Firestore, которых нет в Appwrite (лишние 299 и т.п.).
 *    Два пресета в FB с одним preview, из которых один есть в AW — «лишний» тоже
 *    без id в AW и попадёт в этот список.
 *
 *  Опция --generations: то же для user_generations (удалит только-FB генерации).
 *
 *  По умолчанию DRY-RUN. Запись:
 *    node prune_firestore_to_appwrite_1to1.mjs --execute
 *    node prune_firestore_to_appwrite_1to1.mjs --execute --generations
 *
 *  Список id в файл:
 *    node prune_firestore_to_appwrite_1to1.mjs --out=./prune-plan.json
 *
 *  Только «тени» из отчёта match_firestore_only_presets_to_appwrite (--write-deletes):
 *    node match_firestore_only_presets_to_appwrite.mjs --write-deletes=./fb-shadows.json
 *    node prune_firestore_to_appwrite_1to1.mjs --only-from-json=./fb-shadows.json --execute
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import admin from 'firebase-admin';
import { Client, Databases, Query } from 'node-appwrite';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

function parseArgs(argv) {
  const execute = argv.includes('--execute');
  const generations = argv.includes('--generations');
  let outPath = null;
  let onlyFromJson = null;
  for (const a of argv) {
    if (a.startsWith('--out=')) outPath = a.slice('--out='.length).trim();
    if (a.startsWith('--only-from-json='))
      onlyFromJson = a.slice('--only-from-json='.length).trim();
  }
  return { execute, generations, outPath, onlyFromJson };
}

function readPresetIdsFromJsonFile(absPath) {
  const raw = fs.readFileSync(absPath, 'utf8');
  const data = JSON.parse(raw);
  if (Array.isArray(data)) return data.map(String);
  if (data.presetIds && Array.isArray(data.presetIds))
    return data.presetIds.map(String);
  throw new Error(
    'JSON: ожидается массив id или объект { "presetIds": [...] }',
  );
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
  for (const rel of [
    'firebase-service-account.json',
    path.join('tool', 'firebase-service-account.json'),
    path.join('secrets', 'firebase-service-account.json'),
  ]) {
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
    if (match) return path.join(dir, match);
  }
  return null;
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

async function batchDelete(db, collectionName, ids, execute) {
  const coll = db.collection(collectionName);
  const chunk = 400;
  let done = 0;
  for (let i = 0; i < ids.length; i += chunk) {
    const slice = ids.slice(i, i + chunk);
    if (!execute) {
      done += slice.length;
      continue;
    }
    const batch = db.batch();
    for (const id of slice) {
      batch.delete(coll.doc(id));
    }
    await batch.commit();
    done += slice.length;
  }
  return done;
}

async function main() {
  const { execute, generations, outPath, onlyFromJson } = parseArgs(
    process.argv.slice(2),
  );
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

  if (!appwriteEndpoint || !appwriteProject || !appwriteKey) {
    console.error('Нужны APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY');
    process.exit(1);
  }

  const saPath = resolveServiceAccountPath(env);
  if (!saPath) {
    console.error('Нет Firebase service account JSON.');
    process.exit(1);
  }

  const client = new Client()
    .setEndpoint(appwriteEndpoint)
    .setProject(appwriteProject)
    .setKey(appwriteKey);
  const databases = new Databases(client);

  const serviceAccount = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }
  const db = admin.firestore();

  const plan = {
    mode: execute ? 'execute' : 'dry-run',
    presets: { deleteIdsNotInAppwrite: [] },
    generations: { deleteIdsNotInAppwrite: [] },
  };

  const awPresets = await fetchAllAppwriteDocuments(
    databases,
    appwriteDatabase,
    presetsCollection,
  );
  const awPresetIds = new Set(awPresets.map((d) => d.$id));

  let presetDeleteList;

  if (onlyFromJson) {
    const abs = path.isAbsolute(onlyFromJson)
      ? onlyFromJson
      : path.join(process.cwd(), onlyFromJson);
    if (!fs.existsSync(abs)) {
      console.error('Файл не найден:', abs);
      process.exit(1);
    }
    const fromFile = readPresetIdsFromJsonFile(abs);
    const bad = fromFile.filter((id) => awPresetIds.has(id));
    if (bad.length) {
      console.error(
        'В списке есть id, которые УЖЕ есть в Appwrite (удалять нельзя):',
        bad.slice(0, 20).join(', '),
      );
      process.exit(1);
    }
    presetDeleteList = [...new Set(fromFile)].sort();
    plan.presets.deleteIdsNotInAppwrite = presetDeleteList;
    plan.presets.source = `only-from-json:${abs}`;
  } else {
    const fbPresetSnap = await db.collection('presets').get();
    const orphanPresetIds = fbPresetSnap.docs
      .map((d) => d.id)
      .filter((id) => !awPresetIds.has(id));
    plan.presets.deleteIdsNotInAppwrite = orphanPresetIds.sort();
    presetDeleteList = [...plan.presets.deleteIdsNotInAppwrite];
  }

  if (generations) {
    const awGens = await fetchAllAppwriteDocuments(
      databases,
      appwriteDatabase,
      generationsCollection,
    );
    const awGenIds = new Set(awGens.map((d) => d.$id));
    const fbGenSnap = await db.collection('user_generations').get();
    plan.generations.deleteIdsNotInAppwrite = fbGenSnap.docs
      .map((d) => d.id)
      .filter((id) => !awGenIds.has(id))
      .sort();
  }

  console.log(
    execute
      ? '\n[EXECUTE] Удаление из Firestore\n'
      : '\n[DRY-RUN] Удалений нет. Добавьте --execute\n',
  );

  console.log('--- presets ---');
  if (onlyFromJson) {
    console.log(
      `Режим --only-from-json: удалить указанные id (все отсутствуют в Appwrite): ${presetDeleteList.length}`,
    );
  } else {
    console.log(
      `Удалить документы FB без пары в Appwrite: ${plan.presets.deleteIdsNotInAppwrite.length}`,
    );
  }

  if (generations) {
    console.log('\n--- user_generations ---');
    console.log(
      `Удалить документы FB без пары в Appwrite: ${plan.generations.deleteIdsNotInAppwrite.length}`,
    );
  }

  if (outPath) {
    const abs = path.isAbsolute(outPath)
      ? outPath
      : path.join(PROJECT_ROOT, outPath);
    await fs.promises.writeFile(abs, JSON.stringify(plan, null, 2), 'utf8');
    console.log(`\nПлан записан: ${abs}`);
  }

  if (execute) {
    console.log('\nВыполняю удаление presets…');
    const n = await batchDelete(db, 'presets', presetDeleteList, true);
    console.log(`  удалено документов presets: ${n}`);

    if (generations) {
      console.log('\nВыполняю удаление user_generations…');
      const m = await batchDelete(
        db,
        'user_generations',
        plan.generations.deleteIdsNotInAppwrite,
        true,
      );
      console.log(`  удалено документов user_generations: ${m}`);
    }
  } else {
    console.log(`\nВсего уникальных id presets к удалению: ${presetDeleteList.length}`);
    console.log('Первые 25:', presetDeleteList.slice(0, 25).join(', ') || '(нет)');
    if (generations) {
      console.log(
        'Первые 25 (generations):',
        plan.generations.deleteIdsNotInAppwrite.slice(0, 25).join(', ') ||
          '(нет)',
      );
    }
    console.log('\nДля выполнения: node prune_firestore_to_appwrite_1to1.mjs --execute');
    if (generations) {
      console.log('(добавьте --generations для генераций)');
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
