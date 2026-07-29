#!/usr/bin/env python3
"""
Проверка наличия миниатюр у пресетов в Firestore.
"""

import json
import sys
import time
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
            with open(p, 'r', encoding='utf-8') as f:
                return json.load(f)
    print("❌ Файл service account не найден")
    print("   Создайте firebase-service-account.json или tool/firebase-service-account.json")
    sys.exit(1)


def get_access_token(service_account):
    now = int(time.time())
    payload = {
        'iss': service_account['client_email'],
        'sub': service_account['client_email'],
        'aud': 'https://firestore.googleapis.com/',
        'iat': now,
        'exp': now + 3600,
    }
    
    token = jwt.encode(
        payload,
        service_account['private_key'],
        algorithm='RS256'
    )
    
    return token


def get_all_presets(project_id, access_token):
    """Получить все пресеты из Firestore."""
    url = f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents/presets"
    
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json',
    }
    
    all_docs = []
    page_token = None
    
    while True:
        params = {'pageSize': 300}
        if page_token:
            params['pageToken'] = page_token
        
        response = requests.get(url, headers=headers, params=params)
        
        if response.status_code != 200:
            print(f"❌ Ошибка получения пресетов: {response.status_code}")
            print(response.text)
            return []
        
        data = response.json()
        
        if 'documents' in data:
            all_docs.extend(data['documents'])
        
        page_token = data.get('nextPageToken')
        if not page_token:
            break
    
    return all_docs


def extract_field_value(field_data):
    """Извлечь значение из Firestore field."""
    if not field_data:
        return None
    
    if 'stringValue' in field_data:
        return field_data['stringValue']
    elif 'integerValue' in field_data:
        return int(field_data['integerValue'])
    elif 'booleanValue' in field_data:
        return field_data['booleanValue']
    elif 'timestampValue' in field_data:
        return field_data['timestampValue']
    
    return None


def analyze_thumbnails():
    print('🔍 Анализ пресетов на наличие миниатюр...\n')
    
    service_account = load_service_account()
    project_id = service_account['project_id']
    access_token = get_access_token(service_account)
    
    presets = get_all_presets(project_id, access_token)
    
    total = len(presets)
    with_thumbnail = 0
    without_thumbnail = 0
    missing_presets = []
    
    for doc in presets:
        fields = doc.get('fields', {})
        preset_id = doc['name'].split('/')[-1]
        
        thumbnail_url = extract_field_value(fields.get('thumbnailUrl'))
        preview_url = extract_field_value(fields.get('previewImageUrl'))
        title = extract_field_value(fields.get('title')) or 'Без названия'
        is_public = extract_field_value(fields.get('isPublic')) or False
        
        if thumbnail_url:
            with_thumbnail += 1
        else:
            without_thumbnail += 1
            missing_presets.append({
                'id': preset_id,
                'title': title,
                'preview': preview_url,
                'isPublic': is_public,
            })
    
    print('═══════════════════════════════════════════════════')
    print(f'📊 Всего пресетов: {total}')
    print(f'✅ С миниатюрой (thumbnailUrl): {with_thumbnail} ({with_thumbnail/total*100:.1f}%)')
    print(f'❌ Без миниатюры: {without_thumbnail} ({without_thumbnail/total*100:.1f}%)')
    print('═══════════════════════════════════════════════════\n')
    
    if missing_presets:
        print(f'📋 Пресеты без миниатюр (первые 20):\n')
        for i, preset in enumerate(missing_presets[:20], 1):
            print(f'{i}. {preset["id"]}')
            print(f'   Название: {preset["title"]}')
            print(f'   Публичный: {preset["isPublic"]}')
            print(f'   Preview: {"✓" if preset["preview"] else "✗"}')
            print('')
        
        if len(missing_presets) > 20:
            print(f'... и ещё {len(missing_presets) - 20} пресетов\n')
        
        print('💡 Для генерации миниатюр выполните:')
        print('   curl -X POST https://us-central1-photosession-ai-cbfc3.cloudfunctions.net/backfillThumbnails')
        print('\n   Или через Firebase CLI:')
        print('   firebase functions:shell')
        print('   > backfillThumbnails()')


if __name__ == '__main__':
    analyze_thumbnails()
