#!/usr/bin/env python3
"""
Перегенерирует промпты и превью для уже созданных пресетов.

Алгоритм:
  1. Получает все пресеты из Firebase у которых есть sourceChannel + sourcePostId
  2. Повторно загружает оригинальный пост из Telegram по сохранённому ID
  3. Прогоняет через улучшенный DeepSeek промпт
  4. Перегенерирует превью через Nano Banana
  5. Обновляет документ в Firebase (PATCH)

Запуск:
  python3 -u tool/fix_preset_prompts.py              # все пресеты
  python3 -u tool/fix_preset_prompts.py --limit 5    # первые 5
  python3 -u tool/fix_preset_prompts.py --id preset_17...  # конкретный
  python3 -u tool/fix_preset_prompts.py --dry-run    # без записи
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

# ─── Константы (те же что в preset_pipeline.py) ──────────────────────────────

SA_PATHS = [
    Path('firebase-service-account.json'),
    Path('tool/firebase-service-account.json'),
]
ENV_FILE = Path('.env')

# Улучшенный системный промпт — ИДЕНТИЧЕН тому что в preset_pipeline.py.
# При обновлении обновляй синхронно!
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

_TG_HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                  'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0',
}

# ─── Вспомогательные функции ──────────────────────────────────────────────────

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
    import base64, hashlib, hmac
    try:
        import jwt as pyjwt
        use_pyjwt = True
    except ImportError:
        use_pyjwt = False

    now = int(time.time())
    payload = {
        'iss': sa['client_email'],
        'sub': sa['client_email'],
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now,
        'exp': now + 3600,
        'scope': 'https://www.googleapis.com/auth/datastore '
                 'https://www.googleapis.com/auth/devstorage.read_write',
    }

    if use_pyjwt:
        token = pyjwt.encode(payload, sa['private_key'], algorithm='RS256')
    else:
        header = base64.urlsafe_b64encode(
            json.dumps({'alg': 'RS256', 'typ': 'JWT'}).encode()
        ).rstrip(b'=').decode()
        body = base64.urlsafe_b64encode(
            json.dumps(payload).encode()
        ).rstrip(b'=').decode()
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import padding
        from cryptography.hazmat.backends import default_backend
        private_key = serialization.load_pem_private_key(
            sa['private_key'].encode(), password=None, backend=default_backend()
        )
        sig_input = f'{header}.{body}'.encode()
        signature = private_key.sign(sig_input, padding.PKCS1v15(), hashes.SHA256())
        sig_b64 = base64.urlsafe_b64encode(signature).rstrip(b'=').decode()
        token = f'{header}.{body}.{sig_b64}'

    resp = requests.post(
        'https://oauth2.googleapis.com/token',
        data={
            'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion': token,
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()['access_token']


# ─── Firebase: получение пресетов ────────────────────────────────────────────

def get_all_presets(token: str, project_id: str) -> List[dict]:
    """Возвращает все пресеты из Firebase с полями id, title, tags, sourceChannel, sourcePostId."""
    presets = []
    page_token = None

    while True:
        url = (
            f'https://firestore.googleapis.com/v1/projects/{project_id}'
            f'/databases/(default)/documents/presets?pageSize=300'
        )
        if page_token:
            url += f'&pageToken={page_token}'

        resp = requests.get(
            url,
            headers={'Authorization': f'Bearer {token}'},
            timeout=30,
        )
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
                'tags': tags,
                'sourceChannel': fields.get('sourceChannel', {}).get('stringValue', ''),
                'sourcePostId': fields.get('sourcePostId', {}).get('stringValue', ''),
                'ownerId': fields.get('ownerId', {}).get('stringValue', ''),
            })

        page_token = data.get('nextPageToken')
        if not page_token:
            break

    return presets


# ─── Firebase: обновление пресета ────────────────────────────────────────────

def update_preset_in_firestore(token: str, doc_name: str, new_prompt: str, new_image_url: str) -> bool:
    """PATCH — обновляет только prompt и previewImageUrl."""
    url = (
        f'https://firestore.googleapis.com/v1/{doc_name}'
        f'?updateMask.fieldPaths=prompt'
        f'&updateMask.fieldPaths=previewImageUrl'
        f'&updateMask.fieldPaths=updatedAt'
    )
    body = {
        'fields': {
            'prompt': {'stringValue': new_prompt},
            'previewImageUrl': {'stringValue': new_image_url},
            'updatedAt': {'stringValue': datetime.now().isoformat()},
        }
    }
    resp = requests.patch(
        url,
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        json=body,
        timeout=30,
    )
    return resp.status_code in (200, 201)


# ─── Telegram: загрузка поста по ID ──────────────────────────────────────────

def fetch_telegram_post(channel: str, post_id: str) -> Optional[dict]:
    """
    Загружает конкретный пост Telegram по его ID.
    Использует ?before=POST_ID+1 чтобы получить страницу, содержащую этот пост.
    """
    before = str(int(post_id) + 1)
    url = f'https://t.me/s/{channel}?before={before}'
    try:
        resp = requests.get(url, timeout=30, headers=_TG_HEADERS)
        if resp.status_code != 200:
            return None
    except Exception as e:
        print(f"    ❌ Telegram: {e}")
        return None

    html = resp.text
    # Ищем конкретный блок поста
    pattern = (
        r'<div[^>]+data-post="' + re.escape(channel) + r'/' + re.escape(post_id) +
        r'"[^>]*>(.*?)(?=<div[^>]+data-post="|$)'
    )
    m = re.search(pattern, html, re.DOTALL)
    if not m:
        return None

    block = m.group(1)

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

    code_match = re.search(r'<code[^>]*>(.*?)</code>', block, re.DOTALL)
    prompt = ''
    if code_match:
        p = code_match.group(1)
        p = re.sub(r'<[^>]+>', '', p)
        prompt = (p.replace('&nbsp;', ' ').replace('&amp;', '&')
                  .replace('&lt;', '<').replace('&gt;', '>').strip())

    if not prompt and raw_text:
        # Если нет code-блока — используем весь текст поста как промпт
        prompt = raw_text

    return {'raw_text': raw_text, 'prompt': prompt} if prompt else None


# ─── DeepSeek ──────────────────────────────────────────────────────────────────

def convert_prompt(raw_prompt: str, title: str, tags: List[str], deepseek_key: str) -> Optional[str]:
    if 'женщины' in tags:
        gender_hint = 'ВАЖНО: персонаж — ЖЕНЩИНА. В разделе ПЕРСОНАЖ обязательно начни с "Молодая женщина".'
    elif 'мужчины' in tags:
        gender_hint = 'ВАЖНО: персонаж — МУЖЧИНА. В разделе ПЕРСОНАЖ обязательно начни с "Молодой мужчина".'
    elif 'дети' in tags:
        gender_hint = 'ВАЖНО: персонаж — РЕБЁНОК. В разделе ПЕРСОНАЖ обязательно начни с "Ребёнок".'
    elif 'семья' in tags:
        gender_hint = 'ВАЖНО: персонажи — СЕМЬЯ (мужчина, женщина, возможно дети). Опиши всех.'
    else:
        gender_hint = 'ВАЖНО: персонаж — ЖЕНЩИНА (по умолчанию). Начни с "Молодая женщина".'

    user_msg = (
        f'Название фотосессии: {title}\n\n'
        f'{gender_hint}\n\n'
        f'Исходный промпт из Telegram:\n{raw_prompt}\n\n'
        f'Преобразуй этот промпт в нашу структуру из 6 разделов.'
    )
    try:
        resp = requests.post(
            'https://api.deepseek.com/v1/chat/completions',
            headers={'Authorization': f'Bearer {deepseek_key}', 'Content-Type': 'application/json'},
            json={
                'model': 'deepseek-chat',
                'messages': [
                    {'role': 'system', 'content': DEEPSEEK_SYSTEM_PROMPT},
                    {'role': 'user', 'content': user_msg},
                ],
                'max_tokens': 2200,
                'temperature': 0.4,
            },
            timeout=60,
        )
        resp.raise_for_status()
        content = resp.json()['choices'][0]['message']['content'].strip()
        content = re.sub(r'^```[^\n]*\n?', '', content)
        content = re.sub(r'\n?```$', '', content)
        return content.strip() or None
    except Exception as e:
        print(f"    ❌ DeepSeek: {e}")
        return None


# ─── Nano Banana: генерация изображения ──────────────────────────────────────

def generate_image(prompt: str, piapi_key: str) -> Optional[str]:
    task_url = 'https://api.piapi.ai/api/v1/task'
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
            return None

        print(f"    📋 Task: {task_id}")
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
            print(f"    📊 [{attempt}] {status}")
            if status == 'completed':
                out = pdata.get('output', {})
                imgs = out.get('image_urls') or out.get('temporary_image_urls') or []
                if imgs:
                    return imgs[0]
                url = out.get('image_url') or out.get('temporary_image_url')
                return url
            if status in ('failed', 'error', 'cancelled'):
                print(f"    ❌ Задача завершилась со статусом: {status}")
                return None
        print("    ⏰ Таймаут генерации")
        return None
    except Exception as e:
        print(f"    ❌ PiAPI: {e}")
        return None


# ─── Основной алгоритм ────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Fix Preset Prompts & Previews')
    parser.add_argument('--limit', type=int, default=0,
                        help='Обработать не более N пресетов (0 = все)')
    parser.add_argument('--id', type=str, default='',
                        help='Обработать конкретный пресет по doc_id')
    parser.add_argument('--dry-run', action='store_true',
                        help='Без записи в Firebase и без генерации изображений')
    parser.add_argument('--skip-image', action='store_true',
                        help='Только перегенерировать промпт, не пересоздавать изображение')
    args = parser.parse_args()

    print("═══════════════════════════════════════════════════")
    print("  FIX PRESET PROMPTS  Firebase → Telegram → DeepSeek → Nano Banana")
    print("═══════════════════════════════════════════════════\n")

    if args.dry_run:
        print("🔍 DRY-RUN: без записи в Firebase\n")

    env = load_env()
    piapi_key = env.get('PIAPI_API_KEY', '').strip()
    deepseek_key = env.get('DEEPSEEK_API_KEY', '').strip()

    if not deepseek_key:
        print("❌ DEEPSEEK_API_KEY не найден в .env"); sys.exit(1)
    if not args.skip_image and not piapi_key:
        print("❌ PIAPI_API_KEY не найден в .env (используй --skip-image если не нужна перегенерация)"); sys.exit(1)

    sa = load_service_account() if not args.dry_run else {}
    project_id = sa.get('project_id', 'photosession-ai-cbfc3') if sa else 'photosession-ai-cbfc3'

    print("🔐 Получение Firebase токена...")
    token = get_firebase_token(sa) if not args.dry_run else ''
    if not args.dry_run:
        print("✅ Токен получен\n")

    print("📥 Загрузка пресетов из Firebase...")
    presets = get_all_presets(token, project_id) if not args.dry_run else []
    print(f"   Всего пресетов: {len(presets)}\n")

    # Фильтруем: только пресеты из Telegram (не пользовательские)
    candidates = [
        p for p in presets
        if p.get('sourceChannel') and p.get('sourcePostId') and not p.get('ownerId')
    ]

    if args.id:
        candidates = [p for p in candidates if p['doc_id'] == args.id]
        if not candidates:
            print(f"❌ Пресет {args.id} не найден или не из Telegram")
            return

    if args.limit > 0:
        candidates = candidates[:args.limit]

    print(f"📋 Пресетов для перегенерации: {len(candidates)}\n")

    success = fail = skipped = 0

    for idx, preset in enumerate(candidates, 1):
        title = preset['title']
        channel = preset['sourceChannel']
        post_id = preset['sourcePostId']
        tags = preset['tags']

        print(f"─────────────────────────────────────────────────")
        print(f"[{idx}/{len(candidates)}] {preset['doc_id']}")
        print(f"  📌 {title}")
        print(f"  🏷  {', '.join(tags)}")
        print(f"  📡 Источник: @{channel}/{post_id}")

        if args.dry_run:
            print("  [dry-run] Пропускаем")
            skipped += 1
            continue

        # 1. Загружаем оригинальный Telegram-пост
        print("  📡 Загрузка оригинального поста из Telegram...")
        tg_post = fetch_telegram_post(channel, post_id)
        if not tg_post:
            print(f"  ⚠️  Пост @{channel}/{post_id} недоступен — пропускаем")
            skipped += 1
            continue
        raw_prompt = tg_post['prompt']
        preview_raw = raw_prompt[:100].replace('\n', ' ')
        print(f"  💬 Сырой промпт: {preview_raw}...")

        # 2. Конвертируем через DeepSeek (улучшенный промпт)
        print(f"  🤖 DeepSeek: структурируем промпт...")
        structured = convert_prompt(raw_prompt, title, tags, deepseek_key)
        if not structured:
            print("  ❌ DeepSeek не вернул результат — пропускаем")
            fail += 1
            continue
        preview_struct = structured[:120].replace('\n', ' ')
        print(f"  ✅ Структура: {preview_struct}...")

        new_image_url = None

        if not args.skip_image:
            # 3. Перегенерируем изображение
            print("  🎨 Генерация нового превью (Nano Banana)...")
            new_image_url = generate_image(structured, piapi_key)
            if not new_image_url:
                print("  ⚠️  Изображение не сгенерировано — обновляем только промпт")

        # 4. Обновляем Firebase
        # Обновляем токен каждые 50 пресетов (токен живёт ~1 час)
        if idx % 50 == 0:
            token = get_firebase_token(sa)

        print("  🔥 Обновление в Firebase...")
        # Если изображение не пересоздавалось — передаём пустую строку,
        # чтобы не затирать старый URL (fetch_current_image_url не нужен)
        final_image = new_image_url or ''
        if final_image:
            ok = update_preset_in_firestore(token, preset['doc_name'], structured, final_image)
        else:
            # Обновляем только промпт
            url = (
                f'https://firestore.googleapis.com/v1/{preset["doc_name"]}'
                f'?updateMask.fieldPaths=prompt'
                f'&updateMask.fieldPaths=updatedAt'
            )
            body = {
                'fields': {
                    'prompt': {'stringValue': structured},
                    'updatedAt': {'stringValue': datetime.now().isoformat()},
                }
            }
            r = requests.patch(
                url,
                headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
                json=body,
                timeout=30,
            )
            ok = r.status_code in (200, 201)

        if ok:
            img_status = '+ новое изображение' if final_image else '(изображение без изменений)'
            print(f"  ✅ Обновлено {img_status}")
            success += 1
        else:
            print(f"  ❌ Ошибка обновления Firebase")
            fail += 1

        time.sleep(1)

    print("\n═══════════════════════════════════════════════════")
    print("📊 ИТОГИ")
    print("═══════════════════════════════════════════════════")
    print(f"✅ Обновлено:  {success}")
    print(f"⏭  Пропущено: {skipped}")
    print(f"❌ Ошибки:    {fail}")
    print()


if __name__ == '__main__':
    main()
