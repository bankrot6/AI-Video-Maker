import { Client, Databases, Storage, Query } from 'node-appwrite';

const INACTIVE_DAYS = parseInt(process.env.INACTIVE_DAYS ?? '14', 10);
const BUCKET_ID = process.env.APPWRITE_STORAGE_BUCKET_ID ?? 'user-photos';
const DATABASE_ID = process.env.APPWRITE_DATABASE_ID ?? '';
const COLLECTION_ID = process.env.APPWRITE_COLLECTION_ID ?? 'user_generations';

export default async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY ?? process.env.APPWRITE_FUNCTION_API_KEY ?? '');

  const db = new Databases(client);
  const storage = new Storage(client);

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - INACTIVE_DAYS);
  const cutoffIso = cutoff.toISOString();

  log(`TTL cleanup: ищем пользователей без активности ${INACTIVE_DAYS}+ дней (до ${cutoffIso})`);

  // Шаг 1: собираем всех пользователей у которых есть генерации
  const allUserIds = new Set();
  let cursor = null;

  while (true) {
    const queries = [Query.limit(100)];
    if (cursor) queries.push(Query.cursorAfter(cursor));

    let page;
    try {
      page = await db.listDocuments(DATABASE_ID, COLLECTION_ID, queries);
    } catch (e) {
      error(`Ошибка получения списка генераций: ${e.message}`);
      break;
    }

    if (page.documents.length === 0) break;

    for (const doc of page.documents) {
      const userId = doc.userId ?? doc.firebaseUid ?? doc.$permissions
        ?.find(p => p.startsWith('delete("user:'))
        ?.match(/delete\("user:([^"]+)"\)/)?.[1];
      if (userId) allUserIds.add(userId);
    }

    if (page.documents.length < 100) break;
    cursor = page.documents[page.documents.length - 1].$id;
  }

  log(`Найдено уникальных пользователей: ${allUserIds.size}`);

  // Шаг 2: для каждого пользователя проверяем — есть ли у него НОВЫЕ генерации
  // Если самая новая генерация старше cutoff — пользователь неактивен, удаляем всё
  let deletedDocs = 0;
  let deletedFiles = 0;
  let errors = 0;
  let skippedActiveUsers = 0;

  for (const userId of allUserIds) {
    // Ищем самую свежую генерацию пользователя
    let latestDoc;
    try {
      const latest = await db.listDocuments(DATABASE_ID, COLLECTION_ID, [
        Query.orderDesc('$createdAt'),
        Query.limit(1),
        // Фильтр по userId если поле существует, иначе по permissions
        ...(userId ? [] : []),
      ]);
      latestDoc = latest.documents.find(d =>
        (d.userId ?? d.firebaseUid) === userId ||
        d.$permissions?.some(p => p.includes(`user:${userId}`))
      ) ?? latest.documents[0];
    } catch (e) {
      error(`Ошибка получения последней генерации для ${userId}: ${e.message}`);
      continue;
    }

    if (!latestDoc) continue;

    const latestDate = new Date(latestDoc.$createdAt);
    if (latestDate >= cutoff) {
      // Пользователь активен — не трогаем
      skippedActiveUsers++;
      continue;
    }

    // Пользователь неактивен — удаляем все его генерации
    log(`Пользователь ${userId}: последняя активность ${latestDoc.$createdAt}, удаляем`);

    let userCursor = null;
    while (true) {
      const queries = [Query.limit(100)];
      if (userCursor) queries.push(Query.cursorAfter(userCursor));

      let page;
      try {
        page = await db.listDocuments(DATABASE_ID, COLLECTION_ID, queries);
      } catch (e) {
        error(`Ошибка запроса документов пользователя ${userId}: ${e.message}`);
        break;
      }

      const userDocs = page.documents.filter(d =>
        (d.userId ?? d.firebaseUid) === userId ||
        d.$permissions?.some(p => p.includes(`user:${userId}`))
      );

      if (userDocs.length === 0 && page.documents.length < 100) break;

      for (const doc of userDocs) {
        const fileIds = extractFileIds([
          doc.resultImageUrl,
          doc.userImageUrl,
          doc.referenceImageUrl,
        ]);

        for (const fileId of fileIds) {
          try {
            await storage.deleteFile(BUCKET_ID, fileId);
            deletedFiles++;
          } catch (e) {
            if (e.code !== 404) {
              error(`Ошибка удаления файла ${fileId}: ${e.message}`);
              errors++;
            }
          }
        }

        try {
          await db.deleteDocument(DATABASE_ID, COLLECTION_ID, doc.$id);
          deletedDocs++;
        } catch (e) {
          error(`Ошибка удаления документа ${doc.$id}: ${e.message}`);
          errors++;
        }
      }

      if (page.documents.length < 100) break;
      userCursor = page.documents[page.documents.length - 1].$id;
    }
  }

  const summary = {
    cutoffDate: cutoffIso,
    inactiveDays: INACTIVE_DAYS,
    checkedUsers: allUserIds.size,
    skippedActiveUsers,
    deletedDocuments: deletedDocs,
    deletedFiles: deletedFiles,
    errors,
  };

  log(`TTL cleanup завершён: ${JSON.stringify(summary)}`);
  return res.json(summary);
};

function extractFileIds(urls) {
  const ids = [];
  for (const url of urls) {
    if (!url || !url.includes('/storage/buckets/')) continue;
    const match = url.match(/\/files\/([^/?#]+)/);
    if (match) ids.push(match[1]);
  }
  return ids;
}
