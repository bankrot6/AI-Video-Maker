#!/usr/bin/env python3
"""
Миграция пресетов Firebase Firestore → Appwrite
Использует только встроенные библиотеки Python (без pip install!)

Запуск: python3 scripts/migrate.py
"""

import hashlib
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
import urllib.parse
from pathlib import Path

# ─────────────────────────────────────────────
# КОНФИГУРАЦИЯ
# ─────────────────────────────────────────────

PROJECT_ROOT = Path(__file__).parent.parent
ENV_FILE     = PROJECT_ROOT / ".env"

FIREBASE_COLLECTION = "presets"
APPWRITE_DATABASE   = "main"
APPWRITE_COLLECTION = "presets"

BATCH_DELAY = 0.3   # секунд между записями в Appwrite
RETRY_COUNT = 3

# ─────────────────────────────────────────────
# ЗАГРУЗКА .ENV
# ─────────────────────────────────────────────

def load_env(path: Path) -> dict:
    env = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        env[key.strip()] = val.strip()
    return env

ENV = load_env(ENV_FILE)

FIREBASE_API_KEY  = ENV.get("FIREBASE_API_KEY", "")
FIREBASE_PROJECT  = ENV.get("FIREBASE_PROJECT_ID", "")
APPWRITE_ENDPOINT = ENV.get("APPWRITE_ENDPOINT", "").rstrip("/")
APPWRITE_PROJECT  = ENV.get("APPWRITE_PROJECT_ID", "")
APPWRITE_API_KEY  = ENV.get("APPWRITE_API_KEY", "")

# ─────────────────────────────────────────────
# HTTP УТИЛИТЫ
# ─────────────────────────────────────────────

def http_request(method: str, url: str, headers: dict = None, data: dict = None) -> dict:
    body = json.dumps(data).encode() if data else None
    req  = urllib.request.Request(url, data=body, method=method)
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode()
        try:
            return json.loads(body_text)
        except Exception:
            return {"error": True, "message": body_text, "code": e.code}

def appwrite_headers() -> dict:
    return {
        "X-Appwrite-Project": APPWRITE_PROJECT,
        "X-Appwrite-Key":     APPWRITE_API_KEY,
    }

# ─────────────────────────────────────────────
# ШАГ 1: СОЗДАНИЕ СХЕМЫ APPWRITE
# ─────────────────────────────────────────────

def create_database():
    print("📊 Создание базы данных 'main'...")
    r = http_request("POST", f"{APPWRITE_ENDPOINT}/databases",
                     appwrite_headers(),
                     {"databaseId": "main", "name": "Main Database", "enabled": True})
    if r.get("$id") or r.get("code") == 409:
        print("   ✅ База данных готова")
    else:
        print(f"   ⚠️  {r.get('message', r)}")
    time.sleep(1)

