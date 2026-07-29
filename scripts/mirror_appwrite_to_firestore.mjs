#!/usr/bin/env node
/**
 * Эталон Appwrite → зеркало Firestore: upsert всех пресетов и user_generations
 * с теми же id, бизнес-полями из AW и (по умолчанию при --execute) перекладкой
 * картинок с Appwrite Storage в Firebase Storage. Записывает _syncSource: appwrite
 * (как scheduled sync в functions), чтобы onWrite presets не гонял обратно в AW.
 *
 *   cd scripts && node mirror_appwrite_to_firestore.mjs
 *   node mirror_appwrite_to_firestore.mjs --execute
 *   node mirror_appwrite_to_firestore.mjs --execute --no-mirror-images
 *   node mirror_appwrite_to_firestore.mjs --execute --prune-fb-only
 *   node mirror_appwrite_to_firestore.mjs --execute --presets-only
 *   node mirror_appwrite_to_firestore.mjs --execute --limit=20
 *
 * --prune-fb-only удаляет из Firestore документы, id которых нет в Appwrite
 * (только вместе с --execute). Опасная операция — сначала dry-run без --execute.
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
  const execute = argv.includes('--execute');
  const presetsOnly = argv.includes('--presets-only');
  const generationsOnly = argv.includes('--generations-only');
  const noMirrorImages = argv.includes('--no-mirror-images');
  const pruneFbOnly = argv.includes('--prune-fb-only');
  const mirrorExternalHttp = argv.includes('--mirror-external-http');
  let limit = 0;
  for (const a of argv) {
    if (a.startsWith('--limit=')) {
      const n = parseInt(a.slice('--limit='.length), 10);
      if (Number.isFinite(n) && n > 0) limit = n;
    }
  }
  return {
    dryRun: !execute,
    execute,
    presetsOnly,
    generationsOnly,
    mirrorImages: !noMirrorImages,
    pruneFbOnly,
    mirrorExternalHttp,
    limit,
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

function isFirebaseStorageUrl(url) {
  return Boolean(url && String(url).includes('firebasestorage.googleapis.com'));
}

function isAppwriteStorageUrl(url, appwriteEndpoint) {
  if (!url || typeof url !== 'string') return false;
  const ep = (appwriteEndpoint || '').trim();
  if (!ep) return false;
  try {
    const host = new URL(ep).hostname;
    return Boolean(host && url.includes(host));
  } catch {
    return false;
  }
}

function shouldMirrorHttpToFirebase(url, env, mirrorExternalHttp) {
  const u = String(url ?? '').trim();
  if (!u.startsWith('http://') && !u.startsWith('https://')) return false;
  if (isFirebaseStorageUrl(u)) return false;
  if (isAppwriteStorageUrl(u, env.APPWRITE_ENDPOINT)) return true;
  return Boolean(mirrorExternalHttp);
}

function guessExtFromContentType(ct) {
  const s = (ct || '').toLowerCase();
  if (s.includes('webp')) return 'webp';
  if (s.includes('png')) return 'png';
  if (s.includes('gif')) return 'gif';
  return 'jpg';
}

async function downloadBytes(url) {
  const res = await fetch(url, {
    redirect: 'follow',
    headers: { Accept: 'image/*,*/*' },
    signal: AbortSignal.timeout(120_000),
  });
  if (!res.ok) {
    throw new Error(`GET ${url.slice(0, 90)}… → ${res.status}`);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  if (!buf.length) throw new Error('empty body');
  return { buf, contentType: res.headers.get('content-type') || 'image/jpeg' };
}

async function uploadToFirebaseBucket(bucket, storagePath, buffer, contentType) {
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (exists) {
    const [meta] = await file.getMetadata();
    let token = meta.metadata?.firebaseStorageDownloadTokens;
    if (!token) {
      token = crypto.randomBytes(32).toString('hex');
      await file.setMetadata({
        metadata: { firebaseStorageDownloadTokens: token },
      });
    }
    const encoded = encodeURIComponent(storagePath);
    return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token}`;
  }
  const token = crypto.randomBytes(32).toString('hex');
  await file.save(buffer, {
    resumable: false,
    metadata: {
      contentType,
      metadata: { firebaseStorageDownloadTokens: token },
    },
  });
  const encoded = encodeURIComponent(storagePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${token}`;
}

