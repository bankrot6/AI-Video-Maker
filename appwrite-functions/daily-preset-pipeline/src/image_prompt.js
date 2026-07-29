export function buildImagePrompt(structuredPrompt, idea) {
  const { aspectRatio, temperature } = idea.params;
  return [
    `[${aspectRatio}] [temp=${temperature}]`,
    structuredPrompt,
    '',
    `STYLE LOCK: ${idea.styleReminder}`,
    `OUTPUT FORMAT: vertical ${aspectRatio}, never horizontal. Single coherent image, no collage, no frames, no watermarks.`,
    'Any visible text MUST be in Cyrillic.',
  ].join('\n');
}
