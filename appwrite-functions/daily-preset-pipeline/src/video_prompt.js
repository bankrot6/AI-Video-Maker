export const MAX_VIDEO_PROMPT_LENGTH = 2000;

const DIRECTIVES_BUDGET = 50;

/// Цель для текста, который пишет DeepSeek. Ниже жёсткого предела, потому что
/// сохранённый промпт пресета проходит на клиенте ещё правку под фильтр
/// безопасности, а она добавляет возрасты и описания взамен имён.
export const VIDEO_PROMPT_GENERATION_TARGET = 1700;

export function trimToBoundary(text, limit) {
  if (limit <= 0) return '';
  const source = String(text || '').trim();
  if (source.length <= limit) return source;

  const head = source.slice(0, limit);
  for (const separator of ['\n\n', '\n', '. ', '.', ' ']) {
    const cut = head.lastIndexOf(separator);
    if (cut > limit / 2) {
      const trimmed = head.slice(0, cut).trimEnd();
      if (trimmed) return trimmed;
    }
  }
  return head.trimEnd();
}

function videoTail(idea, aspectRatio, duration) {
  return [
    '',
    `STYLE LOCK: ${idea.styleReminder}`,
    `CAMERA: ${idea.cameraMove}`,
    `MOTION BEAT: ${idea.motionBeat}`,
    `OUTPUT: vertical ${aspectRatio} video, ${duration}s, single continuous shot, no collage, no frames, no watermarks, no subtitles.`,
    'Any visible text MUST be in Cyrillic.',
  ];
}

function videoParams(idea) {
  return {
    aspectRatio: idea.params?.aspectRatio || '9:16',
    duration: idea.params?.durationSeconds || 8,
  };
}

/// Сколько символов остаётся структурированному промпту после директив и
/// служебного хвоста. Число объявляется генератору заранее, чтобы результат
/// не приходилось обрезать после оплаты токенов.
export function structuredPromptBudget(idea) {
  const { aspectRatio, duration } = videoParams(idea);
  const directives = `[${aspectRatio}] [${duration}s] `;
  const tail = videoTail(idea, aspectRatio, duration).join('\n');
  const hardBudget =
    MAX_VIDEO_PROMPT_LENGTH -
    Math.max(directives.length, DIRECTIVES_BUDGET) -
    tail.length -
    1;
  return Math.max(0, Math.min(VIDEO_PROMPT_GENERATION_TARGET, hardBudget));
}

export function buildVideoPrompt(structuredPrompt, idea) {
  const { aspectRatio, duration } = videoParams(idea);
  const directives = `[${aspectRatio}] [${duration}s] `;
  const bodyLimit = MAX_VIDEO_PROMPT_LENGTH - Math.max(directives.length, DIRECTIVES_BUDGET);

  const body = trimToBoundary(
    [structuredPrompt.trim(), ...videoTail(idea, aspectRatio, duration)].join('\n'),
    bodyLimit,
  );

  return `${directives}${body}`;
}

export function buildKeyframePrompt(structuredPrompt, idea) {
  const aspectRatio = idea.params?.aspectRatio || '9:16';
  const temperature = idea.params?.temperature ?? 0.9;
  return [
    `[${aspectRatio}] [temp=${temperature}]`,
    structuredPrompt.trim(),
    '',
    `STYLE LOCK: ${idea.styleReminder}`,
    `OUTPUT FORMAT: vertical ${aspectRatio} keyframe for a short video, never horizontal.`,
    'Single coherent image, no collage, no frames, no watermarks, no people unless the plot requires them.',
    'Any visible text MUST be in Cyrillic.',
  ].join('\n');
}
