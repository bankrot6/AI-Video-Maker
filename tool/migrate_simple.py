#!/usr/bin/env python3
import os
import sys
import requests
import json
from pathlib import Path

# Загрузка .env
env_path = Path(__file__).parent.parent / '.env'
env_vars = {}
if env_path.exists():
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                env_vars[key] = value

print("=" * 60)
print("МИГРАЦИЯ APPWRITE → FIREBASE")
print("=" * 60)

# Конфигурация
APPWRITE_ENDPOINT = env_vars.get('APPWRITE_ENDPOINT')
APPWRITE_PROJECT_ID = env_vars.get('APPWRITE_PROJECT_ID')
APPWRITE_API_KEY = env_vars.get('APPWRITE_API_KEY')
APPWRITE_DATABASE_ID = env_vars.get('APPWRITE_DATABASE_ID')
APPWRITE_PRESETS_COLLECTION = env_vars.get('APPWRITE_PRESETS_COLLECTION_ID')
APPWRITE_GENERATIONS_COLLECTION = env_vars.get('APPWRITE_GENERATIONS_COLLECTION_ID')

FIREBASE_PROJECT_ID = env_vars.get('FIREBASE_PROJECT_ID')
FIREBASE_API_KEY = env_vars.get('FIREBASE_API_KEY')

print(f"\nAppwrite endpoint: {APPWRITE_ENDPOINT}")
print(f"Firebase project: {FIREBASE_PROJECT_ID}\n")

if not APPWRITE_ENDPOINT or not FIREBASE_PROJECT_ID:
    print("ERROR: Missing configuration!")
    sys.exit(1)

# Функция для получения пресетов из Appwrite
def get_appwrite_presets():
    print("Загрузка пресетов из Appwrite...")
    url = f"{APPWRITE_ENDPOINT}/databases/{APPWRITE_DATABASE_ID}/collections/{APPWRITE_PRESETS_COLLECTION}/documents"
    headers = {
        'X-Appwrite-Project': APPWRITE_PROJECT_ID,
        'X-Appwrite-Key': APPWRITE_API_KEY
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        data = response.json()
        docs = data.get('documents', [])
        print(f"✓ Загружено {len(docs)} пресетов")
        return docs
    except Exception as e:
        print(f"✗ Ошибка: {e}")
        return []

# Функция для миграции пресета в Firebase
def migrate_preset(preset):
    preset_id = preset.get('$id')
    data = {
        'fields': {
            'id': {'stringValue': preset_id},
            'prompt': {'stringValue': preset.get('prompt', '')},
            'previewImageUrl': {'stringValue': preset.get('previewImageUrl', '')},
            'createdAt': {'stringValue': preset.get('createdAt', preset.get('$createdAt', ''))}
        }
    }
    
    if preset.get('title'):
        data['fields']['title'] = {'stringValue': preset['title']}
    if preset.get('tags'):
        data['fields']['tags'] = {
            'arrayValue': {
                'values': [{'stringValue': t} for t in preset['tags']]
            }
        }
    if preset.get('ownerId'):
        data['fields']['ownerId'] = {'stringValue': preset['ownerId']}
    
    # Используем POST для создания с кастомным ID
    url = f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents/presets?documentId={preset_id}"
    params = {'key': FIREBASE_API_KEY}
    
    try:
        response = requests.post(url, json=data, params=params, timeout=30)
        if response.status_code in [200, 201]:
            return True
        else:
            # Попробуем через обычный POST если с ID не получилось
            url_auto = f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents/presets"
            response2 = requests.post(url_auto, json=data, params=params, timeout=30)
            if response2.status_code in [200, 201]:
                return True
            print(f"  ✗ Ошибка {preset_id}: {response.status_code}, попытка 2: {response2.status_code}")
            return False
    except Exception as e:
        print(f"  ✗ Ошибка {preset_id}: {e}")
        return False

# Основная миграция
presets = get_appwrite_presets()

if presets:
    print(f"\nМиграция {len(presets)} пресетов в Firebase...")
    success = 0
    failed = 0
    
    for i, preset in enumerate(presets, 1):
        if migrate_preset(preset):
            success += 1
        else:
            failed += 1
        
        if i % 10 == 0:
            print(f"  Обработано {i}/{len(presets)}...")
    
    print("\n" + "=" * 60)
    print("РЕЗУЛЬТАТЫ")
    print("=" * 60)
    print(f"✓ Успешно: {success}")
    print(f"✗ С ошибками: {failed}")
    print("=" * 60)
else:
    print("Нет данных для миграции")
