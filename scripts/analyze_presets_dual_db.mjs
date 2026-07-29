#!/usr/bin/env node
/**
 * Сравнение Appwrite vs Firestore:
 *  - presets: полнота, расхождения полей, дубликаты id, дубликаты по previewImageUrl
 *  - user_generations: id, дубли resultImageUrl AW/FB, расхождения полей у общих id, разбор URL по полям
 *
 *   cd scripts && node analyze_presets_dual_db.mjs
 *   node analyze_presets_dual_db.mjs --json
 *   node analyze_presets_dual_db.mjs --presets-only
 */

import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';
import admin from 'firebase-admin';
import { Client, Databases, Query } from 'node-appwrite';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

function parseArgs(argv) {
  return {
    json: argv.includes('--json'),
    presetsOnly: argv.includes('--presets-only'),
  };
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

function stripAppwrite(doc) {
  const o = { ...doc };
  delete o.$sequence;
  delete o.$permissions;
  delete o.$databaseId;
  delete o.$collectionId;
  return o;
}

function presetFingerprint(d) {
  const prompt = String(d.prompt ?? '');
  const h = crypto.createHash('sha256').update(prompt).digest('hex').slice(0, 16);
  return h;
}

function normalizePreviewUrl(u) {
  if (!u || typeof u !== 'string') return '';
  try {
    const x = new URL(u);
    return `${x.pathname}?${x.search}`.replace(/\?project=[^&]+/, '');
  } catch {
    return u.trim();
  }
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

function findDuplicateIds(docs, idKey) {
  const seen = new Map();
  for (const d of docs) {
    const id = d[idKey];
    seen.set(id, (seen.get(id) || 0) + 1);
  }
  return [...seen.entries()].filter(([, n]) => n > 1);
}

function findPreviewDuplicates(docs, idField) {
  const byUrl = new Map();
  for (const d of docs) {
    const prev = String(d.previewImageUrl ?? '').trim();
    if (!prev || prev.startsWith('/')) continue;
    const key = normalizePreviewUrl(prev) || prev;
    if (!byUrl.has(key)) byUrl.set(key, []);
    byUrl.get(key).push(d[idField]);
  }
  return [...byUrl.entries()].filter(([, ids]) => ids.length > 1);
}

function classifyImageUrl(u) {
  const s = String(u ?? '').trim();
  if (!s) return 'empty';
  if (s.startsWith('/')) return 'local_path';
  if (!s.startsWith('http')) return 'non_http';
  if (s.includes('/v1/storage/buckets/')) return 'appwrite_storage';
  if (s.includes('firebasestorage.googleapis.com')) return 'firebase_storage';
  return 'other_http';
}

function categorizePresetMismatch(diffs) {
  const fields = new Set(diffs.map((d) => d.field));
  if (fields.has('prompt_hash')) return 'prompt_diff';
  const urlOnly = [...fields].every(
    (f) => f === 'previewImageUrl' || f === 'thumbnailUrl',
  );
  if (urlOnly && diffs.length > 0) return 'image_urls_only';
  return 'metadata_or_mixed';
}

function summarizeUrlsOnCommonPresets(awById, fbById, commonIds) {
  const awPrev = {};
  const fbPrev = {};
  for (const id of commonIds) {
    const a = classifyImageUrl(awById.get(id)?.previewImageUrl);
    const b = classifyImageUrl(fbById.get(id)?.previewImageUrl);
    awPrev[a] = (awPrev[a] || 0) + 1;
    fbPrev[b] = (fbPrev[b] || 0) + 1;
  }
  return { appwritePreviewByKind: awPrev, firestorePreviewByKind: fbPrev };
}

function genFieldDiff(aw, fb) {
  const diffs = [];
  const pairs = [
    ['presetId', String(aw.presetId ?? ''), String(fb.presetId ?? '')],
    ['deviceId', String(aw.deviceId ?? ''), String(fb.deviceId ?? '')],
    ['userImageUrl', String(aw.userImageUrl ?? ''), String(fb.userImageUrl ?? '')],
    ['resultImageUrl', String(aw.resultImageUrl ?? ''), String(fb.resultImageUrl ?? '')],
    [
      'referenceImageUrl',
      String(aw.referenceImageUrl ?? ''),
      String(fb.referenceImageUrl ?? ''),
    ],
  ];
  for (const [name, a, b] of pairs) {
    if (a !== b && String(a) !== String(b)) {
      diffs.push({
        field: name,
        appwrite: typeof a === 'string' && a.length > 100 ? a.slice(0, 100) + '…' : a,
        firebase: typeof b === 'string' && b.length > 100 ? b.slice(0, 100) + '…' : b,
      });
    }
  }
  return diffs;
}

function fieldDiff(aw, fb, id) {
  const diffs = [];
  const pairs = [
    ['previewImageUrl', aw.previewImageUrl, fb.previewImageUrl],
    ['thumbnailUrl', aw.thumbnailUrl ?? '', fb.thumbnailUrl ?? ''],
    ['title', aw.title ?? '', fb.title ?? ''],
    ['likesCount', Number(aw.likesCount ?? 0), Number(fb.likesCount ?? 0)],
    ['isPublic', Boolean(aw.isPublic), Boolean(fb.isPublic)],
    ['ownerId', aw.ownerId ?? '', fb.ownerId ?? ''],
  ];
  for (const [name, a, b] of pairs) {
    if (a !== b && String(a) !== String(b)) {
      diffs.push({
        field: name,
        appwrite: typeof a === 'string' && a.length > 120 ? a.slice(0, 120) + '…' : a,
        firebase: typeof b === 'string' && b.length > 120 ? b.slice(0, 120) + '…' : b,
      });
    }
  }
  const awTags = JSON.stringify([...(aw.tags ?? [])].sort());
  const fbTags = JSON.stringify([...(fb.tags ?? [])].sort());
  if (awTags !== fbTags) {
    diffs.push({ field: 'tags', appwrite: awTags, firebase: fbTags });
  }
  const awH = presetFingerprint(aw);
  const fbH = presetFingerprint(fb);
  if (awH !== fbH) {
    diffs.push({
      field: 'prompt_hash',
      appwrite: awH,
      firebase: fbH,
    });
  }
  return diffs;
}

async function main() {
  const { json, presetsOnly } = parseArgs(process.argv.slice(2));
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
    console.error('Нет Firebase service account JSON (см. другие scripts/*.mjs).');
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

  const awRaw = await fetchAllAppwriteDocuments(
    databases,
    appwriteDatabase,
    presetsCollection,
  );

  const awList = awRaw.map((doc) => {
    const d = stripAppwrite(doc);
    return { $id: doc.$id, ...d };
  });

  const fbSnap = await db.collection('presets').get();
  const fbList = fbSnap.docs.map((doc) => ({ $id: doc.id, ...doc.data() }));

  const awIds = new Set(awList.map((d) => d.$id));
  const fbIds = new Set(fbList.map((d) => d.$id));

  const onlyAw = [...awIds].filter((id) => !fbIds.has(id)).sort();
  const onlyFb = [...fbIds].filter((id) => !awIds.has(id)).sort();

  const awDupIds = findDuplicateIds(awList, '$id');
  const fbDupIds = findDuplicateIds(fbList, '$id');

  const awPrevDup = findPreviewDuplicates(awList, '$id');
  const fbPrevDup = findPreviewDuplicates(fbList, '$id');

  const awById = new Map(awList.map((d) => [d.$id, d]));
  const fbById = new Map(fbList.map((d) => [d.$id, d]));

  const mismatches = [];
  for (const id of awIds) {
    if (!fbIds.has(id)) continue;
    const diffs = fieldDiff(awById.get(id), fbById.get(id), id);
    if (diffs.length) mismatches.push({ id, diffs });
  }

  const badPreviewAw = awList.filter(
    (d) =>
      String(d.previewImageUrl ?? '').trim() &&
      !String(d.previewImageUrl).startsWith('http'),
  );
  const badPreviewFb = fbList.filter(
    (d) =>
      String(d.previewImageUrl ?? '').trim() &&
      !String(d.previewImageUrl).startsWith('http'),
  );

  const commonPresetIds = [...awIds].filter((id) => fbIds.has(id));
  const presetMismatchCategoryCounts = {
    prompt_diff: 0,
    image_urls_only: 0,
    metadata_or_mixed: 0,
  };
  for (const m of mismatches) {
    presetMismatchCategoryCounts[categorizePresetMismatch(m.diffs)]++;
  }
  const commonPresetPreviewUrlKinds = summarizeUrlsOnCommonPresets(
    awById,
    fbById,
    commonPresetIds,
  );

  function generationUrlSummaries(list) {
    const fields = ['userImageUrl', 'resultImageUrl', 'referenceImageUrl'];
    const perField = {};
    for (const f of fields) {
      perField[f] = {
        empty: 0,
        localOrDevicePath: 0,
        nonHttpNonPath: 0,
        http: 0,
      };
    }
    const resultBadExamples = [];
    for (const d of list) {
      for (const f of fields) {
        const v = String(d[f] ?? '').trim();
        if (!v) {
          perField[f].empty++;
        } else if (v.startsWith('http')) {
          perField[f].http++;
        } else if (v.startsWith('/')) {
          perField[f].localOrDevicePath++;
        } else {
          perField[f].nonHttpNonPath++;
        }
      }
      const r = String(d.resultImageUrl ?? '').trim();
      if (r && !r.startsWith('http') && !r.startsWith('/')) {
        if (resultBadExamples.length < 10) {
          resultBadExamples.push({ id: d.$id, sample: r.slice(0, 96) });
        }
      }
    }
    return { perField, resultBadExamples };
  }

  function mapUrlDupGroups(pairs) {
    return pairs.slice(0, 20).map(([url, ids]) => ({
      ids,
      count: ids.length,
      urlSample: String(url).slice(0, 100),
    }));
  }

  let generationsSummary = null;
  if (!presetsOnly) {
    const awGenRaw = await fetchAllAppwriteDocuments(
      databases,
      appwriteDatabase,
      generationsCollection,
    );
    const awGenList = awGenRaw.map((doc) => {
      const d = stripAppwrite(doc);
      return { $id: doc.$id, ...d };
    });
    const genFbSnap = await db.collection('user_generations').get();
    const fbGenList = genFbSnap.docs.map((doc) => ({
      $id: doc.id,
      ...doc.data(),
    }));

    const genAwIds = new Set(awGenList.map((d) => d.$id));
    const genFbIds = new Set(fbGenList.map((d) => d.$id));
    const genOnlyAwIds = [...genAwIds].filter((id) => !genFbIds.has(id)).sort();
    const genOnlyFbIds = [...genFbIds].filter((id) => !genAwIds.has(id)).sort();

    const genByAw = new Map(awGenList.map((d) => [d.$id, d]));
    const genByFb = new Map(fbGenList.map((d) => [d.$id, d]));

    const genMismatches = [];
    for (const id of genAwIds) {
      if (!genFbIds.has(id)) continue;
      const diffs = genFieldDiff(genByAw.get(id), genByFb.get(id));
      if (diffs.length) genMismatches.push({ id, diffs });
    }

    const genMismatchCategoryCounts = {
      image_urls_only: 0,
      preset_device_or_mixed: 0,
    };
    for (const m of genMismatches) {
      const fields = new Set(m.diffs.map((d) => d.field));
      const urlOnly = [...fields].every((f) =>
        ['userImageUrl', 'resultImageUrl', 'referenceImageUrl'].includes(f),
      );
      if (urlOnly && fields.size > 0) genMismatchCategoryCounts.image_urls_only++;
      else genMismatchCategoryCounts.preset_device_or_mixed++;
    }

    const genDupAw = findDuplicateIds(awGenList, '$id');
    const genDupFb = findDuplicateIds(fbGenList, '$id');

    const genResultDupAw = findPreviewDuplicates(
      awGenList.map((d) => ({
        $id: d.$id,
        previewImageUrl: d.resultImageUrl,
      })),
      '$id',
    );
    const genResultDupFb = findPreviewDuplicates(
      fbGenList.map((d) => ({
        $id: d.$id,
        previewImageUrl: d.resultImageUrl,
      })),
      '$id',
    );

    const genUrlAw = generationUrlSummaries(awGenList);
    const genUrlFb = generationUrlSummaries(fbGenList);

    generationsSummary = {
      counts: {
        appwrite: awGenList.length,
        firestore: genFbSnap.size,
        inBoth: [...genAwIds].filter((id) => genFbIds.has(id)).length,
      },
      onlyInAppwrite: genOnlyAwIds.length,
      onlyInFirestore: genOnlyFbIds.length,
      onlyInAppwriteSampleIds: genOnlyAwIds.slice(0, 40),
      onlyInFirestoreSampleIds: genOnlyFbIds.slice(0, 40),
      duplicateIds: {
        appwrite: genDupAw.length,
        firestore: genDupFb.length,
      },
      duplicateResultImageUrlGroups: {
        appwrite: genResultDupAw.length,
        firestore: genResultDupFb.length,
      },
      duplicateResultImageUrl: {
        appwrite: mapUrlDupGroups(genResultDupAw),
        firestore: mapUrlDupGroups(genResultDupFb),
      },
      fieldMismatchesInCommonIdsTotal: genMismatches.length,
      fieldMismatchesInCommonIdsSample: genMismatches.slice(0, 80),
      genMismatchCategoryCounts,
      imageUrlBreakdown: {
        appwrite: genUrlAw,
        firestore: genUrlFb,
      },
    };
  }

  const report = {
    generations: generationsSummary,
    counts: {
      appwrite: awList.length,
      firestore: fbList.length,
      inBoth: [...awIds].filter((id) => fbIds.has(id)).length,
    },
    onlyInAppwrite: onlyAw,
    onlyInFirestore: onlyFb,
    duplicateIds: {
      appwrite: awDupIds,
      firestore: fbDupIds,
    },
    duplicatePreviewImageUrl: {
      appwrite: awPrevDup.map(([url, ids]) => ({
        ids,
        count: ids.length,
        urlSample: String(url).slice(0, 100),
      })),
      firestore: fbPrevDup.map(([url, ids]) => ({
        ids,
        count: ids.length,
        urlSample: String(url).slice(0, 100),
      })),
    },
    fieldMismatchesInCommonIds: mismatches,
    presetMismatchCategoryCounts,
    commonPresetPreviewUrlKinds,
    nonHttpPreviewImageUrl: {
      appwriteCount: badPreviewAw.length,
      appwriteIds: badPreviewAw.map((d) => d.$id).slice(0, 50),
      firestoreCount: badPreviewFb.length,
      firestoreIds: badPreviewFb.map((d) => d.$id).slice(0, 50),
    },
  };

  if (json) {
    console.log(JSON.stringify(report, null, 2));
    return;
  }

  if (report.generations) {
    console.log('=== Генерации user_generations ===\n');
    const g = report.generations;
    console.log(`Appwrite:   ${g.counts.appwrite}`);
    console.log(`Firestore:  ${g.counts.firestore}`);
    console.log(`В обоих:    ${g.counts.inBoth}`);
    console.log(`Только AW:  ${g.onlyInAppwrite}`);
    console.log(`Только FB:  ${g.onlyInFirestore}`);
    console.log(
      `Дубликаты id: AW=${g.duplicateIds.appwrite} FB=${g.duplicateIds.firestore}`,
    );
    console.log(
      `Групп с одинаковым resultImageUrl: AW=${g.duplicateResultImageUrlGroups.appwrite} FB=${g.duplicateResultImageUrlGroups.firestore}`,
    );
    console.log(
      `Расхождения полей у общих id: всего ${g.fieldMismatchesInCommonIdsTotal} (в JSON/сэмпл: до 80)`,
    );
    console.log(
      `  из них только URL картинок: ${g.genMismatchCategoryCounts.image_urls_only}; presetId/deviceId/смешанное: ${g.genMismatchCategoryCounts.preset_device_or_mixed}`,
    );
    const uaw = g.imageUrlBreakdown.appwrite.perField;
    const ufb = g.imageUrlBreakdown.firestore.perField;
    console.log(
      `userImageUrl — локальные пути (/data/…): AW=${uaw.userImageUrl.localOrDevicePath} FB=${ufb.userImageUrl.localOrDevicePath} (исторически с клиента, не признак рассинхрона)`,
    );
    console.log(
      `resultImageUrl — HTTP: AW=${uaw.resultImageUrl.http} FB=${ufb.resultImageUrl.http}; локальный путь: AW=${uaw.resultImageUrl.localOrDevicePath} FB=${ufb.resultImageUrl.localOrDevicePath}; пусто: AW=${uaw.resultImageUrl.empty} FB=${ufb.resultImageUrl.empty}; иное не-HTTP: AW=${uaw.resultImageUrl.nonHttpNonPath} FB=${ufb.resultImageUrl.nonHttpNonPath}`,
    );
    if (g.onlyInAppwriteSampleIds?.length) {
      console.log('\n--- Пример id только в Appwrite (генерации) ---');
      console.log(g.onlyInAppwriteSampleIds.join('\n'));
    }
    if (g.onlyInFirestoreSampleIds?.length) {
      console.log('\n--- Пример id только в Firestore (генерации) ---');
      console.log(g.onlyInFirestoreSampleIds.slice(0, 20).join('\n'));
      if (g.onlyInFirestoreSampleIds.length > 20) {
        console.log(`… всего в сэмпле ${g.onlyInFirestoreSampleIds.length}`);
      }
    }
    if (g.fieldMismatchesInCommonIdsSample?.length) {
      console.log('\n--- Примеры расхождений генераций (общие id) ---');
      for (const row of g.fieldMismatchesInCommonIdsSample.slice(0, 8)) {
        console.log(`  id=${row.id}`);
        for (const d of row.diffs) {
          console.log(
            `    ${d.field}: AW=${JSON.stringify(d.appwrite)} | FB=${JSON.stringify(d.firebase)}`,
          );
        }
      }
    }
    console.log('');
  }

  console.log('=== Пресеты: Appwrite vs Firestore ===\n');
  console.log(`Appwrite:   ${report.counts.appwrite} документов`);
  console.log(`Firestore:  ${report.counts.firestore} документов`);
  console.log(`В обоих:    ${report.counts.inBoth}`);
  console.log(`Только AW:  ${onlyAw.length}`);
  console.log(`Только FB:  ${onlyFb.length}`);

  if (onlyAw.length) {
    console.log('\n--- ID только в Appwrite (первые 30) ---');
    console.log(onlyAw.slice(0, 30).join('\n'));
    if (onlyAw.length > 30) console.log(`… +${onlyAw.length - 30} ещё`);
  }
  if (onlyFb.length) {
    console.log('\n--- ID только в Firestore (первые 30) ---');
    console.log(onlyFb.slice(0, 30).join('\n'));
    if (onlyFb.length > 30) console.log(`… +${onlyFb.length - 30} ещё`);
  }

  console.log('\n--- Дубликаты $id внутри одной БД ---');
  console.log(
    `Appwrite:  ${awDupIds.length ? JSON.stringify(awDupIds) : 'нет'}`,
  );
  console.log(
    `Firestore: ${fbDupIds.length ? JSON.stringify(fbDupIds) : 'нет'}`,
  );

  console.log('\n--- Одинаковый previewImageUrl → несколько id (дубликаты картинки) ---');
  console.log(`Appwrite:  групп с дублем: ${awPrevDup.length}`);
  for (const g of report.duplicatePreviewImageUrl.appwrite.slice(0, 15)) {
    console.log(`  count=${g.count} ids=${g.ids.join(', ')}`);
  }
  if (awPrevDup.length > 15) console.log(`  … ещё ${awPrevDup.length - 15} групп`);

  console.log(`Firestore: групп с дублем: ${fbPrevDup.length}`);
  for (const g of report.duplicatePreviewImageUrl.firestore.slice(0, 15)) {
    console.log(`  count=${g.count} ids=${g.ids.join(', ')}`);
  }
  if (fbPrevDup.length > 15) console.log(`  … ещё ${fbPrevDup.length - 15} групп`);

  console.log('\n--- Категории расхождений пресетов (только общие id) ---');
  console.log(
    `  только URL превью/миниатюры: ${presetMismatchCategoryCounts.image_urls_only}`,
  );
  console.log(`  отличается промпт (hash): ${presetMismatchCategoryCounts.prompt_diff}`);
  console.log(
    `  метаданные/смешанное (title, likes, tags, …): ${presetMismatchCategoryCounts.metadata_or_mixed}`,
  );

  console.log('\n--- Типы previewImageUrl на общих id (по БД) ---');
  console.log(
    `  Appwrite:  ${JSON.stringify(commonPresetPreviewUrlKinds.appwritePreviewByKind)}`,
  );
  console.log(
    `  Firestore: ${JSON.stringify(commonPresetPreviewUrlKinds.firestorePreviewByKind)}`,
  );

  console.log('\n--- Расхождения полей у общих id ---');
  console.log(`Документов с отличиями: ${mismatches.length}`);
  for (const m of mismatches.slice(0, 20)) {
    console.log(`  id=${m.id}`);
    for (const d of m.diffs) {
      console.log(`    ${d.field}: AW=${JSON.stringify(d.appwrite)} | FB=${JSON.stringify(d.firebase)}`);
    }
  }
  if (mismatches.length > 20) {
    console.log(`  … ещё ${mismatches.length - 20}, полный список: --json`);
  }

  console.log('\n--- previewImageUrl не HTTP (битые/локальные) ---');
  console.log(
    `Appwrite:  ${badPreviewAw.length} шт. id: ${badPreviewAw.map((d) => d.$id).slice(0, 15).join(', ')}`,
  );
  console.log(
    `Firestore: ${badPreviewFb.length} шт. id: ${badPreviewFb.map((d) => d.$id).slice(0, 15).join(', ')}`,
  );

  const ok =
    onlyAw.length === 0 &&
    onlyFb.length === 0 &&
    awDupIds.length === 0 &&
    fbDupIds.length === 0 &&
    mismatches.length === 0 &&
    badPreviewAw.length === 0 &&
    badPreviewFb.length === 0;

  console.log(
    `\n=== Итог: ${ok ? 'полное совпадение наборов и полей (по проверенным)' : 'есть расхождения — см. выше'} ===`,
  );
  if (!ok) {
    console.log(
      'Подсказка: при двух хранилищах (Appwrite Storage vs Firebase) нормально видеть «только URL» у пресетов и генераций; важнее prompt_hash / presetId / дубли по одному result URL.',
    );
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
