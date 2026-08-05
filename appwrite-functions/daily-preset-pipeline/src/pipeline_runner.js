import crypto from 'crypto';
import { Query } from 'node-appwrite';
import { InputFile } from 'node-appwrite/file';
import { buildIdeas } from './idea_builder.js';
import {
  buildVideoPrompt,
  buildKeyframePrompt,
  structuredPromptBudget,
  trimToBoundary,
} from './video_prompt.js';

const NL_HOST             = process.env.NL_SERVER_HOST         || '';
const NL_TOKEN            = process.env.NL_PROXY_TOKEN          || '';
const PIAPI_PROXY_PORT    = process.env.AI_PROXY_PIAPI_PORT     || '8080';
const DEEPSEEK_PROXY_PORT = process.env.AI_PROXY_DEEPSEEK_PORT  || '8001';
const YANDEX_AI_RELAY_BASE_URL = (process.env.YANDEX_AI_RELAY_BASE_URL ?? '').trim();

function trimTrailingSlashes(value) {
  return String(value || '').trim().replace(/\/+$/, '');
}

function hasYandexRelay() {
  return Boolean(YANDEX_AI_RELAY_BASE_URL && NL_TOKEN);
}

function buildYandexRelayUrl(port, path) {
  const relayBaseUrl = trimTrailingSlashes(YANDEX_AI_RELAY_BASE_URL);
  return `${relayBaseUrl}/${encodeURIComponent(String(port))}/${String(path).replace(/^\/+/, '')}`;
}

function buildTokenizedNlPath(path) {
  return `/ai-${NL_TOKEN}/${String(path).replace(/^\/+/, '')}`;
}

const DEEPSEEK_BASE = hasYandexRelay()
  ? buildYandexRelayUrl(DEEPSEEK_PROXY_PORT, '/chat/completions')
  : NL_HOST && NL_TOKEN
    ? `http://${NL_HOST}:${DEEPSEEK_PROXY_PORT}/chat/completions`
    : 'https://api.deepseek.com/chat/completions';
const USE_DEEPSEEK_PROXY = hasYandexRelay() || (NL_HOST && NL_TOKEN);

const LENGTH_LIMIT_PLACEHOLDER = '{{LENGTH_LIMIT}}';

function deepSeekSystemPrompt(limit) {
  return DEEPSEEK_SYSTEM_PROMPT_TEMPLATE.replace(
    LENGTH_LIMIT_PLACEHOLDER,
    String(limit),
  );
}

const DEEPSEEK_SYSTEM_PROMPT_TEMPLATE = `Ты промпт-инженер генератора коротких вертикальных видео (8 секунд).

Тебе дадут ТЕХНИЧЕСКОЕ ЗАДАНИЕ на ролик из нашего каталога (сюжет, тематика, визуальный стиль, композиция, движение камеры, динамика, палитра, атмосфера). Разверни его в структурированный промпт нашего приложения.

ОБЯЗАТЕЛЬНАЯ СТРУКТУРА (5 разделов, все на РУССКОМ языке, именно эти заголовки):

ОПИСАНИЕ СЦЕНЫ:
[2-4 предложения. Что в кадре: главный объект, окружение, передний и задний планы. Конкретно — формы, материалы, фактуры, масштаб. Не отклоняйся от сюжета, только детализируй.]

КАМЕРА И ДВИЖЕНИЕ:
[2-3 предложения. Точка съёмки и движение камеры строго как в задании. Как меняется кадр за 8 секунд: скорость, траектория, фокус.]

СТИЛЬ И ТЕХНИКА:
[2-3 предложения. Дословно раскрой визуальный стиль: техника, линии/мазки, детализация, эстетика. Стиль должен читаться безошибочно на всём ролике.]

ЦВЕТ И СВЕТ:
[1-2 предложения. Доминирующие цвета, акценты, тип и направление света, атмосферные эффекты из задания.]

ДИНАМИКА ЗА 8 СЕКУНД:
[2-3 предложения. Beat движения из задания: что оживает, что меняется, где кульминация. Без склеек и смены сцен — один непрерывный шот.]

КРИТИЧЕСКИЕ ПРАВИЛА:
- Весь вывод ТОЛЬКО на русском языке
- Строго 5 разделов, именно эти заголовки, ничего лишнего
- В кадре НЕТ людей и частей тела, если сюжет прямо их не требует
- Не превращай задание в фотосессию и не описывай моделей, позы и одежду
- Жёсткий лимит длины: весь ответ не длиннее {{LENGTH_LIMIT}} символов вместе с заголовками и переносами строк. Более длинный текст видеомодель не примет — держись нижней границы диапазонов предложений, пиши плотно, без повторов и общих слов
- Никаких кавычек, вступлений и пояснений — только структура
- ФОРМАТ ВСЕГДА ВЕРТИКАЛЬНЫЙ 9:16, длительность 8 секунд
- Один непрерывный шот: без коллажей, рамок, субтитров, водяных знаков`;

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function stripMarkdownFences(s) {
  let t = s.trim();
  t = t.replace(/^```[^\n]*\n?/, '');
  t = t.replace(/\n?```$/, '');
  return t.trim();
}

