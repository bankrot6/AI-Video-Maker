#!/usr/bin/env node
/**
 * Удаляет дублирующиеся пресеты из Appwrite.
 *
 * Критерии дублирования:
 *   1. Одинаковые sourceChannel + sourcePostId (один и тот же пост из Telegram)
 *   2. Пресеты без sourceChannel/sourcePostId, у которых prompt совпадает
 *      с уже имеющимся пресетом (попали через Firebase-sync без метаданных)
 *
 * Стратегия сохранения:
 *   - Из группы с одинаковым sourceChannel+sourcePostId оставляем тот,
 *     у которого есть thumbnailUrl; иначе — с наибольшим likesCount;
 *     иначе — самый старый (наименьший createdAt).
 *   - Пресеты без sourceChannel/sourcePostId, чей prompt дублирует
 *     пресет «с источником», — удаляются.
 *
 * Запуск:
 *   APPWRITE_ENDPOINT=https://... \
 *   APPWRITE_PROJECT_ID=... \
 *   APPWRITE_API_KEY=... \
 *   APPWRITE_DATABASE_ID=main \
 *   APPWRITE_PRESETS_COLLECTION_ID=presets \
 *   node scripts/delete_appwrite_duplicates.js [--dry-run]
 */

import { Client, Databases, Query } from 'node-appwrite';

const DRY_RUN = process.argv.includes('--dry-run');

function makeClient() {
  const endpoint  = process.env.APPWRITE_ENDPOINT?.trim();
  const projectId = process.env.APPWRITE_PROJECT_ID?.trim();
  const apiKey    = process.env.APPWRITE_API_KEY?.trim();
  if (!endpoint || !projectId || !apiKey) {
    console.error('Необходимо задать APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY');
    process.exit(1);
  }
  return new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
}

const DATABASE_ID   = process.env.APPWRITE_DATABASE_ID              ?? 'main';
const PRESETS_COLL  = process.env.APPWRITE_PRESETS_COLLECTION_ID    ?? 'presets';
const PAGE_SIZE     = 500;

async function fetchAllPresets(databases) {
  const all = [];
  let offset = 0;
  while (true) {
    const res = await databases.listDocuments(DATABASE_ID, PRESETS_COLL, [
      Query.limit(PAGE_SIZE),
      Query.offset(offset),
      Query.orderAsc('$createdAt'),
    ]);
    all.push(...res.documents);
    console.log(`  Загружено: ${all.length} / ${res.total}`);
    if (res.documents.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
  }
  return all;
}

function pickSurvivor(group) {
  // Предпочитаем: есть thumbnailUrl → наибольший likesCount → самый старый
  const withThumb = group.filter(d => d.thumbnailUrl);
  const pool = withThumb.length ? withThumb : group;
  return pool.reduce((best, cur) => {
    if ((cur.likesCount ?? 0) > (best.likesCount ?? 0)) return cur;
    if ((cur.likesCount ?? 0) === (best.likesCount ?? 0)) {
      return (cur.createdAt ?? '') < (best.createdAt ?? '') ? cur : best;
    }
    return best;
  });
}

async function deleteDoc(databases, docId) {
  if (DRY_RUN) {
    console.log(`  [dry-run] удалить ${docId}`);
    return;
  }
  await databases.deleteDocument(DATABASE_ID, PRESETS_COLL, docId);
  console.log(`  Удалён: ${docId}`);
}

async function main() {
  console.log(DRY_RUN ? '=== РЕЖИМ DRY-RUN (без реальных удалений) ===' : '=== РЕАЛЬНОЕ УДАЛЕНИЕ ===');

  const client    = makeClient();
  const databases = new Databases(client);

  console.log('\nЗагружаем все пресеты…');
  const presets = await fetchAllPresets(databases);
  console.log(`Всего пресетов: ${presets.length}\n`);

  let deletedCount = 0;

  // ── 1. Дубли по sourceChannel + sourcePostId ─────────────────────────
  const bySourceKey = new Map();
  for (const doc of presets) {
    const ch  = doc.sourceChannel;
    const pid = doc.sourcePostId;
    if (typeof ch === 'string' && ch.trim() && pid != null && String(pid).trim()) {
      const key = `${ch}|${String(pid)}`;
      if (!bySourceKey.has(key)) bySourceKey.set(key, []);
      bySourceKey.get(key).push(doc);
    }
  }

  console.log(`Групп с sourceChannel+sourcePostId: ${bySourceKey.size}`);
  let sourceGroups = 0;
  for (const [key, group] of bySourceKey) {
    if (group.length < 2) continue;
    sourceGroups++;
    const survivor = pickSurvivor(group);
    console.log(`\nДубль по ключу "${key}" (${group.length} шт.), оставляем ${survivor.$id}`);
    for (const doc of group) {
      if (doc.$id !== survivor.$id) {
        await deleteDoc(databases, doc.$id);
        deletedCount++;
      }
    }
  }
  console.log(`\nГрупп с дублями по source-ключу: ${sourceGroups}`);

  // ── 2. Пресеты без source-данных, у которых prompt совпадает ─────────
  // (попали через Firebase→Appwrite sync без sourceChannel/sourcePostId)
  const withSource    = presets.filter(d => d.sourceChannel && d.sourcePostId);
  const withoutSource = presets.filter(d => !d.sourceChannel || !d.sourcePostId);

  const sourcePrompts = new Set(withSource.map(d => (d.prompt ?? '').trim()));

  console.log(`\nПресетов с источником: ${withSource.length}`);
  console.log(`Пресетов без источника: ${withoutSource.length}`);

  let orphanDupes = 0;
  for (const doc of withoutSource) {
    const p = (doc.prompt ?? '').trim();
    if (p && sourcePrompts.has(p)) {
      orphanDupes++;
      console.log(`\nОрфан-дубль (нет source, промпт совпадает): ${doc.$id} title="${doc.title}"`);
      await deleteDoc(databases, doc.$id);
      deletedCount++;
    }
  }
  console.log(`\nОрфан-дублей удалено: ${orphanDupes}`);

  console.log(`\n✅ Итого удалено: ${deletedCount} пресетов${DRY_RUN ? ' (dry-run)' : ''}`);
}

main().catch(err => {
  console.error('Ошибка:', err.message);
  process.exit(1);
});
