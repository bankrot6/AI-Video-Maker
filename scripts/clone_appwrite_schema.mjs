#!/usr/bin/env node
// Клонирует схему Appwrite (база, коллекции, атрибуты, индексы, бакеты)
// из проекта-источника в проект-приёмник. Документы и файлы не копируются.
//
// Запуск:
//   SRC_PROJECT=... SRC_KEY=... DST_PROJECT=... DST_KEY=... \
//   node scripts/clone_appwrite_schema.mjs

const ENDPOINT = process.env.APPWRITE_ENDPOINT || 'http://158.160.254.66/v1';
const DATABASE_ID = process.env.APPWRITE_DATABASE_ID || 'main';

const SRC = { project: required('SRC_PROJECT'), key: required('SRC_KEY') };
const DST = { project: required('DST_PROJECT'), key: required('DST_KEY') };

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`env ${name} is required`);
  return value;
}

async function api(ctx, path, init = {}) {
  const res = await fetch(`${ENDPOINT}${path}`, {
    ...init,
    headers: {
      'X-Appwrite-Project': ctx.project,
      'X-Appwrite-Key': ctx.key,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
  const text = await res.text();
  let body;
  try { body = JSON.parse(text); } catch { body = text; }
  return { ok: res.ok, status: res.status, body };
}

async function must(ctx, path, init) {
  const res = await api(ctx, path, init);
  if (!res.ok) throw new Error(`${res.status} ${path}: ${JSON.stringify(res.body).slice(0, 400)}`);
  return res.body;
}

const ATTRIBUTE_PATH = {
  string: 'string',
  integer: 'integer',
  double: 'float',
  boolean: 'boolean',
  datetime: 'datetime',
  relationship: 'relationship',
};

function isUserBound(value) {
  return Number.isFinite(value) && Math.abs(value) <= Number.MAX_SAFE_INTEGER;
}

function attributeBody(attr) {
  const base = { key: attr.key, required: attr.required, array: attr.array || false };
  if (!attr.required && attr.default !== null && attr.default !== undefined) {
    base.default = attr.default;
  }
  switch (attr.format) {
    case 'email':
    case 'url':
    case 'ip':
      return { path: attr.format, body: base };
    case 'enum':
      return { path: 'enum', body: { ...base, elements: attr.elements } };
    default:
      break;
  }
  switch (attr.type) {
    case 'string':
      return { path: 'string', body: { ...base, size: attr.size, encrypt: attr.encrypt || false } };
    case 'integer':
    case 'double': {
      const body = { ...base };
      // Appwrite отдаёт границы int64, которые не переживают round-trip через JS
      // number, поэтому переносим только реально заданные пользователем лимиты.
      if (isUserBound(attr.min)) body.min = attr.min;
      if (isUserBound(attr.max)) body.max = attr.max;
      return { path: ATTRIBUTE_PATH[attr.type], body };
    }
    case 'relationship':
      return {
        path: 'relationship',
        body: {
          key: attr.key,
          relatedCollectionId: attr.relatedCollection,
          type: attr.relationType,
          twoWay: attr.twoWay,
          twoWayKey: attr.twoWayKey,
          onDelete: attr.onDelete,
        },
      };
    default:
      return { path: ATTRIBUTE_PATH[attr.type] || attr.type, body: base };
  }
}

async function ensureDatabase() {
  const existing = await api(DST, `/databases/${DATABASE_ID}`);
  if (existing.ok) {
    console.log(`database ${DATABASE_ID}: exists`);
    return;
  }
  const src = await must(SRC, `/databases/${DATABASE_ID}`);
  await must(DST, '/databases', {
    method: 'POST',
    body: JSON.stringify({ databaseId: DATABASE_ID, name: src.name, enabled: src.enabled }),
  });
  console.log(`database ${DATABASE_ID}: created`);
}

async function waitAttributesAvailable(collectionId) {
  for (let i = 0; i < 60; i += 1) {
    const list = await must(DST, `/databases/${DATABASE_ID}/collections/${collectionId}/attributes`);
    const pending = (list.attributes || []).filter((a) => a.status !== 'available');
    if (pending.length === 0) return;
    await new Promise((r) => setTimeout(r, 1000));
  }
  console.warn(`  ! attributes of ${collectionId} are still processing`);
}

async function cloneCollections() {
  const src = await must(SRC, `/databases/${DATABASE_ID}/collections`);
  const collections = src.collections || [];

  for (const coll of collections) {
    const exists = await api(DST, `/databases/${DATABASE_ID}/collections/${coll.$id}`);
    const payload = {
      collectionId: coll.$id,
      name: coll.name,
      permissions: coll.$permissions,
      documentSecurity: coll.documentSecurity,
      enabled: coll.enabled,
    };
    if (exists.ok) {
      await must(DST, `/databases/${DATABASE_ID}/collections/${coll.$id}`, {
        method: 'PUT',
        body: JSON.stringify(payload),
      });
      console.log(`collection ${coll.$id}: updated`);
    } else {
      await must(DST, `/databases/${DATABASE_ID}/collections`, {
        method: 'POST',
        body: JSON.stringify(payload),
      });
      console.log(`collection ${coll.$id}: created`);
    }
  }

  for (const coll of collections) {
    const attrs = (await must(SRC, `/databases/${DATABASE_ID}/collections/${coll.$id}/attributes`)).attributes || [];
    for (const attr of attrs) {
      const existing = await api(DST, `/databases/${DATABASE_ID}/collections/${coll.$id}/attributes/${attr.key}`);
      if (existing.ok) continue;
      if (attr.type === 'relationship' && attr.side === 'child') continue;
      const { path, body } = attributeBody(attr);
      const res = await api(DST, `/databases/${DATABASE_ID}/collections/${coll.$id}/attributes/${path}`, {
        method: 'POST',
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        console.warn(`  ! ${coll.$id}.${attr.key}: ${JSON.stringify(res.body).slice(0, 200)}`);
      } else {
        console.log(`  + ${coll.$id}.${attr.key} (${path})`);
      }
    }
    await waitAttributesAvailable(coll.$id);
  }

  for (const coll of collections) {
    const indexes = (await must(SRC, `/databases/${DATABASE_ID}/collections/${coll.$id}/indexes`)).indexes || [];
    for (const index of indexes) {
      const existing = await api(DST, `/databases/${DATABASE_ID}/collections/${coll.$id}/indexes/${index.key}`);
      if (existing.ok) continue;
      const res = await api(DST, `/databases/${DATABASE_ID}/collections/${coll.$id}/indexes`, {
        method: 'POST',
        body: JSON.stringify({
          key: index.key,
          type: index.type,
          attributes: index.attributes,
          orders: index.orders,
        }),
      });
      if (!res.ok) {
        console.warn(`  ! index ${coll.$id}.${index.key}: ${JSON.stringify(res.body).slice(0, 200)}`);
      } else {
        console.log(`  + index ${coll.$id}.${index.key}`);
      }
    }
  }
}

async function cloneBuckets() {
  const src = await must(SRC, '/storage/buckets');
  for (const bucket of src.buckets || []) {
    const payload = {
      bucketId: bucket.$id,
      name: bucket.name,
      permissions: bucket.$permissions,
      fileSecurity: bucket.fileSecurity,
      enabled: bucket.enabled,
      maximumFileSize: bucket.maximumFileSize,
      allowedFileExtensions: bucket.allowedFileExtensions,
      compression: bucket.compression,
      encryption: bucket.encryption,
      antivirus: bucket.antivirus,
    };
    const exists = await api(DST, `/storage/buckets/${bucket.$id}`);
    if (exists.ok) {
      await must(DST, `/storage/buckets/${bucket.$id}`, { method: 'PUT', body: JSON.stringify(payload) });
      console.log(`bucket ${bucket.$id}: updated`);
    } else {
      await must(DST, '/storage/buckets', { method: 'POST', body: JSON.stringify(payload) });
      console.log(`bucket ${bucket.$id}: created`);
    }
  }
}

await ensureDatabase();
await cloneCollections();
await cloneBuckets();
console.log('schema clone finished');
