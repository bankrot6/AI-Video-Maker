import { Client, Databases, Storage, Query } from 'node-appwrite';

const BUCKET_ID = process.env.BUCKET_ID ?? 'user-photos';
const DATABASE_ID = process.env.DATABASE_ID ?? 'main';
const PAGE_SIZE = 100;
const GB = 1024 * 1024 * 1024;

const SAFE_GB = parseFloat(process.env.SAFE_GB ?? '12');
const WARN_GB = parseFloat(process.env.WARN_GB ?? '15');
const DANGER_GB = parseFloat(process.env.DANGER_GB ?? '18');
const CRITICAL_GB = parseFloat(process.env.CRITICAL_GB ?? '22');
const MAX_DELETE_PER_RUN = parseInt(process.env.MAX_DELETE_PER_RUN ?? '3000', 10);

function pickStrategy(sizeGb) {
  if (sizeGb >= CRITICAL_GB) {
    return { level: 'CRITICAL', keepHours: 0, includeReferenced: false };
  }
  if (sizeGb >= DANGER_GB) {
    return { level: 'DANGER', keepHours: 1, includeReferenced: false };
  }
  if (sizeGb >= WARN_GB) {
    return { level: 'WARN', keepHours: 6, includeReferenced: false };
  }
  if (sizeGb >= SAFE_GB) {
    return { level: 'SAFE', keepHours: 24, includeReferenced: false };
  }
  return { level: 'OK', keepHours: null, includeReferenced: false };
}

async function collectReferencedIds(db, log, error) {
  const referenced = new Set();
  const collections = [
    { collection: 'user_generations', fields: ['resultImageUrl', 'userImageUrl', 'referenceImageUrl'] },
    { collection: 'presets', fields: ['previewImageUrl', 'thumbnailUrl', 'thumbnailSourceUrl'] },
  ];

  for (const { collection, fields } of collections) {
    let cursor = null;
    while (true) {
      const queries = [Query.limit(PAGE_SIZE)];
      if (cursor) queries.push(Query.cursorAfter(cursor));
      let page;
      try {
        page = await db.listDocuments(DATABASE_ID, collection, queries);
      } catch (e) {
        error(`listDocuments(${collection}) failed: ${e.message}`);
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
  return referenced;
}

export default async ({ req, res, log, error }) => {
  const apiKey = process.env.APPWRITE_API_KEY ?? process.env.APPWRITE_FUNCTION_API_KEY;
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(apiKey);

  const db = new Databases(client);
  const storage = new Storage(client);

  log(`Bucket size guard: thresholds SAFE=${SAFE_GB} WARN=${WARN_GB} DANGER=${DANGER_GB} CRITICAL=${CRITICAL_GB} GB`);

  log('Step 1: collecting referenced file IDs...');
  const referenced = await collectReferencedIds(db, log, error);
  log(`Referenced files in DB: ${referenced.size}`);

  log('Step 2: scanning bucket and computing total size...');
  const allFiles = [];
  let totalBytes = 0;
  let cursor = null;
  let pageNum = 0;
  const MAX_PAGES = 200;

  while (pageNum < MAX_PAGES) {
    const queries = [Query.limit(PAGE_SIZE), Query.orderAsc('$id')];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    let page;
    try {
      page = await storage.listFiles(BUCKET_ID, queries);
    } catch (e) {
      error(`listFiles failed (page ${pageNum}): ${e.message}`);
      break;
    }
    pageNum++;
    if (page.files.length === 0) break;
    for (const f of page.files) {
      const size = f.sizeOriginal ?? 0;
      totalBytes += size;
      allFiles.push({
        id: f.$id,
        createdAt: f.$createdAt,
        size,
        isOrphan: !referenced.has(f.$id),
      });
    }
    if (page.files.length < PAGE_SIZE) break;
    cursor = page.files[page.files.length - 1].$id;
  }
  log(`Scanned ${pageNum} pages, ${allFiles.length} files total.`);

  const sizeGb = totalBytes / GB;
  const strategy = pickStrategy(sizeGb);

  log(`Bucket state: files=${allFiles.length}, size=${sizeGb.toFixed(2)}GB, level=${strategy.level}`);

  if (strategy.level === 'OK') {
    log('Below SAFE threshold — no cleanup needed.');
    return res.json({
      level: strategy.level,
      total_files: allFiles.length,
      total_size_gb: parseFloat(sizeGb.toFixed(2)),
      deleted: 0,
    });
  }

  log(`Cleanup strategy: keepHours=${strategy.keepHours}`);

  const cutoffMs = Date.now() - strategy.keepHours * 3600_000;
  const candidates = allFiles
    .filter((f) => f.isOrphan && new Date(f.createdAt).getTime() < cutoffMs)
    .sort((a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime());

  log(`Orphan candidates older than ${strategy.keepHours}h: ${candidates.length}`);

  let deleted = 0;
  let errors = 0;
  let freedBytes = 0;
  const targetBytes = SAFE_GB * GB;

  for (const c of candidates) {
    if (deleted >= MAX_DELETE_PER_RUN) {
      log(`Reached MAX_DELETE_PER_RUN=${MAX_DELETE_PER_RUN}, stopping.`);
      break;
    }
    if (totalBytes - freedBytes <= targetBytes && strategy.level !== 'CRITICAL') {
      log(`Reached SAFE size (${(totalBytes - freedBytes) / GB} GB), stopping.`);
      break;
    }
    try {
      await storage.deleteFile(BUCKET_ID, c.id);
      deleted++;
      freedBytes += c.size;
    } catch (e) {
      if (e.code === 404) {
        deleted++;
      } else {
        error(`delete ${c.id}: ${e.message}`);
        errors++;
      }
    }
  }

  const freedGb = (freedBytes / GB).toFixed(2);
  const finalGb = ((totalBytes - freedBytes) / GB).toFixed(2);
  log(`Done: level=${strategy.level} deleted=${deleted} errors=${errors} freed=${freedGb}GB final=${finalGb}GB`);

  return res.json({
    level: strategy.level,
    total_files_before: allFiles.length,
    total_size_gb_before: parseFloat(sizeGb.toFixed(2)),
    referenced_files: referenced.size,
    keep_hours: strategy.keepHours,
    deleted,
    errors,
    freed_gb: parseFloat(freedGb),
    final_size_gb: parseFloat(finalGb),
  });
};
