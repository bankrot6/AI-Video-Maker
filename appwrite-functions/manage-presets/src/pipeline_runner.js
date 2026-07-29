import crypto from 'crypto';
import { Databases, Storage, Query, ID } from 'node-appwrite';
import { InputFile } from 'node-appwrite/file';

export const CHANNELS       = ['clickpickstyle', 'photosesser'];

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
const APIBOST_BASE  = hasYandexRelay()
  ? buildYandexRelayUrl(PIAPI_PROXY_PORT, buildTokenizedNlPath('/apibost'))
  : NL_HOST && NL_TOKEN
    ? `http://${NL_HOST}:${PIAPI_PROXY_PORT}/ai-${NL_TOKEN}/apibost`
    : 'https://apibost.com';
const USE_DEEPSEEK_PROXY = hasYandexRelay() || (NL_HOST && NL_TOKEN);
const USE_APIBOST_PROXY  = APIBOST_BASE.startsWith('http://');
const TELEGRAM_PROXY_BASE = hasYandexRelay()
  ? buildYandexRelayUrl(PIAPI_PROXY_PORT, buildTokenizedNlPath('/imgproxy'))
  : NL_HOST && NL_TOKEN
    ? `http://${NL_HOST}:${PIAPI_PROXY_PORT}/ai-${NL_TOKEN}/imgproxy`
    : '';
const APIBOST_MODEL = process.env.APIBOST_MODEL || 'gemini-3-pro-image-preview';
const STATE_COLL            = 'pipeline_state';
const STATE_DOC_ID          = 'processed_posts';

const TG_HEADERS = {
  'User-Agent':
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0',
};

