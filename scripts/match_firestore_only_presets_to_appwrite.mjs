#!/usr/bin/env node
/**
 * Автоматически классифицирует пресеты, которые есть в Firestore, но нет в Appwrite:
 *  - совпадение по точному нормализованному prompt
 *  - совпадение по точному previewImageUrl (после trim)
 *  - совпадение по id файла в Appwrite Storage (/files/<id>/) в preview или thumbnail
 *
 * Выход: консоль + JSON (--out=...).
 * --write-deletes=path.json — только fb-id с единственным однозначным совпадением в AW
 *   (безопасные «тени» для удаления из Firestore после твоей проверки).
 *
 *   cd scripts && node match_firestore_only_presets_to_appwrite.mjs
 *   node match_firestore_only_presets_to_appwrite.mjs --out=./fb-only-match-report.json
 *   node match_firestore_only_presets_to_appwrite.mjs --write-deletes=./fb-only-safe-delete-ids.json
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import admin from 'firebase-admin';
import { Client, Databases, Query } from 'node-appwrite';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

function parseArgs(argv) {
  let outPath = null;
  let writeDeletes = null;
  for (const a of argv) {
    if (a.startsWith('--out=')) outPath = a.slice('--out='.length).trim();
    if (a.startsWith('--write-deletes='))
      writeDeletes = a.slice('--write-deletes='.length).trim();
  }
  return { outPath, writeDeletes };
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

function normalizePrompt(p) {
  return String(p ?? '')
    .trim()
    .replace(/\s+/g, ' ');
}

function trimUrl(u) {
  return String(u ?? '').trim();
}

/** Все вхождения fileId из путей Appwrite Storage в строке */
function collectAppwriteStorageFileIds(url) {
  const s = String(url);
  const re = /\/files\/([^/]+)\/(view|preview)/g;
  const ids = [];
  let m;
  while ((m = re.exec(s)) !== null) {
    ids.push(m[1]);
  }
  return ids;
}

function invertMap(keyToIds) {
  const map = new Map();
  for (const [key, ids] of keyToIds) {
    if (!key) continue;
    if (!map.has(key)) map.set(key, []);
    for (const id of ids) {
      if (!map.get(key).includes(id)) map.get(key).push(id);
    }
  }
  return map;
}

function buildAwIndexes(awDocs) {
  const promptKey = new Map();
  const previewKey = new Map();
  const fileIdToAwIds = new Map();

  for (const doc of awDocs) {
    const id = doc.$id;
    const pr = normalizePrompt(doc.prompt);
    if (pr) {
      if (!promptKey.has(pr)) promptKey.set(pr, []);
      promptKey.get(pr).push(id);
    }
    const pv = trimUrl(doc.previewImageUrl);
    if (pv) {
      if (!previewKey.has(pv)) previewKey.set(pv, []);
      previewKey.get(pv).push(id);
    }
    const th = trimUrl(doc.thumbnailUrl);
    if (th) {
      if (!previewKey.has(th)) previewKey.set(th, []);
      previewKey.get(th).push(id);
    }
    for (const u of [pv, th]) {
      for (const fid of collectAppwriteStorageFileIds(u)) {
        if (!fileIdToAwIds.has(fid)) fileIdToAwIds.set(fid, []);
        const arr = fileIdToAwIds.get(fid);
        if (!arr.includes(id)) arr.push(id);
      }
    }
  }

  return { promptKey, previewKey, fileIdToAwIds };
}

function classifyFbDoc(d, indexes) {
  const fbId = d.id;
  const pr = normalizePrompt(d.prompt);
  const pv = trimUrl(d.previewImageUrl);
  const th = trimUrl(d.thumbnailUrl);

  const reasons = [];

  if (pr) {
    const hits = indexes.promptKey.get(pr) || [];
    if (hits.length === 1) {
      reasons.push({
        kind: 'unique_prompt',
        awIds: [...hits],
        confidence: 'high',
      });
    } else if (hits.length > 1) {
      reasons.push({
        kind: 'ambiguous_prompt',
        awIds: [...hits],
        confidence: 'manual',
      });
    }
  }

  if (pv) {
    const hits = indexes.previewKey.get(pv) || [];
    if (hits.length === 1) {
      reasons.push({
        kind: 'unique_preview_url',
        awIds: [...hits],
        confidence: 'high',
      });
    } else if (hits.length > 1) {
      reasons.push({
        kind: 'ambiguous_preview_url',
        awIds: [...hits],
        confidence: 'manual',
      });
    }
  }

  const fileHits = new Set();
  for (const u of [pv, th]) {
    for (const fid of collectAppwriteStorageFileIds(u)) {
      const aw = indexes.fileIdToAwIds.get(fid) || [];
      for (const x of aw) fileHits.add(x);
    }
  }
  const fileArr = [...fileHits];
  if (fileArr.length === 1) {
    reasons.push({
      kind: 'appwrite_storage_file_id',
      awIds: fileArr,
      confidence: 'high',
    });
  } else if (fileArr.length > 1) {
    reasons.push({
      kind: 'ambiguous_appwrite_file_id',
      awIds: fileArr,
      confidence: 'manual',
    });
  }

  const high = reasons.filter((r) => r.confidence === 'high');
  const uniqueAw = new Set();
  for (const r of high) {
    for (const x of r.awIds) uniqueAw.add(x);
  }

  let verdict = 'no_match';
  let suggestedAwId = null;
  if (high.length) {
    if (uniqueAw.size === 1) {
      verdict = 'likely_duplicate_shadow';
      suggestedAwId = [...uniqueAw][0];
    } else {
      verdict = 'conflicting_signals';
      suggestedAwId = null;
    }
  }

  return {
    fbId,
    title: d.title ?? null,
    previewLen: pv.length,
    promptLen: pr.length,
    verdict,
    suggestedAwId,
    reasons,
  };
}

