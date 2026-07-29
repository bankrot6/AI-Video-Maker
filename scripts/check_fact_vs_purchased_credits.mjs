#!/usr/bin/env node
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { Client, Databases, Query } from 'node-appwrite';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

function parseArgs(argv) {
  return {
    json: argv.includes('--json'),
  };
}

async function loadEnvFile(absPath) {
  try {
    const raw = await fs.readFile(absPath, 'utf8');
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
  } catch {
    return {};
  }
}

function toInt(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.trunc(n));
}

function toEndpointV1(endpoint) {
  const trimmed = String(endpoint || '').trim();
  if (!trimmed) return '';
  if (trimmed.endsWith('/v1')) return trimmed;
  return `${trimmed.replace(/\/+$/, '')}/v1`;
}

async function fetchAllDeviceRegistryDocs(databases, databaseId) {
  const out = [];
  let cursor = null;
  for (;;) {
    const queries = [Query.orderAsc('$id'), Query.limit(100)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const res = await databases.listDocuments(databaseId, 'device_registry', queries);
    if (!res.documents.length) break;
    out.push(...res.documents);
    cursor = res.documents[res.documents.length - 1].$id;
    if (res.documents.length < 100) break;
  }
  return out;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  const envMain = await loadEnvFile(path.join(PROJECT_ROOT, '.env'));
  const envDeploy = await loadEnvFile(path.join(PROJECT_ROOT, '.env.deploy'));
  const env = { ...envMain, ...envDeploy, ...process.env };

  const endpoint = toEndpointV1(env.APPWRITE_ENDPOINT);
  const projectId = String(env.APPWRITE_PROJECT_ID || '').trim();
  const apiKey = String(env.APPWRITE_API_KEY || '').trim();
  const databaseId = String(env.APPWRITE_DATABASE_ID || 'main').trim() || 'main';

  if (!endpoint || !projectId || !apiKey) {
    console.error(
      'Нужны APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY (.env/.env.deploy или env).',
    );
    process.exit(1);
  }

  const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
  const databases = new Databases(client);

  const docs = await fetchAllDeviceRegistryDocs(databases, databaseId);
  const rows = docs.map((d) => {
    const purchased = toInt(d.purchasedCredits);
    const earned = toInt(d.earnedCredits);
    const factual = purchased + earned;
    return {
      id: d.$id,
      fingerprint: String(d.fingerprint || ''),
      platform: String(d.platform || ''),
      subscriptionType: String(d.subscriptionType || ''),
      purchased,
      earned,
      factual,
      delta: factual - purchased,
      updatedAt: d.$updatedAt,
    };
  });

  const flagged = rows
    .filter((r) => r.factual > r.purchased)
    .sort((a, b) => b.delta - a.delta || b.factual - a.factual);

  if (args.json) {
    console.log(
      JSON.stringify(
        {
          databaseId,
          totalDocuments: rows.length,
          flaggedCount: flagged.length,
          flagged,
        },
        null,
        2,
      ),
    );
    return;
  }

  console.log(`DB: ${databaseId}`);
  console.log(`Всего документов: ${rows.length}`);
  console.log(`Флагов (factual > purchased): ${flagged.length}`);
  console.log('');
  console.log('id\tfingerprint\tplatform\tsub\tpurchased\tearned\tfactual\tdelta\tupdatedAt');
  for (const r of flagged) {
    console.log(
      `${r.id}\t${r.fingerprint.slice(0, 12)}…\t${r.platform}\t${r.subscriptionType || '-'}\t${r.purchased}\t${r.earned}\t${r.factual}\t${r.delta}\t${r.updatedAt}`,
    );
  }
}

main().catch((e) => {
  console.error(e?.message || e);
  process.exit(1);
});