const DEEPSEEK_SYSTEM_PROMPT = `Ты эксперт по фотосессиям и промпт-инженер приложения для AI-фотографии.

Тебе дадут СЫРОЙ промпт или описание идеи из Telegram-канала. Твоя задача — преобразовать его в СТРОГО СТРУКТУРИРОВАННЫЙ промпт нашего приложения.

ОБЯЗАТЕЛЬНАЯ СТРУКТУРА (6 разделов, все на РУССКОМ языке):

ОПИСАНИЕ СЦЕНЫ:
[3-5 предложений. Локация, окружение, фон — очень конкретно: тип места, пространственная компоновка, планы (передний/задний), текстуры и материалы поверхностей, цвета, качество и направление света.
ОСОБЫЕ ТЕХНИКИ: Если промпт описывает сюрреализм, коллаж, двойную экспозицию, polaroid-сетку, составное изображение (человек состоит из фотографий), типографику поверх изображения — ОБЯЗАТЕЛЬНО сохрани эту технику как главный визуальный приём, опиши её максимально детально в самом начале. НЕ заменяй необычную технику обычной фотографией!]

ПЕРСОНАЖ:
[ОБЯЗАТЕЛЬНО начни с пола и возраста: "Молодая женщина 20-30 лет" / "Молодой мужчина" / "Ребёнок" — НЕ используй слово "модель" без указания пола!
Затем опиши:
— Одежда: конкретный предмет, цвет, паттерн, ткань и посадка ("облегающее бордовое бархатное мини-платье с открытым плечом")
— Аксессуары: украшения, обувь, сумка — конкретно
— Поза и положение тела: угол разворота, положение рук, ног, наклон головы, направление взгляда
— Тип телосложения: опиши кратко если указан в оригинале (стройное / атлетичное / пышное / хрупкое)
ВСЕГДА завершать блоком: "Черты лица, форма скул, линия подбородка, цвет и форма глаз, форма носа и губ, тон и текстура кожи по всему телу, тип телосложения и пропорции фигуры — всё сохраняется точно как на референс-фото без идеализации и без каких-либо изменений."]

ОБЪЕКТЫ И ДЕТАЛИ:
[2-3 предложения. Конкретные реквизиты с материалами, размерами, цветами: "белая керамическая ваза высотой ~40 см с золотым ободком", не просто "ваза". Опиши расположение объектов в кадре относительно персонажа.
ТЕКСТОВЫЕ НАДПИСИ: Если промпт содержит текст на изображении (поздравление, дата, слоган, имя, знак) — ОБЯЗАТЕЛЬНО укажи: точный текст КИРИЛЛИЦЕЙ (не переводи на английский!), стиль шрифта (каллиграфический / рукописный / serif / sans-serif / bold), цвет, размер относительно кадра, точную позицию (центр нижней трети / правый верхний угол / etc). Пример: «Надпись "8 МАРТА" золотым каллиграфическим шрифтом по центру нижней трети кадра.»]

АТМОСФЕРА И НАСТРОЕНИЕ:
[2-3 предложения. Эмоциональный тон — романтика, энергия, спокойствие, роскошь, игривость, загадочность, уверенность, ностальгия, сказочность, тревога. Укажи как эта атмосфера проявляется визуально (через позу, свет, цвета, выражение лица).]

ЦВЕТОВАЯ ПАЛИТРА:
[1-2 предложения. Конкретные названия цветов и оттенков доминирующей гаммы, акцентные цвета и тона кожи: "Доминируют тёплые золотисто-янтарные тона, акценты тёмно-бордового и кремово-белого, кожа персонажа тёплого оливкового оттенка".]

ТЕХНИЧЕСКИЕ ПАРАМЕТРЫ:
[Освещение: конкретный тип с деталями (золотой час — тёплый боковой свет / жёсткая студийная вспышка с тенями / мягкий рассеянный оконный свет / студийный октабокс сверху / освещение Рембрандта 45° / двойной контровой свет). Камера: объектив (85мм для портретов / 35мм для окружения / 50мм для универсальных), диафрагма f/1.4–f/2.8, ракурс (фронтальный / чуть сверху / снизу / 3/4). Завершить точно этой фразой: "профессиональная фотография, высокое разрешение 2K, резкий фокус на лице, натуральная текстура кожи без ретуши, сохранение личности и телосложения с референс-фото, формат 3:4 вертикальный, фотореалистично."]

КРИТИЧЕСКИЕ ПРАВИЛА:
- Весь вывод ТОЛЬКО на русском языке
- Строго соблюдай эту структуру — 6 разделов, именно эти заголовки
- Используй профессиональную фотографическую терминологию
- Будь предельно конкретен: одежда, реквизит, освещение, позиции объектов
- Не добавляй ничего лишнего — только 6 разделов
- Объём: 350-500 слов в сумме
- Никаких кавычек, вступлений, пояснений — только структура
- ФОРМАТ ВСЕГДА ВЕРТИКАЛЬНЫЙ 3:4 — никогда не горизонтальный
- НЕ УПРОЩАЙ: необычные художественные техники (коллаж, сюрреализм, typographic overlay, двойная экспозиция) сохрани в точности как главный элемент
- ТЕКСТ НА ИЗОБРАЖЕНИИ: надписи, даты, поздравления — только кириллицей, никогда не переводить на английский
- ТЕЛО: всегда описывай телосложение как оно есть — без идеализации, без "стройная" если в оригинале не указано`;

const TAG_MAP = {
  женские:'женщины', женщин:'женщины', woman:'женщины', women:'женщины',
  мужские:'мужчины', мужчин:'мужчины', man:'мужчины', men:'мужчины',
  детские:'дети', дети:'дети', ребёнок:'дети', ребенок:'дети', children:'дети', child:'дети', kids:'дети',
  семейные:'семья', семья:'семья', family:'семья',
  природа:'природа', улица:'природа', сад:'природа', nature:'природа',
  студийное_фото:'студия', студия:'студия', studio:'студия',
  город:'город', улицы:'город', city:'город',
  бизнес:'бизнес', деловой:'бизнес', business:'бизнес',
  романтика:'романтика', love:'романтика', romance:'романтика',
  путешествия:'путешествия', travel:'путешествия',
  животные:'животные', питомцы:'животные', animals:'животные',
  фэнтези:'фэнтези', фантастика:'фэнтези', сказка:'фэнтези', fantasy:'фэнтези',
  ретро:'ретро', винтаж:'ретро', retro:'ретро', vintage:'ретро',
  минимализм:'минимализм', minimalism:'минимализм',
  роскошь:'роскошь', luxury:'роскошь',
  спорт:'спорт', sport:'спорт',
  еда:'еда', food:'еда',
  праздник:'праздник', новый_год:'праздник', holiday:'праздник',
  девочка:'дети', мальчик:'дети',
  лето:'лето', summer:'лето', зима:'зима', winter:'зима',
  автомобили:'автомобили', cars:'автомобили', car:'автомобили',
  мода:'мода', fashion:'мода', editorial:'мода',
};

