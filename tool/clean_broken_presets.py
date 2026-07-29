#!/usr/bin/env python3
"""
Скрипт для удаления сломанных пресетов из Firebase
Проверяет доступность изображений и удаляет пресеты с недоступными URL
"""

import os
import sys
import requests
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
print("ОЧИСТКА СЛОМАННЫХ ПРЕСЕТОВ")
print("=" * 60)

FIREBASE_PROJECT_ID = env_vars.get('FIREBASE_PROJECT_ID')
FIREBASE_API_KEY = env_vars.get('FIREBASE_API_KEY')

if not FIREBASE_PROJECT_ID or not FIREBASE_API_KEY:
    print("ERROR: Firebase конфигурация не найдена!")
    sys.exit(1)

print(f"\nFirebase project: {FIREBASE_PROJECT_ID}\n")

# Получить все пресеты
print("📥 Загрузка пресетов из Firebase...")
url = f"https://firestore.googleapis.com/v1/projects/{FIREBASE_PROJECT_ID}/databases/(default)/documents/presets"
params = {'key': FIREBASE_API_KEY}

try:
    response = requests.get(url, params=params, timeout=30)
    response.raise_for_status()
    data = response.json()
    documents = data.get('documents', [])
    print(f"✓ Загружено {len(documents)} пресетов\n")
except Exception as e:
    print(f"❌ Ошибка загрузки: {e}")
    sys.exit(1)

# Проверка доступности изображений
broken_presets = []
working_presets = []

print("🔍 Проверка доступности изображений...")
for doc in documents:
    doc_name = doc.get('name', '')
    doc_id = doc_name.split('/')[-1] if '/' in doc_name else 'unknown'
    
    fields = doc.get('fields', {})
    preview_url_field = fields.get('previewImageUrl', {})
    preview_url = preview_url_field.get('stringValue', '')
    
    prompt_field = fields.get('prompt', {})
    prompt = prompt_field.get('stringValue', '')[:50]
    
    if not preview_url:
        print(f"  ❌ {doc_id}: нет URL изображения")
        broken_presets.append((doc_id, doc_name, "Нет URL"))
        continue
    
    # Проверка доступности URL
    try:
        head_response = requests.head(preview_url, timeout=10, allow_redirects=True)
        if head_response.status_code == 200:
            print(f"  ✓ {doc_id}: OK")
            working_presets.append(doc_id)
        else:
            print(f"  ❌ {doc_id}: HTTP {head_response.status_code}")
            broken_presets.append((doc_id, doc_name, f"HTTP {head_response.status_code}"))
    except Exception as e:
        print(f"  ❌ {doc_id}: {str(e)[:50]}")
        broken_presets.append((doc_id, doc_name, str(e)[:50]))

print(f"\n{'=' * 60}")
print(f"✓ Рабочих пресетов: {len(working_presets)}")
print(f"❌ Сломанных пресетов: {len(broken_presets)}")
print(f"{'=' * 60}\n")

# Удаление сломанных пресетов
if broken_presets:
    print(f"🗑️  Удаление {len(broken_presets)} сломанных пресетов...\n")
    
    deleted = 0
    failed = 0
    
    for doc_id, doc_name, reason in broken_presets:
        try:
            delete_url = f"https://firestore.googleapis.com/v1/{doc_name}"
            response = requests.delete(delete_url, params=params, timeout=30)
            
            if response.status_code in [200, 204]:
                print(f"  ✓ Удален {doc_id} (причина: {reason})")
                deleted += 1
            else:
                print(f"  ✗ Не удалось удалить {doc_id}: HTTP {response.status_code}")
                failed += 1
        except Exception as e:
            print(f"  ✗ Ошибка удаления {doc_id}: {e}")
            failed += 1
    
    print(f"\n{'=' * 60}")
    print(f"РЕЗУЛЬТАТЫ ОЧИСТКИ")
    print(f"{'=' * 60}")
    print(f"✓ Удалено: {deleted}")
    print(f"✗ Ошибок: {failed}")
    print(f"✓ Осталось рабочих: {len(working_presets)}")
    print(f"{'=' * 60}\n")
    print("🎉 Очистка завершена!")
else:
    print("✅ Все пресеты в порядке, удалять нечего!")
