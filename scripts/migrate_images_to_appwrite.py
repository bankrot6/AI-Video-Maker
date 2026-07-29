#!/usr/bin/env python3
"""
Ретроактивная миграция изображений пресетов в Appwrite Storage.

Скрипт:
  1. Создаёт бакет 'preset-images' в Appwrite (если не существует)
  2. Читает все пресеты из Appwrite (постранично)
  3. Для каждого пресета, чьи previewImageUrl/thumbnailUrl ведут на
     Firebase Storage, скачивает изображение и загружает в Appwrite Storage
  4. Обновляет документ пресета в Appwrite новым URL

Запуск:
  python3 scripts/migrate_images_to_appwrite.py

Безопасность: идемпотентный (повторный запуск не дублирует файлы).
"""

import hashlib
import json
import mimetypes
import os
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

APPWRITE_DATABASE   = "main"
APPWRITE_COLLECTION = "presets"
APPWRITE_BUCKET     = "preset-images"

PAGE_SIZE  = 100
BATCH_DELAY = 0.2   # между запросами (не перегружать сервер)
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

APPWRITE_ENDPOINT = ENV.get("APPWRITE_ENDPOINT", "").rstrip("/")
APPWRITE_PROJECT  = ENV.get("APPWRITE_PROJECT_ID", "")
APPWRITE_API_KEY  = ENV.get("APPWRITE_API_KEY", "")

if not APPWRITE_ENDPOINT or not APPWRITE_PROJECT or not APPWRITE_API_KEY:
    print("❌  Не заполнены APPWRITE_ENDPOINT / APPWRITE_PROJECT_ID / APPWRITE_API_KEY в .env")
    sys.exit(1)

# ─────────────────────────────────────────────
# HTTP УТИЛИТЫ
# ─────────────────────────────────────────────

def appwrite_headers() -> dict:
    return {
        "X-Appwrite-Project": APPWRITE_PROJECT,
        "X-Appwrite-Key":     APPWRITE_API_KEY,
    }

def http_json(method: str, url: str, headers: dict = None, data: dict = None) -> dict:
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

def download_bytes(url: str) -> tuple[bytes, str]:
    """Скачивает файл, возвращает (bytes, content_type)."""
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        content_type = resp.headers.get("Content-Type", "image/jpeg").split(";")[0].strip()
        return resp.read(), content_type

def multipart_upload(url: str, headers: dict, file_id: str,
                     file_bytes: bytes, filename: str, content_type: str) -> dict:
    """Multipart-upload файла в Appwrite Storage."""
    boundary = "AppwriteMigration" + hashlib.md5(file_id.encode()).hexdigest()[:16]

    def part(name: str, value: str) -> bytes:
        return (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
            f"{value}\r\n"
        ).encode()

    body = (
        part("fileId", file_id)
        + f"--{boundary}\r\n".encode()
        + f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'.encode()
        + f"Content-Type: {content_type}\r\n\r\n".encode()
        + file_bytes + b"\r\n"
        + part('permissions[]', 'read("any")')
        + f"--{boundary}--\r\n".encode()
    )

    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")
    req.add_header("Content-Length", str(len(body)))
    for k, v in headers.items():
        req.add_header(k, v)

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body_text = e.read().decode()
        try:
            return {"_code": e.code, **json.loads(body_text)}
        except Exception:
            return {"error": True, "message": body_text, "code": e.code}

# ─────────────────────────────────────────────
# ШАГ 1: СОЗДАТЬ БАКЕТ preset-images
# ─────────────────────────────────────────────

