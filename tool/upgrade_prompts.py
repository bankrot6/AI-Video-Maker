#!/usr/bin/env python3
"""
Улучшает существующие промпты в Firebase по новым правилам:
  — Расширяет описание персонажа (тело, пропорции, телосложение)
  — Добавляет/заменяет финальную фразу об идентичности в ПЕРСОНАЖ
  — Добавляет/заменяет финальную фразу в ТЕХНИЧЕСКИЕ ПАРАМЕТРЫ
  — Расширяет объём до 350-500 слов
  — Надписи на изображении — только кириллица
  — НЕ перегенерирует изображения (работает только с текстом)
  — Обрабатывает ВСЕ пресеты (не только из Telegram)

Запуск:
  python3 -u tool/upgrade_prompts.py              # все пресеты
  python3 -u tool/upgrade_prompts.py --limit 10   # первые 10
  python3 -u tool/upgrade_prompts.py --id preset_17...  # конкретный
  python3 -u tool/upgrade_prompts.py --dry-run    # без записи в Firebase
"""

import sys
import json
import re
import time
import argparse
import requests
from pathlib import Path
from datetime import datetime
from typing import Optional, List

# ─── Константы ───────────────────────────────────────────────────────────────

SA_PATHS = [
    Path('firebase-service-account.json'),
    Path('tool/firebase-service-account.json'),
]
ENV_FILE = Path('.env')

# Системный промпт для УЛУЧШЕНИЯ уже структурированного промпта.
# Не конвертирует из Telegram, а дорабатывает готовый 6-секционный текст.
UPGRADE_SYSTEM_PROMPT = '''Ты редактор промптов для AI-фотографии.
Перед тобой уже структурированный промпт в 6 разделах. Твоя задача — УЛУЧШИТЬ его строго по правилам ниже, не меняя концепцию сцены.

ПРАВИЛА УЛУЧШЕНИЯ:

1. ОПИСАНИЕ СЦЕНЫ:
   — Должно быть 3-5 предложений. Если меньше — добавь детали локации, текстур, планов, материалов поверхностей.
   — ОСОБЫЕ ТЕХНИКИ: Если упоминается коллаж, сюрреализм, polaroid-сетка, составное изображение или типографика — опиши эту технику максимально подробно. НЕ убирай и НЕ упрощай необычные художественные приёмы!

2. ПЕРСОНАЖ:
   — Раздел должен начинаться с пола и возраста: "Молодая женщина 20-30 лет" / "Молодой мужчина" / "Ребёнок".
   — Добавь или уточни описание телосложения если это можно вывести из контекста (стройное / атлетичное / пышное / хрупкое).
   — Уточни позу и положение тела: угол разворота, положение рук и ног, наклон головы.
   — ОБЯЗАТЕЛЬНО замени финальную фразу раздела на точно такую:
     "Черты лица, форма скул, линия подбородка, цвет и форма глаз, форма носа и губ, тон и текстура кожи по всему телу, тип телосложения и пропорции фигуры — всё сохраняется точно как на референс-фото без идеализации и без каких-либо изменений."

3. ОБЪЕКТЫ И ДЕТАЛИ:
   — Должно быть 2-3 предложения. Добавь конкретные материалы, размеры, цвета реквизита если их нет.
   — Если в промпте упоминался текст на изображении (надпись, дата, поздравление) — убедись что он написан КИРИЛЛИЦЕЙ. Если был переведён на английский — верни на кириллицу.
   — Добавь позицию объектов в кадре если её нет.

4. АТМОСФЕРА И НАСТРОЕНИЕ:
   — Должно быть 2-3 предложения. Добавь как атмосфера проявляется визуально.

5. ЦВЕТОВАЯ ПАЛИТРА:
   — 1-2 предложения. Добавь тон кожи персонажа если его нет.

6. ТЕХНИЧЕСКИЕ ПАРАМЕТРЫ:
   — Уточни тип освещения и объектив если они расплывчаты.
   — ОБЯЗАТЕЛЬНО замени финальную фразу раздела на точно такую:
     "профессиональная фотография, высокое разрешение 2K, резкий фокус на лице, натуральная текстура кожи без ретуши, сохранение личности и телосложения с референс-фото, формат 3:4 вертикальный, фотореалистично."

СТРОГИЕ ОГРАНИЧЕНИЯ:
— Сохрани все 6 разделов с теми же заголовками
— Весь текст — только на русском языке
— Объём итогового промпта: 350-500 слов
— Не добавляй вступлений, заключений, комментариев — только 6 разделов
— НИКОГДА не упрощай необычные художественные техники (коллаж, сюрреализм и т.д.)
— Формат всегда вертикальный 3:4 — никогда не горизонтальный'''

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
        env[s[:i].strip()] = s[i+1:].strip().strip('"').strip("'")
    return env