def create_collection():
    print("📁 Создание коллекции 'presets'...")
    r = http_request("POST",
                     f"{APPWRITE_ENDPOINT}/databases/{APPWRITE_DATABASE}/collections",
                     appwrite_headers(),
                     {
                         "collectionId": APPWRITE_COLLECTION,
                         "name": "Presets",
                         "permissions": ['read("any")', 'write("any")'],
                         "documentSecurity": False,
                         "enabled": True,
                     })
    created = bool(r.get("$id"))
    if r.get("code") == 409:
        print("   ⚠️  Коллекция уже существует — добавляем атрибуты (если нет)")
    elif created:
        print("   ✅ Коллекция создана")
    else:
        print(f"   ⚠️  {r.get('message', r)}")
    time.sleep(1)

    # Атрибуты
    attrs = [
        ("string",   "prompt",          {"size": 4000, "required": True}),
        ("string",   "previewImageUrl",  {"size": 1000, "required": True}),
        ("string",   "thumbnailUrl",     {"size": 1000, "required": False}),
        ("string",   "title",            {"size": 500,  "required": False}),
        ("string",   "tags",             {"size": 500,  "required": False, "array": True}),
        ("string",   "ownerId",          {"size": 255,  "required": False}),
        ("string",   "likedBy",          {"size": 255,  "required": False, "array": True}),
        ("boolean",  "isPublic",         {"required": False, "default": False}),
        ("integer",  "likesCount",       {"required": False, "default": 0, "min": 0, "max": 9999999}),
        ("datetime", "createdAt",        {"required": False}),
    ]

    print("   ⚙️  Добавление атрибутов...")
    for attr_type, key, params in attrs:
        payload = {"key": key, **params}
        url = f"{APPWRITE_ENDPOINT}/databases/{APPWRITE_DATABASE}/collections/{APPWRITE_COLLECTION}/attributes/{attr_type}"
        r = http_request("POST", url, appwrite_headers(), payload)
        if r.get("key") or r.get("code") == 409:
            print(f"      • {key}: ✅")
        else:
            print(f"      • {key}: ⚠️  {r.get('message', r)}")
        time.sleep(0.6)

    print("   ✅ Атрибуты добавлены")
    print("   ⏳ Ждём 5 секунд пока Appwrite индексирует атрибуты...")
    time.sleep(5)

    # Индекс для сортировки по createdAt — необходим для правильного порядка пресетов
    print("   📑 Создание индекса createdAt...")
    idx_url = f"{APPWRITE_ENDPOINT}/databases/{APPWRITE_DATABASE}/collections/{APPWRITE_COLLECTION}/indexes"
    ri = http_request("POST", idx_url, appwrite_headers(), {
        "key": "idx_createdAt_desc",
        "type": "key",
        "attributes": ["createdAt"],
        "orders": ["DESC"],
    })
    if ri.get("key") or ri.get("code") == 409:
        print("      • idx_createdAt_desc: ✅")
    else:
        print(f"      • idx_createdAt_desc: ⚠️  {ri.get('message', ri)}")
    print("   ⏳ Ждём 8 секунд пока Appwrite строит индекс...")
    time.sleep(8)


def create_user_generations_collection():
    coll_id = "user_generations"
    print(f"📁 Создание коллекции '{coll_id}'...")
    r = http_request("POST",
                     f"{APPWRITE_ENDPOINT}/databases/{APPWRITE_DATABASE}/collections",
                     appwrite_headers(),
                     {
                         "collectionId": coll_id,
                         "name": "User Generations",
                         "permissions": ['read("any")', 'write("any")'],
                         "documentSecurity": False,
                         "enabled": True,
                     })
    created = bool(r.get("$id"))
    if r.get("code") == 409:
        print("   ⚠️  Коллекция уже существует — добавляем атрибуты (если нет)")
    elif created:
        print("   ✅ Коллекция создана")
    else:
        print(f"   ⚠️  {r.get('message', r)}")
    time.sleep(1)

    attrs = [
        ("string",   "presetId",          {"size": 255,  "required": True}),
        ("string",   "userImageUrl",       {"size": 1000, "required": True}),
        ("string",   "resultImageUrl",     {"size": 1000, "required": True}),
        ("string",   "deviceId",           {"size": 255,  "required": True}),
        ("string",   "referenceImageUrl",  {"size": 1000, "required": False}),
        ("datetime", "createdAt",          {"required": False}),
    ]

    print("   ⚙️  Добавление атрибутов...")
    for attr_type, key, params in attrs:
        payload = {"key": key, **params}
        url = f"{APPWRITE_ENDPOINT}/databases/{APPWRITE_DATABASE}/collections/{coll_id}/attributes/{attr_type}"
        r2 = http_request("POST", url, appwrite_headers(), payload)
        if r2.get("key") or r2.get("code") == 409:
            print(f"      • {key}: ✅")
        else:
            print(f"      • {key}: ⚠️  {r2.get('message', r2)}")
        time.sleep(0.6)

    print("   ✅ Атрибуты добавлены")
    time.sleep(3)


# ─────────────────────────────────────────────
# ШАГ 2: ЧТЕНИЕ ИЗ FIREBASE
# ─────────────────────────────────────────────

def firebase_value(v: dict):
    """Парсинг Firestore typed value → Python."""
    if "stringValue"    in v: return v["stringValue"]
    if "booleanValue"   in v: return v["booleanValue"]
    if "integerValue"   in v: return int(v["integerValue"])
    if "doubleValue"    in v: return float(v["doubleValue"])
    if "timestampValue" in v: return v["timestampValue"]
    if "nullValue"      in v: return None
    if "arrayValue"     in v:
        vals = v["arrayValue"].get("values", [])
        return [firebase_value(i) for i in vals]
    if "mapValue"       in v:
        fields = v["mapValue"].get("fields", {})
        return {k: firebase_value(fv) for k, fv in fields.items()}
    return None

