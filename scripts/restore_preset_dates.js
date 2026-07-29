#!/usr/bin/env node
/**
 * Восстанавливает поле createdAt у пресетов Appwrite:
 * если кастомный createdAt расходится с системным $createdAt
 * больше чем на 5 секунд — копирует $createdAt → createdAt.
 *
 * Запуск:
 *   node scripts/restore_preset_dates.js --dry-run   # только показать
 *   node scripts/restore_preset_dates.js             # реально исправить
 */

import { Client, Databases, Query } from 'node-appwrite';

const DRY_RUN = process.argv.includes('--dry-run');

const ENDPOINT   = process.env.APPWRITE_ENDPOINT?.trim();
const PROJECT_ID = process.env.APPWRITE_PROJECT_ID?.trim();
const API_KEY    = process.env.APPWRITE_API_KEY?.trim();
const DB_ID      = (process.env.APPWRITE_DATABASE_ID ?? 'main').trim();
const COLL_ID    = (process.env.APPWRITE_PRESETS_COLLECTION_ID ?? 'presets').trim();
const THRESHOLD_MS = 5_000;
const PAGE_SIZE    = 100;

if (!ENDPOINT || !PROJECT_ID || !API_KEY) {
  console.error('Необходимо задать APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY');
  process.exit(1);
}

const client    = new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
const databases = new Databases(client);

console.log(DRY_RUN
  ? '=== DRY-RUN: изменений не будет, только отчёт ==='
  : '=== РЕАЛЬНОЕ ИСПРАВЛЕНИЕ ===');
console.log(`Endpoint: ${ENDPOINT}`);
console.log(`Database: ${DB_ID} / Collection: ${COLL_ID}\n`);

let offset   = 0;
let total    = 0;
let toFix    = 0;
let fixed    = 0;

while (true) {
  const res = await databases.listDocuments(DB_ID, COLL_ID, [
    Query.limit(PAGE_SIZE),
    Query.offset(offset),
    Query.orderAsc('$createdAt'),
  ]);

  if (!res.documents.length) break;
  total += res.documents.length;

  for (const doc of res.documents) {
    const sysDate    = doc.$createdAt;           // ISO, иммутабельно
    const customDate = doc.createdAt;            // кастомное поле

    if (!sysDate || !customDate) continue;

    const diffMs = Math.abs(new Date(sysDate) - new Date(customDate));
    if (diffMs <= THRESHOLD_MS) continue;

    toFix++;
    const arrow = customDate > sysDate ? '↓ (искусственно завышена)' : '↑ (занижена)';
    console.log(`  [${toFix}] ${doc.$id}`);
    console.log(`       title      : ${doc.title ?? '(нет)'}`);
    console.log(`       createdAt  : ${customDate}  ${arrow}`);
    console.log(`       $createdAt : ${sysDate}  ← будет восстановлено`);
    console.log(`       разница    : ${Math.round(diffMs / 1000 / 60)} мин\n`);

    if (!DRY_RUN) {
      await databases.updateDocument(DB_ID, COLL_ID, doc.$id, {
        createdAt: sysDate,
      });
      fixed++;
    }
  }

  process.stdout.write(`  Проверено: ${total}...\r`);
  if (res.documents.length < PAGE_SIZE) break;
  offset += PAGE_SIZE;
}

console.log(`\n${'─'.repeat(50)}`);
console.log(`Всего пресетов: ${total}`);
console.log(`С расходящейся датой: ${toFix}`);
if (DRY_RUN) {
  console.log(`\n→ Запустите без --dry-run чтобы исправить ${toFix} пресетов`);
} else {
  console.log(`Исправлено: ${fixed}`);
}
