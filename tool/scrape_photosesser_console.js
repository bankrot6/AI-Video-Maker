/**
 * Скрипт для консоли браузера на https://photosesser.ru/
 * Собирает промпты, названия и ссылки на превью.
 *
 * Как использовать:
 * 1. Открой https://photosesser.ru/ , зайди в Категории или туда, где видны карточки пресетов.
 * 2. F12 → вкладка Console.
 * 3. Вставь этот скрипт целиком и нажми Enter.
 * 4. Вызови один из вариантов:
 *    collectCurrent()  — взять только текущий открытый пресет (сначала открой карточку).
 *    collectAll()      — попытаться автоматически кликнуть по всем карточкам и собрать данные (может потребовать подстройки селекторов).
 * 5. Результат: copyOutput() скопирует JSON в буфер; или смотри window.__photosesserPresets__.
 * 6. Сохрани в файл presets.json и запусти: dart run tool/parse_photosesser_prompts.dart --file presets.json --out presets_normalized.json
 */

(function () {
  window.__photosesserPresets__ = window.__photosesserPresets__ || [];

  function getText(el) {
    if (!el) return '';
    return (el.textContent || '').trim().replace(/\s+/g, ' ');
  }

  function findPromptBlock(root) {
    const divs = root.querySelectorAll('div[class*="rounded-lg"][class*="max-h-40"], div[class*="overflow-y-auto"][class*="text-sm"]');
    for (const d of divs) {
      const t = getText(d);
      if (t.length > 80 && !t.includes('</')) return t;
    }
    return '';
  }

  function findTitle(root) {
    const h = root.querySelector('h1, h2, h3, [class*="title"], [class*="font-semibold"]');
    if (h) return getText(h);
    const first = root.querySelector('p, span');
    return first ? getText(first) : '';
  }

  function findPreviewImage(root) {
    const img = root.querySelector('img[src*="http"]');
    return img ? (img.src || img.getAttribute('src') || '') : '';
  }

  function collectCurrent() {
    const prompt = findPromptBlock(document.body);
    if (!prompt) {
      console.warn('Промпт не найден. Открой карточку пресета и вызови collectCurrent() снова.');
      return null;
    }
    const title = findTitle(document.body);
    const previewImageUrl = findPreviewImage(document.body);
    const item = {
      id: 'preset_' + (window.__photosesserPresets__.length + 1),
      title: title || null,
      prompt: prompt,
      previewImageUrl: previewImageUrl || '',
    };
    window.__photosesserPresets__.push(item);
    console.log('Добавлено:', item.title || item.prompt.slice(0, 50) + '...');
    return item;
  }

  function collectAll() {
    const cards = document.querySelectorAll('a[href], [role="button"], div[class*="cursor-pointer"]');
    const clickables = [];
    cards.forEach(function (el) {
      if (el.querySelector('img') && el.getBoundingClientRect().width > 50) clickables.push(el);
    });
    if (clickables.length === 0) {
      console.warn('Карточки не найдены. Открой категорию с пресетами и вызови collectAll() снова.');
      return window.__photosesserPresets__;
    }
    let i = 0;
    function next() {
      if (i >= clickables.length) {
        console.log('Собрано пресетов:', window.__photosesserPresets__.length);
        return window.__photosesserPresets__;
      }
      clickables[i].click();
      setTimeout(function () {
        collectCurrent();
        const close = document.querySelector('[aria-label="Close"], .modal button, [class*="close"]');
        if (close) close.click();
        else document.body.click();
        i += 1;
        setTimeout(next, 800);
      }, 1200);
    }
    next();
    return window.__photosesserPresets__;
  }

  function copyOutput() {
    const json = JSON.stringify(window.__photosesserPresets__, null, 2);
    if (typeof navigator !== 'undefined' && navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(json).then(function () {
        console.log('Скопировано в буфер:', window.__photosesserPresets__.length, 'пресетов.');
      });
    } else {
      console.log(json);
    }
    return json;
  }

  function clearOutput() {
    window.__photosesserPresets__ = [];
    console.log('Массив пресетов очищен.');
  }

  window.collectCurrent = collectCurrent;
  window.collectAll = collectAll;
  window.copyOutput = copyOutput;
  window.clearOutput = clearOutput;
  console.log('Фотосессер: collectCurrent(), collectAll(), copyOutput(), clearOutput(). Результат: window.__photosesserPresets__');
})();
