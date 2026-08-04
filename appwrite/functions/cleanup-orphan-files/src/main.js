import { Client, Databases, Storage, Query } from 'node-appwrite';

const BUCKET_ID = process.env.BUCKET_ID ?? 'user-photos';
const DATABASE_ID = process.env.DATABASE_ID ?? 'main';
const KEEP_HOURS = parseInt(process.env.KEEP_HOURS ?? '24', 10);
const PAGE_SIZE = parseInt(process.env.PAGE_SIZE ?? '1000', 10);
const MAX_FILES_PER_RUN = parseInt(process.env.MAX_FILES_PER_RUN ?? '5000', 10);
const DELETE_CONCURRENCY = parseInt(process.env.DELETE_CONCURRENCY ?? '10', 10);

const REFERENCE_SOURCES = [
  {
    collection: 'user_generations',
    fields: ['resultImageUrl', 'userImageUrl', 'referenceImageUrl'],
  },
  {
    collection: 'presets',
    fields: ['previewImageUrl', 'thumbnailUrl', 'thumbnailSourceUrl'],
  },
];

function extractFileId(url) {
  const match = String(url ?? '').match(/\/files\/([^/?#]+)/);
  return match?.[1] ?? null;
}

async function paginate(fetchPage, extractItems) {
  const items = [];
  let cursor = null;
  for (;;) {
    const queries = [Query.limit(PAGE_SIZE)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const page = await fetchPage(queries);
    const batch = extractItems(page);
    if (batch.length === 0) break;
    items.push(...batch);
    if (batch.length < PAGE_SIZE) break;
    cursor = batch[batch.length - 1].$id;
  }
  return items;
}

// Любой сбой чтения обязан прервать запуск целиком: неполный список ссылок
// превращает живые файлы пользователей в мнимых сирот, и мы их удалим.
async function collectReferencedFileIds(db, log) {
  const referenced = new Set();
  for (const { collection, fields } of REFERENCE_SOURCES) {
    const docs = await paginate(
      (queries) =>
        db.listDocuments(DATABASE_ID, collection, [
          ...queries,
          Query.select(['$id', ...fields]),
        ]),
      (page) => page.documents,
    );
    for (const doc of docs) {
      for (const field of fields) {
        const fileId = extractFileId(doc[field]);
        if (fileId) referenced.add(fileId);
      }
    }
    log(`${collection}: просмотрено документов ${docs.length}`);
  }
  return referenced;
}

// Полное сканирование до удаления: курсор пагинации ссылается на $id файла,
// поэтому удалять во время обхода нельзя — курсор станет невалидным.
async function collectOrphans(storage, referenced, cutoffMs, log) {
  const files = await paginate(
    (queries) => storage.listFiles(BUCKET_ID, queries),
    (page) => page.files,
  );

  const orphans = [];
  let keptReferenced = 0;
  let keptFresh = 0;

  for (const file of files) {
    if (referenced.has(file.$id)) {
      keptReferenced++;
    } else if (new Date(file.$createdAt).getTime() >= cutoffMs) {
      keptFresh++;
    } else {
      orphans.push(file);
    }
  }

  log(
    `бакет: файлов ${files.length}, используются ${keptReferenced}, свежих ${keptFresh}, сирот ${orphans.length}`,
  );
  return { orphans, scanned: files.length, keptReferenced, keptFresh };
}

async function mapWithConcurrency(items, limit, worker) {
  let next = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    for (;;) {
      const index = next++;
      if (index >= items.length) return;
      await worker(items[index]);
    }
  });
  await Promise.all(runners);
}

// Записи без файла на диске Appwrite удалить не даёт: unlink падает, приходит 500,
// а строка в БД остаётся. Считаем их отдельно, иначе лог тонет в одинаковых ошибках.
async function deleteOrphans(storage, orphans, log, error) {
  let deleted = 0;
  let ghosts = 0;
  let errors = 0;
  let freedBytes = 0;
  const samples = [];

  await mapWithConcurrency(orphans, DELETE_CONCURRENCY, async (file) => {
    try {
      await storage.deleteFile(BUCKET_ID, file.$id);
      deleted++;
      freedBytes += file.sizeOriginal ?? 0;
    } catch (e) {
      if (e.code === 404) {
        deleted++;
      } else if (e.code === 500) {
        ghosts++;
        if (samples.length < 5) samples.push(file.$id);
      } else {
        error(`не удалось удалить ${file.$id}: ${e.message}`);
        errors++;
      }
    }
  });

  if (ghosts > 0) {
    log(`записей без файла на диске: ${ghosts} (примеры: ${samples.join(', ')})`);
  }

  return { deleted, ghosts, errors, freedBytes };
}

export default async ({ req, res, log, error }) => {
  const apiKey = process.env.APPWRITE_API_KEY ?? process.env.APPWRITE_FUNCTION_API_KEY;
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(apiKey);

  const db = new Databases(client);
  const storage = new Storage(client);
  const cutoffMs = Date.now() - KEEP_HOURS * 3600_000;
  const dryRun = String(req?.query?.dryRun ?? '') === '1';

  log(`очистка сирот: храним файлы новее ${KEEP_HOURS}ч (граница ${new Date(cutoffMs).toISOString()})`);

  let referenced;
  let scan;
  try {
    referenced = await collectReferencedFileIds(db, log);
    log(`собрано ссылок на файлы: ${referenced.size}`);
    scan = await collectOrphans(storage, referenced, cutoffMs, log);
  } catch (e) {
    error(`обход прерван, удаление не выполнялось: ${e.message}`);
    return res.json({ aborted: true, reason: e.message, deleted: 0 }, 503);
  }

  const planned = scan.orphans.slice(0, MAX_FILES_PER_RUN);
  const remaining = scan.orphans.length - planned.length;

  if (dryRun) {
    return res.json({
      dry_run: true,
      referenced_files: referenced.size,
      scanned: scan.scanned,
      orphans: scan.orphans.length,
      would_delete: planned.length,
      remaining,
    });
  }

  const { deleted, ghosts, errors, freedBytes } = await deleteOrphans(storage, planned, log, error);
  const freedGb = parseFloat((freedBytes / 1024 ** 3).toFixed(2));

  log(
    `готово: удалено ${deleted}, призрачных ${ghosts}, ошибок ${errors}, освобождено ${freedGb} ГБ, осталось ${remaining}`,
  );

  return res.json({
    referenced_files: referenced.size,
    scanned: scan.scanned,
    skipped: scan.keptReferenced + scan.keptFresh,
    deleted,
    ghosts,
    errors,
    freed_gb: freedGb,
    remaining,
    keep_hours: KEEP_HOURS,
  });
};
