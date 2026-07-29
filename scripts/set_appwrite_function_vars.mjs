#!/usr/bin/env node
// Заполняет переменные окружения всех Appwrite-функций значениями из
// .env и .env.deploy. Скрипт идемпотентен: существующие переменные
// пересоздаются, лишние удаляются.
//
// Запуск: node scripts/set_appwrite_function_vars.mjs

import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function loadEnv(file) {
  const path = resolve(ROOT, file);
  if (!existsSync(path)) return {};
  const result = {};
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const match = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$/.exec(line);
    if (!match) continue;
    let value = match[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    result[match[1]] = value;
  }
  return result;
}

const env = { ...loadEnv('.env'), ...loadEnv('.env.deploy') };
const pick = (key, fallback = '') => env[key] ?? fallback;

const ENDPOINT = pick('APPWRITE_ENDPOINT');
const PROJECT = pick('APPWRITE_PROJECT_ID');
const KEY = pick('APPWRITE_API_KEY');
if (!ENDPOINT || !PROJECT || !KEY) {
  throw new Error('APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY must be set in .env/.env.deploy');
}

const DATABASE_ID = pick('APPWRITE_DATABASE_ID', 'main');
const PRESETS = pick('APPWRITE_PRESETS_COLLECTION_ID', 'presets');
const GENERATIONS = pick('APPWRITE_GENERATIONS_COLLECTION_ID', 'user_generations');
const BUCKET = pick('APPWRITE_STORAGE_BUCKET_ID', 'user-photos');
const AD_BUCKET = pick('APPWRITE_AD_CREATIVES_BUCKET_ID', 'ad-creatives');
const EARNINGS = pick('APPWRITE_EARNINGS_COLLECTION_ID', 'preset_earnings');
const ADMIN_KEY = pick('ADMIN_API_KEY', 'photosession_admin_key_2026_secure_secret');

const APPWRITE_CORE = {
  APPWRITE_ENDPOINT: ENDPOINT,
  APPWRITE_PROJECT_ID: PROJECT,
  APPWRITE_API_KEY: KEY,
  APPWRITE_DATABASE_ID: DATABASE_ID,
};

const AI_PROXY = {
  NL_SERVER_HOST: pick('NL_SERVER_HOST'),
  NL_PROXY_TOKEN: pick('NL_PROXY_TOKEN'),
  AI_PROXY_PIAPI_PORT: pick('AI_PROXY_PIAPI_PORT', '8080'),
  YANDEX_AI_RELAY_BASE_URL: pick('YANDEX_AI_RELAY_BASE_URL'),
};

