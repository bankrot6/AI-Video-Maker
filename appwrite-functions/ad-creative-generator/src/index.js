import { Client, Storage } from 'node-appwrite';
import { InputFile } from 'node-appwrite/file';
import sharp from 'sharp';

const ENDPOINT = (process.env.APPWRITE_ENDPOINT ?? '').trim();
const PROJECT_ID = (process.env.APPWRITE_PROJECT_ID ?? '').trim();
const API_KEY = (process.env.APPWRITE_API_KEY ?? '').trim();
const BUCKET_ID = (process.env.APPWRITE_AD_CREATIVES_BUCKET_ID ?? 'ad-creatives').trim();
const API_BOST_KEY = (process.env.API_BOST_API_KEY ?? '').trim();
const ADMIN_KEY = (process.env.ADMIN_API_KEY || 'photosession_admin_key_2026_secure_secret').trim();
const REQUIRE_ADMIN_KEY = String(process.env.AD_CREATIVE_REQUIRE_ADMIN_KEY ?? 'false').trim().toLowerCase() === 'true';
const NL_HOST = (process.env.NL_SERVER_HOST ?? '').trim();
const NL_TOKEN = (process.env.NL_PROXY_TOKEN ?? '').trim();
const PIAPI_PORT = (process.env.AI_PROXY_PIAPI_PORT ?? '8080').trim();
const YANDEX_AI_RELAY_BASE_URL = (process.env.YANDEX_AI_RELAY_BASE_URL ?? '').trim();
const APIBOST_MODEL = (process.env.APIBOST_MODEL ?? 'gemini-2.5-flash-image').trim();
const MAX_BYTES = 5 * 1024 * 1024;

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

const APIBOST_BASE = hasYandexRelay()
  ? buildYandexRelayUrl(PIAPI_PORT, `/ai-${NL_TOKEN}/apibost`)
  : NL_HOST && NL_TOKEN
    ? `http://${NL_HOST}:${PIAPI_PORT}/ai-${NL_TOKEN}/apibost`
    : 'https://apibost.com';

const USE_APIBOST_PROXY = APIBOST_BASE.startsWith('http://');

const SIZE_PRESETS = {
  '1:1': { width: 600, height: 600, aspectRatio: '1:1' },
  '4:5': { width: 1080, height: 1350, aspectRatio: '4:5' },
  '16:9': { width: 1080, height: 607, aspectRatio: '16:9' },
};

// Пул случайных обстановок для кадра "до" — чтобы фон не повторялся
// (без постоянной комнаты и еды на столе). Используется только когда
// вызывающий не передал свой leftScene.
const BEFORE_SCENES = [
  'на городской улице зимой, в обычной куртке, спешит по делам',
  'в вагоне метро или в автобусе, повседневная одежда, усталый вид',
  'в обычном супермаркете с тележкой, домашняя одежда',
  'на остановке общественного транспорта под пасмурным небом',
  'в типичном офисе за рабочим столом с компьютером, простая одежда',
  'во дворе панельной многоэтажки, обычная повседневная одежда',
  'в раздевалке обычного фитнес-зала, спортивная форма',
  'на лестничной площадке подъезда, выходит из квартиры',
  'в недорогом кафе с бумажным стаканом кофе',
  'на парковке у торгового центра, повседневный лук',
  'в парке осенью на скамейке, простая куртка',
  'в маршрутке у окна, обычная будничная одежда',
];

// Пул люксовых/желанных локаций для кадра "после" — разнообразные места по миру,
// куда мечтают попасть на фотосессию. Используется когда не передан rightScene.
// Отдельные наборы для женского и мужского образа (наряд в описании зависит от пола).
const AFTER_SCENES_FEMALE = [
  'на роскошной яхте в открытом море, в элегантном вечернем платье',
  'на террасе виллы в Санторини с видом на белые дома и море, лёгкое дорогое платье',
  'в небоскрёбе Дубая на фоне панорамы города, вечерний образ в платье',
  'на пляже Мальдив у бирюзовой воды, лёгкое дорогое платье',
  'на парижской улице у Эйфелевой башни, шикарный модный лук',
  'в роскошном пятизвёздочном отеле с мраморным лобби, элегантное платье',
  'у бассейна-инфинити на крыше отеля с видом на город',
  'в дорогом бутике/на показе мод, гламурный вечерний образ',
  'на фоне старинной европейской архитектуры в Италии, элегантный наряд',
  'в тропическом раю у пальм и белого песка, курортный люкс-образ',
  'в роскошном салоне частного самолёта, деловой шик',
  'на красной дорожке светского мероприятия, вечернее платье',
];