async function createPresetDocument(databases, databaseId, presetsColl, docId, data, optionalKeys) {
  try {
    return await databases.createDocument(databaseId, presetsColl, docId, data, ['read("any")']);
  } catch (e) {
    const unknown = /Unknown attribute: "([^"]+)"/.exec(String(e.message || ''));
    if (!unknown || !optionalKeys.includes(unknown[1])) throw e;
    console.log(`Collection has no attribute "${unknown[1]}", retrying without it`);
    const { [unknown[1]]: _removed, ...rest } = data;
    return createPresetDocument(databases, databaseId, presetsColl, docId, rest, optionalKeys);
  }
}

function makePresetDocId() {
  const ts  = Date.now().toString(36);
  const rnd = Math.random().toString(36).slice(2, 10);
  return `p_${ts}_${rnd}`;
}

async function askDeepSeek(systemPrompt, userMsg, deepseekKey) {
  const dsHeaders = {
    'Content-Type': 'application/json',
    ...(USE_DEEPSEEK_PROXY
      ? { 'X-Ai-Proxy-Token': NL_TOKEN }
      : { Authorization: `Bearer ${deepseekKey}` }),
  };
  console.log(`DeepSeek via: ${DEEPSEEK_BASE}`);
  const resp = await fetch(DEEPSEEK_BASE, {
    method: 'POST',
    headers: dsHeaders,
    body: JSON.stringify({
      model: 'deepseek-v4-flash',
      thinking: { type: 'disabled' },
      messages: [{ role: 'system', content: systemPrompt }, { role: 'user', content: userMsg }],
      max_tokens: 1800,
      temperature: 0.65,
    }),
    signal: AbortSignal.timeout(90_000),
  });
  if (!resp.ok) throw new Error(`DeepSeek HTTP ${resp.status}: ${(await resp.text()).slice(0, 200)}`);
  const data = await resp.json();
  const content = data.choices?.[0]?.message?.content;
  return content ? (stripMarkdownFences(content) || null) : null;
}

const COMPRESSION_SYSTEM_PROMPT = 'Ты редактор промптов для генеративной видеомодели. '
  + 'Сокращаешь текст, не теряя смысла: сохраняешь все разделы и их заголовки, '
  + 'сюжет, движение камеры, свет, стиль и палитру. Убираешь только повторы, '
  + 'общие слова и второстепенные уточнения. Ответ: только сокращённый текст.';

/// Перерасход отдаётся обратно модели: она сама решит, чем пожертвовать.
/// Механическая обрезка остаётся страховкой, если и сжатие промахнулось.
async function fitStructuredPrompt(structured, limit, deepseekKey) {
  if (structured.length <= limit) return structured;

  console.log(`Structured prompt ${structured.length} > ${limit}, compressing`);
  try {
    const compressed = await askDeepSeek(
      COMPRESSION_SYSTEM_PROMPT,
      `Сократи текст ниже до ${limit} символов или меньше.\n\n${structured}`,
      deepseekKey,
    );
    if (compressed && compressed.length <= limit) {
      console.log(`Compressed to ${compressed.length} chars`);
      return compressed;
    }
    if (compressed && compressed.length < structured.length) {
      return trimToBoundary(compressed, limit);
    }
  } catch (e) {
    console.log(`Compression failed: ${e.message}`);
  }
  return trimToBoundary(structured, limit);
}

