#!/usr/bin/env python3
"""
Ретроактивное исправление тегов в Firebase:
- Умное определение пола из полного текста промпта
- Перевод английских тегов на русский
- Обновление всех пресетов в Firestore

Запуск:
    python3 -u tool/fix_preset_tags.py              # обновить всё
    python3 -u tool/fix_preset_tags.py --dry-run    # только показать что изменится
"""

import argparse
import json
import re
import sys
import time
from pathlib import Path
from typing import List, Optional, Dict, Any

try:
    import requests
except ImportError:
    print("❌ Установите: pip3 install requests"); sys.exit(1)

try:
    import jwt
except ImportError:
    print("❌ Установите: pip3 install PyJWT cryptography"); sys.exit(1)


# ─── Конфигурация путей ──────────────────────────────────────────────────────

SA_PATHS = [Path('firebase-service-account.json'), Path('tool/firebase-service-account.json')]
ENV_FILE = Path('.env')


# ─── Расширенная карта тегов ─────────────────────────────────────────────────

# Теги-синонимы (английские и неверные → каноническое русское название)
TAG_TRANSLATIONS = {
    # English → Russian
    'women': 'женщины', 'woman': 'женщины', 'female': 'женщины', 'girl': 'женщины',
    'men': 'мужчины', 'man': 'мужчины', 'male': 'мужчины',
    'boy': 'дети', 'boys': 'дети', 'girl': 'дети',
    'children': 'дети', 'child': 'дети', 'kids': 'дети', 'baby': 'дети',
    'family': 'семья', 'nature': 'природа', 'studio': 'студия', 'city': 'город',
    'business': 'бизнес', 'romance': 'романтика', 'travel': 'путешествия',
    'animals': 'животные', 'fantasy': 'фэнтези', 'retro': 'ретро',
    'minimalism': 'минимализм', 'luxury': 'роскошь', 'sport': 'спорт',
    'food': 'еда', 'holiday': 'праздник', 'fashion': 'мода', 'portrait': 'портрет',
    'outdoor': 'природа', 'indoor': 'студия', 'artistic': 'арт', 'editorial': 'мода',
    'summer': 'лето', 'winter': 'зима', 'spring': 'весна', 'autumn': 'осень',
    'cars': 'автомобили', 'car': 'автомобили', 'vehicle': 'автомобили',
    'dark': 'тёмный стиль', 'light': 'светлый стиль',
    'custom': None,  # убираем служебный тег
    # Неканонические русские формы
    'женщина': 'женщины', 'девушки': 'женщины', 'девочки': 'дети',
    'мальчики': 'дети', 'ребёнок': 'дети', 'ребенок': 'дети',
    'фотография': None, 'съёмка': None, 'фотосессия': None,
    # Теги которые уже правильные — оставляем как есть
    'студия': 'студия', 'город': 'город', 'роскошь': 'роскошь',
    'минимализм': 'минимализм', 'мода': 'мода', 'арт': 'арт',
    'лето': 'лето', 'зима': 'зима', 'весна': 'весна', 'осень': 'осень',
    'цветы': 'цветы', 'дома': 'дома', 'автомобили': 'автомобили',
    'праздник': 'праздник', 'романтика': 'романтика',
}