const AFTER_SCENES_MALE = [
  'на роскошной яхте в открытом море, в элегантном светлом костюме',
  'на террасе виллы в Санторини с видом на белые дома и море, льняная рубашка и брюки премиум-класса',
  'в небоскрёбе Дубая на фоне панорамы города, деловой костюм высокого класса',
  'на пляже Мальдив у бирюзовой воды, лёгкий белый костюм/рубашка',
  'на парижской улице у Эйфелевой башни, шикарный модный мужской лук',
  'в роскошном пятизвёздочном отеле с мраморным лобби, деловой костюм',
  'у бассейна-инфинити на крыше отеля с видом на город',
  'на показе мод/светском приёме, элегантный смокинг',
  'на фоне старинной европейской архитектуры в Италии, элегантный костюм',
  'в тропическом раю у пальм и белого песка, курортный люкс-образ',
  'в роскошном салоне частного самолёта, деловой шик',
  'на красной дорожке светского мероприятия, классический смокинг',
];

function pickRandom(list) {
  return list[Math.floor(Math.random() * list.length)];
}

function normalizeGender(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (['male', 'man', 'м', 'мужской', 'мужчина'].includes(normalized)) return 'male';
  if (['female', 'woman', 'ж', 'женский', 'женщина'].includes(normalized)) return 'female';
  return null;
}

function randomGender() {
  return Math.random() < 0.5 ? 'male' : 'female';
}

function randomAge() {
  return 20 + Math.floor(Math.random() * 31); // 20..50
}

function makeClient() {
  return new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Admin-API-Key',
  };
}

function parseBody(req) {
  try {
    if (req.bodyJson) return req.bodyJson;
  } catch {
    // req.bodyJson бросает SyntaxError, если тело запроса пустое или не JSON.
  }
  if (typeof req.body === 'string') {
    try { return JSON.parse(req.body); } catch { return {}; }
  }
  return req.body ?? {};
}

function isAuthorized(req, body) {
  if (!REQUIRE_ADMIN_KEY) return true;
  const fromHeader = req.headers['x-admin-api-key'];
  const fromBody = body?.adminKey ?? body?.admin_key;
  const fromQuery = req.query?.key;
  const provided = (fromHeader || fromBody || fromQuery || '').trim();
  return provided === ADMIN_KEY;
}

function sanitize(value, fallback = 'ad') {
  const normalized = String(value || '')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 24);
  return normalized || fallback;
}

