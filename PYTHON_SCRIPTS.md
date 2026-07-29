# Python-скрипты: пресеты, лайки, Firebase

Все команды выполнять из **корня репозитория** (`Photosession-AI/`).

## Подготовка окружения

```bash
cd /path/to/Photosession-AI
pip3 install -r tool/requirements.txt
pip3 install PyJWT cryptography
```

Дополнительно для `tool/upload_via_python.py` и `tool/migrate_appwrite_to_firebase.py` нужен **firebase-admin** (уже в `tool/requirements.txt`).

### Файлы и секреты

| Что | Где |
|-----|-----|
| Service Account (Firestore REST, JWT) | `firebase-service-account.json` **или** `tool/firebase-service-account.json` |
| Ключи API и проект | корневой `.env` |

Типичные переменные в `.env` (зависят от скрипта):

- `PIAPI_API_KEY`, `DEEPSEEK_API_KEY` — пайплайн генерации и правки промптов
- `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY` — `clean_broken_presets.py`, `migrate_simple.py`
- Для миграции Appwrite: `APPWRITE_*` (см. `tool/MIGRATION_README.md`)

Скрипты с генерацией читают `.env` из корня проекта.

---

## Основной поток: новые пресеты из Telegram

**`tool/preset_pipeline.py`** — парсинг каналов → DeepSeek (структура промпта) → Nano Banana (превью) → запись в Firestore.

Учитывает `tool/processed_posts.json`, чтобы не дублировать посты.

```bash
python3 -u tool/preset_pipeline.py
python3 -u tool/preset_pipeline.py --limit 5
python3 -u tool/preset_pipeline.py --limit 50
python3 -u tool/preset_pipeline.py --channel photosesser --limit 10
python3 -u tool/preset_pipeline.py --channel clickpickstyle
python3 -u tool/preset_pipeline.py --dry-run
```

| Флаг | Назначение |
|------|------------|
| `--limit N` | Обработать не более N новых постов (`0` = без лимита после отбора новых) |
| `--channel` | Только `photosesser` или `clickpickstyle` |
| `--dry-run` | Без запросов к API и без записи в БД |

---

## Лайки (синтетические для витрины)

**`tool/seed_preset_likes.py`** — для каждого документа в коллекции задаёт случайное число лайков в диапазоне и заполняет `likedBy` синтетическими id вида `seed_*`. Реальные id пользователей **не удаляет**; старые `seed_*` пересоздаёт при новом запуске.

```bash
python3 -u tool/seed_preset_likes.py
python3 -u tool/seed_preset_likes.py --dry-run
python3 -u tool/seed_preset_likes.py --min 10 --max 40
python3 -u tool/seed_preset_likes.py --collection presets
python3 -u tool/seed_preset_likes.py --seed 42
```

| Флаг | Назначение |
|------|------------|
| `--min` / `--max` | Диапазон итогового числа лайков (по умолчанию 5–50) |
| `--collection` | Имя коллекции Firestore (по умолчанию `presets`) |
| `--dry-run` | Только вывод, без записи |
| `--seed` | Фиксированный seed для `random` |

Нужен **Service Account** (см. таблицу выше).

**`tool/seed_preset_likes_zero.py`** — то же правило (случайное число лайков в диапазоне, `seed_*`, реальные id не трогает), но обрабатываются **только** документы, у которых сейчас **0 лайков**. Критерий нуля: поле `likesCount` равно 0 или отсутствует; если `likesCount` нет — считается длина массива `likedBy` (пустой массив = 0). Остальные пресеты пропускаются. Внутри переиспользует `tool/seed_preset_likes.py` (запускать из корня репозитория).

```bash
python3 -u tool/seed_preset_likes_zero.py --dry-run
python3 -u tool/seed_preset_likes_zero.py --min 10 --max 40
python3 -u tool/seed_preset_likes_zero.py --collection presets --seed 42
```

Флаги те же, что у `seed_preset_likes.py`: `--min`, `--max`, `--collection`, `--dry-run`, `--seed`.

---

## Правка существующих пресетов в Firebase

### Только текст промптов (без картинок)

**`tool/upgrade_prompts.py`** — прогон существующих структурированных промптов через DeepSeek по новым правилам, без перегенерации превью.

```bash
python3 -u tool/upgrade_prompts.py
python3 -u tool/upgrade_prompts.py --limit 10
python3 -u tool/upgrade_prompts.py --id preset_xxxxxxxx
python3 -u tool/upgrade_prompts.py --dry-run
python3 -u tool/upgrade_prompts.py --force
python3 -u tool/upgrade_prompts.py --include-custom
```

