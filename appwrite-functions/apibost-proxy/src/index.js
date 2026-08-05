import { Client, Databases, Query, Storage } from 'node-appwrite';
import { InputFile } from 'node-appwrite/file';

const ENDPOINT     = (process.env.APPWRITE_ENDPOINT          ?? '').trim();
const PROJECT_ID   = (process.env.APPWRITE_PROJECT_ID        ?? '').trim();
const API_KEY      = (process.env.APPWRITE_API_KEY           ?? '').trim();
const DATABASE_ID  = (process.env.APPWRITE_DATABASE_ID       ?? 'main').trim();
const BUCKET_ID    = (process.env.APPWRITE_STORAGE_BUCKET_ID ?? 'user-photos').trim();
const DEVICE_COLLECTION = 'device_registry';
const API_BOST_KEY = (process.env.API_BOST_API_KEY           ?? '').trim();
const NL_HOST      = (process.env.NL_SERVER_HOST             ?? '').trim();
const NL_TOKEN     = (process.env.NL_PROXY_TOKEN             ?? '').trim();
const PIAPI_PORT   = (process.env.AI_PROXY_PIAPI_PORT        ?? '8080').trim();
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

const APIBOST_BASE        = hasYandexRelay()
  ? buildYandexRelayUrl(PIAPI_PORT, `/ai-${NL_TOKEN}/apibost`)
  : NL_HOST && NL_TOKEN
    ? `http://${NL_HOST}:${PIAPI_PORT}/ai-${NL_TOKEN}/apibost`
    : 'https://apibost.com';
const USE_APIBOST_PROXY   = APIBOST_BASE.startsWith('http://');
const DOWNLOAD_TIMEOUT_MS = 45_000;
const APIBOST_TIMEOUT_MS  = 420_000;

function makeClient() {
  return new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
}

// Тарифы видео повторяют CreditCost в lib/config/credit_config.dart.
// Порядок проверок важен: pro-4k и fast-preview должны срабатывать раньше
// более общих `-pro` и `-fast`.
const VIDEO_MODEL_CREDITS = [
  ['veo3.1-pro-4k', 255],
  ['veo-3.1-fast-generate-preview', 110],
  ['veo-3.1-generate-preview', 255],
  ['veo3.1-pro', 32],
  ['veo3.1-fast', 18],
  ['veo3.1-lite', 8],
];

function isVideoModel(model) {
  const normalized = String(model || '').trim().toLowerCase();
  return normalized.startsWith('veo');
}

function creditsForModel(model) {
  const normalized = String(model || '').toLowerCase();
  for (const [prefix, credits] of VIDEO_MODEL_CREDITS) {
    if (normalized.startsWith(prefix)) return credits;
  }
  if (normalized.startsWith('gpt-image-')) return 35;
  if (normalized.startsWith('grok-3-image')) return 15;
  if (normalized.includes('3-pro-image-preview')) return 25;
  if (normalized.includes('3.1-flash-image')) return 10;
  if (normalized.includes('2.5-flash-image')) return 5;
  return 10;
}

// OpenAI-совместимые модели ApiBost не понимают :generateContent и работают
// через /v1/images/*. Все остальные модели остаются на прежнем Gemini-пути,
// поэтому другие приложения, использующие эту функцию, не затрагиваются.
const OPENAI_IMAGE_MODELS = new Set(['gpt-image-1.5', 'gpt-image-2']);
const CHAT_COMPLETION_IMAGE_MODELS = new Set(['grok-3-image']);
const TEXT_ONLY_MODELS = new Set(['grok-3-image']);
const LANDSCAPE_RATIOS = new Set(['3:2', '4:3', '5:4', '16:9', '21:9']);

function isOpenAiImageModel(model) {
  return OPENAI_IMAGE_MODELS.has(String(model || '').trim().toLowerCase());
}

function isChatCompletionImageModel(model) {
  return CHAT_COMPLETION_IMAGE_MODELS.has(String(model || '').trim().toLowerCase());
}

