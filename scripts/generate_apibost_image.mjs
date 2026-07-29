#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');

function loadEnvFile(path) {
  try {
    const text = readFileSync(path, 'utf8');
    for (const line of text.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      const key = trimmed.slice(0, eq).trim();
      let value = trimmed.slice(eq + 1).trim();
      if (
        (value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))
      ) {
        value = value.slice(1, -1);
      }
      if (process.env[key] == null || process.env[key] === '') {
        process.env[key] = value;
      }
    }
  } catch {
    /* optional */
  }
}

loadEnvFile(join(ROOT, '.env'));
loadEnvFile(join(ROOT, '.env.deploy'));

const API_KEY = (process.env.API_BOST_API_KEY ?? '').trim();
const BASE_URL = (process.env.APIBOST_BASE_URL ?? 'https://apibost.com').replace(/\/$/, '');
const DEFAULT_MODEL = process.env.APIBOST_MODEL ?? 'gemini-2.5-flash-image';

const OPENAI_IMAGE_MODELS = new Set(['gpt-image-1.5', 'gpt-image-2']);
const CHAT_IMAGE_MODELS = new Set(['grok-3-image']);

function usage() {
  console.error(`Usage:
  node scripts/generate_apibost_image.mjs "your prompt here" [options]

Options:
  --model <name>     Model (default: ${DEFAULT_MODEL})
  --out <path>       Output file (default: ./generated/apibost-<timestamp>.png)
  --size <WxH>       For OpenAI models: 1024x1024 | 1024x1536 | 1536x1024
  --aspect <ratio>   Portrait default for OpenAI: 3:4

Env:
  API_BOST_API_KEY   Required (from .env.deploy or shell)
`);
  process.exit(1);
}

function parseArgs(argv) {
  const positional = [];
  const opts = {
    model: DEFAULT_MODEL,
    out: null,
    size: null,
    aspect: '3:4',
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--model') opts.model = argv[++i];
    else if (arg === '--out') opts.out = argv[++i];
    else if (arg === '--size') opts.size = argv[++i];
    else if (arg === '--aspect') opts.aspect = argv[++i];
    else if (arg === '--help' || arg === '-h') usage();
    else positional.push(arg);
  }

  const prompt = positional.join(' ').trim();
  if (!prompt) usage();
  return { prompt, ...opts };
}

function sizeForAspect(aspect) {
  if (aspect === '1:1') return '1024x1024';
  if (['3:2', '4:3', '5:4', '16:9', '21:9'].includes(aspect)) return '1536x1024';
  return '1024x1536';
}

function transportFor(model) {
  const m = model.trim().toLowerCase();
  if (OPENAI_IMAGE_MODELS.has(m)) return 'openai-images';
  if (CHAT_IMAGE_MODELS.has(m)) return 'chat';
  return 'gemini';
}

function extractGeminiBase64(data) {
  for (const candidate of data?.candidates ?? []) {
    for (const part of candidate?.content?.parts ?? []) {
      const inline = part.inlineData ?? part.inline_data;
      if (inline?.data) return inline.data;
    }
  }
  return null;
}

async function downloadAsBuffer(url) {
  const resp = await fetch(url, {
    headers: { 'User-Agent': 'AIVideoMaker/generate_apibost_image' },
    signal: AbortSignal.timeout(60_000),
  });
  if (!resp.ok) throw new Error(`Download failed HTTP ${resp.status}`);
  return Buffer.from(await resp.arrayBuffer());
}

async function extractOpenAiBase64(data) {
  for (const item of data?.data ?? []) {
    if (item?.b64_json) return item.b64_json;
    if (item?.url) {
      const buf = await downloadAsBuffer(item.url);
      return buf.toString('base64');
    }
  }

  for (const choice of data?.choices ?? []) {
    const content = choice?.message?.content;
    if (typeof content === 'string') {
      const match = content.match(/https?:\/\/[^\s()<>"\]]+/i);
      if (match) {
        const buf = await downloadAsBuffer(match[0]);
        return buf.toString('base64');
      }
    }
  }
  return null;
}

async function callGemini(model, prompt) {
  const url = `${BASE_URL}/v1beta/models/${model}:generateContent`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${API_KEY}`,
    },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { responseModalities: ['TEXT', 'IMAGE'] },
    }),
    signal: AbortSignal.timeout(420_000),
  });

  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`ApiBost HTTP ${resp.status}: ${text.slice(0, 400)}`);
  }

  const data = JSON.parse(text);
  const b64 = extractGeminiBase64(data);
  if (!b64) {
    const reason = data?.candidates?.[0]?.finishReason ?? 'unknown';
    throw new Error(`No image in response (finishReason=${reason})`);
  }
  return b64;
}

async function callOpenAiImages(model, prompt, size) {
  const resp = await fetch(`${BASE_URL}/v1/images/generations`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${API_KEY}`,
    },
    body: JSON.stringify({ model, prompt, size, n: 1 }),
    signal: AbortSignal.timeout(420_000),
  });

  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`ApiBost HTTP ${resp.status}: ${text.slice(0, 400)}`);
  }

  const b64 = await extractOpenAiBase64(JSON.parse(text));
  if (!b64) throw new Error('No image in OpenAI response');
  return b64;
}

async function callChat(model, prompt) {
  const resp = await fetch(`${BASE_URL}/v1/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${API_KEY}`,
    },
    body: JSON.stringify({
      model,
      messages: [{ role: 'user', content: prompt }],
      temperature: 0.7,
    }),
    signal: AbortSignal.timeout(420_000),
  });

  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`ApiBost HTTP ${resp.status}: ${text.slice(0, 400)}`);
  }

  const b64 = await extractOpenAiBase64(JSON.parse(text));
  if (!b64) throw new Error('No image in chat response');
  return b64;
}

async function main() {
  const { prompt, model, out, size, aspect } = parseArgs(process.argv.slice(2));

  if (!API_KEY) {
    console.error('API_BOST_API_KEY не найден. Добавьте в .env.deploy или экспортируйте в shell.');
    process.exit(1);
  }

  const transport = transportFor(model);
  const started = Date.now();
  console.error(`Model: ${model} (${transport})`);
  console.error(`Prompt: ${prompt.slice(0, 120)}${prompt.length > 120 ? '…' : ''}`);

  let b64;
  if (transport === 'openai-images') {
    b64 = await callOpenAiImages(model, prompt, size ?? sizeForAspect(aspect));
  } else if (transport === 'chat') {
    b64 = await callChat(model, prompt);
  } else {
    b64 = await callGemini(model, prompt);
  }

  const outPath = resolve(
    out ?? join(ROOT, 'generated', `apibost-${Date.now()}.png`),
  );
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, Buffer.from(b64, 'base64'));

  console.log(outPath);
  console.error(`Done in ${((Date.now() - started) / 1000).toFixed(1)}s`);
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