def load_service_account() -> dict:
    for p in SA_PATHS:
        if p.exists():
            return json.loads(p.read_text())
    print("❌ firebase-service-account.json не найден"); sys.exit(1)


def get_firebase_token(sa: dict) -> str:
    now = int(time.time())
    payload = {
        'iss': sa['client_email'],
        'sub': sa['client_email'],
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now,
        'exp': now + 3600,
        'scope': 'https://www.googleapis.com/auth/datastore',
    }
    try:
        import jwt as pyjwt
        token = pyjwt.encode(payload, sa['private_key'], algorithm='RS256')
    except ImportError:
        import base64
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding
        from cryptography.hazmat.backends import default_backend
        header = base64.urlsafe_b64encode(
            json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode()
        ).rstrip(b'=').decode()
        body = base64.urlsafe_b64encode(
            json.dumps(payload).encode()
        ).rstrip(b'=').decode()
        pk = serialization.load_pem_private_key(
            sa['private_key'].encode(), password=None, backend=default_backend()
        )
        sig = pk.sign(f'{header}.{body}'.encode(), padding.PKCS1v15(), hashes.SHA256())
        sig_b64 = base64.urlsafe_b64encode(sig).rstrip(b'=').decode()
        token = f'{header}.{body}.{sig_b64}'

    resp = requests.post(
        'https://oauth2.googleapis.com/token',
        data={'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer', 'assertion': token},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()['access_token']


# ─── Firebase ─────────────────────────────────────────────────────────────────

def get_all_presets(token: str, project_id: str) -> List[dict]:
    """Возвращает все пресеты из Firebase."""
    presets = []
    page_token = None

    while True:
        url = (
            f'https://firestore.googleapis.com/v1/projects/{project_id}'
            f'/databases/(default)/documents/presets?pageSize=300'
        )
        if page_token:
            url += f'&pageToken={page_token}'

        resp = requests.get(url, headers={'Authorization': f'Bearer {token}'}, timeout=30)
        resp.raise_for_status()
        data = resp.json()

        for doc in data.get('documents', []):
            fields = doc.get('fields', {})
            doc_id = doc['name'].split('/')[-1]
            tags = [
                tv.get('stringValue', '')
                for tv in fields.get('tags', {}).get('arrayValue', {}).get('values', [])
            ]
            presets.append({
                'doc_id': doc_id,
                'doc_name': doc['name'],
                'title': fields.get('title', {}).get('stringValue', ''),
                'prompt': fields.get('prompt', {}).get('stringValue', ''),
                'tags': tags,
                'owner_id': fields.get('ownerId', {}).get('stringValue', ''),
            })

        page_token = data.get('nextPageToken')
        if not page_token:
            break

    return presets


def update_prompt_only(token: str, doc_name: str, new_prompt: str, retries: int = 3) -> bool:
    """PATCH — обновляет только поле prompt и updatedAt. Повторяет при сетевых ошибках."""
    url = (
        f'https://firestore.googleapis.com/v1/{doc_name}'
        f'?updateMask.fieldPaths=prompt'
        f'&updateMask.fieldPaths=updatedAt'
    )
    body = {
        'fields': {
            'prompt': {'stringValue': new_prompt},
            'updatedAt': {'stringValue': datetime.now().isoformat()},
        }
    }
    for attempt in range(1, retries + 1):
        try:
            resp = requests.patch(
                url,
                headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
                json=body,
                timeout=30,
            )
            return resp.status_code in (200, 201)
        except Exception as e:
            if attempt < retries:
                print(f"    ⚠️  Firebase ошибка (попытка {attempt}/{retries}): {e}")
                time.sleep(5 * attempt)
            else:
                print(f"    ❌ Firebase недоступен после {retries} попыток: {e}")
                return False
    return False


# ─── DeepSeek ─────────────────────────────────────────────────────────────────

def is_already_new_format(prompt: str) -> bool:
    """Проверяет есть ли уже новая финальная фраза о телосложении."""
    return 'телосложения и пропорции фигуры' in prompt


def upgrade_prompt(
    existing_prompt: str,
    title: str,
    tags: List[str],
    deepseek_key: str,
    retries: int = 3,
) -> Optional[str]:
    """Улучшает существующий структурированный промпт по новым правилам."""

    if 'женщины' in tags:
        gender_hint = 'Персонаж — ЖЕНЩИНА. Начало раздела ПЕРСОНАЖ: "Молодая женщина 20-30 лет".'
    elif 'мужчины' in tags:
        gender_hint = 'Персонаж — МУЖЧИНА. Начало раздела ПЕРСОНАЖ: "Молодой мужчина".'
    elif 'дети' in tags:
        gender_hint = 'Персонаж — РЕБЁНОК. Начало раздела ПЕРСОНАЖ: "Ребёнок".'
    elif 'семья' in tags:
        gender_hint = 'Персонажи — СЕМЬЯ. Опиши всех членов семьи в разделе ПЕРСОНАЖ.'
    else:
        gender_hint = 'Персонаж — ЖЕНЩИНА (по умолчанию). Начало раздела ПЕРСОНАЖ: "Молодая женщина 20-30 лет".'

    user_msg = (
        f'Название пресета: {title}\n'
        f'{gender_hint}\n\n'
        f'Существующий промпт для улучшения:\n\n{existing_prompt}\n\n'
        f'Улучши этот промпт строго по правилам системного промпта.'
    )

    for attempt in range(1, retries + 1):
        try:
            resp = requests.post(
                'https://api.deepseek.com/v1/chat/completions',
                headers={'Authorization': f'Bearer {deepseek_key}', 'Content-Type': 'application/json'},
                json={
                    'model': 'deepseek-chat',
                    'messages': [
                        {'role': 'system', 'content': UPGRADE_SYSTEM_PROMPT},
                        {'role': 'user', 'content': user_msg},
                    ],
                    'max_tokens': 2200,
                    'temperature': 0.3,
                },
                timeout=90,
            )
            resp.raise_for_status()
            content = resp.json()['choices'][0]['message']['content'].strip()
            content = re.sub(r'^```[^\n]*\n?', '', content)
            content = re.sub(r'\n?```$', '', content)
            return content.strip() or None
        except Exception as e:
            if attempt < retries:
                wait = 10 * attempt
                print(f"    ⚠️  DeepSeek ошибка (попытка {attempt}/{retries}), повтор через {wait}с: {e}")
                time.sleep(wait)
            else:
                print(f"    ❌ DeepSeek: {e}")
                return None
    return None


# ─── Основной алгоритм ────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Upgrade existing preset prompts to new rules')
    parser.add_argument('--limit', type=int, default=0,
                        help='Обработать не более N пресетов (0 = все)')
    parser.add_argument('--id', type=str, default='',
                        help='Обработать конкретный пресет по doc_id')
    parser.add_argument('--dry-run', action='store_true',
                        help='Без записи в Firebase — показывает что будет изменено')
    parser.add_argument('--force', action='store_true',
                        help='Обрабатывать даже пресеты которые уже обновлены')
    parser.add_argument('--skip-custom', action='store_true', default=True,
                        help='Пропустить пользовательские пресеты (с ownerId). По умолчанию: да')
    parser.add_argument('--include-custom', action='store_true',
                        help='Включить пользовательские пресеты (с ownerId)')
    args = parser.parse_args()

    skip_custom = args.skip_custom and not args.include_custom

    print("═══════════════════════════════════════════════════")
    print("  UPGRADE PROMPTS  Firebase → DeepSeek → Firebase")
    print("═══════════════════════════════════════════════════\n")

    if args.dry_run:
        print("🔍 DRY-RUN: без записи в Firebase\n")

    env = load_env()
    deepseek_key = env.get('DEEPSEEK_API_KEY', '').strip()
    if not deepseek_key:
        print("❌ DEEPSEEK_API_KEY не найден в .env"); sys.exit(1)

    sa = load_service_account() if not args.dry_run else {}
    project_id = sa.get('project_id', 'photosession-ai-cbfc3') if sa else 'photosession-ai-cbfc3'

    print("🔐 Получение Firebase токена...")
    token = get_firebase_token(sa) if not args.dry_run else 'dry-run'
    if not args.dry_run:
        print("✅ Токен получен\n")

    print("📥 Загрузка пресетов из Firebase...")
    all_presets = get_all_presets(token, project_id) if not args.dry_run else []
    print(f"   Всего пресетов: {len(all_presets)}\n")

    # Фильтрация
    candidates = []
    for p in all_presets:
        if args.id and p['doc_id'] != args.id:
            continue
        if not p['prompt']:
            continue
        if skip_custom and p['owner_id']:
            continue
        if not args.force and is_already_new_format(p['prompt']):
            continue
        candidates.append(p)

    if args.id and not candidates:
        print(f"❌ Пресет {args.id} не найден или уже обновлён (используй --force)")
        return

    if args.limit > 0:
        candidates = candidates[:args.limit]

    already_done = len(all_presets) - len(candidates) if not args.dry_run else 0

    print(f"📋 Уже актуальны: {already_done}")
    print(f"📋 Требуют обновления: {len(candidates)}\n")

    if not candidates:
        print("✅ Все пресеты уже соответствуют новым правилам!")
        return

    success = fail = skipped = 0

    for idx, preset in enumerate(candidates, 1):
        title = preset['title']
        tags = preset['tags']
        existing_prompt = preset['prompt']

        print(f"─────────────────────────────────────────────────")
        print(f"[{idx}/{len(candidates)}] {preset['doc_id']}")
        print(f"  📌 {title}")
        print(f"  🏷  {', '.join(tags) or '—'}")

        old_len = len(existing_prompt.split())
        print(f"  📝 Текущий объём: ~{old_len} слов")

        if args.dry_run:
            print("  [dry-run] Будет улучшен через DeepSeek")
            skipped += 1
            continue

        print(f"  🤖 DeepSeek: улучшаем промпт...")
        upgraded = upgrade_prompt(existing_prompt, title, tags, deepseek_key)

        if not upgraded:
            print("  ❌ DeepSeek не вернул результат — пропускаем")
            fail += 1
            continue

        new_len = len(upgraded.split())
        delta = new_len - old_len
        sign = '+' if delta >= 0 else ''
        print(f"  ✅ Готово: ~{new_len} слов ({sign}{delta})")

        # Покажем первые строки нового промпта для контроля
        first_line = upgraded.split('\n')[0][:80]
        print(f"  👁  {first_line}...")

        # Обновляем токен каждые 45 пресетов (токен живёт ~1 час)
        if idx % 45 == 0:
            token = get_firebase_token(sa)

        ok = update_prompt_only(token, preset['doc_name'], upgraded)

        if ok:
            print(f"  🔥 Сохранено в Firebase")
            success += 1
        else:
            print(f"  ❌ Ошибка сохранения в Firebase")
            fail += 1

        time.sleep(0.5)

    print("\n═══════════════════════════════════════════════════")
    print("📊 ИТОГИ")
    print("═══════════════════════════════════════════════════")
    print(f"✅ Обновлено:  {success}")
    if args.dry_run:
        print(f"⏭  Dry-run:    {skipped}")
    print(f"❌ Ошибки:    {fail}")
    print()
    if success > 0:
        print("🎉 Промпты обновлены! Пользователи получат улучшенные результаты.")
    print()


if __name__ == '__main__':
    main()