async function convertIdeaToStructure(idea, deepseekKey) {
  const limit = structuredPromptBudget(idea);
  const userMsg = [
    `Название ролика: ${idea.title}`,
    '',
    'ТЕХНИЧЕСКОЕ ЗАДАНИЕ:',
    idea.brief,
    '',
    'Разверни это задание в нашу структуру из 5 разделов для короткого видео.',
  ].join('\n');

  const structured = await askDeepSeek(
    deepSeekSystemPrompt(limit),
    userMsg,
    deepseekKey,
  );
  if (!structured) return null;
  return fitStructuredPrompt(structured, limit, deepseekKey);
}

const APIBOST_BASE = hasYandexRelay()
  ? buildYandexRelayUrl(PIAPI_PROXY_PORT, buildTokenizedNlPath('/apibost'))
  : NL_HOST && NL_TOKEN
    ? `http://${NL_HOST}:${PIAPI_PROXY_PORT}/ai-${NL_TOKEN}/apibost`
    : 'https://apibost.com';
const USE_APIBOST_PROXY = APIBOST_BASE.startsWith('http://');
const APIBOST_IMAGE_MODEL = process.env.APIBOST_MODEL || 'gemini-3-pro-image-preview';
const APIBOST_VIDEO_MODEL = process.env.APIBOST_VIDEO_MODEL || 'veo3.1-lite';

const VIDEO_URL_PATTERN = /https?:\/\/[^\s()<>"\]]+\.mp4/i;

function asList(value) {
  return Array.isArray(value) ? value : [];
}

function extractVideoUrl(data) {
  for (const candidate of asList(data?.candidates)) {
    const parts = asList(candidate?.content?.parts);
    for (const part of parts) {
      const text = part?.text;
      if (typeof text === 'string') {
        const match = VIDEO_URL_PATTERN.exec(text);
        if (match) return match[0];
      }
    }
  }
  for (const choice of asList(data?.choices)) {
    const content = choice?.message?.content;
    if (typeof content === 'string') {
      const match = VIDEO_URL_PATTERN.exec(content);
      if (match) return match[0];
    }
  }
  return null;
}

function extractFinishReason(data) {
  for (const candidate of asList(data?.candidates)) {
    if (candidate?.finishReason) return String(candidate.finishReason);
  }
  return null;
}

async function generateKeyframeWithApiBost(prompt, apiBostKey, idea) {
  const url = `${APIBOST_BASE}/v1beta/models/${APIBOST_IMAGE_MODEL}:generateContent`;
  console.log(`ApiBost keyframe via: ${url}, model=${APIBOST_IMAGE_MODEL}, temp=${idea.params.temperature}`);

  const enhancedPrompt = buildKeyframePrompt(prompt, idea);
  const payload = {
    contents: [{ role: 'user', parts: [{ text: enhancedPrompt }] }],
  };

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(USE_APIBOST_PROXY ? {} : { Authorization: `Bearer ${apiBostKey}` }),
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(120_000),
  });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`ApiBost keyframe HTTP ${resp.status}: ${body.slice(0, 200)}`);
  }

  const data = await resp.json();
  for (const candidate of asList(data.candidates)) {
    for (const part of asList(candidate?.content?.parts)) {
      const inlineData = part.inlineData || part.inline_data;
      if (inlineData?.data) {
        return Buffer.from(inlineData.data, 'base64');
      }
    }
  }

  console.log(`ApiBost: no keyframe, finishReason=${extractFinishReason(data)}`);
  return null;
}

