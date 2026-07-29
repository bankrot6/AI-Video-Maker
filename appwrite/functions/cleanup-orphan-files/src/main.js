import { Client, Databases, Storage, Query } from 'node-appwrite';

const BUCKET_ID = process.env.BUCKET_ID ?? 'user-photos';
const DATABASE_ID = process.env.DATABASE_ID ?? 'main';
const KEEP_HOURS = parseInt(process.env.KEEP_HOURS ?? '24', 10);
const PAGE_SIZE = 100;
const MAX_FILES_PER_RUN = parseInt(process.env.MAX_FILES_PER_RUN ?? '5000', 10);

export default async ({ req, res, log, error }) => {
  const apiKey = process.env.APPWRITE_API_KEY ?? process.env.APPWRITE_FUNCTION_API_KEY;
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(apiKey);

  const db = new Databases(client);
  const storage = new Storage(client);

  const cutoffMs = Date.now() - KEEP_HOURS * 3600_000;
  log(`Orphan files cleanup: keep files newer than ${KEEP_HOURS}h (cutoff ${new Date(cutoffMs).toISOString()})`);

  log('Step 1: collecting referenced file IDs from user_generations and presets...');
  const referenced = new Set();

  for (const { collection, fields } of [
    { collection: 'user_generations', fields: ['resultImageUrl', 'userImageUrl', 'referenceImageUrl'] },
    { collection: 'presets', fields: ['previewImageUrl', 'thumbnailUrl', 'thumbnailSourceUrl'] },
  ]) {
    let cursor = null;
    while (true) {
      const queries = [Query.limit(PAGE_SIZE)];
      if (cursor) queries.push(Query.cursorAfter(cursor));
      let page;
      try {
        page = await db.listDocuments(DATABASE_ID, collection, queries);
      } catch (e) {
        error(`Failed to list ${collection}: ${e.message}`);
        break;
      }
      if (page.documents.length === 0) break;
      for (const doc of page.documents) {
        for (const f of fields) {
          const url = doc[f];
          if (!url || !url.includes('/files/')) continue;
          const m = url.match(/\/files\/([^/?#]+)/);
          if (m) referenced.add(m[1]);
        }
      }
      if (page.documents.length < PAGE_SIZE) break;
      cursor = page.documents[page.documents.length - 1].$id;
    }
  }
  log(`Referenced fileIds: ${referenced.size}`);

  log('Step 2: scanning bucket for orphans...');
  let deleted = 0;
  let skipped = 0;
  let errors = 0;
  let freedBytes = 0;
  let cursor = null;

  while (deleted + errors < MAX_FILES_PER_RUN) {
    let page;
    try {
      page = await storage.listFiles(BUCKET_ID, [Query.limit(PAGE_SIZE)], undefined, cursor ?? undefined);
    } catch (e) {
      error(`Failed to list bucket files: ${e.message}`);
      break;
    }
    if (page.files.length === 0) break;

    for (const file of page.files) {
      const created = new Date(file.$createdAt).getTime();
      if (created >= cutoffMs) {
        skipped++;
        continue;
      }
      if (referenced.has(file.$id)) {
        skipped++;
        continue;
      }
      try {
        await storage.deleteFile(BUCKET_ID, file.$id);
        deleted++;
        freedBytes += file.sizeOriginal ?? 0;
      } catch (e) {
        if (e.code === 404) {
          deleted++;
        } else {
          error(`Failed to delete ${file.$id}: ${e.message}`);
          errors++;
        }
      }
      if (deleted + errors >= MAX_FILES_PER_RUN) break;
    }

    if (page.files.length < PAGE_SIZE) break;
    cursor = page.files[page.files.length - 1].$id;
  }

  const freedGb = (freedBytes / 1024 / 1024 / 1024).toFixed(2);
  const summary = {
    referenced_files: referenced.size,
    deleted,
    skipped,
    errors,
    freed_gb: parseFloat(freedGb),
    keep_hours: KEEP_HOURS,
  };
  log(`Done: deleted=${deleted}, skipped=${skipped}, errors=${errors}, freed=${freedGb}GB`);
  return res.json(summary);
};