async function downloadImageAsBuffer(url) {
  const response = await fetch(url, {
    headers: { 'User-Agent': 'AppwriteFunction/ad-creative-generator' },
    signal: AbortSignal.timeout(45_000),
  });
  if (!response.ok) {
    throw new Error(`Не удалось скачать reference image: HTTP ${response.status}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

function buildPrompt({
  leftScene,
  rightScene,
  offerText,
  aspectRatio,
  age,
  gender,
}) {
  const isMale = gender === 'male';
  const subject = isMale ? 'man' : 'woman';
  const pronounPossessive = isMale ? 'his' : 'her';
  const pronounObject = isMale ? 'him' : 'her';
  const dreamerGroup = isMale ? 'men' : 'women';

  return [
    `[${aspectRatio}] [temp=0.75]`,
    'STRICT RULE #1 (HIGHEST PRIORITY): The final image must contain ZERO text. No letters, no words, no captions, no labels, no watermarks, no numbers. Specifically NEVER render the words "before", "after", "до", "после" or any similar label anywhere. These words below are ONLY internal instructions for you — they must NOT appear as visible text in the picture.',
    `Create ONE single hyper-photorealistic advertising image of a ${subject}, split vertically into a LEFT part and a RIGHT part with a smooth natural transition in the center. Absolutely photorealistic, real human skin texture with pores and natural imperfections, realistic lighting and shadows — NOT illustrated, NOT 3D render, NOT plastic, NOT over-smoothed, NOT AI-looking.`,
    `The ${subject} has a RUSSIAN (Slavic) appearance with natural Slavic facial features. ${pronounPossessive[0].toUpperCase()}${pronounPossessive.slice(1)} age is approximately ${age} years old — render ${pronounObject} clearly looking that age.`,
    'The LEFT (before) everyday environment should feel like ordinary Russian/Eastern-European daily life. The RIGHT (after) environment is NOT limited to Russia — it must be a glamorous aspirational location anywhere in the world.',
    `The SAME exact ${subject} must appear on both sides with identical identity, face geometry, age, skin tone, body proportions and hair features. Same person, only the styling, location and photo quality change.`,
    'LEFT PART (the "before" idea — do NOT write this word): an authentic AMATEUR snapshot, as if taken on an average smartphone in an ordinary everyday moment. Casual everyday clothing, flat ambient lighting, slightly mediocre framing, mild phone-camera noise, no professional retouch. It must look like a real ordinary candid photo.',
    `LEFT FACE RULE (MANDATORY): the ${subject} is facing the camera directly, head turned straight towards the lens, both eyes clearly open and visible, looking into the camera. NEVER show ${pronounObject} in profile, from the back, looking away, or with the head turned sideways — the face must be frontal and clearly recognizable.`,
    'IMPORTANT VARIETY: the LEFT everyday environment must be DIFFERENT and varied every time — do NOT default to a room/kitchen, and do NOT put food on a table. Choose a realistic everyday Russian setting and freely improvise the exact location; it is left to your discretion.',
    `LEFT DETAILS (use this everyday setting): ${leftScene}`,
    `RIGHT PART (the "after" idea — do NOT write this word): a high-end PROFESSIONAL photoshoot of the same ${subject}, as if taken by a professional photographer with a full-frame camera and 85mm lens, soft studio/cinematic lighting, elegant expensive outfit appropriate for a ${subject}, flattering pose, magazine editorial quality, crisp sharp focus, professional color grading.`,
    `RIGHT FACE RULE (MANDATORY): the ${subject}'s face is turned towards the camera, clearly visible and well lit — a flattering three-quarter or frontal angle is fine, but the face must never be hidden, turned fully away, or obscured.`,
    `IMPORTANT VARIETY: the RIGHT location must be DIFFERENT and varied every time — a glamorous, desirable destination where ${dreamerGroup} dream to have a photoshoot (luxury resorts, famous world cities, yachts, exotic beaches, premium interiors). Do NOT keep it Russian and do NOT repeat the same place; freely improvise the exact glamorous location.`,
    `RIGHT DETAILS (use this aspirational location): ${rightScene}`,
    offerText
      ? `The ONLY text allowed in the whole image is exactly this Cyrillic headline: "${offerText}", minimal premium typography. Absolutely no other letters or words anywhere.`
      : 'No text at all.',
    'STRICT RULE #2 (FRAMING, HIGH PRIORITY): on BOTH halves, the whole head and full body (or at minimum head-to-hips) of the person must fit completely inside the frame with comfortable margin on every side. NEVER crop, cut off, or clip the top of the head, the forehead, the chin, the face, the hands or the feet at the image edge. Zoom out and reposition as needed so nothing important is cut by the frame border.',
    'STRICT RULE #3 (HORIZONTAL LAYOUT, HIGH PRIORITY): the overall image is WIDE/LANDSCAPE, wider than it is tall. Frame both halves so the person is shown at a similar, comfortably zoomed-out scale on the LEFT and on the RIGHT — do NOT shoot one side as an extreme close-up and the other as a distant full-body shot.',
    `EYE-LEVEL ALIGNMENT (MANDATORY): the ${subject}'s eyes/face must sit at approximately the SAME height (same vertical position within the frame) on both the LEFT and the RIGHT half, so the two heads line up horizontally across the split. Keep a similar camera distance and framing scale on both sides to make this alignment natural.`,
    'Composition rules: left part = amateur, right part = professional; both halves balanced in scale and face height; medium-full or full body portrait, fully inside frame, generous headroom; no collage borders; no duplicated heads; no extra limbs; no deformations.',
    'STRICT RULE #4 (REPEAT): the picture is 100% free of any text/letters/words/labels. Never paint "before", "after", "до", "после". A clean photo with no typography.',
    'Final output: a single believable photorealistic advertising photo suitable for VK Ads, with a clear visual contrast between an amateur snapshot on the left and a professional shoot on the right.',
  ].join('\n');
}

async function callApiBost({ prompt, referenceBuffer, model }) {
  const url = `${APIBOST_BASE}/v1beta/models/${model}:generateContent`;
  const parts = [{ text: prompt }];
  if (referenceBuffer) {
    parts.push({ inlineData: { mimeType: 'image/jpeg', data: referenceBuffer.toString('base64') } });
  }
  const payload = {
    contents: [
      {
        role: 'user',
        parts,
      },
    ],
    generationConfig: {
      responseModalities: ['IMAGE'],
    },
  };

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(USE_APIBOST_PROXY ? {} : { Authorization: `Bearer ${API_BOST_KEY}` }),
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(420_000),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`ApiBost HTTP ${response.status}: ${text.slice(0, 300)}`);
  }

  const data = await response.json();
  for (const candidate of data?.candidates ?? []) {
    for (const part of candidate?.content?.parts ?? []) {
      const inline = part?.inlineData ?? part?.inline_data;
      if (inline?.data) return Buffer.from(inline.data, 'base64');
    }
  }

  const finishReason = data?.candidates?.[0]?.finishReason ?? 'UNKNOWN';
  throw new Error(`ApiBost не вернул изображение (finishReason=${finishReason})`);
}

