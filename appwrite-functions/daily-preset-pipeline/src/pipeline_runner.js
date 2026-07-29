import crypto from 'crypto';
import { Query } from 'node-appwrite';
import { InputFile } from 'node-appwrite/file';
import { buildIdeas } from './idea_builder.js';
import { buildImagePrompt } from './image_prompt.js';

// NL-прокси (Нидерланды) для обхода блокировок с российского сервера
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

const DEEPSEEK_SYSTEM_PROMPT = `Ты промпт-инженер генератора изображений.

Тебе дадут ТЕХНИЧЕСКОЕ ЗАДАНИЕ на картинку из нашего каталога (сюжет, тематика, визуальный стиль, композиция, палитра, атмосфера). Твоя задача — развернуть его в структурированный промпт нашего приложения.

ОБЯЗАТЕЛЬНАЯ СТРУКТУРА (5 разделов, все на РУССКОМ языке, именно эти заголовки):

ОПИСАНИЕ СЦЕНЫ:
[3-5 предложений. Что именно изображено: главный объект, окружение, передний и задний планы. Очень конкретно — формы, материалы, фактуры, масштаб, состояние (мокрое, обледенелое, раскалённое). Не отклоняйся от сюжета из задания, только детализируй его.]

КОМПОЗИЦИЯ И РАКУРС:
[2-3 предложения. Кадрирование и точка съёмки строго как в задании, расположение главного объекта в кадре, ведущие линии, глубина резкости, что в фокусе и что размыто.]

СТИЛЬ И ТЕХНИКА:
[2-4 предложения. Дословно раскрой визуальный стиль из задания: техника исполнения, характер линий и мазков, уровень детализации, фактура поверхности изображения, референсная эстетика. Это главный раздел — стиль должен читаться безошибочно.]

ЦВЕТ И СВЕТ:
[2-3 предложения. Доминирующие цвета с конкретными названиями оттенков, акценты, тип и направление освещения, контраст, атмосферные эффекты из задания.]

ДЕТАЛИ:
[2-3 предложения. Мелкие элементы, усиливающие сюжет: частицы, отражения, надписи на объектах, износ материалов, микрофактуры.
ТЕКСТ НА ИЗОБРАЖЕНИИ: добавляй надписи только если этого требует праздничный повод из задания. Тогда укажи точный текст КИРИЛЛИЦЕЙ, стиль шрифта, цвет и позицию в кадре.]

КРИТИЧЕСКИЕ ПРАВИЛА:
- Весь вывод ТОЛЬКО на русском языке
- Строго 5 разделов, именно эти заголовки, ничего лишнего
- В кадре НЕТ людей и частей тела, если сюжет прямо их не требует — это изображение объекта, сцены или графики
- Не превращай задание в фотосессию и не описывай моделей, позы и одежду
- Объём: 250-400 слов в сумме
- Никаких кавычек, вступлений и пояснений — только структура
- ФОРМАТ ВСЕГДА ВЕРТИКАЛЬНЫЙ 3:4
- Один цельный кадр: без коллажей, рамок, подписей автора и водяных знаков`;

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function stripMarkdownFences(s) {
  let t = s.trim();
  t = t.replace(/^```[^\n]*\n?/, '');
  t = t.replace(/\n?```$/, '');
  return t.trim();
}

const PROMPT_MAX_LENGTH = 4000;

// Атрибут prompt в коллекции ограничен по длине: режем по границе абзаца, а не посреди слова.
function fitPromptToLimit(prompt) {
  if (prompt.length <= PROMPT_MAX_LENGTH) return prompt;
  const head = prompt.slice(0, PROMPT_MAX_LENGTH);
  const lastBreak = Math.max(head.lastIndexOf('\n\n'), head.lastIndexOf('\n'));
  return (lastBreak > PROMPT_MAX_LENGTH * 0.6 ? head.slice(0, lastBreak) : head).trim();
}

// Схема коллекции на разных инсталляциях может не иметь опциональных полей.
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