const KEYWORD_TAG_ENTRIES = Object.entries({
  женщин:'женщины', девушк:'женщины', невест:'женщины', платье:'женщины', юбк:'женщины',
  блузк:'женщины', корсет:'женщины', каблук:'женщины', шпильк:'женщины', серьг:'женщины', ожерель:'женщины',
  мужчин:'мужчины', мужской:'мужчины', парень:'мужчины', борода:'мужчины', джентльмен:'мужчины',
  'ребёнок':'дети', 'ребенок':'дети', малыш:'дети', девочк:'дети', мальчик:'дети', подростк:'дети',
  ' семь':'семья', мама:'семья', папа:'семья', родител:'семья',
  лес:'природа', парк:'природа', природ:'природа', поле:'природа', луг:'природа', река:'природа', озеро:'природа',
  хвойн:'природа', цветущ:'природа',
  студи:'студия', 'белый фон':'студия', 'тёмный фон':'студия', 'нейтральный фон':'студия',
  город:'город', улиц:'город', набережн:'город', переулк:'город', площадь:'город', кафе:'город',
  ресторан:'город', архитектур:'город',
  сказк:'фэнтези', мистик:'фэнтези', ангел:'фэнтези', магич:'фэнтези', волшебн:'фэнтези',
  ретро:'ретро', винтаж:'ретро', полароид:'ретро',
  роскошн:'роскошь', vip:'роскошь', шёлк:'роскошь', бархат:'роскошь', брилли:'роскошь',
  яхт:'роскошь', пентхаус:'роскошь',
  бизнес:'бизнес', офис:'бизнес', корпоратив:'бизнес', конференц:'бизнес',
  пляж:'путешествия', море:'путешествия', океан:'путешествия', курорт:'путешествия', тропик:'путешествия',
  волк:'животные', лошадь:'животные', кошк:'животные', пантер:'животные', питомц:'животные', собак:'животные',
  праздник:'праздник', карнавал:'праздник', фиеста:'праздник', фестиваль:'праздник', маскарад:'праздник',
  минимализм:'минимализм',
  романтик:'романтика', влюблённ:'романтика',
  еда:'еда', кухн:'еда', овощ:'еда', фрукт:'еда',
});

const GENDER_TAGS   = new Set(['женщины', 'мужчины', 'дети', 'семья']);
const TAG_MAP_ENTRIES = Object.entries(TAG_MAP);

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function stripMarkdownFences(s) {
  let t = s.trim();
  t = t.replace(/^```[^\n]*\n?/, '');
  t = t.replace(/\n?```$/, '');
  return t.trim();
}

function titleSlug(title) {
  const base = (title || 'preset')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '_')
    .replace(/^_|_$/g, '');
  return (base || 'preset').slice(0, 15);
}

function makePresetDocId() {
  const ts  = Date.now().toString(36);
  const rnd = Math.random().toString(36).slice(2, 10);
  return `p_${ts}_${rnd}`;
}

