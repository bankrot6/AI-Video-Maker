#!/usr/bin/env node
// Показывает статус активных деплойментов всех функций проекта Appwrite.
//
// Запуск: PROJECT=... KEY=... node scripts/check_appwrite_functions.mjs

const ENDPOINT = process.env.APPWRITE_ENDPOINT || 'http://158.160.254.66/v1';
const PROJECT = process.env.PROJECT;
const KEY = process.env.KEY;
if (!PROJECT || !KEY) throw new Error('env PROJECT and KEY are required');

async function api(path) {
  const res = await fetch(`${ENDPOINT}${path}`, {
    headers: { 'X-Appwrite-Project': PROJECT, 'X-Appwrite-Key': KEY },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${path}: ${text.slice(0, 300)}`);
  return JSON.parse(text);
}

const { functions } = await api('/functions');
let failed = 0;
let pending = 0;

for (const fn of functions) {
  const deployments = await api(`/functions/${fn.$id}/deployments`);
  const latest = (deployments.deployments || [])[0];
  const status = latest ? latest.status : 'none';
  if (status === 'failed') failed += 1;
  if (status === 'building' || status === 'waiting' || status === 'processing') pending += 1;
  const activeId = fn.deploymentId || fn.deployment;
  const active = activeId && activeId === (latest && latest.$id) ? 'active' : 'not-active';
  console.log(`${fn.$id.padEnd(30)} ${String(status).padEnd(12)} ${active}`);
  if (status === 'failed' && latest.buildLogs) {
    console.log(`  ${latest.buildLogs.slice(-600).replace(/\n/g, '\n  ')}`);
  }
}

console.log(`\ntotal=${functions.length} failed=${failed} pending=${pending}`);
if (pending > 0) process.exitCode = 2;
if (failed > 0) process.exitCode = 1;