function acceptsImageInput(model) {
  return !TEXT_ONLY_MODELS.has(String(model || '').trim().toLowerCase());
}

function imageSizeForAspectRatio(aspectRatio) {
  const ratio = String(aspectRatio || '').trim();
  if (ratio === '1:1') return '1024x1024';
  if (LANDSCAPE_RATIOS.has(ratio)) return '1536x1024';
  return '1024x1536';
}

function responseModalitiesForModel(model) {
  const normalized = String(model || '').toLowerCase();
  if (normalized.includes('flash-image') || normalized.includes('pro-image')) {
    return ['TEXT', 'IMAGE'];
  }
  return ['IMAGE'];
}

const APIBOST_FLASH_25_MODEL = 'gemini-2.5-flash-image';

function is31FlashImageModel(model) {
  return String(model || '').toLowerCase().includes('3.1-flash-image');
}

function shouldRelay31To25(model, status, message) {
  if (!is31FlashImageModel(model)) return false;
  if (status === 400 || status === 404 || status === 503) return true;
  if (Number(status) >= 500) return true;
  const msg = String(message || '').toLowerCase();
  return msg.includes('not been priced')
    || msg.includes('价格尚未')
    || msg.includes('no available channel')
    || msg.includes('openai_error');
}

function intVal(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.trunc(n));
}

async function reserveServerCredits({
  db,
  fingerprint,
  model,
  log,
}) {
  const docs = await db.listDocuments(DATABASE_ID, DEVICE_COLLECTION, [
    Query.equal('fingerprint', fingerprint),
    Query.limit(1),
  ]);

  if (docs.total === 0) {
    log(`device not registered fp=${fingerprint.slice(0, 8)}…`);
    return {
      ok: false,
      status: 426,
      error: 'Требуется обновление приложения.',
    };
  }

  const doc = docs.documents[0];
  const cost = creditsForModel(model);
  const fallbackBalance = intVal(doc.purchasedCredits) + intVal(doc.earnedCredits);
  const balance = intVal(doc.currentBalance, fallbackBalance);

  if (balance < cost) {
    log(`insufficient credits fp=${fingerprint.slice(0, 8)}… balance=${balance} cost=${cost}`);
    return {
      ok: false,
      status: 402,
      error: `Недостаточно кредитов: ${balance} из ${cost} необходимых`,
    };
  }

  const nextBalance = Math.max(0, balance - cost);
  // Для free-устройств ведём счётчики бесплатного расхода так же, как
  // verify-trial reserve_credits — иначе клиентский reconcile (который для
  // free-пользователей берёт usedCredits = freeCreditsUsed) разойдётся с
  // серверным currentBalance.
  const isFreeDevice = (doc.subscriptionType ?? '') === 'free';
  const patch = { currentBalance: nextBalance };
  if (isFreeDevice) {
    patch.freeCreditsUsed = intVal(doc.freeCreditsUsed) + cost;
    patch.freeGenerationsUsed = intVal(doc.freeGenerationsUsed) + 1;
  }
  await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, doc.$id, patch);

  return {
    ok: true,
    reservation: {
      docId: doc.$id,
      chargedCredits: cost,
      balanceBefore: balance,
      balanceAfter: nextBalance,
      wasFree: isFreeDevice,
    },
  };
}

async function rollbackServerCredits(db, reservation) {
  if (!reservation?.docId || !reservation?.chargedCredits) return;
  try {
    const doc = await db.getDocument(DATABASE_ID, DEVICE_COLLECTION, reservation.docId);
    const fallbackBalance = intVal(doc.purchasedCredits) + intVal(doc.earnedCredits);
    const current = intVal(doc.currentBalance, fallbackBalance);
    const charged = intVal(reservation.chargedCredits);
    const patch = { currentBalance: current + charged };
    // Откатываем и счётчики бесплатного расхода, если они были увеличены.
    if (reservation.wasFree) {
      patch.freeCreditsUsed = Math.max(0, intVal(doc.freeCreditsUsed) - charged);
      patch.freeGenerationsUsed = Math.max(0, intVal(doc.freeGenerationsUsed) - 1);
    }
    await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, reservation.docId, patch);
  } catch {
    // Функция не должна падать из-за ошибки rollback.
  }
}