async function main() {
  const { outPath, writeDeletes } = parseArgs(process.argv.slice(2));
  const env = await loadEnv();

  const appwriteEndpoint = (env.APPWRITE_ENDPOINT || '').trim();
  const appwriteProject = (env.APPWRITE_PROJECT_ID || '').trim();
  const appwriteKey = (env.APPWRITE_API_KEY || '').trim();
  const appwriteDatabase =
    (env.APPWRITE_DATABASE_ID || '').trim() || 'main';
  const presetsCollection =
    (env.APPWRITE_PRESETS_COLLECTION_ID || '').trim() || 'presets';

  if (!appwriteEndpoint || !appwriteProject || !appwriteKey) {
    console.error('Нужны APPWRITE_* в .env');
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

  const awDocs = await fetchAllAppwriteDocuments(
    databases,
    appwriteDatabase,
    presetsCollection,
  );
  const awIds = new Set(awDocs.map((d) => d.$id));
  const indexes = buildAwIndexes(awDocs);

  const fbSnap = await db.collection('presets').get();
  const fbOnly = fbSnap.docs
    .filter((doc) => !awIds.has(doc.id))
    .map((doc) => ({ id: doc.id, ...doc.data() }));

  const rows = fbOnly.map((d) => classifyFbDoc(d, indexes));

  const summary = {
    firestoreOnlyCount: fbOnly.length,
    likelyDuplicateShadow: rows.filter(
      (r) => r.verdict === 'likely_duplicate_shadow',
    ).length,
    conflictingSignals: rows.filter((r) => r.verdict === 'conflicting_signals')
      .length,
    noMatch: rows.filter((r) => r.verdict === 'no_match').length,
  };

  const safeDeleteIds = rows
    .filter((r) => r.verdict === 'likely_duplicate_shadow' && r.suggestedAwId)
    .map((r) => ({
      fbPresetId: r.fbId,
      matchedAppwritePresetId: r.suggestedAwId,
      reasons: r.reasons.filter((x) => x.confidence === 'high'),
    }));

  const report = {
    summary,
    safeDeleteCandidates: safeDeleteIds,
    conflicting: rows
      .filter((r) => r.verdict === 'conflicting_signals')
      .map((r) => ({
        fbId: r.fbId,
        title: r.title,
        reasons: r.reasons,
      })),
    noMatchSample: rows
      .filter((r) => r.verdict === 'no_match')
      .slice(0, 40)
      .map((r) => ({
        fbId: r.fbId,
        title: r.title,
        previewLen: r.previewLen,
        promptLen: r.promptLen,
      })),
    noMatchTotal: rows.filter((r) => r.verdict === 'no_match').length,
  };

  console.log('=== Firestore-only пресеты vs Appwrite (автосопоставление) ===\n');
  console.log(`Только в Firestore:     ${summary.firestoreOnlyCount}`);
  console.log(
    `Похоже на «тень» дубля: ${summary.likelyDuplicateShadow} (однозначное совпадение prompt/preview/fileId)`,
  );
  console.log(`Конфликт сигналов:       ${summary.conflictingSignals}`);
  console.log(`Без совпадения:         ${summary.noMatch}`);

  console.log('\n--- Примеры «тень» (fbId → appwrite id) ---');
  for (const x of safeDeleteIds.slice(0, 15)) {
    console.log(`  ${x.fbPresetId}  →  ${x.matchedAppwritePresetId}`);
  }
  if (safeDeleteIds.length > 15) {
    console.log(`  … ещё ${safeDeleteIds.length - 15}`);
  }

  console.log('\n--- Примеры без совпадения (первые 10 id) ---');
  for (const r of rows.filter((x) => x.verdict === 'no_match').slice(0, 10)) {
    console.log(
      `  ${r.fbId}  title=${JSON.stringify(r.title)}  promptLen=${r.promptLen}  previewLen=${r.previewLen}`,
    );
  }

  if (outPath) {
    const abs = path.isAbsolute(outPath)
      ? outPath
      : path.join(process.cwd(), outPath);
    const full = { ...report, allRows: rows };
    await fs.promises.writeFile(abs, JSON.stringify(full, null, 2), 'utf8');
    console.log(`\nПолный отчёт: ${abs}`);
  }

  if (writeDeletes) {
    const abs = path.isAbsolute(writeDeletes)
      ? writeDeletes
      : path.join(process.cwd(), writeDeletes);
    const payload = {
      generatedAt: new Date().toISOString(),
      note: 'fb-id с единственным совпадением в Appwrite; проверь и используй для точечного удаления',
      presetIds: safeDeleteIds.map((x) => x.fbPresetId),
      details: safeDeleteIds,
    };
    await fs.promises.writeFile(abs, JSON.stringify(payload, null, 2), 'utf8');
    console.log(`\nСписок кандидатов на удаление: ${abs} (${payload.presetIds.length} id)`);
  }

  console.log(
    '\nДальше: открой JSON (--out), прими решение по no_match, для «теней» можно удалить только перечисленные fb-id.',
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