async function convertIdeaToStructure(idea, deepseekKey) {
  const userMsg = [
    `Название изображения: ${idea.title}`,
    '',
    'ТЕХНИЧЕСКОЕ ЗАДАНИЕ:',
    idea.brief,
    '',
    'Разверни это задание в нашу структуру из 5 разделов.',
  ].join('\n');

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
      messages: [{ role:'system', content: DEEPSEEK_SYSTEM_PROMPT }, { role:'user', content: userMsg }],
      max_tokens: 2200, temperature: 0.6,
    }),
    signal: AbortSignal.timeout(90_000),
  });
  if (!resp.ok) throw new Error(`DeepSeek HTTP ${resp.status}: ${(await resp.text()).slice(0,200)}`);
  const data = await resp.json();
  const content = data.choices?.[0]?.message?.content;
  return content ? (stripMarkdownFences(content) || null) : null;
}

const APIBOST_BASE  = hasYandexRelay()
  ? buildYandexRelayUrl(PIAPI_PROXY_PORT, buildTokenizedNlPath('/apibost'))
  : NL_HOST && NL_TOKEN
    ? `http://${NL_HOST}:${PIAPI_PROXY_PORT}/ai-${NL_TOKEN}/apibost`
    : 'https://apibost.com';
const USE_APIBOST_PROXY = APIBOST_BASE.startsWith('http://');
const APIBOST_MODEL = process.env.APIBOST_MODEL || 'gemini-3-pro-image-preview';

async function generateImageWithApiBost(prompt, apiBostKey, idea) {
  const url = `${APIBOST_BASE}/v1beta/models/${APIBOST_MODEL}:generateContent`;
  console.log(`ApiBost via: ${url}, model=${APIBOST_MODEL}, temp=${idea.params.temperature}`);

  const enhancedPrompt = buildImagePrompt(prompt, idea);

  const payload = {
    contents: [
      {
        role: 'user',
        parts: [{ text: enhancedPrompt }],
      },
    ],
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
    throw new Error(`ApiBost HTTP ${resp.status}: ${body.slice(0, 200)}`);
  }

  const data = await resp.json();
  const candidates = data.candidates || [];
  for (const candidate of candidates) {
    const parts = candidate?.content?.parts || [];
    for (const part of parts) {
      const inlineData = part.inlineData || part.inline_data;
      if (inlineData?.data) {
        return Buffer.from(inlineData.data, 'base64');
      }
    }
  }

  const finishReason = candidates[0]?.finishReason;
  console.log(`ApiBost: no image in response, finishReason=${finishReason}`);
  return null;
}

async function uploadBufferToAppwrite(buffer, fileId, storage, bucketId, endpoint, projectId) {
  try { await storage.deleteFile(bucketId, fileId); } catch { /* ok */ }
  await storage.createFile(bucketId, fileId, InputFile.fromBuffer(buffer, `${fileId}.jpg`), ['read("any")']);
  const base = endpoint.replace(/\/v1\/?$/, '');
  return `${base}/v1/storage/buckets/${bucketId}/files/${fileId}/view?project=${projectId}`;
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
  const n       = 2 + Math.floor(Math.random() * 7);
  const likedBy = Array.from({ length: n }, () => `seed_${crypto.randomUUID().replace(/-/g,'')}`);
  return { likesCount: n, likedBy };
}

async function createThumbnail(imageBuffer, safeId, storage, bucketId, endpoint, projectId) {
  const { default: sharp } = await import('sharp').catch(() => ({ default: null }));
  const thumbFileId = `th-${safeId.replace(/[^a-zA-Z0-9._-]/g, '-').slice(0, 29)}`;
  const thumbBuf = sharp
    ? await sharp(imageBuffer).resize(400, null, { withoutEnlargement: true }).webp({ quality: 80 }).toBuffer()
    : imageBuffer;
  try { await storage.deleteFile(bucketId, thumbFileId); } catch { /* ok */ }
  await storage.createFile(bucketId, thumbFileId, InputFile.fromBuffer(thumbBuf, `${thumbFileId}.webp`), ['read("any")']);
  const base = endpoint.replace(/\/v1\/?$/, '');
  return `${base}/v1/storage/buckets/${bucketId}/files/${thumbFileId}/view?project=${projectId}`;
}