async function downloadImageAsBuffer(url) {
  const resp = await fetch(url, {
    headers: { 'User-Agent': 'AppwriteFunction/apibost-proxy' },
    signal: AbortSignal.timeout(DOWNLOAD_TIMEOUT_MS),
  });
  if (!resp.ok) throw new Error(`Не удалось скачать изображение: HTTP ${resp.status}`);
  return Buffer.from(await resp.arrayBuffer());
}

// Все модели ApiBost используют /v1beta/models:generateContent с inlineData.
// Многоизображённый ввод — несколько inlineData частей (до 4 фото).
// Аспект-рейтио передаётся в тексте промпта как [3:4].
async function callApiBostOnce(model, prompt, imageBuffers) {
  const url = `${APIBOST_BASE}/v1beta/models/${model}:generateContent`;

  // Текст ПЕРЕД изображениями — как показано в документации ApiBost.
  // При обратном порядке модель интерпретирует первое изображение как базовое
  // для редактирования и возвращает его нетронутым.
  const parts = [{ text: prompt }];
  for (const buf of imageBuffers) {
    parts.push({ inlineData: { mimeType: 'image/jpeg', data: buf.toString('base64') } });
  }

  const payload = {
    contents: [{ role: 'user', parts }],
    generationConfig: {
      responseModalities: responseModalitiesForModel(model),
    },
  };

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(USE_APIBOST_PROXY ? {} : { Authorization: `Bearer ${API_BOST_KEY}` }),
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(APIBOST_TIMEOUT_MS),
  });
  if (!resp.ok) {
    const text = await resp.text();
    const message = tryParseErrorMessage(text) ?? `ApiBost HTTP ${resp.status}`;
    return { ok: false, status: resp.status, message };
  }
  return { ok: true, data: await resp.json() };
}

async function callApiBost(model, prompt, imageBuffers, log) {
  const primary = await callApiBostOnce(model, prompt, imageBuffers);
  if (primary.ok) {
    log(`фактическая модель=${model} (запрошена=${model})`);
    return { data: primary.data, actualModel: model, requestedModel: model };
  }

  if (shouldRelay31To25(model, primary.status, primary.message)) {
    log(`relay 3.1→2.5: model=${model} HTTP ${primary.status} ${primary.message}`);
    const fallback = await callApiBostOnce(APIBOST_FLASH_25_MODEL, prompt, imageBuffers);
    if (fallback.ok) {
      log(`фактическая модель=${APIBOST_FLASH_25_MODEL} (запрошена=${model})`);
      return {
        data: fallback.data,
        actualModel: APIBOST_FLASH_25_MODEL,
        requestedModel: model,
      };
    }
    throw new Error(fallback.message ?? `ApiBost HTTP ${fallback.status}`);
  }

  throw new Error(primary.message ?? `ApiBost HTTP ${primary.status}`);
}

