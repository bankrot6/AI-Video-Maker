#!/usr/bin/env node
// Делает активным последний успешно собранный деплоймент каждой функции
// и удаляет остальные деплойменты.
//
// Запуск: PROJECT=... KEY=... node scripts/activate_appwrite_deployments.mjs

import { existsSync } from 'node:fs';

if (existsSync(new URL('../PROJECT_PAUSED', import.meta.url))) {
  console.error('AI-Video-Maker is paused. See PROJECT_PAUSED before activating deployments.');
  process.exit(1);
}

const ENDPOINT = process.env.APPWRITE_ENDPOINT || 'http://158.160.254.66/v1';
const PROJECT = process.env.PROJECT;
const KEY = process.env.KEY;
if (!PROJECT || !KEY) throw new Error('env PROJECT and KEY are required');

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

const { functions } = await api('/functions');

for (const fn of functions) {
  const { deployments } = await api(`/functions/${fn.$id}/deployments`);
  const ready = (deployments || [])
    .filter((d) => d.status === 'ready')
    .sort((a, b) => new Date(b.$createdAt) - new Date(a.$createdAt));

  if (ready.length === 0) {
    console.log(`${fn.$id.padEnd(30)} no ready deployment`);
    continue;
  }

  const target = ready[0];
  if (fn.deployment !== target.$id) {
    await api(`/functions/${fn.$id}/deployments/${target.$id}`, { method: 'PATCH' });
  }

  for (const stale of deployments) {
    if (stale.$id !== target.$id) {
      await api(`/functions/${fn.$id}/deployments/${stale.$id}`, { method: 'DELETE' });
    }
  }

  const updated = await api(`/functions/${fn.$id}`);
  console.log(`${fn.$id.padEnd(30)} active=${updated.deployment}`);
}