async function normalizeOutput({
  sourceBuffer,
  width,
  height,
  format,
}) {
  const base = sharp(sourceBuffer)
    .rotate()
    .resize(width, height, { fit: 'cover', position: 'center' });

  if (format === 'png') {
    const attempts = [
      { compressionLevel: 9, quality: 95, adaptiveFiltering: true, palette: false },
      { compressionLevel: 9, quality: 85, adaptiveFiltering: true, palette: true },
      { compressionLevel: 9, quality: 75, adaptiveFiltering: true, palette: true },
    ];
    for (const cfg of attempts) {
      const buf = await base.clone().png(cfg).toBuffer();
      if (buf.length <= MAX_BYTES) {
        return { buffer: buf, ext: 'png', mimeType: 'image/png' };
      }
    }
    throw new Error('PNG превысил лимит 5 МБ. Используйте формат JPG.');
  }

  const qualities = [90, 85, 80, 75, 70, 65, 60];
  for (const quality of qualities) {
    const buf = await base.clone().jpeg({ quality, mozjpeg: true }).toBuffer();
    if (buf.length <= MAX_BYTES) {
      return { buffer: buf, ext: 'jpg', mimeType: 'image/jpeg' };
    }
  }
  throw new Error('Не удалось уложить JPG в 5 МБ.');
}

async function uploadResult(storage, { fileBuffer, ext, filePrefix }) {
  const fileId = `${filePrefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`
    .replace(/[^a-zA-Z0-9._-]/g, '-')
    .slice(0, 36);
  await storage.createFile(
    BUCKET_ID,
    fileId,
    InputFile.fromBuffer(fileBuffer, `${fileId}.${ext}`),
    ['read("any")'],
  );
  const base = ENDPOINT.replace(/\/v1\/?$/, '');
  const fileUrl = `${base}/v1/storage/buckets/${BUCKET_ID}/files/${fileId}/view?project=${PROJECT_ID}`;
  return { fileId, fileUrl };
}