const FUNCTION_VARS = {
  'generate-thumbnail': {
    ...APPWRITE_CORE,
    APPWRITE_PRESETS_COLLECTION_ID: PRESETS,
    APPWRITE_STORAGE_BUCKET_ID: BUCKET,
  },
  'process-preset-rewards': {
    ...APPWRITE_CORE,
    APPWRITE_PRESETS_COLLECTION_ID: PRESETS,
    APPWRITE_EARNINGS_COLLECTION_ID: EARNINGS,
  },
  'repair-preset-permissions': {
    ...APPWRITE_CORE,
    APPWRITE_PRESETS_COLLECTION_ID: PRESETS,
    APPWRITE_GENERATIONS_COLLECTION_ID: GENERATIONS,
    REPAIR_PRESET_PERMISSIONS_PAGE_SIZE: pick('REPAIR_PRESET_PERMISSIONS_PAGE_SIZE', '50'),
  },
  'daily-preset-pipeline': {
    ...APPWRITE_CORE,
    ...AI_PROXY,
    APPWRITE_PRESETS_COLLECTION_ID: PRESETS,
    APPWRITE_STORAGE_BUCKET_ID: BUCKET,
    API_BOST_API_KEY: pick('API_BOST_API_KEY'),
    DEEPSEEK_API_KEY: pick('DEEPSEEK_API_KEY'),
    AI_PROXY_DEEPSEEK_PORT: pick('AI_PROXY_DEEPSEEK_PORT', '8001'),
    ADMIN_API_KEY: ADMIN_KEY,
  },
  'manage-presets': {
    ...APPWRITE_CORE,
    ...AI_PROXY,
    APPWRITE_PRESETS_COLLECTION_ID: PRESETS,
    APPWRITE_STORAGE_BUCKET_ID: BUCKET,
    API_BOST_API_KEY: pick('API_BOST_API_KEY'),
    DEEPSEEK_API_KEY: pick('DEEPSEEK_API_KEY'),
    PIAPI_API_KEY: pick('PIAPI_API_KEY'),
    AI_PROXY_DEEPSEEK_PORT: pick('AI_PROXY_DEEPSEEK_PORT', '8001'),
    ADMIN_API_KEY: ADMIN_KEY,
  },
  'verify-trial': { ...APPWRITE_CORE },
  'preset-manager': { ...APPWRITE_CORE },
  'apibost-proxy': {
    ...APPWRITE_CORE,
    ...AI_PROXY,
    APPWRITE_STORAGE_BUCKET_ID: BUCKET,
    API_BOST_API_KEY: pick('API_BOST_API_KEY'),
  },
  'ad-creative-generator': {
    APPWRITE_ENDPOINT: ENDPOINT,
    APPWRITE_PROJECT_ID: PROJECT,
    APPWRITE_API_KEY: KEY,
    ...AI_PROXY,
    APPWRITE_STORAGE_BUCKET_ID: BUCKET,
    APPWRITE_AD_CREATIVES_BUCKET_ID: AD_BUCKET,
    API_BOST_API_KEY: pick('API_BOST_API_KEY'),
    ADMIN_API_KEY: ADMIN_KEY,
  },
  'verify-rustore-purchase': {
    ...APPWRITE_CORE,
    RUSTORE_APP_ID: pick('RUSTORE_APP_ID'),
    RUSTORE_KEY_ID: pick('RUSTORE_KEY_ID'),
    RUSTORE_PRIVATE_KEY: pick('RUSTORE_PRIVATE_KEY'),
    MYTRACKER_S2S_APP_ID: pick('MYTRACKER_S2S_APP_ID'),
    MYTRACKER_S2S_TOKEN: pick('MYTRACKER_S2S_TOKEN'),
  },
  'cleanup-inactive-generations': {
    ...APPWRITE_CORE,
    APPWRITE_COLLECTION_ID: GENERATIONS,
    APPWRITE_STORAGE_BUCKET_ID: BUCKET,
    INACTIVE_DAYS: pick('INACTIVE_DAYS', '14'),
  },
  'cleanup-orphan-files': {
    APPWRITE_API_KEY: KEY,
    BUCKET_ID: BUCKET,
    DATABASE_ID,
    KEEP_HOURS: pick('KEEP_HOURS', '24'),
    MAX_FILES_PER_RUN: pick('MAX_FILES_PER_RUN', '5000'),
  },
  'bucket-size-guard': {
    APPWRITE_API_KEY: KEY,
    BUCKET_ID: BUCKET,
    DATABASE_ID,
    SAFE_GB: pick('SAFE_GB', '12'),
    WARN_GB: pick('WARN_GB', '15'),
    DANGER_GB: pick('DANGER_GB', '18'),
    CRITICAL_GB: pick('CRITICAL_GB', '22'),
    MAX_DELETE_PER_RUN: pick('MAX_DELETE_PER_RUN', '3000'),
  },
};

async function api(path, init = {}) {
  const res = await fetch(`${ENDPOINT}${path}`, {
    ...init,
    headers: {
      'X-Appwrite-Project': PROJECT,
      'X-Appwrite-Key': KEY,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${path}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

for (const [functionId, vars] of Object.entries(FUNCTION_VARS)) {
  const existing = await api(`/functions/${functionId}/variables`);
  for (const variable of existing.variables || []) {
    await api(`/functions/${functionId}/variables/${variable.$id}`, { method: 'DELETE' });
  }
  const missing = [];
  for (const [key, value] of Object.entries(vars)) {
    if (!value) missing.push(key);
    await api(`/functions/${functionId}/variables`, {
      method: 'POST',
      body: JSON.stringify({ key, value: String(value), secret: false }),
    });
  }
  const suffix = missing.length ? ` (пустые: ${missing.join(', ')})` : '';
  console.log(`${functionId.padEnd(30)} ${Object.keys(vars).length} vars${suffix}`);
}
