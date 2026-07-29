#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Preset Pipeline — парсинг Telegram каналов → DeepSeek (унификация) → Nano Banana → Firebase
Каналы: @photosesser, @clickpickstyle

Флоу:
  1. Парсинг t.me/s/channel → сырой промпт (любой формат)
  2. DeepSeek приводит к единой 6-секционной структуре на РУССКОМ
  3. Nano Banana генерирует превью по структурированному промпту
  4. Firebase: title (рус), prompt (рус, 6 секций), tags (рус)

Запуск:
    python3 tool/preset_pipeline.py              # все новые посты
    python3 tool/preset_pipeline.py --limit 5    # только 5 постов
    python3 tool/preset_pipeline.py --dry-run    # без записи в БД
    python3 tool/preset_pipeline.py --channel photosesser --limit 10
"""

import argparse
import json
import random
import re
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import List, Optional

try:
    import requests
except ImportError:
    print("❌ Установите: pip3 install requests"); sys.exit(1)

try:
    import jwt
except ImportError:
    print("❌ Установите: pip3 install PyJWT cryptography"); sys.exit(1)


# ─── Конфигурация ────────────────────────────────────────────────────────────

# Системный промпт DeepSeek: конвертирует ЛЮБОЙ сырой промпт в нашу структуру
DEEPSEEK_SYSTEM_PROMPT = '''Ты эксперт по фотосессиям и промпт-инженер приложения для AI-фотографии.

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
- ТЕЛО: всегда описывай телосложение как оно есть — без идеализации, без "стройная" если в оригинале не указано'''

CHANNELS = ['clickpickstyle', 'photosesser']

PROCESSED_FILE = Path('tool/processed_posts.json')
SA_PATHS = [Path('firebase-service-account.json'), Path('tool/firebase-service-account.json')]
ENV_FILE = Path('.env')

# Маппинг хештегов → русские теги приложения
# Маппинг хештегов Telegram → канонический русский тег
TAG_MAP = {
    'женские': 'женщины', 'женщин': 'женщины', 'woman': 'женщины', 'women': 'женщины',
    'мужские': 'мужчины', 'мужчин': 'мужчины', 'man': 'мужчины', 'men': 'мужчины',
    'детские': 'дети', 'дети': 'дети', 'ребёнок': 'дети', 'ребенок': 'дети',
    'children': 'дети', 'child': 'дети', 'kids': 'дети',
    'семейные': 'семья', 'семья': 'семья', 'family': 'семья',
    'природа': 'природа', 'улица': 'природа', 'сад': 'природа', 'nature': 'природа',
    'студийное_фото': 'студия', 'студия': 'студия', 'studio': 'студия',
    'город': 'город', 'улицы': 'город', 'city': 'город',
    'бизнес': 'бизнес', 'деловой': 'бизнес', 'business': 'бизнес',
    'романтика': 'романтика', 'love': 'романтика', 'romance': 'романтика',
    'путешествия': 'путешествия', 'travel': 'путешествия',
    'животные': 'животные', 'питомцы': 'животные', 'animals': 'животные',
    'фэнтези': 'фэнтези', 'фантастика': 'фэнтези', 'сказка': 'фэнтези', 'fantasy': 'фэнтези',
    'ретро': 'ретро', 'винтаж': 'ретро', 'retro': 'ретро', 'vintage': 'ретро',
    'минимализм': 'минимализм', 'minimalism': 'минимализм',
    'роскошь': 'роскошь', 'luxury': 'роскошь',
    'спорт': 'спорт', 'sport': 'спорт',
    'еда': 'еда', 'food': 'еда',
    'праздник': 'праздник', 'новый_год': 'праздник', 'holiday': 'праздник',
    'девочка': 'дети', 'мальчик': 'дети',
    'лето': 'лето', 'summer': 'лето',
    'зима': 'зима', 'winter': 'зима',
    'автомобили': 'автомобили', 'cars': 'автомобили', 'car': 'автомобили',
    'мода': 'мода', 'fashion': 'мода', 'editorial': 'мода',
}

# Ключевые слова в тексте промпта → теги (из 6-секционного формата)
# ВАЖНО: не включать слова из технических параметров ("профессиональная", "золотой час" и т.д.)
KEYWORD_TAGS = {
    # Пол — женщины
    'женщин': 'женщины', 'девушк': 'женщины', 'невест': 'женщины',
    'платье': 'женщины', 'юбк': 'женщины', 'блузк': 'женщины',
    'корсет': 'женщины', 'каблук': 'женщины', 'шпильк': 'женщины',
    'серьг': 'женщины', 'ожерель': 'женщины',
    # Пол — мужчины
    'мужчин': 'мужчины', 'мужской': 'мужчины', 'парень': 'мужчины',
    'борода': 'мужчины', 'джентльмен': 'мужчины',
    # Дети
    'ребёнок': 'дети', 'ребенок': 'дети', 'малыш': 'дети',
    'девочк': 'дети', 'мальчик': 'дети', 'подростк': 'дети',
    # Семья
    ' семь': 'семья', 'мама': 'семья', 'папа': 'семья', 'родител': 'семья',
    # Природа
    'лес': 'природа', 'парк': 'природа', 'сад': 'природа', 'природ': 'природа',
    'поле': 'природа', 'луг': 'природа', 'река': 'природа', 'озеро': 'природа',
    'хвойн': 'природа', 'цветущ': 'природа',
    # Студия
    'студи': 'студия', 'белый фон': 'студия', 'тёмный фон': 'студия',
    'нейтральный фон': 'студия', 'бесшовный фон': 'студия',
    # Город
    'город': 'город', 'улиц': 'город', 'набережн': 'город',
    'переулк': 'город', 'площадь': 'город', 'кафе': 'город',
    'ресторан': 'город', 'архитектур': 'город',
    # Фэнтези
    'сказк': 'фэнтези', 'сказочн': 'фэнтези', 'мистик': 'фэнтези',
    'ангел': 'фэнтези', 'магич': 'фэнтези', 'фэнтези': 'фэнтези',
    'волшебн': 'фэнтези',
    # Ретро
    'ретро': 'ретро', 'винтаж': 'ретро', 'полароид': 'ретро',
    'vintage': 'ретро',
    # Роскошь (только явные — не "золотой час")
    'роскошн': 'роскошь', 'vip': 'роскошь', 'эксклюзивн': 'роскошь',
    'шёлк': 'роскошь', 'бархат': 'роскошь', 'брилли': 'роскошь',
    'яхт': 'роскошь', 'пентхаус': 'роскошь',
    # Бизнес (только явные — не "профессиональная фотография")
    'бизнес': 'бизнес', 'офис': 'бизнес', 'корпоратив': 'бизнес',
    'деловая встреч': 'бизнес', 'конференц': 'бизнес',
    # Путешествия
    'пляж': 'путешествия', 'море': 'путешествия', 'океан': 'путешествия',
    'курорт': 'путешествия', 'тропик': 'путешествия',
    # Животные
    'волк': 'животные', 'лошадь': 'животные', 'кошк': 'животные',
    'пантер': 'животные', 'питомц': 'животные', 'собак': 'животные',
    # Праздник
    'праздник': 'праздник', 'карнавал': 'праздник', 'фиеста': 'праздник',
    'фестиваль': 'праздник', 'маскарад': 'праздник',
    # Минимализм
    'минимализм': 'минимализм', 'minimal': 'минимализм',
    # Романтика
    'романтик': 'романтика', 'влюблённ': 'романтика',
    # Еда
    'еда': 'еда', 'кухн': 'еда', 'овощ': 'еда', 'фрукт': 'еда',
}


# ─── Утилиты ─────────────────────────────────────────────────────────────────

def load_env() -> dict:
    env = {}
    if not ENV_FILE.exists():
        return env
    for line in ENV_FILE.read_text().split('\n'):
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        i = s.find('=')
        if i <= 0:
            continue
        key = s[:i].strip()
        val = s[i+1:].strip().strip('"').strip("'")
        env[key] = val
    return env


def load_processed() -> dict:
    if not PROCESSED_FILE.exists():
        return {ch: [] for ch in CHANNELS}
    try:
        data = json.loads(PROCESSED_FILE.read_text())
        for ch in CHANNELS:
            if ch not in data:
                data[ch] = []
        return data
    except Exception:
        return {ch: [] for ch in CHANNELS}


def save_processed(processed: dict):
    PROCESSED_FILE.parent.mkdir(exist_ok=True)
    PROCESSED_FILE.write_text(json.dumps(processed, indent=2, ensure_ascii=False))


def load_service_account() -> dict:
    for p in SA_PATHS:
        if p.exists():
            return json.loads(p.read_text())
    print("❌ firebase-service-account.json не найден")
    print("   Скачайте из Firebase Console → Project Settings → Service accounts")
    sys.exit(1)


# ─── Парсинг Telegram ─────────────────────────────────────────────────────────

_TG_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                  'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0',
}


def _parse_tg_html(channel: str, html: str) -> List[dict]:
    """Извлекает посты из HTML одной страницы t.me/s/channel."""
    posts = []
    blocks = re.findall(
        r'<div[^>]+data-post="' + re.escape(channel) + r'/(\d+)"[^>]*>(.*?)'
        r'(?=<div[^>]+data-post="|$)',
        html, re.DOTALL
    )
    for post_id, block in blocks:
        text_match = re.search(
            r'<div[^>]*class="[^"]*tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>',
            block, re.DOTALL
        )
        raw_text = ''
        if text_match:
            raw = text_match.group(1)
            raw = re.sub(r'<br\s*/?>', '\n', raw)
            raw = re.sub(r'<[^>]+>', '', raw)
            raw_text = (raw.replace('&nbsp;', ' ').replace('&amp;', '&')
                        .replace('&lt;', '<').replace('&gt;', '>').strip())
        if not raw_text:
            continue

        code_match = re.search(r'<code[^>]*>(.*?)</code>', block, re.DOTALL)
        prompt = ''
        if code_match:
            p = code_match.group(1)
            p = re.sub(r'<[^>]+>', '', p)
            prompt = (p.replace('&nbsp;', ' ').replace('&amp;', '&')
                      .replace('&lt;', '<').replace('&gt;', '>').strip())
        if not prompt:
            continue

        first_line = raw_text.split('\n')[0].strip()
        title = re.sub(r'^[\U0001F300-\U0001FFFF\u2600-\u27FF\s]+', '', first_line).strip()
        if not title:
            title = first_line

        hashtags = re.findall(r'#([\w\u0400-\u04FF]+)', block)

        views_match = re.search(
            r'<span[^>]*class="[^"]*tgme_widget_message_views[^"]*"[^>]*>([^<]+)<', block
        )
        views = 0
        if views_match:
            v = views_match.group(1).strip().replace('K', '00').replace('.', '')
            try:
                views = int(re.sub(r'[^\d]', '', v)) if v else 0
            except Exception:
                views = 0

        reactions = 0
        reaction_matches = re.findall(
            r'<span[^>]*class="[^"]*tgme_widget_message_reactions[^"]*"[^>]*>(.*?)</span>',
            block, re.DOTALL
        )
        for rm in reaction_matches:
            reactions += sum(int(n) for n in re.findall(r'(\d+)', rm))

        popularity = reactions * 100 + views
        tags = _extract_tags(hashtags, raw_text + ' ' + title)

        posts.append({
            'id': post_id,
            'channel': channel,
            'title': title,
            'prompt': prompt,
            'hashtags': hashtags,
            'tags': tags,
            'reactions': reactions,
            'views': views,
            'popularity': popularity,
            'url': f'https://t.me/{channel}/{post_id}',
        })
    return posts


def parse_channel(channel: str, max_posts: int = 150, max_pages: int = 8) -> List[dict]:
    """
    Парсит публичный канал через t.me/s/channel с пагинацией назад.
    Поддерживает ?before=POST_ID для загрузки более старых постов.
    """
    posts_by_id: dict = {}
    before_id: Optional[str] = None

    for page_num in range(max_pages):
        url = f'https://t.me/s/{channel}'
        if before_id:
            url += f'?before={before_id}'
        try:
            resp = requests.get(url, timeout=30, headers=_TG_HEADERS)
            if resp.status_code != 200:
                print(f"  ⚠️  HTTP {resp.status_code} для @{channel} (стр. {page_num+1})")
                break
        except Exception as e:
            print(f"  ❌ @{channel} стр.{page_num+1}: {e}")
            break

        page_posts = _parse_tg_html(channel, resp.text)
        if not page_posts:
            break

        added = 0
        for p in page_posts:
            if p['id'] not in posts_by_id:
                posts_by_id[p['id']] = p
                added += 1

        if added == 0:
            break  # дубликаты — дальше нет нового

        if len(posts_by_id) >= max_posts:
            break

        # Следующая страница — берём ID самого старого поста
        min_id = min(int(p['id']) for p in page_posts)
        before_id = str(min_id)
        time.sleep(0.8)  # вежливая пауза

    return list(posts_by_id.values())


GENDER_TAGS = {'женщины', 'мужчины', 'дети', 'семья'}


def _extract_tags(hashtags: List[str], text: str) -> List[str]:
    """Собирает теги из хештегов и ключевых слов структурированного промпта."""
    found = set()

    for tag in hashtags:
        normalized = tag.lower().strip()
        if normalized in TAG_MAP:
            val = TAG_MAP[normalized]
            if val:
                found.add(val)
        else:
            for key, val in TAG_MAP.items():
                if val and (key in normalized or normalized in key):
                    found.add(val)
                    break

    text_lower = text.lower()
    for keyword, tag in KEYWORD_TAGS.items():
        if keyword in text_lower:
            found.add(tag)

    # Если пол не определён — по умолчанию "женщины" (90%+ пресетов для женщин)
    if not (found & GENDER_TAGS):
        found.add('женщины')

    return sorted(found)[:6]  # максимум 6 тегов


# ─── Firebase ─────────────────────────────────────────────────────────────────

_firebase_token_cache = {'token': None, 'expires': 0}


def get_firebase_token(sa: dict, force_refresh: bool = False) -> str:
    now = time.time()
    if not force_refresh and _firebase_token_cache['token'] and now < _firebase_token_cache['expires']:
        return _firebase_token_cache['token']

    payload = {
        'iss': sa['client_email'],
        'sub': sa['client_email'],
        'aud': sa['token_uri'],
        'iat': int(now),
        'exp': int(now) + 3600,
        'scope': 'https://www.googleapis.com/auth/datastore',
    }
    signed = jwt.encode(payload, sa['private_key'], algorithm='RS256')
    resp = requests.post(sa['token_uri'], data={
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': signed,
    }, timeout=30)
    resp.raise_for_status()
    token = resp.json()['access_token']
    _firebase_token_cache['token'] = token
    _firebase_token_cache['expires'] = now + 3500  # refresh 100s before expiry
    return token


def upload_to_firestore(token: str, project_id: str, preset: dict) -> str:
    ts = int(time.time() * 1000)
    slug = re.sub(r'[^\w]', '_', preset['title'].lower())[:40]
    doc_id = f"preset_{ts}_{slug}"

    url = (
        f"https://firestore.googleapis.com/v1/projects/{project_id}"
        f"/databases/(default)/documents/presets?documentId={doc_id}"
    )

    tags = preset.get('tags', [])
    initial_likes = random.randint(5, 20)
    liked_by = [f"seed_{uuid.uuid4().hex}" for _ in range(initial_likes)]
    fields = {
        'title':          {'stringValue': preset.get('title', '')},
        'prompt':         {'stringValue': preset.get('prompt', '')},
        'previewImageUrl':{'stringValue': preset.get('previewImageUrl', '')},
        'createdAt':      {'stringValue': preset.get('createdAt', datetime.now().isoformat())},
        'sourceChannel':  {'stringValue': preset.get('sourceChannel', '')},
        'sourcePostId':   {'stringValue': str(preset.get('sourcePostId', ''))},
        'likesCount':     {'integerValue': str(initial_likes)},
        'likedBy': {
            'arrayValue': {
                'values': [{'stringValue': x} for x in liked_by],
            }
        },
        'tags': {
            'arrayValue': {
                'values': [{'stringValue': t} for t in tags]
            }
        },
    }

    resp = requests.post(
        url,
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        json={'fields': fields},
        timeout=30,
    )
    if resp.status_code in (200, 201):
        return doc_id
    # Token expired — refresh and retry
    raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:300]}")


# ─── Умная сортировка: заполняем дефицитные категории ────────────────────────

def collect_telegram_source_keys(token: str, project_id: str) -> set:
    """
    Пары channel|postId из Firestore presets — та же дедупликация, что в
    functions/preset_pipeline_runner.js (loadExistingTelegramSourceKeys).
    """
    keys: set = set()
    base = (
        f'https://firestore.googleapis.com/v1/projects/{project_id}'
        f'/databases/(default)/documents/presets'
    )
    page_token: Optional[str] = None
    while True:
        params: dict = {'pageSize': 300}
        if page_token:
            params['pageToken'] = page_token
        resp = requests.get(
            base,
            headers={'Authorization': f'Bearer {token}'},
            params=params,
            timeout=60,
        )
        resp.raise_for_status()
        data = resp.json()
        for doc in data.get('documents', []):
            fields = doc.get('fields', {})
            ch = fields.get('sourceChannel', {}).get('stringValue', '').strip()
            pid = fields.get('sourcePostId', {}).get('stringValue', '').strip()
            if ch and pid:
                keys.add(f'{ch}|{pid}')
        page_token = data.get('nextPageToken')
        if not page_token:
            break
        time.sleep(0.15)
    return keys


def get_firebase_tag_counts(token: str, project_id: str) -> dict:
    """
    Возвращает словарь {тег: количество_пресетов} из Firebase.
    Используется для балансировки категорий.
    """
    url = (
        f'https://firestore.googleapis.com/v1/projects/{project_id}'
        f'/databases/(default)/documents/presets?pageSize=300'
    )
    try:
        resp = requests.get(url, headers={'Authorization': f'Bearer {token}'}, timeout=30)
        resp.raise_for_status()
        docs = resp.json().get('documents', [])
    except Exception as e:
        print(f"  ⚠️  Не удалось получить статистику тегов: {e}")
        return {}

    counts: dict = {}
    for doc in docs:
        fields = doc.get('fields', {})
        tags_field = fields.get('tags', {})
        for tv in tags_field.get('arrayValue', {}).get('values', []):
            tag = tv.get('stringValue', '')
            if tag and tag not in ('custom',):
                counts[tag] = counts.get(tag, 0) + 1
    return counts


def score_post_for_balance(post: dict, tag_counts: dict, session_counts: dict) -> float:
    """
    Рейтинг поста: чем меньше тегов поста представлено в каталоге —
    тем выше приоритет. Внутри одного уровня дефицита сортируем по популярности.
    """
    tags = post.get('tags', [])
    if not tags:
        deficit = 0.0
    else:
        # Суммарный дефицит: сумма (1 / (count + 1)) по каждому тегу поста
        deficit = sum(
            1.0 / (tag_counts.get(t, 0) + session_counts.get(t, 0) + 1)
            for t in tags
        )
    # Нормируем популярность в диапазон [0, 1] условно (макс ~500K)
    popularity_norm = post.get('popularity', 0) / 500_000
    # Итоговый балл: дефицит доминирует, популярность — тай-брейкер
    return deficit * 1000 + popularity_norm


def sort_posts_smart(posts: List[dict], tag_counts: dict) -> List[dict]:
    """
    Сортирует посты так, чтобы сначала шли посты из самых дефицитных категорий,
    среди равных — самые популярные. Обновляет счётчики по мере выбора постов.
    """
    session_counts: dict = {}
    result = []
    remaining = list(posts)

    while remaining:
        # Пересчитываем рейтинг с учётом уже выбранных в этой сессии
        best = max(remaining, key=lambda p: score_post_for_balance(p, tag_counts, session_counts))
        result.append(best)
        remaining.remove(best)
        # Учитываем теги выбранного поста в счётчике сессии
        for t in best.get('tags', []):
            session_counts[t] = session_counts.get(t, 0) + 1

    return result


# ─── DeepSeek: конвертация промпта ──────────────────────────────────────────

def convert_prompt_to_structure(
    raw_prompt: str, title: str, deepseek_key: str, tags: Optional[List[str]] = None
) -> Optional[str]:
    """
    Конвертирует сырой Telegram-промпт в нашу единую 6-секционную структуру
    на русском языке через DeepSeek. Передаёт гендерную подсказку.
    """
    tags = tags or []
    if 'женщины' in tags:
        gender_hint = 'ВАЖНО: персонаж — ЖЕНЩИНА. В разделе ПЕРСОНАЖ обязательно начни с "Молодая женщина".'
    elif 'мужчины' in tags:
        gender_hint = 'ВАЖНО: персонаж — МУЖЧИНА. В разделе ПЕРСОНАЖ обязательно начни с "Молодой мужчина".'
    elif 'дети' in tags:
        gender_hint = 'ВАЖНО: персонаж — РЕБЁНОК. В разделе ПЕРСОНАЖ обязательно начни с "Ребёнок".'
    elif 'семья' in tags:
        gender_hint = 'ВАЖНО: персонажи — СЕМЬЯ (мужчина, женщина, возможно дети). Опиши всех.'
    else:
        gender_hint = 'ВАЖНО: персонаж — ЖЕНЩИНА (по умолчанию для fashion-фотосессий). Начни с "Молодая женщина".'

    user_msg = (
        f'Название фотосессии: {title}\n\n'
        f'{gender_hint}\n\n'
        f'Исходный промпт из Telegram:\n{raw_prompt}\n\n'
        f'Преобразуй этот промпт в нашу структуру из 6 разделов.'
    )
    try:
        resp = requests.post(
            'https://api.deepseek.com/v1/chat/completions',
            headers={
                'Authorization': f'Bearer {deepseek_key}',
                'Content-Type': 'application/json',
            },
            json={
                'model': 'deepseek-chat',
                'messages': [
                    {'role': 'system', 'content': DEEPSEEK_SYSTEM_PROMPT},
                    {'role': 'user', 'content': user_msg},
                ],
                'max_tokens': 2200,
                'temperature': 0.5,
            },
            timeout=60,
        )
        resp.raise_for_status()
        content = resp.json()['choices'][0]['message']['content'].strip()
        # Убираем лишние обёртки если есть
        content = re.sub(r'^```[^\n]*\n?', '', content)
        content = re.sub(r'\n?```$', '', content)
        return content.strip() if content else None
    except Exception as e:
        print(f"    ❌ DeepSeek ошибка: {e}")
        return None


# ─── Генерация изображения ─────────────────────────────────────────────────────

def generate_image(prompt: str, piapi_key: str, reference_url: Optional[str] = None) -> Optional[str]:
    """
    Генерирует изображение через PiAPI Nano Banana.
    Если передан reference_url — используем img2img для близости к оригиналу.
    """
    task_url = 'https://api.piapi.ai/api/v1/task'

    if reference_url:
        # img2img: сохраняем стиль/композицию референса
        final_prompt = (
            "Match the overall composition, lighting style, and visual aesthetic "
            "of the reference image exactly. Keep the scene structure and mood.\n\n"
            + prompt
        )
        payload = {
            'model': 'gemini',
            'task_type': 'nano-banana-pro',
            'input': {
                'prompt': final_prompt,
                'image_urls': [reference_url],
                'output_format': 'jpeg',
                'aspect_ratio': '3:4',
                'resolution': '2K',
                'safety_level': 'high',
            },
        }
    else:
        payload = {
            'model': 'gemini',
            'task_type': 'nano-banana-pro',
            'input': {
                'prompt': prompt,
                'output_format': 'jpeg',
                'aspect_ratio': '3:4',
                'resolution': '2K',
                'safety_level': 'high',
            },
        }

    try:
        resp = requests.post(
            task_url,
            headers={'X-API-Key': piapi_key, 'Content-Type': 'application/json'},
            json=payload,
            timeout=30,
        )
        resp.raise_for_status()
        task_id = resp.json().get('data', {}).get('task_id')
        if not task_id:
            print(f"    ⚠️  Нет task_id в ответе: {resp.text[:200]}")
            return None

        print(f"    📋 Task ID: {task_id}")
        print(f"    ⏳ Ожидание...")

        deadline = time.time() + 360
        attempt = 0
        while time.time() < deadline:
            time.sleep(6)
            attempt += 1
            poll = requests.get(
                f'{task_url}/{task_id}',
                headers={'X-API-Key': piapi_key},
                timeout=30,
            )
            if poll.status_code != 200:
                continue
            pdata = poll.json().get('data', {})
            status = pdata.get('status', '').lower()
            print(f"    📊 Попытка {attempt}: {status}")
            if status == 'completed':
                out = pdata.get('output', {})
                return out.get('image_url') or (out.get('image_urls') or [None])[0]
            if status == 'failed':
                err = pdata.get('error', {})
                print(f"    ❌ Задача провалена: {err}")
                return None
        print("    ⏱️  Таймаут")
        return None
    except Exception as e:
        print(f"    ❌ PiAPI ошибка: {e}")
        return None


def upload_reference_to_piapi(image_url: str, piapi_key: str) -> Optional[str]:
    """Загружает изображение во временное хранилище PiAPI (для img2img)."""
    try:
        img_resp = requests.get(image_url, timeout=20)
        if img_resp.status_code != 200:
            return None
        upload_resp = requests.post(
            'https://upload.theapi.app/api/ephemeral_resource',
            headers={'X-API-Key': piapi_key},
            files={'file': ('ref.jpg', img_resp.content, 'image/jpeg')},
            timeout=30,
        )
        if upload_resp.status_code in (200, 201):
            data = upload_resp.json()
            return data.get('url') or data.get('data', {}).get('url')
        return None
    except Exception:
        return None


# ─── Основной пайплайн ────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Preset Pipeline')
    parser.add_argument('--limit', type=int, default=0,
                        help='Максимум постов для обработки (0 = все)')
    parser.add_argument('--channel', type=str, default='',
                        help='Конкретный канал (photosesser / clickpickstyle)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Без реальных запросов к API и БД')
    args = parser.parse_args()

    print("═══════════════════════════════════════════════════")
    print("  PRESET PIPELINE  Telegram → Nano Banana → Firebase")
    print("═══════════════════════════════════════════════════\n")

    if args.dry_run:
        print("🔍 DRY-RUN режим — без записи в БД\n")

    env = load_env()
    piapi_key = env.get('PIAPI_API_KEY', '').strip()
    deepseek_key = env.get('DEEPSEEK_API_KEY', '').strip()

    if not args.dry_run:
        if not piapi_key:
            print("❌ PIAPI_API_KEY не найден в .env"); sys.exit(1)
        if not deepseek_key:
            print("❌ DEEPSEEK_API_KEY не найден в .env"); sys.exit(1)

    sa = load_service_account() if not args.dry_run else {}
    project_id = sa.get('project_id', 'photosession-ai-cbfc3')

    processed = load_processed()

    channels = [args.channel] if args.channel else CHANNELS

    firebase_token = None
    if not args.dry_run:
        print("🔐 Получение Firebase токена...")
        try:
            firebase_token = get_firebase_token(sa)
            print("✅ Токен получен\n")
        except Exception as e:
            print(f"❌ Ошибка токена Firebase: {e}"); sys.exit(1)

    # ── Ключи уже импортированных постов из Firestore (как у Cloud Function) ──
    firestore_tg_keys: set = set()
    if not args.dry_run and firebase_token:
        print("🔍 Дедупликация: пары channel|postId из Firestore presets...")
        try:
            firestore_tg_keys = collect_telegram_source_keys(firebase_token, project_id)
            print(f"   Уже в каталоге по Telegram-источнику: {len(firestore_tg_keys)}")
        except Exception as e:
            print(f"  ⚠️  Не удалось загрузить ключи из Firestore: {e}")

    # ── Сбор новых постов с пагинацией ────────────────────────────────────
    all_new = []
    for ch in channels:
        print(f"📡 Парсинг @{ch} (пагинация)...")
        # max_posts: берём с запасом чтобы было из чего выбирать
        max_fetch = max(200, (args.limit or 50) * 3)
        posts = parse_channel(ch, max_posts=max_fetch)
        known = set(processed.get(ch, []))
        new_posts = [
            p for p in posts
            if p['id'] not in known and f"{ch}|{p['id']}" not in firestore_tg_keys
        ]
        print(f"   Всего в ленте: {len(posts)} | Новых: {len(new_posts)}")
        all_new.extend(new_posts)

    if not all_new:
        print("\n✅ Нет новых постов для обработки. Запустите позже.")
        return

    # ── Умная сортировка по дефицитным категориям ─────────────────────────
    tag_counts: dict = {}
    if not args.dry_run and firebase_token:
        print("📊 Анализ баланса категорий в каталоге...")
        tag_counts = get_firebase_tag_counts(firebase_token, project_id)
        if tag_counts:
            bottom5 = sorted(tag_counts.items(), key=lambda x: x[1])[:5]
            print(f"   Дефицитные: {', '.join(f'{t}={c}' for t,c in bottom5)}")

    all_new = sort_posts_smart(all_new, tag_counts)

    if args.limit > 0:
        all_new = all_new[:args.limit]

    print(f"\n📋 К обработке: {len(all_new)} постов\n")

    # ── Обработка постов ──────────────────────────────────────────────────
    success = fail = skipped = 0

    for idx, post in enumerate(all_new, 1):
        ch = post['channel']
        post_id = post['id']
        title = post['title']

        print(f"─────────────────────────────────────────────────")
        print(f"[{idx}/{len(all_new)}] @{ch}/{post_id}  👁 {post['views']}  ❤ {post['reactions']}")
        print(f"  📌 {title}")
        print(f"  🏷  {', '.join(post['tags'])}")
        if post['prompt']:
            preview = post['prompt'][:120].replace('\n', ' ')
            print(f"  💬 Промпт: {preview}...")

        if args.dry_run:
            print("  [dry-run] Структура промпта будет:")
            print(f"    Заголовки: ОПИСАНИЕ СЦЕНЫ / ПЕРСОНАЖ / ОБЪЕКТЫ И ДЕТАЛИ /")
            print(f"               АТМОСФЕРА И НАСТРОЕНИЕ / ЦВЕТОВАЯ ПАЛИТРА / ТЕХНИЧЕСКИЕ ПАРАМЕТРЫ")
            print()
            skipped += 1
            continue

        try:
            # 1. Конвертируем сырой промпт в единую структуру через DeepSeek
            print(f"  🤖 Приведение промпта к структуре (DeepSeek)...")
            structured_prompt = convert_prompt_to_structure(
                post['prompt'], title, deepseek_key, tags=post['tags']
            )
            if not structured_prompt:
                print("  ❌ Не удалось структурировать промпт — пропускаем\n")
                fail += 1
                continue

            # Показываем первую секцию для контроля
            preview = structured_prompt[:160].replace('\n', ' ')
            print(f"  ✅ Структура готова: {preview}...")

            # 2. Генерируем превью по структурированному промпту
            print(f"  🎨 Генерация изображения (Nano Banana)...")
            image_url = generate_image(structured_prompt, piapi_key)

            if not image_url:
                print("  ❌ Не удалось сгенерировать изображение\n")
                fail += 1
                continue

            print(f"  ✅ Изображение готово")

            # Обновляем токен если нужно (Firebase токен живёт ~1 час)
            firebase_token = get_firebase_token(sa)

            # 3. Загружаем в Firebase
            print("  🔥 Загрузка в Firebase...")
            preset_doc = {
                'title': title,
                'prompt': structured_prompt,   # единый формат, виден в UI
                'previewImageUrl': image_url,
                'tags': post['tags'],
                'createdAt': datetime.now().isoformat(),
                'sourceChannel': ch,
                'sourcePostId': post_id,
            }
            doc_id = upload_to_firestore(firebase_token, project_id, preset_doc)
            print(f"  ✅ Сохранено (ID: {doc_id})\n")

            # Отмечаем как обработанный
            if ch not in processed:
                processed[ch] = []
            processed[ch].append(post_id)
            save_processed(processed)

            success += 1
            time.sleep(1)  # небольшая пауза между постами

        except Exception as e:
            print(f"  ❌ Ошибка: {e}\n")
            fail += 1

    # ── Итоги ─────────────────────────────────────────────────────────────
    print("═══════════════════════════════════════════════════")
    print("📊 ИТОГИ")
    print("═══════════════════════════════════════════════════")
    if args.dry_run:
        print(f"🔍 Найдено новых постов: {skipped}")
        print(f"💾 Обработано каналов: {', '.join(channels)}")
    else:
        print(f"✅ Успешно создано пресетов: {success}")
        print(f"❌ Ошибки: {fail}")
        print(f"💾 Статус дедупликации: {PROCESSED_FILE}")
    print()
    if success > 0:
        print("🎉 Новые пресеты доступны в приложении!")
    print("📅 Запускайте скрипт регулярно для пополнения каталога.")
    print()


if __name__ == '__main__':
    main()
