#!/usr/bin/env node
// Клонирует функции Appwrite из проекта-источника в проект-приёмник:
// настройки, переменные окружения и код активного деплоймента.
//
// Запуск:
//   SRC_PROJECT=... SRC_KEY=... DST_PROJECT=... DST_KEY=... \
//   node scripts/clone_appwrite_functions.mjs

import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const ENDPOINT = process.env.APPWRITE_ENDPOINT || 'http://158.160.254.66/v1';
const CHUNK_SIZE = 5 * 1024 * 1024;

const SRC = { project: required('SRC_PROJECT'), key: required('SRC_KEY') };
const DST = { project: required('DST_PROJECT'), key: required('DST_KEY') };

// Переменные, значение которых должно указывать на новый проект, а не на источник.
const VARIABLE_OVERRIDES = {
  APPWRITE_PROJECT_ID: DST.project,
  APPWRITE_API_KEY: DST.key,
  ...(process.env.RUSTORE_APP_ID ? { RUSTORE_APP_ID: process.env.RUSTORE_APP_ID } : {}),
};

function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`env ${name} is required`);
  return value;
}

function headers(ctx, extra = {}) {
  return {
    'X-Appwrite-Project': ctx.project,
    'X-Appwrite-Key': ctx.key,
    ...extra,
  };
}

async function api(ctx, path, init = {}) {
  const res = await fetch(`${ENDPOINT}${path}`, {
    ...init,
    headers: headers(ctx, { 'Content-Type': 'application/json', ...(init.headers || {}) }),
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

async function downloadDeployment(functionId, deploymentId, target) {
  const res = await fetch(
    `${ENDPOINT}/functions/${functionId}/deployments/${deploymentId}/download`,
    { headers: headers(SRC) },
  );
  if (!res.ok) throw new Error(`download ${functionId}: ${res.status} ${await res.text()}`);
  writeFileSync(target, Buffer.from(await res.arrayBuffer()));
}

async function uploadDeployment(functionId, filePath, fn) {
  const buffer = readFileSync(filePath);
  const total = buffer.length;
  const fileName = `${functionId}.tar.gz`;
  let deploymentId = 'unique()';
  let last;

  for (let start = 0; start < total; start += CHUNK_SIZE) {
    const end = Math.min(start + CHUNK_SIZE, total);
    const form = new FormData();
    form.append('activate', 'true');
    if (fn.entrypoint) form.append('entrypoint', fn.entrypoint);
    if (fn.commands) form.append('commands', fn.commands);
    form.append(
      'code',
      new Blob([buffer.subarray(start, end)], { type: 'application/x-gzip' }),
      fileName,
    );

    const extra = {};
    if (total > CHUNK_SIZE) {
      extra['content-range'] = `bytes ${start}-${end - 1}/${total}`;
      if (deploymentId !== 'unique()') extra['x-appwrite-id'] = deploymentId;
    }

    const res = await fetch(`${ENDPOINT}/functions/${functionId}/deployments`, {
      method: 'POST',
      headers: headers(DST, extra),
      body: form,
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`upload ${functionId}: ${res.status} ${text.slice(0, 300)}`);
    last = JSON.parse(text);
    if (last.$id) deploymentId = last.$id;
  }
  return last;
}

async function cloneVariables(functionId) {
  const src = await must(SRC, `/functions/${functionId}/variables`);
  const dst = await must(DST, `/functions/${functionId}/variables`);
  const existing = new Map((dst.variables || []).map((v) => [v.key, v.$id]));

  for (const variable of src.variables || []) {
    const value = VARIABLE_OVERRIDES[variable.key] ?? variable.value;
    const payload = JSON.stringify({ key: variable.key, value, secret: variable.secret ?? false });
    const id = existing.get(variable.key);
    if (id) {
      await must(DST, `/functions/${functionId}/variables/${id}`, { method: 'PUT', body: payload });
    } else {
      await must(DST, `/functions/${functionId}/variables`, { method: 'POST', body: payload });
    }
  }
  return (src.variables || []).length;
}

const workDir = mkdtempSync(join(tmpdir(), 'aw-fn-'));
const list = await must(SRC, '/functions');
const only = process.argv.slice(2);
const functions = (list.functions || []).filter((f) => only.length === 0 || only.includes(f.$id));

for (const fn of functions) {
  console.log(`\n=== ${fn.$id} (${fn.name}) ===`);
  const payload = {
    functionId: fn.$id,
    name: fn.name,
    runtime: fn.runtime,
    execute: fn.execute,
    events: fn.events,
    schedule: fn.schedule,
    timeout: fn.timeout,
    enabled: fn.enabled,
    logging: fn.logging,
    entrypoint: fn.entrypoint,
    commands: fn.commands,
    scopes: fn.scopes,
  };

  const exists = await api(DST, `/functions/${fn.$id}`);
  if (exists.ok) {
    await must(DST, `/functions/${fn.$id}`, { method: 'PUT', body: JSON.stringify(payload) });
    console.log('  settings: updated');
  } else {
    await must(DST, '/functions', { method: 'POST', body: JSON.stringify(payload) });
    console.log('  settings: created');
  }

  const count = await cloneVariables(fn.$id);
  console.log(`  variables: ${count}`);

  const deploymentId = fn.deployment || fn.deploymentId;
  if (!deploymentId) {
    console.log('  ! no active deployment in source, code skipped');
    continue;
  }
  // У части функций entrypoint задан только на уровне деплоймента,
  // а в настройках функции пуст — тогда берём его из исходного деплоймента.
  const srcDeployment = await must(SRC, `/functions/${fn.$id}/deployments/${deploymentId}`);
  const buildConfig = {
    entrypoint: fn.entrypoint || srcDeployment.entrypoint,
    commands: fn.commands || srcDeployment.commands,
  };

  const archive = join(workDir, `${fn.$id}.tar.gz`);
  await downloadDeployment(fn.$id, deploymentId, archive);
  const deployment = await uploadDeployment(fn.$id, archive, buildConfig);
  console.log(`  deployment: ${deployment.$id} (build started)`);
}

rmSync(workDir, { recursive: true, force: true });
console.log('\nfunctions clone finished');
