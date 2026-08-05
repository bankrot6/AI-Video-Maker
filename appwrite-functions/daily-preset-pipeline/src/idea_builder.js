import {
  VISUAL_STYLES,
  MOTIFS,
  COMPOSITIONS,
  PALETTES,
  ATMOSPHERES,
  CAMERA_MOVES,
  MOTION_BEATS,
} from './style_catalog.js';
import { getActiveHolidayMotifs } from './holiday_calendar.js';

const HOLIDAY_PICK_CHANCE = 0.3;
const ASPECT_RATIO = '9:16';
const DURATION_SECONDS = 8;
const TEMPERATURES = [0.7, 0.9, 1.0];
const VIDEO_TAG = 'видео';

const VIDEO_STYLES = VISUAL_STYLES.filter(s => s.videoSuitable !== false);

function pickOne(list) {
  return list[Math.floor(Math.random() * list.length)];
}

function shuffle(list) {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

function styleAllowsMotif(style, motif) {
  if (motif.isHoliday) return true;
  if (!style.motifs?.length) return true;
  return style.motifs.includes(motif.id);
}

function deficitWeight(tags, tagCounts) {
  const list = tags?.length ? tags : ['арт'];
  return list.reduce((sum, t) => sum + 1 / ((tagCounts[t] || 0) + 1), 0) / list.length;
}

function pickMotif({ motifs, tagCounts, usedMotifIds, style }) {
  const pool = motifs.filter(m => !usedMotifIds.has(m.id) && styleAllowsMotif(style, m));
  const source = pool.length ? pool : motifs.filter(m => styleAllowsMotif(style, m));
  if (!source.length) return null;
  return shuffle(source).reduce((best, motif) =>
    deficitWeight(motif.tags, tagCounts) + Math.random() * 0.4 >
    deficitWeight(best.tags, tagCounts) + Math.random() * 0.4 ? motif : best, source[0]);
}

function pickStyle(usedStyleIds) {
  const pool = VIDEO_STYLES.filter(s => !usedStyleIds.has(s.id));
  return pickOne(pool.length ? pool : VIDEO_STYLES);
}

const TITLE_MIN_SCENE_LENGTH = 20;
const TITLE_MAX_SCENE_LENGTH = 70;

function shortenScene(scene) {
  const full = String(scene).trim();
  const head = full.split(/[,:]/)[0].trim();
  const base = head.length >= TITLE_MIN_SCENE_LENGTH ? head : full;
  if (base.length <= TITLE_MAX_SCENE_LENGTH) return base;
  const cut = base.slice(0, TITLE_MAX_SCENE_LENGTH);
  const lastSpace = cut.lastIndexOf(' ');
  return `${(lastSpace > TITLE_MIN_SCENE_LENGTH ? cut.slice(0, lastSpace) : cut).trim()}…`;
}

function buildTitle(style, scene) {
  const title = `${style.title}: ${shortenScene(scene)}`;
  return title.length > 110 ? `${title.slice(0, 107)}…` : title;
}

function buildBrief({
  style, motif, scene, composition, palette, atmosphere, cameraMove, motionBeat,
}) {
  const lines = [
    `Сюжет: ${scene}.`,
    `Тематика: ${motif.title}.`,
    `Визуальный стиль: ${style.title} — ${style.render}.`,
    `Композиция и ракурс: ${composition}.`,
    `Движение камеры: ${cameraMove}.`,
    `Динамика за ${DURATION_SECONDS} секунд: ${motionBeat}.`,
    `Цветовая палитра: ${palette}.`,
    `Атмосфера и свет: ${atmosphere}.`,
    `Формат: вертикальный ролик ${ASPECT_RATIO}, длительность ${DURATION_SECONDS}с.`,
  ];
  if (style.sceneNote) lines.push(`Особое требование стиля: ${style.sceneNote}`);
  if (motif.isHoliday) {
    lines.push(
      `Праздничный повод: «${motif.title}» — ролик должен однозначно читаться как приуроченный к этому празднику.`,
    );
  }
  return lines.join('\n');
}

function mergeTags(style, motif) {
  return Array.from(
    new Set([VIDEO_TAG, ...(motif.tags || []), ...(style.tags || [])]),
  ).slice(0, 6);
}

export function buildIdeas({ count, tagCounts = {}, usedTitles = new Set(), now = new Date() }) {
  const holidayMotifs = getActiveHolidayMotifs(now);
  const localUsedTitles = new Set(Array.from(usedTitles).map(t => String(t).toLowerCase()));
  const usedStyleIds = new Set();
  const usedMotifIds = new Set();
  const ideas = [];

  for (let attempt = 0; ideas.length < count && attempt < count * 8; attempt++) {
    const style = pickStyle(usedStyleIds);

    // Первый пресет отдаём ближайшему празднику, остальные — с небольшой вероятностью.
    const useHoliday = holidayMotifs.length
      && (ideas.length === 0 || Math.random() < HOLIDAY_PICK_CHANCE);
    const motifPool = useHoliday ? holidayMotifs : MOTIFS;
    const motif = pickMotif({ motifs: motifPool, tagCounts, usedMotifIds, style });
    if (!motif) continue;

    const scene = pickOne(motif.scenes);
    const composition = pickOne(COMPOSITIONS);
    const palette = pickOne(PALETTES);
    const atmosphere = pickOne(ATMOSPHERES);
    const cameraMove = pickOne(CAMERA_MOVES);
    const motionBeat = pickOne(MOTION_BEATS);
    const title = buildTitle(style, scene);
    if (localUsedTitles.has(title.toLowerCase())) continue;

    const idea = {
      title,
      imageStyle: style.id,
      styleId: style.id,
      motifId: motif.id,
      tags: mergeTags(style, motif),
      brief: buildBrief({
        style, motif, scene, composition, palette, atmosphere, cameraMove, motionBeat,
      }),
      styleReminder: style.render,
      cameraMove,
      motionBeat,
      params: {
        aspectRatio: ASPECT_RATIO,
        durationSeconds: DURATION_SECONDS,
        temperature: pickOne(TEMPERATURES),
      },
    };

    ideas.push(idea);
    localUsedTitles.add(title.toLowerCase());
    usedStyleIds.add(style.id);
    usedMotifIds.add(motif.id);
    for (const t of idea.tags) tagCounts[t] = (tagCounts[t] || 0) + 1;
  }

  return ideas;
}