async function downloadBytes(url, { timeoutMs = 180_000, label = 'download' } = {}) {
  const resp = await fetch(url, {
    headers: { 'User-Agent': 'AIVideoMaker/daily-preset-pipeline' },
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!resp.ok) {
    throw new Error(`${label} HTTP ${resp.status}`);
  }
  return Buffer.from(await resp.arrayBuffer());
}

async function downloadVideoBytes(videoUrl) {
  try {
    return await downloadBytes(videoUrl, { timeoutMs: 180_000, label: 'video' });
  } catch (firstErr) {
    // Ссылки ApiBost могут быть недоступны из РФ — пробуем через тот же NL/Yandex relay imgproxy-путь.
    if (!NL_HOST || !NL_TOKEN) throw firstErr;
    const proxyUrl = hasYandexRelay()
      ? buildYandexRelayUrl(PIAPI_PROXY_PORT, buildTokenizedNlPath(`/imgproxy?url=${encodeURIComponent(videoUrl)}`))
      : `http://${NL_HOST}:${PIAPI_PROXY_PORT}/ai-${NL_TOKEN}/imgproxy?url=${encodeURIComponent(videoUrl)}`;
    console.log(`Video direct download failed (${firstErr.message}), retry via proxy`);
    return downloadBytes(proxyUrl, { timeoutMs: 180_000, label: 'video-proxy' });
  }
}

async function generateVideoWithApiBost(structuredPrompt, keyframeBuffer, apiBostKey, idea) {
  const url = `${APIBOST_BASE}/v1beta/models/${APIBOST_VIDEO_MODEL}:generateContent`;
  const enhancedPrompt = buildVideoPrompt(structuredPrompt, idea);
  console.log(
    `ApiBost video via: ${url}, model=${APIBOST_VIDEO_MODEL}, `
    + `ratio=${idea.params.aspectRatio}, duration=${idea.params.durationSeconds}s, `
    + `promptLen=${enhancedPrompt.length}`,
  );

  const payload = {
    contents: [{
      role: 'user',
      parts: [
        { text: enhancedPrompt },
        {
          inlineData: {
            mimeType: 'image/jpeg',
            data: keyframeBuffer.toString('base64'),
          },
        },
      ],
    }],
  };

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(USE_APIBOST_PROXY ? {} : { Authorization: `Bearer ${apiBostKey}` }),
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(600_000),
  });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`ApiBost video HTTP ${resp.status}: ${body.slice(0, 300)}`);
  }

  const data = await resp.json();
  const videoUrl = extractVideoUrl(data);
  if (!videoUrl) {
    const finishReason = extractFinishReason(data);
    console.log(`ApiBost: no video URL, finishReason=${finishReason}`);
    return null;
  }

  console.log(`ApiBost video URL: ${videoUrl}`);
  return downloadVideoBytes(videoUrl);
}

function fileViewUrl(endpoint, bucketId, fileId, projectId) {
  const base = endpoint.replace(/\/v1\/?$/, '');
  return `${base}/v1/storage/buckets/${bucketId}/files/${fileId}/view?project=${projectId}`;
}

async function uploadBufferToAppwrite(buffer, fileId, fileName, storage, bucketId, endpoint, projectId) {
  try { await storage.deleteFile(bucketId, fileId); } catch { /* ok */ }
  await storage.createFile(
    bucketId,
    fileId,
    InputFile.fromBuffer(buffer, fileName),
    ['read("any")'],
  );
  return fileViewUrl(endpoint, bucketId, fileId, projectId);
}

async function loadCatalogState(databases, databaseId, presetsColl) {
  const tagCounts = {};
  const usedTitles = new Set();
  let offset = 0;
  const limit = 300;
  while (true) {
    const res = await databases.listDocuments(databaseId, presetsColl, [
      Query.limit(limit), Query.offset(offset),
    ]);
    for (const doc of res.documents) {
      if (Array.isArray(doc.tags)) {
        for (const t of doc.tags) {
          if (t && t !== 'custom') tagCounts[t] = (tagCounts[t] || 0) + 1;
        }
      }
      if (typeof doc.title === 'string' && doc.title.trim()) usedTitles.add(doc.title.trim());
    }
    if (res.documents.length < limit) break;
    offset += limit;
  }
  return { tagCounts, usedTitles };
}

function buildInitialLikes() {
  const n = 2 + Math.floor(Math.random() * 7);
  const likedBy = Array.from({ length: n }, () => `seed_${crypto.randomUUID().replace(/-/g, '')}`);
  return { likesCount: n, likedBy };
}

async function createThumbnail(imageBuffer, safeId, storage, bucketId, endpoint, projectId) {
  const { default: sharp } = await import('sharp').catch(() => ({ default: null }));
  const thumbFileId = `th-${safeId.replace(/[^a-zA-Z0-9._-]/g, '-').slice(0, 29)}`;
  const thumbBuf = sharp
    ? await sharp(imageBuffer).resize(400, null, { withoutEnlargement: true }).webp({ quality: 80 }).toBuffer()
    : imageBuffer;
  try { await storage.deleteFile(bucketId, thumbFileId); } catch { /* ok */ }
  await storage.createFile(
    bucketId,
    thumbFileId,
    InputFile.fromBuffer(thumbBuf, `${thumbFileId}.webp`),
    ['read("any")'],
  );
  return fileViewUrl(endpoint, bucketId, thumbFileId, projectId);
}

