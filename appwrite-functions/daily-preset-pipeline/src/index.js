import { Client, Databases, Storage } from 'node-appwrite';
import { runPresetPipeline } from './pipeline_runner.js';

// .trim() защищает от trailing \n, которые deploy-скрипт добавляет через JSON-escape
const ENDPOINT      = (process.env.APPWRITE_ENDPOINT              ?? '').trim();
const PROJECT_ID    = (process.env.APPWRITE_PROJECT_ID            ?? '').trim();
const API_KEY       = (process.env.APPWRITE_API_KEY               ?? '').trim();
const DATABASE_ID   = (process.env.APPWRITE_DATABASE_ID           ?? 'main').trim();
const PRESETS_COLL  = (process.env.APPWRITE_PRESETS_COLLECTION_ID ?? 'presets').trim();
const BUCKET_ID     = (process.env.APPWRITE_STORAGE_BUCKET_ID     ?? 'user-photos').trim();
const API_BOST_KEY  = (process.env.API_BOST_API_KEY               ?? '').trim();
const DEEPSEEK_KEY  = (process.env.DEEPSEEK_API_KEY               ?? '').trim();

function makeClient() {
  return new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
}

const DEFAULT_PRESETS_PER_RUN = Number(
  (process.env.DAILY_PRESET_PIPELINE_COUNT ?? '1').trim(),
) || 1;

function resolveCount(req) {
  const raw = req?.body?.count ?? req?.query?.count;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_PRESETS_PER_RUN;
  return Math.min(Math.floor(parsed), 10);
}

async function runPipeline({ log, error, count }) {
  const client    = makeClient();
  const databases = new Databases(client);
  const storage   = new Storage(client);

  try {
    log(`Starting daily preset pipeline (count=${count})…`);
    const summary = await runPresetPipeline({
      databases,
      storage,
      apiBostKey:  API_BOST_KEY,
      deepseekKey: DEEPSEEK_KEY,
      limit:       count,
      databaseId:  DATABASE_ID,
      presetsColl: PRESETS_COLL,
      bucketId:    BUCKET_ID,
      endpoint:    ENDPOINT,
      projectId:   PROJECT_ID,
    });
    log(`Pipeline done: ${JSON.stringify(summary)}`);
    return summary;
  } catch (err) {
    error(`Pipeline error: ${err.message}`);
    return { ok: false, error: err.message };
  }
}

export default async ({ req, res, log, error }) => {
  if (!API_BOST_KEY || !DEEPSEEK_KEY) {
    error('API_BOST_API_KEY or DEEPSEEK_API_KEY not set');
    return res.json({ ok: false, message: 'Missing API keys' }, 500);
  }

  const summary = await runPipeline({ log, error, count: resolveCount(req) });
  return res.json(summary, summary.ok === false ? 500 : 200);
};
