#!/usr/bin/env python3
"""
Миграция обложек пресетов с заблокированных CDN в Appwrite Storage.

Запускать на сервере с доступом к внешним CDN (NL-сервер или из-за VPN).
На NL-сервере app-uploads.krea.ai / img.theapi.app доступны без ограничений.

Использование:
  python3 scripts/migrate_preset_images_to_appwrite.py

Конфигурация читается из .env (APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, ...)
"""
import sys
import os
import json
import time
import random
import string
import urllib.request
import urllib.error
import urllib.parse
import io
from pathlib import Path


# ─── Домены, требующие миграции ───────────────────────────────
EXTERNAL_DOMAINS = {
    'app-uploads.krea.ai',
    'krea.ai',
    'img.theapi.app',
    'theapi.app',
    'mule-router-assets.muleusercontent.com',
    'muleusercontent.com',
    'd1q70pf5vjeyhc.cloudfront.net',
    'firebasestorage.googleapis.com',
    'fra.cloud.appwrite.io',
}


# ─── Загрузка .env ────────────────────────────────────────────
def _load_env():
    env_file = Path(__file__).parent.parent / '.env'
    env = {}
    if env_file.exists():
        with open(env_file, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                key, _, val = line.partition('=')
                env[key.strip()] = val.strip()
    env.update({k: v for k, v in os.environ.items() if k not in env})
    return env


ENV = _load_env()

ENDPOINT      = ENV.get('APPWRITE_ENDPOINT', '').rstrip('/')   # http://host/v1
PROJECT_ID    = ENV.get('APPWRITE_PROJECT_ID', '')
API_KEY       = ENV.get('APPWRITE_API_KEY', '')
DATABASE_ID   = ENV.get('APPWRITE_DATABASE_ID', 'main')
COLLECTION_ID = ENV.get('APPWRITE_PRESETS_COLLECTION_ID', 'presets')
BUCKET_ID     = ENV.get('APPWRITE_STORAGE_BUCKET_ID', 'user-photos')

# Базовый URL без /v1 (для построения публичных ссылок)
BASE_URL = ENDPOINT.rstrip('/v1').rstrip('/')
if BASE_URL.endswith('/v'):
    BASE_URL = BASE_URL[:-2]
BASE_URL = ENDPOINT.replace('/v1', '').rstrip('/')


# ─── Appwrite REST ─────────────────────────────────────────────
def _aw_headers():
    return {
        'X-Appwrite-Project': PROJECT_ID,
        'X-Appwrite-Key': API_KEY,
    }


def aw_get(path, queries=None):
    """queries — list of Appwrite query strings (JSON encoded)."""
    url = ENDPOINT + path
    if queries:
        parts = []
        for q in queries:
            parts.append('queries[]=' + urllib.parse.quote(q))
        url += '?' + '&'.join(parts)
    req = urllib.request.Request(url, headers=_aw_headers())
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f'  GET {path} → HTTP {e.code}: {e.read()[:200]}', file=sys.stderr)
        return None


def aw_patch(path, data):
    # Appwrite 1.x updateDocument expects {"data": {...}}
    body = json.dumps({'data': data}).encode()
    headers = {**_aw_headers(), 'Content-Type': 'application/json'}
    req = urllib.request.Request(ENDPOINT + path, data=body, headers=headers, method='PATCH')
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f'  PATCH {path} → HTTP {e.code}: {e.read()[:200]}', file=sys.stderr)
        return None