# Ключевые слова в тексте промпта → тег (искать как подстроку)
PROMPT_KEYWORDS: List[tuple] = [
    # ─ Пол: женщины (очень широкий список — большинство пресетов для женщин) ─
    ('девушк', 'женщины'), ('женщин', 'женщины'), ('модель', 'женщины'),
    ('невест', 'женщины'), ('актрис', 'женщины'),
    # Одежда, характерная для женщин
    ('платье', 'женщины'), ('юбк', 'женщины'), ('блузк', 'женщины'),
    ('корсет', 'женщины'), ('сарафан', 'женщины'), ('бикини', 'женщины'),
    ('каблук', 'женщины'), ('шпильк', 'женщины'), ('декольте', 'женщины'),
    # Аксессуары
    ('серьг', 'женщины'), ('ожерель', 'женщины'), ('браслет', 'женщины'),
    # Местоимения и описания
    ('she ', 'женщины'), (' her ', 'женщины'), ('молодая женщин', 'женщины'),
    ('красивая женщин', 'женщины'), ('элегантная', 'женщины'),
    # ─ Пол: мужчины ─
    ('мужчин', 'мужчины'), ('мужской', 'мужчины'), ('парень', 'мужчины'),
    ('джентльмен', 'мужчины'), ('костюм с галстук', 'мужчины'),
    ('борода', 'мужчины'), ('усы', 'мужчины'),
    (' he ', 'мужчины'), (' his ', 'мужчины'),
    # ─ Дети ─
    ('ребёнок', 'дети'), ('ребенок', 'дети'), ('малыш', 'дети'),
    ('девочк', 'дети'), ('мальчик', 'дети'), ('дошкольн', 'дети'),
    ('подростк', 'дети'), ('школьник', 'дети'),
    # ─ Семья ─
    (' семь', 'семья'), ('мама', 'семья'), ('папа', 'семья'),
    ('родител', 'семья'), ('супруг', 'семья'),
    # ─ Локация: природа ─
    ('лес', 'природа'), ('парк', 'природа'), ('сад', 'природа'),
    ('природ', 'природа'), ('поле', 'природа'), ('луг', 'природа'),
    ('река', 'природа'), ('озеро', 'природа'), ('горы', 'природа'),
    ('хвойн', 'природа'), ('берёзов', 'природа'), ('цветущ', 'природа'),
    ('трав', 'природа'),
    # ─ Локация: студия ─
    ('студи', 'студия'), ('белый фон', 'студия'), ('тёмный фон', 'студия'),
    ('тёмно-серый фон', 'студия'), ('нейтральный фон', 'студия'),
    ('бесшовный фон', 'студия'), ('задник', 'студия'), ('студийн', 'студия'),
    # ─ Локация: город ─
    ('город', 'город'), ('улиц', 'город'), ('мостов', 'город'),
    ('набережн', 'город'), ('переулк', 'город'), ('площадь', 'город'),
    ('кафе', 'город'), ('ресторан', 'город'), ('витрин', 'город'),
    ('европейск', 'город'), ('архитектур', 'город'),
    # ─ Стиль: фэнтези ─
    ('сказк', 'фэнтези'), ('сказочн', 'фэнтези'), ('мистик', 'фэнтези'),
    ('ангел', 'фэнтези'), ('магич', 'фэнтези'), ('фэнтези', 'фэнтези'),
    ('enchant', 'фэнтези'), ('fairy', 'фэнтези'), ('волшебн', 'фэнтези'),
    ('cinematic fantasy', 'фэнтези'), ('красная шапочк', 'фэнтези'),
    # ─ Стиль: ретро ─
    ('ретро', 'ретро'), ('винтаж', 'ретро'), ('полароид', 'ретро'),
    ('vintage', 'ретро'), ('70-е', 'ретро'), ('80-е', 'ретро'), ('90-е', 'ретро'),
    # ─ Стиль: мода / editorial ─
    ('editorial', 'мода'), ('fashion', 'мода'), ('vogue', 'мода'),
    ('подиум', 'мода'), ('haute couture', 'мода'),
    # ─ Бизнес (НЕ 'профессиональн' — совпадает с "профессиональная фотография" в технических параметрах) ─
    ('бизнес', 'бизнес'), ('офис', 'бизнес'), ('деловой стиль', 'бизнес'),
    ('корпоратив', 'бизнес'), ('деловая встреч', 'бизнес'),
    ('конференц', 'бизнес'), ('переговор', 'бизнес'),
    # ─ Путешествия ─
    ('пляж', 'путешествия'), ('море', 'путешествия'), ('океан', 'путешествия'),
    ('отдых', 'путешествия'), ('курорт', 'путешествия'), ('тропик', 'путешествия'),
    # ─ Животные ─
    ('волк', 'животные'), ('лошадь', 'животные'), ('кошк', 'животные'),
    ('пантер', 'животные'), ('питомц', 'животные'), ('собак', 'животные'),
    ('медведь', 'животные'),
    # ─ Роскошь (НЕ 'золот' — совпадает с "золотой час" в технических параметрах) ─
    ('роскошн', 'роскошь'), ('luxury', 'роскошь'), ('glamour', 'роскошь'),
    ('шёлк', 'роскошь'), ('бархат', 'роскошь'), ('брилли', 'роскошь'),
    ('меховой', 'роскошь'), ('золотое украшени', 'роскошь'),
    ('vip', 'роскошь'), ('эксклюзивн', 'роскошь'), ('дизайнерск', 'роскошь'),
    ('люкс', 'роскошь'), ('пентхаус', 'роскошь'), ('яхт', 'роскошь'),
    # ─ Праздник ─
    ('праздник', 'праздник'), ('новый год', 'праздник'), ('рождество', 'праздник'),
    ('карнавал', 'праздник'), ('фиеста', 'праздник'), ('маскарад', 'праздник'),
    ('фестиваль', 'праздник'),
    # ─ Романтика ─
    ('романтик', 'романтика'), ('love', 'романтика'), ('влюблённ', 'романтика'),
    ('нежн', 'романтика'),
    # ─ Минимализм ─
    ('минимализм', 'минимализм'), ('minimal', 'минимализм'), ('лаконичн', 'минимализм'),
]

