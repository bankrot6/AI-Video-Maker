#!/usr/bin/env python3
"""
Постоянное решение для загрузки пресетов в Firebase.
Использует Service Account + Firestore REST API (без gRPC).
"""

import json
import sys
import time
import base64
import hashlib
from pathlib import Path

try:
    import requests
except ImportError:
    print("❌ requests не установлен: pip3 install requests")
    sys.exit(1)

try:
    import jwt
except ImportError:
    print("❌ PyJWT не установлен: pip3 install PyJWT cryptography")
    sys.exit(1)


def load_service_account():
    for path in ['firebase-service-account.json', 'tool/firebase-service-account.json']:
        p = Path(path)
        if p.exists():
            with open(p) as f:
                return json.load(f)
    print("❌ Service Account ключ не найден")
    print("   Сохраните как: firebase-service-account.json (корень проекта)")
    sys.exit(1)


def get_access_token(sa):
    now = int(time.time())
    payload = {
        'iss': sa['client_email'],
        'sub': sa['client_email'],
        'aud': sa['token_uri'],
        'iat': now,
        'exp': now + 3600,
        'scope': 'https://www.googleapis.com/auth/datastore',
    }
    signed_jwt = jwt.encode(payload, sa['private_key'], algorithm='RS256')
    resp = requests.post(sa['token_uri'], data={
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': signed_jwt,
    }, timeout=30)
    resp.raise_for_status()
    return resp.json()['access_token']


def upload_preset(token, project_id, preset, index):
    timestamp = int(time.time() * 1000) + index
    title = preset.get('title', 'preset')
    title_slug = ''.join(c if c.isalnum() else '_' for c in title.lower())
    doc_id = f"preset_{timestamp}_{title_slug}"

    url = (
        f"https://firestore.googleapis.com/v1/projects/{project_id}"
        f"/databases/(default)/documents/presets?documentId={doc_id}"
    )

    tags = preset.get('tags', [])
    fields = {
        'title':          {'stringValue': preset.get('title', '')},
        'prompt':         {'stringValue': preset.get('prompt', '')},
        'previewImageUrl':{'stringValue': preset.get('previewImageUrl', '')},
        'createdAt':      {'stringValue': preset.get('createdAt', '')},
        'likesCount':     {'integerValue': '0'},
        'likedBy':        {'arrayValue': {}},
        'tags': {
            'arrayValue': {
                'values': [{'stringValue': t} for t in tags]
            }
        },
    }

    resp = requests.post(
        url,
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
        },
        json={'fields': fields},
        timeout=30,
    )

    if resp.status_code in (200, 201):
        return doc_id
    raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:200]}")


def main():
    print("=== Загрузка пресетов в Firebase (REST, без gRPC) ===\n")

    sa = load_service_account()
    project_id = sa['project_id']
    print(f"🔑 Service Account: {sa['client_email']}")
    print(f"📦 Project: {project_id}\n")

    print("🔐 Получение токена доступа...")
    try:
        token = get_access_token(sa)
        print("✅ Токен получен\n")
    except Exception as e:
        print(f"❌ Ошибка получения токена: {e}")
        sys.exit(1)

    presets_file = Path('tool/generated_presets.json')
    if not presets_file.exists():
        print("❌ Файл tool/generated_presets.json не найден")
        print("💡 Сначала запустите: dart tool/generate_presets_simple.dart")
        sys.exit(1)

    with open(presets_file) as f:
        presets = json.load(f)

    print(f"📋 Загружено {len(presets)} пресетов\n")

    success, fail = 0, 0

    for i, preset in enumerate(presets, 1):
        title = preset.get('title', 'Unknown')
        print(f"[{i}/{len(presets)}] 📸 {title}")
        try:
            doc_id = upload_preset(token, project_id, preset, i)
            print(f"  ✅ Загружено (ID: {doc_id})\n")
            success += 1
        except Exception as e:
            print(f"  ❌ Ошибка: {e}\n")
            fail += 1

    print("═══════════════════════════════════════")
    print(f"✅ Успешно: {success}/{len(presets)}")
    print(f"❌ Ошибки:  {fail}")
    if success > 0:
        print("\n🎉 Пресеты доступны в приложении!")


if __name__ == '__main__':
    main()