function extractTags(hashtags, text) {
  const found = new Set();

  for (const tag of hashtags) {
    const norm = String(tag).toLowerCase().trim();
    if (TAG_MAP[norm]) {
      found.add(TAG_MAP[norm]);
    } else {
      for (const [key, val] of TAG_MAP_ENTRIES) {
        if (val && (norm.includes(key) || key.includes(norm))) {
          found.add(val);
          break;
        }
      }
    }
  }

  const textLow = text.toLowerCase();
  for (const [kw, tag] of KEYWORD_TAG_ENTRIES) {
    if (textLow.includes(kw)) found.add(tag);
  }

  let hasGender = false;
  for (const g of GENDER_TAGS) if (found.has(g)) { hasGender = true; break; }
  if (!hasGender) found.add('женщины');

  return Array.from(found).sort().slice(0, 6);
}

function parseTgHtml(channel, html) {
  const esc = channel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re  = new RegExp(
    `<div[^>]+data-post="${esc}/(\\d+)"[^>]*>([\\s\\S]*?)(?=<div[^>]+data-post="|$)`, 'g'
  );
  const posts = [];
  let m;
  while ((m = re.exec(html)) !== null) {
    const postId = m[1];
    const block  = m[2];

    const textMatch = block.match(/<div[^>]*class="[^"]*tgme_widget_message_text[^"]*"[^>]*>([\s\S]*?)<\/div>/);
    let rawText = '';
    if (textMatch) {
      let raw = textMatch[1];
      raw = raw.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '');
      rawText = raw.replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').trim();
    }
    if (!rawText) continue;

    const codeMatch = block.match(/<code[^>]*>([\s\S]*?)<\/code>/);
    if (!codeMatch) continue;
    const prompt = codeMatch[1].replace(/<[^>]+>/g,'')
      .replace(/&nbsp;/g,' ').replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').trim();
    if (!prompt) continue;

    const firstLine = rawText.split('\n')[0].trim();
    let title = firstLine.replace(/^[\u{1F300}-\u{1FFFF}\u2600-\u27FF\s]+/u, '').trim();
    if (!title) title = firstLine;

    const hashtagRe = /#([\w\u0400-\u04FF]+)/g;
    const hashtags  = [];
    let hm;
    while ((hm = hashtagRe.exec(block)) !== null) hashtags.push(hm[1]);

    let views = 0;
    const viewsMatch = block.match(/<span[^>]*class="[^"]*tgme_widget_message_views[^"]*"[^>]*>([^<]+)</);
    if (viewsMatch) {
      const v = viewsMatch[1].trim().replace(/K/g,'00').replace(/\./g,'');
      views = parseInt(v.replace(/[^\d]/g,''), 10) || 0;
    }

    let reactions = 0;
    const reactionRe = /<span[^>]*class="[^"]*tgme_widget_message_reactions[^"]*"[^>]*>([\s\S]*?)<\/span>/g;
    let rm;
    while ((rm = reactionRe.exec(block)) !== null) {
      const nums = rm[1].match(/(\d+)/g);
      if (nums) for (const n of nums) reactions += parseInt(n, 10);
    }

    posts.push({
      id: postId, channel, title, prompt, hashtags,
      tags: extractTags(hashtags, `${rawText} ${title}`),
      reactions, views, popularity: reactions * 100 + views,
      url: `https://t.me/${channel}/${postId}`,
    });
  }
  return posts;
}