/** fileId обязан содержать .mp4 — клиент определяет видео по сегменту пути. */
function makeVideoFileId(safeId) {
  const ext = '.mp4';
  const maxBase = 36 - ext.length;
  const base = `prev-${safeId}`
    .replace(/[^a-zA-Z0-9._-]/g, '-')
    .slice(0, maxBase)
    .replace(/\.+$/, '');
  return `${base}${ext}`;
}

export async function runPresetPipeline(opts) {
  const {
    databases, storage, apiBostKey, deepseekKey, limit,
    databaseId, presetsColl, bucketId, endpoint, projectId,
  } = opts;

  const count = limit > 0 ? limit : 1;
  const summary = { ok: true, limit: count, processed: 0, success: 0, failed: 0, errors: [], created: [] };

  const { tagCounts, usedTitles } = await loadCatalogState(databases, databaseId, presetsColl);
  console.log(`Catalog state: ${usedTitles.size} titles, ${Object.keys(tagCounts).length} tags in use`);

  const ideas = buildIdeas({ count, tagCounts, usedTitles, now: new Date() });
  if (!ideas.length) {
    summary.ok = false;
    summary.errors.push({ step: 'ideas', msg: 'no ideas generated' });
    return summary;
  }
  console.log(`Pipeline: generating ${ideas.length} video preset(s) from style catalog`);

  for (let idx = 0; idx < ideas.length; idx++) {
    const idea = ideas[idx];
    summary.processed++;
    console.log(`[${idx + 1}/${ideas.length}] style=${idea.styleId} motif=${idea.motifId} | ${idea.title}`);

    try {
      const structured = await convertIdeaToStructure(idea, deepseekKey);
      if (!structured) {
        summary.failed++;
        summary.errors.push({ idea: idea.title, step: 'deepseek', msg: 'empty response' });
        continue;
      }

      const keyframeBuffer = await generateKeyframeWithApiBost(structured, apiBostKey, idea);
      if (!keyframeBuffer) {
        summary.failed++;
        summary.errors.push({ idea: idea.title, step: 'keyframe', msg: 'no image' });
        continue;
      }

      const videoBuffer = await generateVideoWithApiBost(structured, keyframeBuffer, apiBostKey, idea);
      if (!videoBuffer) {
        summary.failed++;
        summary.errors.push({ idea: idea.title, step: 'apibost-video', msg: 'no video' });
        continue;
      }

      const safeId = makePresetDocId();
      const videoFileId = makeVideoFileId(safeId);

      let previewImageUrl;
      try {
        previewImageUrl = await uploadBufferToAppwrite(
          videoBuffer,
          videoFileId,
          `${videoFileId}`,
          storage,
          bucketId,
          endpoint,
          projectId,
        );
        console.log(`Video uploaded: ${previewImageUrl}`);
      } catch (e) {
        console.log(`Video upload failed: ${e.message}`);
        summary.failed++;
        summary.errors.push({ idea: idea.title, step: 'upload', msg: e.message });
        continue;
      }

      let thumbnailUrl = null;
      try {
        thumbnailUrl = await createThumbnail(keyframeBuffer, safeId, storage, bucketId, endpoint, projectId);
        console.log(`Thumbnail generated: ${thumbnailUrl}`);
      } catch (e) {
        console.log(`Thumbnail generation failed: ${e.message}`);
      }

      const { likesCount, likedBy } = buildInitialLikes();
      await createPresetDocument(databases, databaseId, presetsColl, safeId, {
        title: idea.title,
        prompt: structured,
        previewImageUrl,
        tags: idea.tags,
        imageStyle: idea.imageStyle,
        isPublic: true,
        createdAt: new Date().toISOString(),
        likesCount,
        likedBy,
        ...(thumbnailUrl ? { thumbnailUrl, thumbnailSourceUrl: previewImageUrl } : {}),
      }, ['imageStyle', 'isPublic', 'thumbnailUrl', 'thumbnailSourceUrl', 'likesCount', 'likedBy']);

      usedTitles.add(idea.title);
      summary.success++;
      summary.created.push({
        id: safeId,
        title: idea.title,
        style: idea.imageStyle,
        tags: idea.tags,
        media: 'video',
      });
      await sleep(1_000);
    } catch (e) {
      console.log(`Error on "${idea.title}": ${e.message}`);
      summary.failed++;
      summary.errors.push({ idea: idea.title, step: 'exception', msg: String(e.message || e) });
    }
  }

  summary.ok = summary.success > 0;
  return summary;
}