async function callOpenAiImages(model, prompt, imageBuffers, aspectRatio, log) {
  const size = imageSizeForAspectRatio(aspectRatio);
  const useEdits = imageBuffers.length > 0;

  if (useEdits && !acceptsImageInput(model)) {
    throw new Error(`Модель ${model} не поддерживает генерацию по фото`);
  }

  const headers = USE_APIBOST_PROXY ? {} : { Authorization: `Bearer ${API_BOST_KEY}` };
  let url;
  let body;

  if (useEdits) {
    url = `${APIBOST_BASE}/v1/images/edits`;
    const form = new FormData();
    form.append('model', model);
    form.append('prompt', prompt);
    form.append('size', size);
    form.append('n', '1');
    imageBuffers.forEach((buf, index) => {
      form.append('image[]', new Blob([buf], { type: 'image/jpeg' }), `image_${index}.jpg`);
    });
    body = form;
  } else {
    url = `${APIBOST_BASE}/v1/images/generations`;
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify({ model, prompt, size, n: 1 });
  }

  const resp = await fetch(url, {
    method: 'POST',
    headers,
    body,
    signal: AbortSignal.timeout(APIBOST_TIMEOUT_MS),
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(tryParseErrorMessage(text) ?? `ApiBost HTTP ${resp.status}`);
  }

  log(`фактическая модель=${model} (запрошена=${model}) size=${size}`);
  return { data: await resp.json(), actualModel: model, requestedModel: model };
}

async function callChatCompletionsImage(model, prompt, temperature, log) {
  const resp = await fetch(`${APIBOST_BASE}/v1/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(USE_APIBOST_PROXY ? {} : { Authorization: `Bearer ${API_BOST_KEY}` }),
    },
    body: JSON.stringify({
      model,
      messages: [{ role: 'user', content: prompt }],
      temperature,
    }),
    signal: AbortSignal.timeout(APIBOST_TIMEOUT_MS),
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(tryParseErrorMessage(text) ?? `ApiBost HTTP ${resp.status}`);
  }

  log(`фактическая модель=${model} (запрошена=${model}) transport=chat`);
  return { data: await resp.json(), actualModel: model, requestedModel: model };
}

const CHAT_IMAGE_URL_RE = /https?:\/\/[^\s()<>"\]]+/i;

function firstImageUrlInChatResponse(data) {
  for (const choice of data?.choices ?? []) {
    const message = choice?.message;
    if (!message) continue;
    for (const image of message.images ?? []) {
      const url = image?.image_url;
      if (typeof url === 'string' && url) return url;
      if (url && typeof url.url === 'string' && url.url) return url.url;
    }
    if (typeof message.content === 'string') {
      const match = message.content.match(CHAT_IMAGE_URL_RE);
      if (match) return match[0];
    }
  }
  return null;
}

// `/v1/images/*` отдаёт результат в data[] (обычно ссылкой), а
// `/v1/chat/completions` — markdown-ссылкой в тексте ответа.
async function extractBase64FromOpenAiResponse(data) {
  for (const item of data?.data ?? []) {
    if (item?.b64_json) return item.b64_json;
    if (item?.url) {
      const buf = await downloadImageAsBuffer(item.url);
      return buf.toString('base64');
    }
  }
  const chatUrl = firstImageUrlInChatResponse(data);
  if (chatUrl) {
    const buf = await downloadImageAsBuffer(chatUrl);
    return buf.toString('base64');
  }
  return null;
}

function tryParseErrorMessage(body) {
  try {
    const j = JSON.parse(body);
    return j?.error?.message ?? j?.error ?? null;
  } catch { return null; }
}

function extractBase64FromResponse(data) {
  for (const candidate of data?.candidates ?? []) {
    for (const part of candidate?.content?.parts ?? []) {
      const inline = part.inlineData ?? part.inline_data;
      if (inline?.data) return inline.data;
    }
  }
  return null;
}

function extractFinishReason(data) {
  return data?.candidates?.[0]?.finishReason ?? null;
}

async function uploadResultToStorage(storage, imageBuffer) {
  const fileId = `gen_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`.slice(0, 36);
  await storage.createFile(
    BUCKET_ID,
    fileId,
    InputFile.fromBuffer(imageBuffer, `${fileId}.jpg`),
    ['read("any")'],
  );
  const base = ENDPOINT.replace(/\/v1\/?$/, '');
  return `${base}/v1/storage/buckets/${BUCKET_ID}/files/${fileId}/view?project=${PROJECT_ID}`;
}

async function writeJobResult(storage, fileId, payload) {
  if (!fileId) return;
  const safeFileId = String(fileId).slice(0, 36);
  const body = Buffer.from(JSON.stringify({
    ...payload,
    updatedAt: new Date().toISOString(),
  }));
  try { await storage.deleteFile(BUCKET_ID, safeFileId); } catch { /* first write */ }
  await storage.createFile(
    BUCKET_ID,
    safeFileId,
    InputFile.fromBuffer(body, `${safeFileId}.json`),
    ['read("any")'],
  );
}

export default async ({ req, res, log, error }) => {
  let body;
  try {
    body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body ?? {});
  } catch {
    return res.json({ error: 'invalid_json' }, 400);
  }

  const {
    action,
    fingerprint,
    model = 'gemini-2.5-flash-image',
    prompt,
    userImageUrl,
    referenceImageUrl,
    aspectRatio = '3:4',
    temperature = 0.7,
    jobResultFileId,
  } = body;

  const storage = new Storage(makeClient());
  const db = new Databases(makeClient());

  if (!API_BOST_KEY && !USE_APIBOST_PROXY) {
    await writeJobResult(storage, jobResultFileId, { status: 'failed', error: 'API_BOST_API_KEY не задан' });
    return res.json({ error: 'API_BOST_API_KEY не задан' }, 500);
  }
  if (!prompt) {
    await writeJobResult(storage, jobResultFileId, { status: 'failed', error: 'prompt обязателен' });
    return res.json({ error: 'prompt обязателен' }, 400);
  }
  // Генерация видео идёт клиентским контуром (USE_CLIENT_SIDE_APIBOST): эта
  // функция умеет только выгружать картинки в сторадж. Отказываем явно, иначе
  // MP4 был бы сохранён как .jpg и результат не открылся бы в приложении.
  if (isVideoModel(model)) {
    const message = `Модель ${model} доступна только в клиентском контуре генерации.`;
    await writeJobResult(storage, jobResultFileId, { status: 'failed', error: message });
    return res.json({ error: message }, 400);
  }
  if (!['generate_with_face', 'generate_image'].includes(action)) {
    await writeJobResult(storage, jobResultFileId, {
      status: 'failed',
      error: `Неизвестное действие: ${action}`,
    });
    return res.json({ error: `Неизвестное действие: ${action}` }, 400);
  }
  if (action === 'generate_with_face' && !userImageUrl) {
    await writeJobResult(storage, jobResultFileId, {
      status: 'failed',
      error: 'userImageUrl обязателен для generate_with_face',
    });
    return res.json({ error: 'userImageUrl обязателен для generate_with_face' }, 400);
  }
  if (!fingerprint || typeof fingerprint !== 'string' || fingerprint.length < 16) {
    await writeJobResult(storage, jobResultFileId, {
      status: 'failed',
      error: 'Требуется обновление приложения.',
    });
    return res.json({ error: 'Требуется обновление приложения.' }, 426);
  }

  let reservation = null;
  try {
    // Сначала скачиваем исходные изображения и только потом резервируем кредиты.
    // Иначе при недоступности фото (HTTP 404 во время сбоя стораджа) кредиты
    // успевали списаться, и приходилось их откатывать; теперь списания не будет.
    // Порядок: референс сцены первым (если есть), затем фото пользователя.
    const imageBuffers = [];

    if (referenceImageUrl) {
      log(`Скачиваю референс: ${referenceImageUrl}`);
      const buf = await downloadImageAsBuffer(referenceImageUrl);
      imageBuffers.push(buf);
      log(`Референс скачан: ${buf.length} байт (inlineData[0])`);
    }

    if (userImageUrl) {
      log(`Скачиваю фото пользователя: ${userImageUrl}`);
      const buf = await downloadImageAsBuffer(userImageUrl);
      imageBuffers.push(buf);
      log(`Фото пользователя скачано: ${buf.length} байт (inlineData[${imageBuffers.length - 1}])`);
    }

    const reserve = await reserveServerCredits({
      db,
      fingerprint,
      model,
      log,
    });
    if (!reserve.ok) {
      await writeJobResult(storage, jobResultFileId, {
        status: 'failed',
        error: reserve.error,
      });
      return res.json({ error: reserve.error }, reserve.status ?? 402);
    }
    reservation = reserve.reservation;
    log(
      `credits reserved fp=${fingerprint.slice(0, 8)}… `
      + `cost=${reservation.chargedCredits} `
      + `balance=${reservation.balanceBefore}->${reservation.balanceAfter}`,
    );

    const openAiImagesModel = isOpenAiImageModel(model);
    const chatImageModel = isChatCompletionImageModel(model);
    const openAiModel = openAiImagesModel || chatImageModel;
    // Gemini-модели получают аспект-рейтио текстом промпта ([3:4]) согласно
    // документации ApiBost; OpenAI-модели — отдельным полем `size`.
    const fullPrompt = openAiImagesModel ? prompt : `[${aspectRatio}] ${prompt}`;

    const transport = openAiImagesModel
      ? 'openai-images'
      : chatImageModel ? 'openai-chat' : 'gemini';
    log(`callApiBost: model=${model} images=${imageBuffers.length} `
      + `aspectRatio=${aspectRatio} transport=${transport}`);

    let generation;
    if (openAiImagesModel) {
      generation = await callOpenAiImages(model, fullPrompt, imageBuffers, aspectRatio, log);
    } else if (chatImageModel) {
      generation = await callChatCompletionsImage(model, fullPrompt, temperature, log);
    } else {
      generation = await callApiBost(model, fullPrompt, imageBuffers, log);
    }

    const base64Image = openAiModel
      ? await extractBase64FromOpenAiResponse(generation.data)
      : extractBase64FromResponse(generation.data);
    if (!base64Image) {
      const finishReason = extractFinishReason(generation.data);
      log(`Нет изображения в ответе, finishReason=${finishReason}`);
      const BLOCKED = new Set(['PROHIBITED_CONTENT', 'IMAGE_PROHIBITED_CONTENT', 'BLOCKED_REASON_UNSPECIFIED']);
      if (BLOCKED.has(finishReason)) {
        // Контент заблокирован модерацией — кредиты НЕ возвращаем: запрос к ApiBost
        // выполнен (мы за него заплатили), а возврат открыл бы абьюз через
        // повторную отправку запрещённого контента.
        await writeJobResult(storage, jobResultFileId, {
          status: 'failed',
          error: 'Контент заблокирован политикой безопасности. Попробуйте другое фото.',
          finishReason,
        });
        return res.json({
          error: 'Контент заблокирован политикой безопасности. Попробуйте другое фото.',
          finishRatio: finishReason,
        }, 422);
      }
      // Пустой ответ модели — генерация не состоялась, возвращаем кредиты.
      await rollbackServerCredits(db, reservation);
      await writeJobResult(storage, jobResultFileId, {
        status: 'failed',
        error: 'Не удалось получить изображение из ответа',
        finishReason,
      });
      return res.json({ error: 'Не удалось получить изображение из ответа', finishReason }, 422);
    }

    const resultBuffer = Buffer.from(base64Image, 'base64');
    log(`Загружаю результат в Storage: ${resultBuffer.length} байт`);
    const imageUrl = await uploadResultToStorage(storage, resultBuffer);
    await writeJobResult(storage, jobResultFileId, {
      status: 'completed',
      imageUrl,
      chargedCredits: reservation?.chargedCredits ?? 0,
      balanceAfterCharge: reservation?.balanceAfter ?? null,
      actualModel: generation.actualModel,
      requestedModel: generation.requestedModel,
    });
    log(`Готово: ${imageUrl}`);
    return res.json({ imageUrl });

  } catch (e) {
    await rollbackServerCredits(db, reservation);
    error(`Ошибка: ${e.message}`);
    try {
      await writeJobResult(storage, jobResultFileId, { status: 'failed', error: e.message });
    } catch (writeErr) {
      error(`Ошибка записи результата job: ${writeErr.message}`);
    }
    return res.json({ error: e.message }, 500);
  }
};