export default async ({ req, res, log, error }) => {
  const headers = corsHeaders();
  if (req.method === 'OPTIONS') {
    return res.send('', 204, headers);
  }

  // Принимаем и POST (с body), и GET (нажал Create без body — берутся дефолты).
  const body = parseBody(req);
  if (!isAuthorized(req, body)) {
    return res.json({ error: 'Unauthorized' }, 403, headers);
  }
  if (!API_BOST_KEY && !USE_APIBOST_PROXY) {
    return res.json({ error: 'API_BOST_API_KEY не задан' }, 500, headers);
  }
  if (!ENDPOINT || !PROJECT_ID || !API_KEY) {
    return res.json({ error: 'APPWRITE env не настроен' }, 500, headers);
  }

  const referenceImageUrl = String(body.referenceImageUrl || '').trim();
  const preset = String(body.sizePreset || '4:5').trim();
  const outputFormat = String(body.outputFormat || 'jpg').trim().toLowerCase();
  const gender = normalizeGender(body.gender) || randomGender();
  const afterScenesPool = gender === 'male' ? AFTER_SCENES_MALE : AFTER_SCENES_FEMALE;
  const leftScene = String(
    body.leftScene || pickRandom(BEFORE_SCENES),
  ).trim();
  const rightScene = String(
    body.rightScene || pickRandom(afterScenesPool),
  ).trim();
  const age = Number.isFinite(Number(body.age)) && Number(body.age) >= 18 && Number(body.age) <= 70
    ? Math.trunc(Number(body.age))
    : randomAge();
  const offerText = String(body.offerText || '').trim();
  const campaignName = String(body.campaignName || 'vk_ads').trim();
  const model = String(body.model || APIBOST_MODEL).trim();

  const hasReference = referenceImageUrl.startsWith('http://') || referenceImageUrl.startsWith('https://');
  if (!SIZE_PRESETS[preset]) {
    return res.json({ error: 'sizePreset должен быть одним из: 1:1, 4:5, 16:9' }, 400, headers);
  }
  if (!['jpg', 'jpeg', 'png'].includes(outputFormat)) {
    return res.json({ error: 'outputFormat должен быть jpg или png' }, 400, headers);
  }

  const { width, height, aspectRatio } = SIZE_PRESETS[preset];
  const normalizedFormat = outputFormat === 'jpeg' ? 'jpg' : outputFormat;

  try {
    log(`ad creative start preset=${preset} format=${normalizedFormat} reference=${hasReference} gender=${gender} age=${age}`);
    let referenceBuffer = null;
    if (hasReference) {
      try {
        referenceBuffer = await downloadImageAsBuffer(referenceImageUrl);
      } catch (downloadErr) {
        // Сервер Appwrite (РФ) часто не может тянуть внешние URL напрямую.
        // Не валим генерацию — переходим в надёжный text-to-image режим.
        log(`reference download failed, fallback to text-to-image: ${downloadErr.message}`);
        referenceBuffer = null;
      }
    }
    const prompt = buildPrompt({
      leftScene,
      rightScene,
      offerText,
      aspectRatio,
      age,
      gender,
    });
    const generatedBuffer = await callApiBost({
      prompt,
      referenceBuffer,
      model,
    });
    const normalized = await normalizeOutput({
      sourceBuffer: generatedBuffer,
      width,
      height,
      format: normalizedFormat,
    });
    const storage = new Storage(makeClient());
    const uploaded = await uploadResult(storage, {
      fileBuffer: normalized.buffer,
      ext: normalized.ext,
      filePrefix: `ad_${sanitize(campaignName, 'vkads')}`,
    });

    return res.json({
      ok: true,
      imageUrl: uploaded.fileUrl,
      fileId: uploaded.fileId,
      bucketId: BUCKET_ID,
      format: normalized.ext,
      mimeType: normalized.mimeType,
      width,
      height,
      bytes: normalized.buffer.length,
      sizePreset: preset,
      aspectRatio,
      model,
      age,
      gender,
      referenceUsed: referenceBuffer !== null,
    }, 200, headers);
  } catch (e) {
    error(`ad creative error: ${e.message}`);
    return res.json({
      ok: false,
      error: e.message,
    }, 500, headers);
  }
};