async function mirrorHttpImageIfNeeded(
  url,
  env,
  bucket,
  storagePath,
  { mirrorImages, mirrorExternalHttp, dryRun },
) {
  if (!url || typeof url !== 'string') return url;
  const u = url.trim();
  if (u.startsWith('/')) return url;
  if (!shouldMirrorHttpToFirebase(u, env, mirrorExternalHttp)) return url;
  if (!mirrorImages) return url;
  if (dryRun) return url;
  const { buf, contentType } = await downloadBytes(u);
  const ext = guessExtFromContentType(contentType);
  const pathWithExt = storagePath.includes('.') ? storagePath : `${storagePath}.${ext}`;
  return uploadToFirebaseBucket(bucket, pathWithExt, buf, contentType);
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

function buildPresetBase(doc) {
  const d = stripAppwriteMeta(doc);
  const createdAt = d.createdAt || d.$createdAt || new Date().toISOString();
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
  };
  if (d.thumbnailUrl != null && String(d.thumbnailUrl).length > 0) {
    out.thumbnailUrl = String(d.thumbnailUrl);
  }
  if (d.sourceChannel != null && String(d.sourceChannel).length > 0) {
    out.sourceChannel = String(d.sourceChannel);
  }
  if (d.sourcePostId != null && String(d.sourcePostId).length > 0) {
    out.sourcePostId = String(d.sourcePostId);
  }
  return out;
}

function buildGenerationBase(doc) {
  const d = stripAppwriteMeta(doc);
  const createdAt = d.createdAt || d.$createdAt || new Date().toISOString();
  const out = {
    presetId: String(d.presetId ?? ''),
    userImageUrl: String(d.userImageUrl ?? ''),
    resultImageUrl: String(d.resultImageUrl ?? ''),
    deviceId: String(d.deviceId ?? ''),
    createdAt: String(createdAt),
    accountKeyDeviceId: String(d.deviceId ?? ''),
  };
  if (d.referenceImageUrl != null && String(d.referenceImageUrl).length > 0) {
    out.referenceImageUrl = String(d.referenceImageUrl);
  }
  return out;
}