def fetch_firebase_presets() -> list:
    """Загрузка всех документов из Firestore через REST API."""
    print(f"\n🔥 Загрузка пресетов из Firebase (проект: {FIREBASE_PROJECT})...")
    presets = []
    page_token = None

    while True:
        url = (
            f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT}"
            f"/databases/(default)/documents/{FIREBASE_COLLECTION}"
            f"?key={FIREBASE_API_KEY}&pageSize=300"
        )
        if page_token:
            url += f"&pageToken={page_token}"

        r = http_request("GET", url)

        if "error" in r and r["error"] is True:
            print(f"   ❌ Ошибка Firebase: {r.get('message', r)}")
            break

        if "error" in r and isinstance(r["error"], dict):
            print(f"   ❌ Ошибка Firebase: {r['error'].get('message', r)}")
            break

        documents = r.get("documents", [])
        for doc in documents:
            name   = doc.get("name", "")
            doc_id = name.rsplit("/", 1)[-1] if "/" in name else name
            fields = {k: firebase_value(v) for k, v in doc.get("fields", {}).items()}
            fields["_id"] = doc_id
            presets.append(fields)

        page_token = r.get("nextPageToken")
        print(f"   • Загружено: {len(presets)} документов")
        if not page_token:
            break
        time.sleep(0.5)

    print(f"   ✅ Всего из Firebase: {len(presets)} пресетов\n")
    return presets

# ─────────────────────────────────────────────
# ШАГ 3: ЗАПИСЬ В APPWRITE
# ─────────────────────────────────────────────

def write_to_appwrite(presets: list):
    """Запись всех пресетов в Appwrite."""
    total    = len(presets)
    migrated = 0
    skipped  = 0
    errors   = 0
    url      = f"{APPWRITE_ENDPOINT}/databases/{APPWRITE_DATABASE}/collections/{APPWRITE_COLLECTION}/documents"

    print(f"🚀 Запись {total} пресетов в Appwrite...")
    print("─" * 50)

    for i, preset in enumerate(presets, 1):
        raw_id = preset.get("_id", "")
        # Appwrite: max 36 chars, only a-z A-Z 0-9 period hyphen underscore
        safe_id = re.sub(r'[^a-zA-Z0-9._-]', '_', raw_id)
        if len(safe_id) > 36:
            safe_id = hashlib.md5(raw_id.encode()).hexdigest()[:36]
        doc_id = safe_id if safe_id else "unique()"

        # Маппинг Firebase полей → Appwrite
        prompt          = preset.get("prompt", "")
        preview_url     = preset.get("previewImageUrl") or preset.get("preview_image_url", "")
        thumbnail_url   = preset.get("thumbnailUrl") or preset.get("thumbnail_url")
        title           = preset.get("title")
        tags            = preset.get("tags") or []
        owner_id        = preset.get("ownerId") or preset.get("owner_id")
        is_public       = preset.get("isPublic", False)
        likes_count     = preset.get("likesCount", 0)
        liked_by        = preset.get("likedBy") or []
        created_at      = preset.get("createdAt") or preset.get("created_at")

        # Пропускаем пустые
        if not prompt or not preview_url:
            print(f"   [{i}/{total}] ⏭️  Пропуск (нет prompt/previewImageUrl): {doc_id}")
            skipped += 1
            continue

        # Очистка данных
        if isinstance(tags, list):
            tags = [str(t) for t in tags if t][:10]
        else:
            tags = []

        if isinstance(liked_by, list):
            liked_by = [str(x) for x in liked_by if x]
        else:
            liked_by = []

        if isinstance(likes_count, float):
            likes_count = int(likes_count)
        elif not isinstance(likes_count, int):
            likes_count = 0

        data = {
            "prompt":         str(prompt)[:4000],
            "previewImageUrl": str(preview_url)[:1000],
            "isPublic":       bool(is_public),
            "likesCount":     likes_count,
        }
        if thumbnail_url:
            data["thumbnailUrl"] = str(thumbnail_url)[:1000]
        if title:
            data["title"] = str(title)[:500]
        if tags:
            data["tags"] = tags
        if owner_id:
            data["ownerId"] = str(owner_id)[:255]
        if liked_by:
            data["likedBy"] = liked_by
        if created_at:
            data["createdAt"] = str(created_at)

        payload = {
            "documentId": doc_id,
            "data":        data,
            "permissions": ['read("any")'],
        }

        # Попытки с повтором
        success = False
        r = {}
        for attempt in range(1, RETRY_COUNT + 1):
            try:
                r = http_request("POST", url, appwrite_headers(), payload)
            except Exception as e:
                msg = str(e)[:80]
                print(f"   [{i}/{total}] ⚠️  Попытка {attempt} (сеть): {msg}")
                time.sleep(attempt * 2)
                continue

            if r.get("$id"):
                success = True
                break
            elif r.get("code") == 409:
                skipped += 1
                success = True
                break
            elif r.get("code") in (429, 503):
                wait = attempt * 2
                print(f"   [{i}/{total}] ⏳ Лимит запросов, ждём {wait}с...")
                time.sleep(wait)
            else:
                msg = r.get("message", str(r))[:100]
                print(f"   [{i}/{total}] ⚠️  Попытка {attempt}: {msg}")
                time.sleep(1)

        if success and r.get("$id"):
            migrated += 1
            print(f"   [{i}/{total}] ✅ {doc_id[:36]}")
        elif success and r.get("code") == 409:
            print(f"   [{i}/{total}] ⏭️  Уже есть: {doc_id[:36]}")
        elif not success:
            errors += 1
            print(f"   [{i}/{total}] ❌ Ошибка: {doc_id}")

        time.sleep(BATCH_DELAY)

    return migrated, skipped, errors