def aw_ensure_bucket():
    """Создаёт бакет BUCKET_ID, если он не существует."""
    result = aw_get(f'/storage/buckets/{BUCKET_ID}')
    if result and result.get('$id'):
        print(f'  Бакет «{BUCKET_ID}» уже существует')
        return True
    print(f'  Создаём бакет «{BUCKET_ID}»...')
    body = json.dumps({
        'bucketId': BUCKET_ID,
        'name': BUCKET_ID,
        'permissions': ['read("any")'],
        'fileSecurity': False,
        'enabled': True,
        'maximumFileSize': 30_000_000,
        'allowedFileExtensions': ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        'compression': 'none',
        'encryption': False,
        'antivirus': False,
    }).encode()
    headers = {
        **_aw_headers(),
        'Content-Type': 'application/json',
        'Content-Length': str(len(body)),
    }
    req = urllib.request.Request(
        ENDPOINT + '/storage/buckets', data=body, headers=headers, method='POST'
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            resp = json.loads(r.read())
            print(f'  ✓ Бакет создан: {resp["$id"]}')
            return True
    except urllib.error.HTTPError as e:
        print(f'  ✗ Не удалось создать бакет: HTTP {e.code}: {e.read()[:200]}', file=sys.stderr)
        return False


def aw_upload_file(file_id, filename, data, content_type):
    """Загружает файл в Appwrite Storage через multipart/form-data."""
    boundary = '----AW' + ''.join(random.choices(string.ascii_lowercase, k=16))
    body = io.BytesIO()

    def part_text(name, value):
        body.write(f'--{boundary}\r\n'.encode())
        body.write(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode())
        body.write(f'{value}\r\n'.encode())

    def part_file(name, fname, fdata, ftype):
        body.write(f'--{boundary}\r\n'.encode())
        body.write(
            f'Content-Disposition: form-data; name="{name}"; filename="{fname}"\r\n'.encode()
        )
        body.write(f'Content-Type: {ftype}\r\n\r\n'.encode())
        body.write(fdata)
        body.write(b'\r\n')

    part_text('fileId', file_id)
    part_text('permissions[]', 'read("any")')
    part_file('file', filename, data, content_type)
    body.write(f'--{boundary}--\r\n'.encode())

    raw = body.getvalue()
    headers = {
        **_aw_headers(),
        'Content-Type': f'multipart/form-data; boundary={boundary}',
        'Content-Length': str(len(raw)),
    }
    url = ENDPOINT + f'/storage/buckets/{BUCKET_ID}/files'
    req = urllib.request.Request(url, data=raw, headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f'  UPLOAD → HTTP {e.code}: {e.read()[:300]}', file=sys.stderr)
        return None


# ─── Хелперы ──────────────────────────────────────────────────
def is_external(url):
    if not url:
        return False
    try:
        host = urllib.parse.urlparse(url).netloc.lower()
        return any(host == d or host.endswith('.' + d) for d in EXTERNAL_DOMAINS)
    except Exception:
        return False


def download_image(url):
    req = urllib.request.Request(
        url,
        headers={'User-Agent': 'Mozilla/5.0 (compatible; AppwriteMigrator/1.0)'},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
        ct = r.headers.get('Content-Type', 'image/jpeg').split(';')[0].strip()
        return data, ct


def appwrite_file_url(file_id):
    return (
        f'{BASE_URL}/v1/storage/buckets/{BUCKET_ID}'
        f'/files/{file_id}/view?project={PROJECT_ID}'
    )


def safe_file_id(prefix='preset'):
    ts = str(int(time.time() * 1000))
    rnd = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
    return f'{prefix}_{ts}_{rnd}'


def ext_for_ct(ct):
    return {'image/png': '.png', 'image/webp': '.webp', 'image/gif': '.gif'}.get(ct, '.jpg')


MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB — safe for Appwrite nginx default


def maybe_resize(data, content_type):
    """Resize image to fit within MAX_UPLOAD_BYTES. Returns (data, new_content_type)."""
    if len(data) <= MAX_UPLOAD_BYTES:
        return data, content_type
    try:
        import struct, zlib
        # Try using sips (macOS) → convert large PNG/JPEG to smaller JPEG
        import subprocess, tempfile, os
        suffix = ext_for_ct(content_type)
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as src_f:
            src_f.write(data)
            src_path = src_f.name
        dst_path = src_path + '_resized.jpg'
        subprocess.run(
            ['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '80',
             '--resampleHeightWidthMax', '2048', src_path, '--out', dst_path],
            check=True, capture_output=True,
        )
        with open(dst_path, 'rb') as f:
            resized = f.read()
        os.unlink(src_path)
        os.unlink(dst_path)
        print(f'         ⚙ resized {len(data)//1024}KB → {len(resized)//1024}KB (JPEG)')
        return resized, 'image/jpeg'
    except Exception as e:
        print(f'         ⚠ resize failed: {e} — uploading original', file=sys.stderr)
        return data, content_type


# ─── Загрузка всех пресетов ───────────────────────────────────
def _aw_query(method, *values):
    return json.dumps({'method': method, 'values': list(values)})


def fetch_all_presets():
    print('Загружаем пресеты из Appwrite...')
    docs = []
    limit = 100
    offset = 0
    while True:
        queries = [
            _aw_query('limit', limit),
            _aw_query('offset', offset),
        ]
        result = aw_get(
            f'/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/documents',
            queries,
        )
        if not result:
            break
        batch = result.get('documents', [])
        docs.extend(batch)
        total = result.get('total', len(docs))
        print(f'  {len(docs)} / {total}', end='\r')
        if len(batch) < limit:
            break
        offset += limit
        time.sleep(0.05)
    print(f'\n  Итого: {len(docs)} пресетов')
    return docs


# ─── main ──────────────────────────────────────────────────────
def main():
    print('=== Миграция обложек пресетов → Appwrite Storage ===\n')

    if not ENDPOINT or not PROJECT_ID or not API_KEY:
        print('ОШИБКА: заполни APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY в .env')
        sys.exit(1)

    print(f'Endpoint : {ENDPOINT}')
    print(f'Project  : {PROJECT_ID}')
    print(f'Database : {DATABASE_ID} / {COLLECTION_ID}')
    print(f'Bucket   : {BUCKET_ID}')
    print()

    print('Проверяем / создаём бакет...')
    if not aw_ensure_bucket():
        sys.exit(1)
    print()

    presets = fetch_all_presets()
    to_migrate = [p for p in presets if is_external(p.get('previewImageUrl', ''))]

    print(f'\nТребуют миграции: {len(to_migrate)} из {len(presets)}\n')
    if not to_migrate:
        print('Нечего мигрировать — все обложки уже в Appwrite.')
        return

    ok = fail = 0
    for i, preset in enumerate(to_migrate, 1):
        doc_id = preset['$id']
        old_url = preset.get('previewImageUrl', '')
        title = (preset.get('title') or doc_id[:8])[:40]
        print(f'[{i:>4}/{len(to_migrate)}] {title}')
        print(f'         src: {old_url[:80]}')

        try:
            image_data, ct = download_image(old_url)
            image_data, ct = maybe_resize(image_data, ct)
            ext = ext_for_ct(ct)
            file_id = safe_file_id()
            filename = f'{file_id}{ext}'

            result = aw_upload_file(file_id, filename, image_data, ct)
            if not result:
                print('         ✗ не удалось загрузить в Appwrite')
                fail += 1
                continue

            new_url = appwrite_file_url(result['$id'])
            updated = aw_patch(
                f'/databases/{DATABASE_ID}/collections/{COLLECTION_ID}/documents/{doc_id}',
                {'previewImageUrl': new_url},
            )
            if updated:
                print(f'         ✓ {new_url[:80]}')
                ok += 1
            else:
                print('         ✗ документ не обновлён')
                fail += 1

        except urllib.error.HTTPError as e:
            print(f'         ✗ HTTP {e.code} при скачивании')
            fail += 1
        except Exception as e:
            print(f'         ✗ {e}')
            fail += 1

        time.sleep(0.1)

    print(f'\n{"─"*50}')
    print(f'Готово.  Успешно: {ok}   Ошибки: {fail}')
    if fail:
        print('Запусти скрипт повторно — он пропустит уже мигрированные.')


if __name__ == '__main__':
    main()