async function main() {
  const {
    dryRun,
    execute,
    presetsOnly,
    generationsOnly,
    mirrorImages,
    pruneFbOnly,
    mirrorExternalHttp,
    limit,
  } = parseArgs(process.argv.slice(2));

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
    console.error('Нет ключа Firebase Admin (см. sync_appwrite_missing_to_firebase.mjs).');
    process.exit(1);
  }
  if (!appwriteEndpoint || !appwriteProject || !appwriteKey) {
    console.error('Нужны APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY');
    process.exit(1);
  }

  const serviceAccount = JSON.parse(fs.readFileSync(saPath, 'utf8'));
  const projectId = serviceAccount.project_id;
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }
  const db = admin.firestore();
  const bucketNameRaw =
    (env.FIREBASE_STORAGE_BUCKET || '').trim() || `${projectId}.appspot.com`;
  const bucketName = bucketNameRaw.replace(/^gs:\/\//, '');
  const bucket = admin.storage().bucket(bucketName);

  const client = new Client()
    .setEndpoint(appwriteEndpoint)
    .setProject(appwriteProject)
    .setKey(appwriteKey);
  const databases = new Databases(client);

  console.log('Ключ Firebase:', saPath);
  console.log('Bucket:', bucket.name);
  console.log(
    dryRun
      ? '\n[DRY-RUN] Запись отключена. Добавьте --execute.\n'
      : '\n[EXECUTE] Запись в Firestore' +
          (mirrorImages ? ' + перекладка изображений (HTTP→Firebase при необходимости)\n' : ' (без перекладки изображений)\n'),
  );
  if (mirrorExternalHttp) {
    console.log(
      '[mirror-external-http] В Firebase Storage уйдут и не-Appwrite внешние HTTP URL (кроме уже Firebase).\n',
    );
  }
  if (pruneFbOnly && dryRun) {
    console.log(
      '[dry-run] --prune-fb-only: в логе ниже — сколько документов было бы удалено с --execute\n',
    );
  }
  if (pruneFbOnly && !dryRun) {
    console.log('[EXECUTE] --prune-fb-only: удаление лишних документов в Firestore\n');
  }

  const mirrorOpts = { mirrorImages, mirrorExternalHttp, dryRun };

  let presetUpserts = 0;
  let genUpserts = 0;
  let presetImagesWouldMirror = 0;
  let genImagesWouldMirror = 0;
  let dryRunPresetCount = 0;
  let dryRunGenCount = 0;

  const awPresetIds = new Set();
  const awGenIds = new Set();

  if (!generationsOnly) {
    console.log('Загрузка пресетов из Appwrite…');
    const awPresetsAll = await fetchAllAppwriteDocuments(
      databases,
      appwriteDatabase,
      presetsCollection,
    );
    for (const doc of awPresetsAll) awPresetIds.add(doc.$id);
    let awPresets =
      limit > 0 ? awPresetsAll.slice(0, limit) : awPresetsAll;

    console.log(`  К обработке: ${awPresets.length} пресетов`);

    for (const doc of awPresets) {
      const id = doc.$id;
      const base = buildPresetBase(doc);
      const fidPrev = crypto.createHash('md5').update(`fbprev_${id}`).digest('hex');
      const fidThumb = crypto.createHash('md5').update(`fbthumb_${id}`).digest('hex');

      if (
        shouldMirrorHttpToFirebase(base.previewImageUrl, env, mirrorExternalHttp)
      ) {
        presetImagesWouldMirror += 1;
      }
      if (
        base.thumbnailUrl &&
        shouldMirrorHttpToFirebase(base.thumbnailUrl, env, mirrorExternalHttp)
      ) {
        presetImagesWouldMirror += 1;
      }

      let previewImageUrl = base.previewImageUrl;
      let thumbnailUrl = base.thumbnailUrl;
      try {
        previewImageUrl = await mirrorHttpImageIfNeeded(
          previewImageUrl,
          env,
          bucket,
          `preset-images/${fidPrev}`,
          mirrorOpts,
        );
        if (thumbnailUrl) {
          thumbnailUrl = await mirrorHttpImageIfNeeded(
            thumbnailUrl,
            env,
            bucket,
            `preset-images/${fidThumb}`,
            mirrorOpts,
          );
        }
      } catch (e) {
        console.warn(`  preset ${id} зеркало картинки: ${e.message || e}`);
      }

      const existing = await db.collection('presets').doc(id).get();
      const payload = {
        ...base,
        previewImageUrl,
        ...(thumbnailUrl != null && thumbnailUrl !== ''
          ? { thumbnailUrl }
          : {}),
        _syncSource: 'appwrite',
        _appwriteId: id,
        mirroredFromAppwriteAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (existing.exists && existing.data()?.firebaseUid) {
        payload.firebaseUid = existing.data().firebaseUid;
      }

      if (dryRun) {
        dryRunPresetCount += 1;
        console.log(`  [dry-run] upsert preset ${id}`);
      } else {
        await db.collection('presets').doc(id).set(payload, { merge: false });
        presetUpserts += 1;
      }
    }
  }

  if (!presetsOnly) {
    console.log('Загрузка генераций из Appwrite…');
    const awGensAll = await fetchAllAppwriteDocuments(
      databases,
      appwriteDatabase,
      generationsCollection,
    );
    for (const doc of awGensAll) awGenIds.add(doc.$id);
    let awGens = limit > 0 ? awGensAll.slice(0, limit) : awGensAll;

    console.log(`  К обработке: ${awGens.length} генераций`);

    for (const doc of awGens) {
      const id = doc.$id;
      const base = buildGenerationBase(doc);
      if (!base.deviceId) {
        console.warn(`  пропуск ${id}: нет deviceId`);
        continue;
      }

      const safe = String(id).replace(/[^\w-]+/g, '_').slice(0, 80);
      for (const field of ['userImageUrl', 'resultImageUrl', 'referenceImageUrl']) {
        const u = base[field];
        if (u && shouldMirrorHttpToFirebase(u, env, mirrorExternalHttp)) {
          genImagesWouldMirror += 1;
        }
      }

      let userImageUrl = base.userImageUrl;
      let resultImageUrl = base.resultImageUrl;
      let referenceImageUrl = base.referenceImageUrl;
      try {
        userImageUrl = await mirrorHttpImageIfNeeded(
          userImageUrl,
          env,
          bucket,
          `mirror-gen/${safe}/user`,
          mirrorOpts,
        );
        resultImageUrl = await mirrorHttpImageIfNeeded(
          resultImageUrl,
          env,
          bucket,
          `mirror-gen/${safe}/result`,
          mirrorOpts,
        );
        if (referenceImageUrl) {
          referenceImageUrl = await mirrorHttpImageIfNeeded(
            referenceImageUrl,
            env,
            bucket,
            `mirror-gen/${safe}/ref`,
            mirrorOpts,
          );
        }
      } catch (e) {
        console.warn(`  gen ${id} зеркало картинки: ${e.message || e}`);
      }

      const existing = await db.collection('user_generations').doc(id).get();
      const payload = {
        ...base,
        userImageUrl,
        resultImageUrl,
        ...(referenceImageUrl ? { referenceImageUrl } : {}),
        mirroredFromAppwriteAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      if (existing.exists && existing.data()?.firebaseUid) {
        payload.firebaseUid = existing.data().firebaseUid;
      }

      if (dryRun) {
        dryRunGenCount += 1;
        console.log(`  [dry-run] upsert generation ${id}`);
      } else {
        await db.collection('user_generations').doc(id).set(payload, { merge: false });
        genUpserts += 1;
      }
    }
  }

  let prunedPresets = 0;
  let prunedGens = 0;
  if (pruneFbOnly) {
    let awPresetSet = awPresetIds;
    let awGenSet = awGenIds;
    if (!generationsOnly && awPresetSet.size === 0) {
      const all = await fetchAllAppwriteDocuments(
        databases,
        appwriteDatabase,
        presetsCollection,
      );
      awPresetSet = new Set(all.map((d) => d.$id));
    }
    if (!presetsOnly && awGenSet.size === 0) {
      const allG = await fetchAllAppwriteDocuments(
        databases,
        appwriteDatabase,
        generationsCollection,
      );
      awGenSet = new Set(allG.map((d) => d.$id));
    }

    if (!generationsOnly) {
      const snap = await db.collection('presets').get();
      for (const d of snap.docs) {
        if (awPresetSet.has(d.id)) continue;
        if (dryRun) {
          console.log(`  [dry-run] prune preset ${d.id}`);
          prunedPresets += 1;
        } else {
          await d.ref.delete();
          prunedPresets += 1;
        }
      }
    }
    if (!presetsOnly) {
      const snap = await db.collection('user_generations').get();
      for (const d of snap.docs) {
        if (awGenSet.has(d.id)) continue;
        if (dryRun) {
          console.log(`  [dry-run] prune user_generations ${d.id}`);
          prunedGens += 1;
        } else {
          await d.ref.delete();
          prunedGens += 1;
        }
      }
    }
  }

  console.log('\n--- Сводка ---');
  if (dryRun) {
    if (!generationsOnly) {
      console.log(`  Пресеты: dry-run upsert: ${dryRunPresetCount}`);
    }
    if (!presetsOnly) {
      console.log(`  Генерации: dry-run upsert: ${dryRunGenCount}`);
    }
    console.log(
      `  Оценка полей превью для перекладки (при --execute и зеркале): ~${presetImagesWouldMirror}`,
    );
    console.log(
      `  Генерации: оценка полей изображений для перекладки: ~${genImagesWouldMirror}`,
    );
    if (pruneFbOnly) {
      console.log(`  Prune: пресеты ${prunedPresets}, генерации ${prunedGens}`);
    }
    console.log('\nПовторите с --execute для применения.');
  } else {
    console.log(`  Upsert пресетов: ${presetUpserts}`);
    console.log(`  Upsert генераций: ${genUpserts}`);
    if (pruneFbOnly) {
      console.log(`  Удалено пресетов (только FB): ${prunedPresets}`);
      console.log(`  Удалено генераций (только FB): ${prunedGens}`);
    }
  }
  console.log(
    '\nПроверка: npm run analyze:presets-dual-db (или node analyze_presets_dual_db.mjs)\n',
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
