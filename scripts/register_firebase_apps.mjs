#!/usr/bin/env node
import { createSign } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SA = JSON.parse(readFileSync(resolve(ROOT, 'firebase-service-account.json'), 'utf8'));

const ANDROID_PACKAGE = process.env.ANDROID_PACKAGE || 'com.aivideomaker.app';
const IOS_BUNDLE = process.env.IOS_BUNDLE || ANDROID_PACKAGE;
const DISPLAY_NAME = process.env.APP_DISPLAY_NAME || 'AI Video Maker';

const b64url = (buf) => Buffer.from(buf).toString('base64url');

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = b64url(JSON.stringify({
    iss: SA.client_email,
    scope: 'https://www.googleapis.com/auth/cloud-platform',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }));
  const signer = createSign('RSA-SHA256');
  signer.update(`${header}.${claim}`);
  const signature = b64url(signer.sign(SA.private_key));
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claim}.${signature}`,
    }),
  });
  const json = await res.json();
  if (!json.access_token) throw new Error(`token error: ${JSON.stringify(json)}`);
  return json.access_token;
}

const BASE = `https://firebase.googleapis.com/v1beta1/projects/${SA.project_id}`;

async function api(token, path, init = {}) {
  const res = await fetch(path.startsWith('http') ? path : `${BASE}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
  const text = await res.text();
  let body;
  try { body = JSON.parse(text); } catch { body = text; }
  if (!res.ok) throw new Error(`${res.status} ${path}: ${text.slice(0, 500)}`);
  return body;
}

async function waitOperation(token, op) {
  let current = op;
  for (let i = 0; i < 30 && !current.done; i += 1) {
    await new Promise((r) => setTimeout(r, 2000));
    current = await api(token, `https://firebase.googleapis.com/v1beta1/${op.name}`);
  }
  if (current.error) throw new Error(JSON.stringify(current.error));
  return current.response;
}

async function ensureApp(token, kind, idField, idValue) {
  const list = await api(token, `/${kind}?pageSize=100`);
  const existing = (list[kind] || []).find((a) => a[idField] === idValue);
  if (existing) return existing;
  const op = await api(token, `/${kind}`, {
    method: 'POST',
    body: JSON.stringify({ [idField]: idValue, displayName: DISPLAY_NAME }),
  });
  return op.done ? op.response : waitOperation(token, op);
}

const token = await accessToken();

const android = await ensureApp(token, 'androidApps', 'packageName', ANDROID_PACKAGE);
const androidConfig = await api(token, `https://firebase.googleapis.com/v1beta1/${android.name}/config`);
writeFileSync(
  resolve(ROOT, 'android/app/google-services.json'),
  Buffer.from(androidConfig.configFileContents, 'base64'),
);
console.log(`android appId: ${android.appId}`);

const ios = await ensureApp(token, 'iosApps', 'bundleId', IOS_BUNDLE);
const iosConfig = await api(token, `https://firebase.googleapis.com/v1beta1/${ios.name}/config`);
writeFileSync(
  resolve(ROOT, 'ios/Runner/GoogleService-Info.plist'),
  Buffer.from(iosConfig.configFileContents, 'base64'),
);
console.log(`ios appId: ${ios.appId}`);