def ensure_bucket():
    print(f"🪣  Проверяем бакет '{APPWRITE_BUCKET}'...")
    url = f"{APPWRITE_ENDPOINT}/storage/buckets/{APPWRITE_BUCKET}"
    r = http_json("GET", url, appwrite_headers())
    if r.get("$id"):
        print(f"   ✅ Бакет уже существует")
        return

    print(f"   Создаём бакет '{APPWRITE_BUCKET}'...")
    r = http_json("POST", f"{APPWRITE_ENDPOINT}/storage/buckets", appwrite_headers(), {
        "bucketId": APPWRITE_BUCKET,
        "name": "Preset Images",
        "enabled": True,
        "maximumFileSize": 20 * 1024 * 1024,  # 20 MB
        "allowedFileExtensions": ["jpg", "jpeg", "png", "webp", "gif"],
        "compression": "none",
        "encryption": False,
        "antivirus": False,
        "permissions": ['read("any")'],
        "fileSecurity": False,
    })
    if r.get("$id") or r.get("code") == 409:
        print(f"   ✅ Бакет '{APPWRITE_BUCKET}' готов")
    else:
        print(f"   ❌ Ошибка создания бакета: {r.get('message', r)}")
        sys.exit(1)

# ─────────────────────────────────────────────
# ШАГ 2: ПОЛУЧИТЬ ВСЕ ПРЕСЕТЫ ИЗ APPWRITE
# ─────────────────────────────────────────────

def fetch_all_presets() -> list[dict]:
    print("📋 Загружаем все пресеты из Appwrite...")
    all_docs = []
    offset = 0
    base_url = (
        f"{APPWRITE_ENDPOINT}/databases/{APPWRITE_DATABASE}"
        f"/collections/{APPWRITE_COLLECTION}/documents"
    )
    while True:
        q = urllib.parse.urlencode([
            ("queries[]", json.dumps({"method": "limit",  "values": [PAGE_SIZE]})),
            ("queries[]", json.dumps({"method": "offset", "values": [offset]})),
        ])
        url = f"{base_url}?{q}"
        r = http_json("GET", url, appwrite_headers())
        docs = r.get("documents", [])
        if not docs:
            break
        all_docs.extend(docs)
        print(f"   ... загружено {len(all_docs)}")
        if len(docs) < PAGE_SIZE:
            break
        offset += PAGE_SIZE
        time.sleep(0.2)
    print(f"   Итого: {len(all_docs)} пресетов")
    return all_docs

# ─────────────────────────────────────────────
# ШАГ 3: ЗЕРКАЛИРОВАНИЕ ИЗОБРАЖЕНИЯ
# ─────────────────────────────────────────────

def is_firebase_url(url: str) -> bool:
    return bool(url and "firebasestorage.googleapis.com" in url)

def is_already_appwrite(url: str) -> bool:
    if not url:
        return False
    try:
        host = urllib.parse.urlparse(APPWRITE_ENDPOINT).hostname or ""
        return host in url
    except Exception:
        return False

def deterministic_file_id(prefix: str, preset_id: str) -> str:
    """MD5-хэш ≤ 36 символов — безопасный и идемпотентный file ID."""
    return hashlib.md5(f"{prefix}_{preset_id}".encode()).hexdigest()  # 32 hex chars

def appwrite_file_url(file_id: str) -> str:
    return (
        f"{APPWRITE_ENDPOINT}/storage/buckets/{APPWRITE_BUCKET}"
        f"/files/{file_id}/view?project={APPWRITE_PROJECT}"
    )