| Флаг | Назначение |
|------|------------|
| `--limit N` | Не более N пресетов (`0` = все) |
| `--id` | Один документ по id |
| `--dry-run` | Без записи в Firebase |
| `--force` | Обрабатывать и уже «обновлённые» по меткам скрипта |
| `--include-custom` | Включить пользовательские пресеты (`ownerId`); по умолчанию они пропускаются |

### Промпт + превью из исходного Telegram-поста

**`tool/fix_preset_prompts.py`** — для пресетов с `sourceChannel` + `sourcePostId`: снова тянет пост, DeepSeek, Nano Banana, PATCH в Firebase.

```bash
python3 -u tool/fix_preset_prompts.py
python3 -u tool/fix_preset_prompts.py --limit 5
python3 -u tool/fix_preset_prompts.py --id preset_xxxxxxxx
python3 -u tool/fix_preset_prompts.py --dry-run
python3 -u tool/fix_preset_prompts.py --skip-image
```

| Флаг | Назначение |
|------|------------|
| `--skip-image` | Обновить только промпт, не пересоздавать изображение |

### Теги в Firestore

**`tool/fix_preset_tags.py`** — нормализация/перевод тегов по правилам внутри скрипта.

```bash
python3 -u tool/fix_preset_tags.py
python3 -u tool/fix_preset_tags.py --dry-run
```

---

## Очистка сломанных пресетов

**`tool/clean_broken_presets.py`** — загрузка пресетов через Firestore REST с **web API key** (`FIREBASE_API_KEY` в `.env`), проверка `previewImageUrl` (HEAD), удаление документов с битыми/пустыми URL.

```bash
python3 tool/clean_broken_presets.py
```

**Внимание:** скрипт после анализа **сразу удаляет** сломанные документы; отдельного `--dry-run` нет.

---

## Загрузка готового JSON в Firestore

Источник данных: **`tool/generated_presets.json`** (часто получают через Dart, см. подсказки в скриптах).

### Через REST + Service Account

```bash
python3 tool/upload_with_service_account.py
```

### Через Firebase Admin SDK

```bash
python3 tool/upload_via_python.py
```

Требуется ADC (`gcloud auth application-default login`) или правка скрипта под путь к JSON ключу (см. комментарии в файле). В скрипте зашит пример `projectId` — при необходимости приведите к своему проекту.

---

## Миграция Appwrite → Firebase

| Скрипт | Подход |
|--------|--------|
| `tool/migrate_simple.py` | Упрощённый: REST, переменные из `.env` без `python-dotenv` |
| `tool/migrate_appwrite_to_firebase.py` | Расширенный: `firebase_admin`, `python-dotenv`, перенос файлов и коллекций |

```bash
python3 tool/migrate_simple.py
python3 tool/migrate_appwrite_to_firebase.py
```

Детали переменных и порядок действий: **`tool/MIGRATION_README.md`**, **`tool/QUICK_MIGRATION.md`**.

---

## Смежные инструменты (не Python)

- Dart/JS утилиты в **`tool/`** (загрузка, переводы, тесты) — смотри имена файлов `*.dart`, `*.js`.
- Обслуживание пресетов на стороне Firebase: скрипты в **`functions/`** (Node.js), например бэкфилл миниатюр.

---

## Краткая шпаргалка

| Задача | Команда |
|--------|---------|
| Новые пресеты из TG | `python3 -u tool/preset_pipeline.py [--limit N] [--channel …]` |
| Синтетические лайки (все пресеты) | `python3 -u tool/seed_preset_likes.py [--dry-run] [--min M --max M]` |
| Лайки только у пресетов с 0 | `python3 -u tool/seed_preset_likes_zero.py [--dry-run] [--min M --max M]` |
| Улучшить текст промптов | `python3 -u tool/upgrade_prompts.py [--limit N\|--id …]` |
| Пересобрать промпт+превью из TG | `python3 -u tool/fix_preset_prompts.py [--limit N\|--id …]` |
| Починить теги | `python3 -u tool/fix_preset_tags.py [--dry-run]` |
| Удалить пресеты с битым preview | `python3 tool/clean_broken_presets.py` |
| Залить JSON пресетов | `python3 tool/upload_with_service_account.py` или `upload_via_python.py` |