# ─────────────────────────────────────────────
# ОСНОВНОЙ ПОТОК
# ─────────────────────────────────────────────

def validate_config():
    missing = []
    if not FIREBASE_API_KEY:  missing.append("FIREBASE_API_KEY")
    if not FIREBASE_PROJECT:  missing.append("FIREBASE_PROJECT_ID")
    if not APPWRITE_ENDPOINT: missing.append("APPWRITE_ENDPOINT")
    if not APPWRITE_PROJECT:  missing.append("APPWRITE_PROJECT_ID")
    if not APPWRITE_API_KEY:  missing.append("APPWRITE_API_KEY")
    if missing:
        print(f"❌ Отсутствуют переменные в .env: {', '.join(missing)}")
        sys.exit(1)

def main():
    print("=" * 55)
    print("  🔄  Firebase Firestore → Appwrite Migration")
    print("=" * 55)
    print(f"  Firebase: {FIREBASE_PROJECT}")
    print(f"  Appwrite: {APPWRITE_ENDPOINT}")
    print(f"  Project:  {APPWRITE_PROJECT}")
    print("=" * 55)
    print()

    validate_config()

    # ШАГ 1: Создание схемы
    create_database()
    create_collection()
    create_user_generations_collection()

    # ШАГ 2: Загрузка из Firebase
    presets = fetch_firebase_presets()

    if not presets:
        print("⚠️  Нет данных для миграции. Проверьте правила Firestore.")
        print()
        print("Если Firestore требует авторизацию, добавьте в правила:")
        print('  match /presets/{doc} { allow read: if true; }')
        sys.exit(0)

    # ШАГ 3: Запись в Appwrite
    start = time.time()
    migrated, skipped, errors = write_to_appwrite(presets)
    elapsed = time.time() - start

    # Итоговый отчёт
    print()
    print("=" * 55)
    print("  🎉  МИГРАЦИЯ ЗАВЕРШЕНА!")
    print("=" * 55)
    print(f"  Всего из Firebase:  {len(presets)}")
    print(f"  Перенесено:         {migrated}")
    print(f"  Уже существовали:   {skipped}")
    print(f"  Ошибки:             {errors}")
    print(f"  Время:              {elapsed:.1f}с")
    print("=" * 55)
    print()
    print("📱 Проверьте в Appwrite Console:")
    print(f"   http://158.160.254.66/console")
    print()

if __name__ == "__main__":
    main()