def mirror_image_to_appwrite(source_url: str, file_id: str) -> str | None:
    """Скачивает source_url, загружает в Appwrite Storage, возвращает Appwrite URL."""
    upload_url = f"{APPWRITE_ENDPOINT}/storage/buckets/{APPWRITE_BUCKET}/files"

    for attempt in range(1, RETRY_COUNT + 1):
        try:
            img_bytes, content_type = download_bytes(source_url)

            ext_map = {"image/jpeg": "jpg", "image/png": "png",
                       "image/webp": "webp", "image/gif": "gif"}
            ext = ext_map.get(content_type, "jpg")
            filename = f"{file_id}.{ext}"

            r = multipart_upload(
                upload_url, appwrite_headers(),
                file_id, img_bytes, filename, content_type
            )

            code = r.get("code") or r.get("_code")
            if r.get("$id"):
                return appwrite_file_url(r["$id"])
            elif code == 409:
                # Файл уже существует — URL детерминирован
                return appwrite_file_url(file_id)
            else:
                print(f"      ⚠️  Попытка {attempt}/{RETRY_COUNT}: {r.get('message', r)}")
                time.sleep(2 * attempt)
        except Exception as ex:
            print(f"      ⚠️  Попытка {attempt}/{RETRY_COUNT}: {ex}")
            time.sleep(2 * attempt)

    return None

# ─────────────────────────────────────────────
# ШАГ 4: ОБНОВИТЬ ДОКУМЕНТ В APPWRITE
# ─────────────────────────────────────────────

def update_preset_urls(doc_id: str, updates: dict):
    url = (
        f"{APPWRITE_ENDPOINT}/databases/{APPWRITE_DATABASE}"
        f"/collections/{APPWRITE_COLLECTION}/documents/{doc_id}"
    )
    r = http_json("PATCH", url, appwrite_headers(), {"data": updates})
    if r.get("$id"):
        return True
    print(f"      ❌ PATCH {doc_id}: {r.get('message', r)}")
    return False

# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  Миграция изображений пресетов → Appwrite Storage")
    print("=" * 60)
    print(f"  Endpoint : {APPWRITE_ENDPOINT}")
    print(f"  Bucket   : {APPWRITE_BUCKET}")
    print()

    ensure_bucket()
    print()

    presets = fetch_all_presets()
    print()

    needs_migration = [
        p for p in presets
        if is_firebase_url(p.get("previewImageUrl"))
        or is_firebase_url(p.get("thumbnailUrl"))
    ]
    already_done = [
        p for p in presets
        if is_already_appwrite(p.get("previewImageUrl"))
    ]

    print(f"📊  Статус:")
    print(f"    Всего пресетов     : {len(presets)}")
    print(f"    Уже мигрированы   : {len(already_done)}")
    print(f"    Требуют миграции  : {len(needs_migration)}")
    print()

    if not needs_migration:
        print("✅  Все изображения уже в Appwrite Storage. Ничего делать не нужно.")
        return

    ok = 0
    fail = 0

    for i, preset in enumerate(needs_migration, 1):
        doc_id   = preset.get("$id", "")
        title    = preset.get("title") or doc_id[:12]
        preview  = preset.get("previewImageUrl", "")
        thumb    = preset.get("thumbnailUrl", "")

        print(f"[{i}/{len(needs_migration)}] {title}")

        updates = {}

        # Превью
        if is_firebase_url(preview):
            fid = deterministic_file_id("preview", doc_id)
            new_url = mirror_image_to_appwrite(preview, fid)
            if new_url:
                updates["previewImageUrl"] = new_url
                print(f"      ✅ preview → {new_url[:60]}...")
            else:
                print(f"      ❌ preview — не удалось загрузить")
                fail += 1

        # Миниатюра
        if is_firebase_url(thumb):
            fid = deterministic_file_id("thumb", doc_id)
            new_url = mirror_image_to_appwrite(thumb, fid)
            if new_url:
                updates["thumbnailUrl"] = new_url
                print(f"      ✅ thumbnail → {new_url[:60]}...")
            else:
                print(f"      ❌ thumbnail — не удалось загрузить")

        if updates:
            if update_preset_urls(doc_id, updates):
                ok += 1
            else:
                fail += 1

        time.sleep(BATCH_DELAY)

    print()
    print("=" * 60)
    print(f"  Готово: успешно={ok}  ошибок={fail}")
    print("=" * 60)
    if fail > 0:
        print("  Повторите запуск скрипта — он идемпотентен.")


if __name__ == "__main__":
    main()