# Максимум тегов на пресет
MAX_TAGS = 6

# Если гендер не определён и нет детей/семьи — применяем "женщины" по умолчанию
# (90%+ fashion-пресетов для женщин)
GENDER_TAGS = {'женщины', 'мужчины', 'дети', 'семья'}


def smart_extract_tags(title: str, prompt: str, existing_tags: List[str]) -> List[str]:
    """
    Умное определение тегов по полному тексту промпта (6-секционный формат).
    Учитывает секцию ПЕРСОНАЖ, одежду, локацию и стиль.
    """
    found = set()
    text = (title + ' ' + prompt).lower()

    # Ищем ключевые слова
    for keyword, tag in PROMPT_KEYWORDS:
        if keyword.lower() in text:
            found.add(tag)

    # Переводим существующие теги (English → Russian, убираем служебные)
    for tag in existing_tags:
        t = tag.strip().lower()
        if t in TAG_TRANSLATIONS:
            translated = TAG_TRANSLATIONS[t]
            if translated is not None:
                found.add(translated)
        elif t and t not in ('фотосессия', 'custom', 'фотография', 'съёмка'):
            found.add(t)  # оставляем валидные русские теги

    # По умолчанию — женщины, если нет гендерного тега
    # (fashion-пресеты почти всегда для женщин)
    has_gender = bool(found & GENDER_TAGS)
    if not has_gender:
        found.add('женщины')

    # Убираем мусор и пустые теги (НЕ 'custom' — он нужен для пользовательских пресетов)
    for junk in ('фотосессия', 'фотография', 'съёмка', '', None):
        found.discard(junk)

    result = sorted(found)
    return result[:MAX_TAGS]


# ─── Firebase ─────────────────────────────────────────────────────────────────

def load_env() -> dict:
    env: Dict[str, str] = {}
    if not ENV_FILE.exists():
        return env
    for line in ENV_FILE.read_text().split('\n'):
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        i = s.find('=')
        if i <= 0:
            continue
        env[s[:i].strip()] = s[i+1:].strip().strip('"').strip("'")
    return env


def load_service_account() -> dict:
    for p in SA_PATHS:
        if p.exists():
            data = json.loads(p.read_text())
            print(f"✅ Service Account: {p}")
            return data
    print("❌ firebase-service-account.json не найден")
    sys.exit(1)


def get_firebase_token(sa: dict) -> str:
    now = time.time()
    payload = {
        'iss': sa['client_email'], 'sub': sa['client_email'],
        'aud': sa['token_uri'],
        'iat': int(now), 'exp': int(now) + 3600,
        'scope': 'https://www.googleapis.com/auth/datastore',
    }
    signed = jwt.encode(payload, sa['private_key'], algorithm='RS256')
    resp = requests.post(sa['token_uri'], data={
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': signed,
    }, timeout=30)
    resp.raise_for_status()
    return resp.json()['access_token']


