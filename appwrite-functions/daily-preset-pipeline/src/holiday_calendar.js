const MS_PER_DAY = 86_400_000;

// Праздники выступают дополнительным мотивом: в окне перед датой они попадают в выдачу.
const HOLIDAY_RULES = [
  {
    id: 'valentine', month: 2, day: 14, preStartDays: 21,
    title: 'День всех влюблённых',
    tags: ['праздник'],
    scenes: [
      'сердце из красных лепестков на тёмном фоне',
      'две чашки какао с зефиром и гирлянда-сердечки',
      'бумажные валентинки и сургучная печать на письме',
      'воздушные шары-сердца, поднимающиеся в закатное небо',
    ],
  },
  {
    id: 'defender', month: 2, day: 23, preStartDays: 21,
    title: '23 февраля',
    tags: ['праздник'],
    scenes: [
      'георгиевская лента и звезда на тёмном сукне',
      'винтажный компас, карта и бинокль на деревянном столе',
      'силуэты военных самолётов в рассветном небе',
    ],
  },
  {
    id: 'womens_day', month: 3, day: 8, preStartDays: 28,
    title: '8 Марта',
    tags: ['праздник', 'цветы'],
    scenes: [
      'букет тюльпанов в стеклянной вазе у окна',
      'ветки мимозы на льняной скатерти',
      'весенние цветы в подарочной упаковке с лентой',
      'цифра 8 из живых цветов на пастельном фоне',
    ],
  },
  {
    id: 'easter', movable: 'orthodox_easter', preStartDays: 14, postEndDays: 1,
    title: 'Пасха',
    tags: ['праздник', 'еда'],
    scenes: [
      'куличи и крашеные яйца в плетёной корзине',
      'вербные ветви в керамическом кувшине',
      'расписные яйца на белом льне в утреннем свете',
    ],
  },
  {
    id: 'spring_labor', month: 5, day: 1, preStartDays: 21,
    title: 'Майские',
    tags: ['праздник', 'природа'],
    scenes: [
      'пикник на цветущем лугу: плед, корзина, велосипед',
      'цветущая яблоня в лепестковом дождь-ветре',
      'первая майская зелень в парке с фонтаном',
    ],
  },
  {
    id: 'victory_day', month: 5, day: 9, preStartDays: 30,
    title: '9 Мая',
    tags: ['праздник'],
    scenes: [
      'красные гвоздики и георгиевская лента на камне мемориала',
      'праздничный салют над площадью',
      'вечный огонь в вечернем свете',
    ],
  },
  {
    id: 'russia_day', month: 6, day: 12, preStartDays: 21,
    title: 'День России',
    tags: ['праздник', 'город'],
    scenes: [
      'летняя городская набережная с флагами',
      'фейерверк над рекой в белую ночь',
    ],
  },
  {
    id: 'knowledge_day', month: 9, day: 1, preStartDays: 21,
    title: '1 сентября',
    tags: ['праздник'],
    scenes: [
      'школьный портфель, глобус и букет астр на парте',
      'стопка учебников и яблоко в утреннем свете класса',
      'школьный двор с кленовыми листьями и колокольчиком',
    ],
  },
  {
    id: 'teacher_day', month: 10, day: 5, preStartDays: 14,
    title: 'День учителя',
    tags: ['праздник'],
    scenes: [
      'букет хризантем на учительском столе рядом с журналом',
      'меловая доска с осенним рисунком и мел в держателе',
    ],
  },
  {
    id: 'mothers_day', movable: 'last_sunday_november', preStartDays: 21,
    title: 'День матери',
    tags: ['праздник', 'цветы'],
    scenes: [
      'букет пионов и открытка на светлом столе',
      'чайный сервиз, свеча и вязаный плед в тёплом свете',
    ],
  },
  {
    id: 'new_year', month: 12, day: 31, preStartDays: 35, postEndDays: 7,
    title: 'Новый год',
    tags: ['праздник', 'зима'],
    scenes: [
      'ёлочные шары и гирлянда с боке-огнями',
      'подарки в крафтовой бумаге под ёлкой',
      'заснеженный домик с тёплым светом в окнах',
      'мандарины, корица и еловые ветви на столе',
      'бенгальские огни и шампанское в полумраке',
    ],
  },
];

function makeUtcDate(year, month, day) {
  return new Date(Date.UTC(year, month - 1, day));
}

function startOfUtcDay(d) {
  return makeUtcDate(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate());
}

function addDaysUtc(d, days) {
  return new Date(d.getTime() + days * MS_PER_DAY);
}

function daysBetweenUtc(a, b) {
  return Math.floor((startOfUtcDay(b).getTime() - startOfUtcDay(a).getTime()) / MS_PER_DAY);
}

function getOrthodoxEasterDate(year) {
  const a = year % 4;
  const b = year % 7;
  const c = year % 19;
  const d = (19 * c + 15) % 30;
  const e = (2 * a + 4 * b - d + 34) % 7;
  const month = Math.floor((d + e + 114) / 31);
  const day = ((d + e + 114) % 31) + 1;
  return addDaysUtc(makeUtcDate(year, month, day), year >= 2100 ? 14 : 13);
}

function getLastSundayOfNovember(year) {
  const nov30 = makeUtcDate(year, 11, 30);
  return addDaysUtc(nov30, -nov30.getUTCDay());
}

function getHolidayDate(rule, year) {
  if (rule.movable === 'orthodox_easter') return getOrthodoxEasterDate(year);
  if (rule.movable === 'last_sunday_november') return getLastSundayOfNovember(year);
  return makeUtcDate(year, rule.month, rule.day);
}

function getTiming(rule, now) {
  const nowDay = startOfUtcDay(now);
  for (const year of [now.getUTCFullYear(), now.getUTCFullYear() + 1]) {
    const target = getHolidayDate(rule, year);
    const windowStart = addDaysUtc(target, -(rule.preStartDays || 0));
    const windowEnd = addDaysUtc(target, rule.postEndDays || 0);
    if (nowDay > windowEnd) continue;
    return {
      daysUntil: daysBetweenUtc(nowDay, target),
      withinWindow: nowDay >= windowStart && nowDay <= windowEnd,
    };
  }
  return null;
}

/// Праздники в активном окне, отсортированные по близости к дате.
export function getActiveHolidayMotifs(now) {
  const active = [];
  for (const rule of HOLIDAY_RULES) {
    const timing = getTiming(rule, now);
    if (!timing?.withinWindow) continue;
    const window = Math.max(1, rule.preStartDays || 1);
    const closeness = Math.min(1, Math.max(0, 1 - Math.max(0, timing.daysUntil) / window));
    active.push({
      id: `holiday_${rule.id}`,
      title: rule.title,
      tags: rule.tags,
      scenes: rule.scenes,
      isHoliday: true,
      closeness,
      daysUntil: timing.daysUntil,
    });
  }
  return active.sort((a, b) => b.closeness - a.closeness);
}
