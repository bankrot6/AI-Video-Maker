#!/usr/bin/env node
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import { Client, Databases, Query } from 'node-appwrite';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

function parseArgs(argv) {
  const apply = argv.includes('--apply');
  const thresholdArg = argv.find((a) => a.startsWith('--threshold='));
  const threshold = thresholdArg ? Number(thresholdArg.split('=')[1]) : 100;
  if (!Number.isFinite(threshold) || threshold < 1) {
    throw new Error('Некорректный --threshold. Пример: --threshold=100');
  }
  return { apply, threshold: Math.trunc(threshold) };
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

function toEndpointV1(endpoint) {
  const trimmed = String(endpoint || '').trim();
  if (!trimmed) return '';
  if (trimmed.endsWith('/v1')) return trimmed;
  return `${trimmed.replace(/\/+$/, '')}/v1`;
}

function toInt(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.trunc(n));
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

async function ensureReportsDir() {
  const dir = path.join(PROJECT_ROOT, 'scripts', 'reports');
  await fs.mkdir(dir, { recursive: true });
  return dir;
}

async function main() {
  const { apply, threshold } = parseArgs(process.argv.slice(2));

  const envMain = await loadEnvFile(path.join(PROJECT_ROOT, '.env'));
  const envDeploy = await loadEnvFile(path.join(PROJECT_ROOT, '.env.deploy'));
  const env = { ...envMain, ...envDeploy, ...process.env };

  const endpoint = toEndpointV1(env.APPWRITE_ENDPOINT);
  const projectId = String(env.APPWRITE_PROJECT_ID || '').trim();
  const apiKey = String(env.APPWRITE_API_KEY || '').trim();
  const databaseId = String(env.APPWRITE_DATABASE_ID || 'main').trim() || 'main';

  if (!endpoint || !projectId || !apiKey) {
    throw new Error(
      'Нужны APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY (.env/.env.deploy/env).',
    );
  }

  const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
  const databases = new Databases(client);
  const docs = await fetchAllDeviceRegistryDocs(databases, databaseId);

  const anomalies = docs
    .filter((d) => String(d.subscriptionType || '') === 'free')
    .filter((d) => toInt(d.purchasedCredits) >= threshold)
    .map((d) => ({
      id: d.$id,
      fingerprint: String(d.fingerprint || ''),
      platform: String(d.platform || ''),
      subscriptionType: String(d.subscriptionType || ''),
      purchasedCredits: toInt(d.purchasedCredits),
      earnedCredits: toInt(d.earnedCredits),
      freeCreditsUsed: toInt(d.freeCreditsUsed),
      freeGenerationsUsed: toInt(d.freeGenerationsUsed),
      firstSeenAt: d.firstSeenAt,
      updatedAt: d.$updatedAt,
    }))
    .sort((a, b) => b.purchasedCredits - a.purchasedCredits);

  console.log(`DB: ${databaseId}`);
  console.log(`Всего записей: ${docs.length}`);
  console.log(
    `Аномалии (sub=free && purchasedCredits>=${threshold}): ${anomalies.length}`,
  );

  if (!anomalies.length) return;

  const reportsDir = await ensureReportsDir();
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupPath = path.join(
    reportsDir,
    `device_registry_anomalies_backup_${stamp}.json`,
  );
  await fs.writeFile(
    backupPath,
    JSON.stringify(
      {
        createdAt: new Date().toISOString(),
        databaseId,
        threshold,
        totalAnomalies: anomalies.length,
        anomalies,
      },
      null,
      2,
    ),
    'utf8',
  );
  console.log(`Бэкап: ${path.relative(PROJECT_ROOT, backupPath)}`);

  for (const a of anomalies) {
    console.log(
      `${a.id}\t${a.fingerprint.slice(0, 12)}…\tp=${a.purchasedCredits}\te=${a.earnedCredits}\tfreeUsed=${a.freeCreditsUsed}`,
    );
  }

  if (!apply) {
    console.log('');
    console.log('Dry-run: изменений не внесено. Добавь --apply для очистки.');
    return;
  }

  let updated = 0;
  for (const a of anomalies) {
    await databases.updateDocument(databaseId, 'device_registry', a.id, {
      purchasedCredits: 0,
    });
    updated += 1;
  }
  console.log('');
  console.log(`Готово: updated ${updated} документ(ов), purchasedCredits сброшен в 0.`);
}

main().catch((e) => {
  console.error(e?.message || e);
  process.exit(1);
});