async function parseChannel(channel, maxPosts) {
  const postsById = new Map();
  let beforeId    = null;
  const target    = Math.max(200, maxPosts * 3);

  for (let page = 0; page < 8; page++) {
    const directUrl = new URL(`https://t.me/s/${channel}`);
    if (beforeId) directUrl.searchParams.set('before', beforeId);
    const urlsToTry = [];
    if (TELEGRAM_PROXY_BASE) {
      const proxyUrl = new URL(TELEGRAM_PROXY_BASE);
      proxyUrl.searchParams.set('url', directUrl.toString());
      urlsToTry.push(proxyUrl.toString());
    }
    urlsToTry.push(directUrl.toString());
    let resp;
    let lastError = null;
    for (const url of urlsToTry) {
      try {
        resp = await fetch(url, { headers: TG_HEADERS, signal: AbortSignal.timeout(20_000) });
        if (resp.ok) break;
        lastError = new Error(`HTTP ${resp.status}`);
        console.log(`parseChannel @${channel} page ${page+1}: ${url} -> HTTP ${resp.status}`);
      } catch (e) {
        lastError = e;
        console.log(`parseChannel @${channel} page ${page+1}: ${url} -> ${e.message}`);
      }
    }
    if (!resp?.ok) {
      console.log(`parseChannel @${channel} page ${page+1}: ${lastError?.message || 'fetch failed'}`);
      break;
    }
    const pagePosts = parseTgHtml(channel, await resp.text());
    if (!pagePosts.length) break;
    let added = 0;
    for (const p of pagePosts) { if (!postsById.has(p.id)) { postsById.set(p.id, p); added++; } }
    if (added === 0 || postsById.size >= target) break;
    const minId = Math.min(...pagePosts.map(p => parseInt(p.id, 10)));
    beforeId = String(minId);
    await sleep(800);
  }
  return Array.from(postsById.values());
}

function scorePost(post, tagCounts, sessionCounts) {
  const tags = post.tags || [];
  const deficit = tags.length
    ? tags.reduce((s,t) => s + 1/((tagCounts[t]||0)+(sessionCounts[t]||0)+1), 0)
    : 0;
  return deficit * 1000 + (post.popularity || 0) / 500000;
}

function sortPostsSmart(posts, tagCounts) {
  const sessionCounts = {};
  const result = [];
  const remaining = [...posts];
  while (remaining.length) {
    let best = remaining[0], bestScore = scorePost(best, tagCounts, sessionCounts);
    for (let i = 1; i < remaining.length; i++) {
      const s = scorePost(remaining[i], tagCounts, sessionCounts);
      if (s > bestScore) { bestScore = s; best = remaining[i]; }
    }
    result.push(best);
    remaining.splice(remaining.indexOf(best), 1);
    for (const t of best.tags || []) sessionCounts[t] = (sessionCounts[t]||0) + 1;
  }
  return result;
}

function genderHint(tags) {
  if (tags.includes('женщины')) return 'ВАЖНО: персонаж — ЖЕНЩИНА. В разделе ПЕРСОНАЖ обязательно начни с "Молодая женщина".';
  if (tags.includes('мужчины')) return 'ВАЖНО: персонаж — МУЖЧИНА. В разделе ПЕРСОНАЖ обязательно начни с "Молодой мужчина".';
  if (tags.includes('дети'))    return 'ВАЖНО: персонаж — РЕБЁНОК. В разделе ПЕРСОНАЖ обязательно начни с "Ребёнок".';
  if (tags.includes('семья'))   return 'ВАЖНО: персонажи — СЕМЬЯ (мужчина, женщина, возможно дети). Опиши всех.';
  return 'ВАЖНО: персонаж — ЖЕНЩИНА (по умолчанию). Начни с "Молодая женщина".';
}

async function convertPromptToStructure(rawPrompt, title, deepseekKey, tags) {
  const userMsg = `Название фотосессии: ${title}\n\n${genderHint(tags||[])}\n\nИсходный промпт из Telegram:\n${rawPrompt}\n\nПреобразуй этот промпт в нашу структуру из 6 разделов.`;
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
      max_tokens: 2200, temperature: 0.5,
    }),
    signal: AbortSignal.timeout(90_000),
  });
  if (!resp.ok) throw new Error(`DeepSeek HTTP ${resp.status}: ${(await resp.text()).slice(0,200)}`);
  const data = await resp.json();
  const content = data.choices?.[0]?.message?.content;
  return content ? (stripMarkdownFences(content) || null) : null;
}

