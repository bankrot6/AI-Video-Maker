#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Пайплайн только для мужских фотосессий: те же шаги, что preset_pipeline.py,
но отбор постов под мужской персонаж и нормализация тегов для DeepSeek.

Дедупликация:
  - tool/processed_posts.json (как основной скрипт)
  - пары channel|postId из Firestore presets (как functions/preset_pipeline_runner.js)

Запуск:
  python3 -u tool/preset_pipeline_male.py --limit 5
  python3 -u tool/preset_pipeline_male.py --heuristic --limit 10
  python3 -u tool/preset_pipeline_male.py --channel photosesser --dry-run
"""

from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime
from typing import List

import preset_pipeline as pp

MALE_HINT_KEYWORDS = (
    'мужчин',
    'мужской',
    'мужская',
    'парень',
    'бород',
    'борода',
    'джентльмен',
    'гентльмен',
    'смокинг',
    'костюм',
    'пиджак',
    'жилетк',
    'галстук',
    'бабочка',
    'оксфорд',
    'лофер',
    'барбер',
    'жених',
    'groom',
    'male model',
    ' his ',
    ' man ',
    ' men ',
    ' businessman',
)

FEMALE_STRONG_HINTS = (
    'девушк',
    'женщин',
    'невест',
    'платье',
    'юбк',
    'каблук',
    'шпильк',
    'корсет',
    'блузк',
    'мини-плать',
    'беременн',
)


def is_male_session_candidate(post: dict, heuristic: bool) -> bool:
    tags = post.get('tags') or []
    if 'дети' in tags:
        return False
    if 'семья' in tags:
        return False
    if 'мужчины' in tags:
        return 'женщины' not in tags
    if not heuristic:
        return False
    blob = f"{post.get('prompt', '')} {post.get('title', '')}".lower()
    if not any(k in blob for k in MALE_HINT_KEYWORDS):
        return False
    if any(k in blob for k in FEMALE_STRONG_HINTS):
        return False
    return True


def tags_for_male_preset(tags: List[str]) -> List[str]:
    base = [t for t in tags if t not in pp.GENDER_TAGS]
    base.append('мужчины')
    return sorted(set(base))[:6]


def main():
    parser = argparse.ArgumentParser(description='Preset Pipeline — только мужские фотосессии')
    parser.add_argument('--limit', type=int, default=0, help='Максимум постов (0 = все отобранные)')
    parser.add_argument('--channel', type=str, default='', help='photosesser или clickpickstyle')
    parser.add_argument('--dry-run', action='store_true', help='Без API и без записи в БД')
    parser.add_argument(
        '--heuristic',
        action='store_true',
        help='Включить посты без тега «мужчины», но с явными мужскими формулировками в тексте',
    )
    parser.add_argument(
        '--max-pages',
        type=int,
        default=20,
        metavar='N',
        help='Сколько страниц t.me пролистать на канал (больше — глубже в архив, больше кандидатов)',
    )
    args = parser.parse_args()

    print('═══════════════════════════════════════════════════')
    print('  PRESET PIPELINE (MALE)  Telegram → DeepSeek → Nano Banana → Firebase')
    print('═══════════════════════════════════════════════════\n')

    if args.dry_run:
        print('🔍 DRY-RUN — без записи в БД\n')

    env = pp.load_env()
    piapi_key = env.get('PIAPI_API_KEY', '').strip()
    deepseek_key = env.get('DEEPSEEK_API_KEY', '').strip()

    if not args.dry_run:
        if not piapi_key:
            print('❌ PIAPI_API_KEY не найден в .env')
            sys.exit(1)
        if not deepseek_key:
            print('❌ DEEPSEEK_API_KEY не найден в .env')
            sys.exit(1)

    sa = pp.load_service_account() if not args.dry_run else {}
    project_id = sa.get('project_id', 'photosession-ai-cbfc3')

    processed = pp.load_processed()
    channels = [args.channel] if args.channel else pp.CHANNELS

    firebase_token = None
    if not args.dry_run:
        print('🔐 Получение Firebase токена...')
        try:
            firebase_token = pp.get_firebase_token(sa)
            print('✅ Токен получен\n')
        except Exception as e:
            print(f'❌ Ошибка токена Firebase: {e}')
            sys.exit(1)

    firestore_tg_keys: set = set()
    if not args.dry_run and firebase_token:
        print('🔍 Дедупликация: channel|postId из Firestore presets...')
        try:
            firestore_tg_keys = pp.collect_telegram_source_keys(firebase_token, project_id)
            print(f'   Уже в каталоге по Telegram-источнику: {len(firestore_tg_keys)}')
        except Exception as e:
            print(f'  ⚠️  Не удалось загрузить ключи: {e}')

    all_new: list = []
    for ch in channels:
        print(f'📡 Парсинг @{ch} (до {args.max_pages} стр., глубокий проход для редких мужских постов)...')
        max_fetch = max(400, (args.limit or 50) * 25)
        posts = pp.parse_channel(ch, max_posts=max_fetch, max_pages=args.max_pages)
        known = set(processed.get(ch, []))
        fresh = [
            p
            for p in posts
            if p['id'] not in known and f"{ch}|{p['id']}" not in firestore_tg_keys
        ]
        male_posts = [p for p in fresh if is_male_session_candidate(p, args.heuristic)]
        print(
            f'   Лента: {len(posts)} | новых: {len(fresh)} | '
            f'мужских (кандидатов): {len(male_posts)}'
        )
        all_new.extend(male_posts)

    if not all_new:
        print('\n✅ Нет новых мужских постов. Попробуйте --heuristic или зайдите позже.')
        return

    if args.limit > 0 and len(all_new) < args.limit:
        print(
            f'\n⚠️  Мужских кандидатов {len(all_new)} < --limit {args.limit}: '
            'обработаются все найденные. Добавьте --heuristic и/или --max-pages 30 для большего охвата.\n'
        )

    tag_counts: dict = {}
    if not args.dry_run and firebase_token:
        print('\n📊 Баланс тегов в каталоге...')
        tag_counts = pp.get_firebase_tag_counts(firebase_token, project_id)
        if tag_counts:
            mc = tag_counts.get('мужчины', 0)
            print(f'   Сейчас пресетов с тегом «мужчины»: {mc}')

    all_new = pp.sort_posts_smart(all_new, tag_counts)

    if args.limit > 0:
        all_new = all_new[: args.limit]

    print(f'\n📋 К обработке (мужские): {len(all_new)} постов\n')

    success = fail = skipped = 0

    for idx, post in enumerate(all_new, 1):
        ch = post['channel']
        post_id = post['id']
        title = post['title']
        male_tags = tags_for_male_preset(post['tags'])

        print('─────────────────────────────────────────────────')
        print(f"[{idx}/{len(all_new)}] @{ch}/{post_id}  👁 {post['views']}  ❤ {post['reactions']}")
        print(f'  📌 {title}')
        print(f'  🏷  {", ".join(male_tags)}')

        if args.dry_run:
            skipped += 1
            print('  [dry-run] пропуск\n')
            continue

        try:
            print('  🤖 DeepSeek (структура, персонаж — мужчина)...')
            structured = pp.convert_prompt_to_structure(
                post['prompt'], title, deepseek_key, tags=male_tags
            )
            if not structured:
                print('  ❌ DeepSeek не вернул текст\n')
                fail += 1
                continue

            print('  🎨 Nano Banana...')
            image_url = pp.generate_image(structured, piapi_key)
            if not image_url:
                print('  ❌ Нет изображения\n')
                fail += 1
                continue

            firebase_token = pp.get_firebase_token(sa)
            print('  🔥 Firestore...')
            preset_doc = {
                'title': title,
                'prompt': structured,
                'previewImageUrl': image_url,
                'tags': male_tags,
                'createdAt': datetime.now().isoformat(),
                'sourceChannel': ch,
                'sourcePostId': post_id,
            }
            doc_id = pp.upload_to_firestore(firebase_token, project_id, preset_doc)
            print(f'  ✅ {doc_id}\n')

            if ch not in processed:
                processed[ch] = []
            processed[ch].append(post_id)
            pp.save_processed(processed)

            success += 1
            time.sleep(1)
        except Exception as e:
            print(f'  ❌ {e}\n')
            fail += 1

    print('═══════════════════════════════════════════════════')
    print('📊 ИТОГИ (male pipeline)')
    print('═══════════════════════════════════════════════════')
    if args.dry_run:
        print(f'🔍 Кандидатов: {skipped}')
    else:
        print(f'✅ Успешно: {success}')
        print(f'❌ Ошибки: {fail}')
        print(f'💾 Дедуп: {pp.PROCESSED_FILE}')
    print()


if __name__ == '__main__':
    main()