export async function runPresetPipeline(opts) {
  const { databases, storage, apiBostKey, deepseekKey, limit,
          databaseId, presetsColl, bucketId, endpoint, projectId } = opts;

  const count = limit > 0 ? limit : 1;
  const summary = { ok:true, limit: count, processed:0, success:0, failed:0, errors:[], created:[] };

  const { tagCounts, usedTitles } = await loadCatalogState(databases, databaseId, presetsColl);
  console.log(`Catalog state: ${usedTitles.size} titles, ${Object.keys(tagCounts).length} tags in use`);

  const ideas = buildIdeas({ count, tagCounts, usedTitles, now: new Date() });
  if (!ideas.length) {
    summary.ok = false;
    summary.errors.push({ step:'ideas', msg:'no ideas generated' });
    return summary;
  }
  console.log(`Pipeline: generating ${ideas.length} image preset(s) from style catalog`);

  for (let idx = 0; idx < ideas.length; idx++) {
    const idea = ideas[idx];
    summary.processed++;
    console.log(`[${idx+1}/${ideas.length}] style=${idea.styleId} motif=${idea.motifId} | ${idea.title}`);

    try {
      const structured = await convertIdeaToStructure(idea, deepseekKey);
      if (!structured) {
        summary.failed++;
        summary.errors.push({ idea: idea.title, step:'deepseek', msg:'empty response' });
        continue;
      }

      const imageBuffer = await generateImageWithApiBost(structured, apiBostKey, idea);
      if (!imageBuffer) {
        summary.failed++;
        summary.errors.push({ idea: idea.title, step:'apibost', msg:'no image' });
        continue;
      }

      const safeId = makePresetDocId();
      const fileId = `prev-${safeId}`.slice(0, 36);
      let previewImageUrl;
      try {
        previewImageUrl = await uploadBufferToAppwrite(imageBuffer, fileId, storage, bucketId, endpoint, projectId);
        console.log(`Image uploaded: ${previewImageUrl}`);
      } catch (e) {
        console.log(`Image upload failed: ${e.message}`);
        summary.failed++;
        summary.errors.push({ idea: idea.title, step:'upload', msg:e.message });
        continue;
      }

      let thumbnailUrl = null;
      try {
        thumbnailUrl = await createThumbnail(imageBuffer, safeId, storage, bucketId, endpoint, projectId);
        console.log(`Thumbnail generated: ${thumbnailUrl}`);
      } catch (e) {
        console.log(`Thumbnail generation failed (trigger will retry): ${e.message}`);
      }

      const { likesCount, likedBy } = buildInitialLikes();
      await createPresetDocument(databases, databaseId, presetsColl, safeId, {
        title:      idea.title,
        prompt:     fitPromptToLimit(structured),
        previewImageUrl,
        tags:       idea.tags,
        imageStyle: idea.imageStyle,
        isPublic:   true,
        createdAt:  new Date().toISOString(),
        likesCount,
        likedBy,
        ...(thumbnailUrl ? { thumbnailUrl, thumbnailSourceUrl: previewImageUrl } : {}),
      }, ['imageStyle', 'isPublic', 'thumbnailUrl', 'thumbnailSourceUrl', 'likesCount', 'likedBy']);

      usedTitles.add(idea.title);
      summary.success++;
      summary.created.push({ id: safeId, title: idea.title, style: idea.imageStyle, tags: idea.tags });
      await sleep(1_000);
    } catch (e) {
      console.log(`Error on "${idea.title}": ${e.message}`);
      summary.failed++;
      summary.errors.push({ idea: idea.title, step:'exception', msg:String(e.message||e) });
    }
  }

  summary.ok = summary.success > 0;
  return summary;
}