def list_all_presets(token: str, project_id: str) -> List[Dict[str, Any]]:
    """Загружает все документы из коллекции presets."""
    url = (
        f'https://firestore.googleapis.com/v1/projects/{project_id}'
        f'/databases/(default)/documents/presets?pageSize=300'
    )
    resp = requests.get(url, headers={'Authorization': f'Bearer {token}'}, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    return data.get('documents', [])


def parse_firestore_value(fv: dict) -> Any:
    """Декодирует Firestore-значение в Python."""
    if 'stringValue' in fv:
        return fv['stringValue']
    if 'arrayValue' in fv:
        return [parse_firestore_value(v) for v in fv['arrayValue'].get('values', [])]
    if 'integerValue' in fv:
        return int(fv['integerValue'])
    if 'booleanValue' in fv:
        return fv['booleanValue']
    if 'timestampValue' in fv:
        return fv['timestampValue']
    return None


def doc_to_preset(doc: dict) -> dict:
    """Преобразует Firestore-документ в удобный dict."""
    fields = doc.get('fields', {})
    result = {'_name': doc.get('name', '')}
    for k, v in fields.items():
        result[k] = parse_firestore_value(v)
    return result


def update_preset_tags(token: str, doc_name: str, new_tags: List[str]):
    """Обновляет только поле tags в существующем документе."""
    url = f'https://firestore.googleapis.com/v1/{doc_name}?updateMask.fieldPaths=tags'
    body = {
        'fields': {
            'tags': {
                'arrayValue': {
                    'values': [{'stringValue': t} for t in new_tags]
                }
            }
        }
    }
    resp = requests.patch(
        url,
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        json=body,
        timeout=30,
    )
    resp.raise_for_status()


# ─── Основной цикл ────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true', help='Показать изменения без записи')
    args = parser.parse_args()

    env = load_env()
    project_id = env.get('FIREBASE_PROJECT_ID', '').strip()
    if not project_id:
        print("❌ FIREBASE_PROJECT_ID не найден в .env"); sys.exit(1)

    sa = load_service_account()

    print('\n═══════════════════════════════════════════════')
    print('  FIX PRESET TAGS  — умные теги + перевод')
    print('═══════════════════════════════════════════════\n')

    if args.dry_run:
        print('🔍 DRY-RUN — без записи в Firebase\n')

    print('🔐 Получение Firebase токена...')
    token = get_firebase_token(sa)
    print('✅ Токен получен\n')

    print('📥 Загрузка пресетов из Firestore...')
    docs = list_all_presets(token, project_id)
    presets = [doc_to_preset(d) for d in docs]
    print(f'✅ Найдено пресетов: {len(presets)}\n')

    updated = 0
    unchanged = 0

    for i, preset in enumerate(presets, 1):
        title = preset.get('title', '')
        prompt = preset.get('prompt', '')
        old_tags = preset.get('tags', []) or []
        if isinstance(old_tags, str):
            old_tags = [old_tags]
        owner_id = preset.get('ownerId')

        # Пользовательские пресеты (ownerId != null) — только сохраняем 'custom',
        # не перезаписываем теги алгоритмически
        if owner_id:
            new_tags = [t for t in old_tags if t and t not in TAG_TRANSLATIONS or TAG_TRANSLATIONS.get(t) is not None]
            if 'custom' not in new_tags:
                new_tags.append('custom')   # восстанавливаем если был удалён
            new_tags = sorted(set(new_tags))
        else:
            new_tags = smart_extract_tags(title, prompt, old_tags)

        changed = sorted(old_tags) != sorted(new_tags)
        status = '✏️ ' if changed else '─ '

        print(f'[{i:03d}] {status}{title}')
        if changed:
            print(f'      было:  {old_tags}')
            print(f'      стало: {new_tags}')
        else:
            print(f'      теги:  {new_tags}')

        if changed and not args.dry_run:
            try:
                # Обновляем токен каждые 50 документов
                if i % 50 == 0:
                    token = get_firebase_token(sa)
                update_preset_tags(token, preset['_name'], new_tags)
                updated += 1
            except Exception as e:
                print(f'      ❌ Ошибка обновления: {e}')
        elif changed:
            updated += 1  # в dry-run считаем как "будет обновлено"
        else:
            unchanged += 1

    print(f'\n═══════════════════════════════════════════════')
    print(f'📊 ИТОГИ')
    print(f'═══════════════════════════════════════════════')
    if args.dry_run:
        print(f'🔍 Будет обновлено: {updated} | Без изменений: {unchanged}')
    else:
        print(f'✅ Обновлено: {updated} | Без изменений: {unchanged}')
    print()


if __name__ == '__main__':
    main()