async function generateImageWithApiBost(prompt, apiBostKey) {
  const url = `${APIBOST_BASE}/v1beta/models/${APIBOST_MODEL}:generateContent`;
  console.log(`ApiBost via: ${url}, model=${APIBOST_MODEL}`);

  const enhancedPrompt = `[3:4] [temp=0.9]\n${prompt}\n\nFINAL REMINDER: OUTPUT FORMAT: VERTICAL PORTRAIT, aspect ratio 3:4. NEVER generate a horizontal or landscape image. Any text MUST be in Cyrillic.`;

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

async function getTagCounts(databases, databaseId, presetsColl) {
  const counts = {};
  let offset   = 0;
  const limit  = 300;
  while (true) {
    const res = await databases.listDocuments(databaseId, presetsColl, [
      Query.limit(limit), Query.offset(offset),
    ]);
    for (const doc of res.documents) {
      if (!Array.isArray(doc.tags)) continue;
      for (const t of doc.tags) {
        if (t && t !== 'custom') counts[t] = (counts[t] || 0) + 1;
      }
    }
    if (res.documents.length < limit) break;
    offset += limit;
  }
  return counts;
}

async function loadProcessedIds(databases, databaseId) {
  const out = {};
  for (const ch of CHANNELS) out[ch] = new Set();
  try {
    const doc  = await databases.getDocument(databaseId, STATE_COLL, STATE_DOC_ID);
    for (const ch of CHANNELS) {
      const arr = doc[ch];
      if (Array.isArray(arr)) arr.forEach(id => out[ch].add(String(id)));
    }
  } catch { /* doc not yet created */ }
  return out;
}

async function loadExistingTelegramKeys(databases, databaseId, presetsColl) {
  const keys   = new Set();
  let   offset = 0;
  const limit  = 500;
  while (true) {
    const res = await databases.listDocuments(databaseId, presetsColl, [
      Query.limit(limit), Query.offset(offset),
    ]);
    for (const doc of res.documents) {
      const ch  = doc.sourceChannel;
      const pid = doc.sourcePostId;
      if (typeof ch === 'string' && ch.trim() && pid != null && String(pid).trim()) {
        keys.add(`${ch}|${String(pid)}`);
      }
    }
    if (res.documents.length < limit) break;
    offset += limit;
  }
  console.log(`Dedup from presets: ${keys.size} with sourceChannel+sourcePostId`);
  return keys;
}

async function markProcessed(databases, databaseId, channel, postId, knownByChannel) {
  const knownArr = Array.from(knownByChannel[channel]);
  if (!knownArr.includes(String(postId))) knownArr.push(String(postId));
  const data = { [channel]: knownArr, updatedAt: new Date().toISOString() };
  try {
    await databases.updateDocument(databaseId, STATE_COLL, STATE_DOC_ID, data);
  } catch {
    try {
      await databases.createDocument(databaseId, STATE_COLL, STATE_DOC_ID, data, ['read("any")']);
    } catch (e) {
      console.log(`markProcessed: ${e.message}`);
    }
  }
}

function buildInitialLikes() {
  const n       = 2 + Math.floor(Math.random() * 7);
  const likedBy = Array.from({ length: n }, () => `seed_${crypto.randomUUID().replace(/-/g,'')}`);
  return { likesCount: n, likedBy };
}

export async function runPresetPipeline(opts) {
  const { databases, storage, apiBostKey, deepseekKey, limit,
          databaseId, presetsColl, bucketId, endpoint, projectId } = opts;

  const summary = { ok:true, limit, processed:0, success:0, failed:0, skippedNoNew:0, errors:[] };

  const knownByChannel     = await loadProcessedIds(databases, databaseId);
  const existingTgKeys     = await loadExistingTelegramKeys(databases, databaseId, presetsColl);

  const allNew = [];
  for (const ch of CHANNELS) {
    console.log(`Parsing @${ch}…`);
    const posts = await parseChannel(ch, Math.max(200, limit * 3));
    const fresh = posts.filter(p => !knownByChannel[ch].has(p.id) && !existingTgKeys.has(`${ch}|${p.id}`));
    console.log(`  @${ch}: feed ${posts.length}, new ${fresh.length}`);
    allNew.push(...fresh);
  }

  if (!allNew.length) {
    summary.skippedNoNew = 1;
    console.log('No new Telegram posts.');
    return summary;
  }

  const tagCounts = await getTagCounts(databases, databaseId, presetsColl);
  const toProcess = sortPostsSmart(allNew, tagCounts).slice(0, limit > 0 ? limit : Infinity);
  console.log(`Pipeline: processing ${toProcess.length} post(s)`);

  for (let idx = 0; idx < toProcess.length; idx++) {
    const post   = toProcess[idx];
    const ch     = post.channel;
    const postId = post.id;
    summary.processed++;
    console.log(`[${idx+1}/${toProcess.length}] @${ch}/${postId} ${post.title?.slice(0,60)}`);

    try {
      const structured = await convertPromptToStructure(post.prompt, post.title, deepseekKey, post.tags);
      if (!structured) {
        summary.failed++;
        summary.errors.push({ post:`${ch}/${postId}`, step:'deepseek', msg:'empty response' });
        continue;
      }

      const imageBuffer = await generateImageWithApiBost(structured, apiBostKey);
      if (!imageBuffer) {
        summary.failed++;
        summary.errors.push({ post:`${ch}/${postId}`, step:'apibost', msg:'no image' });
        continue;
      }

      const safeId = makePresetDocId();
      const fileId = `prev-${safeId}`.slice(0, 36);
      let   previewImageUrl = null;

      try {
        previewImageUrl = await uploadBufferToAppwrite(imageBuffer, fileId, storage, bucketId, endpoint, projectId);
        console.log(`Image uploaded to Appwrite: ${previewImageUrl}`);
      } catch (e) {
        console.log(`Image upload failed: ${e.message}`);
        summary.failed++;
        summary.errors.push({ post:`${ch}/${postId}`, step:'upload', msg:e.message });
        continue;
      }

      let thumbnailUrl       = null;
      let thumbnailSourceUrl = null;
      try {
        const { default: sharp } = await import('sharp').catch(() => ({ default: null }));
        const thumbFileId = `th-${safeId.replace(/[^a-zA-Z0-9._-]/g, '-').slice(0, 29)}`;
        const thumbBuf    = sharp
          ? await sharp(imageBuffer).resize(400, null, { withoutEnlargement: true }).webp({ quality: 80 }).toBuffer()
          : imageBuffer;
        try { await storage.deleteFile(bucketId, thumbFileId); } catch { /* ok */ }
        await storage.createFile(bucketId, thumbFileId, InputFile.fromBuffer(thumbBuf, `${thumbFileId}.webp`), ['read("any")']);
        const base = endpoint.replace(/\/v1\/?$/, '');
        thumbnailUrl       = `${base}/v1/storage/buckets/${bucketId}/files/${thumbFileId}/view?project=${projectId}`;
        thumbnailSourceUrl = previewImageUrl;
        console.log(`Thumbnail generated: ${thumbnailUrl}`);
      } catch (e) {
        console.log(`Thumbnail generation failed: ${e.message}`);
      }

      const { likesCount, likedBy } = buildInitialLikes();
      await databases.createDocument(databaseId, presetsColl, safeId, {
        title:          post.title,
        prompt:         structured,
        previewImageUrl,
        tags:           post.tags || [],
        createdAt:      new Date().toISOString(),
        sourceChannel:  ch,
        sourcePostId:   String(postId),
        likesCount,
        likedBy,
        ...(thumbnailUrl ? { thumbnailUrl, thumbnailSourceUrl } : {}),
      }, ['read("any")']);

      await markProcessed(databases, databaseId, ch, postId, knownByChannel);
      knownByChannel[ch].add(postId);
      existingTgKeys.add(`${ch}|${postId}`);

      summary.success++;
      await sleep(1_000);
    } catch (e) {
      console.log(`Error @${ch}/${postId}: ${e.message}`);
      summary.failed++;
      summary.errors.push({ post:`${ch}/${postId}`, step:'exception', msg:String(e.message||e) });
    }
  }

  summary.ok = summary.failed === 0 || summary.success > 0;
  return summary;
}
