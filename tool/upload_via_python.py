#!/usr/bin/env python3
"""
Загрузка пресетов в Firebase через Admin SDK
Постоянное решение для создания пресетов
"""

import json
import sys
from pathlib import Path

try:
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    print("❌ firebase-admin не установлен")
    print("💡 Установите: pip3 install firebase-admin")
    sys.exit(1)


def main():
    print("=== Загрузка пресетов в Firebase ===\n")
    
    if not firebase_admin._apps:
        try:
            cred = credentials.ApplicationDefault()
            firebase_admin.initialize_app(cred, {
                'projectId': 'photosession-ai-cbfc3',
            })
            print("✅ Firebase Admin SDK инициализирован (ADC)\n")
        except Exception as e:
            print(f"❌ Ошибка инициализации: {e}")
            print("\n💡 Выполните настройку:")
            print("   gcloud auth application-default login")
            print("\n   Или используйте Service Account:")
            print("   1. Скачайте JSON из Firebase Console")
            print("   2. Сохраните как tool/firebase-service-account.json")
            print("   3. Раскомментируйте код в скрипте")
            sys.exit(1)
    
    db = firestore.client()
    
    presets_file = Path('tool/generated_presets.json')
    if not presets_file.exists():
        print("❌ Файл tool/generated_presets.json не найден")
        print("💡 Сначала запустите: dart tool/generate_presets_simple.dart")
        sys.exit(1)
    
    with open(presets_file) as f:
        presets = json.load(f)
    
    print(f"📋 Загружено {len(presets)} пресетов\n")
    
    success_count = 0
    fail_count = 0
    
    for i, preset in enumerate(presets, 1):
        title = preset.get('title', 'Unknown')
        print(f"[{i}/{len(presets)}] 📸 {title}")
        
        try:
            import time
            timestamp = int(time.time() * 1000)
            title_slug = ''.join(c if c.isalnum() else '_' for c in title.lower())
            doc_id = f"preset_{timestamp}_{title_slug}"
            
            doc_data = {
                'title': preset.get('title'),
                'prompt': preset.get('prompt'),
                'previewImageUrl': preset.get('previewImageUrl'),
                'tags': preset.get('tags', []),
                'createdAt': preset.get('createdAt'),
            }
            
            db.collection('presets').document(doc_id).set(doc_data)
            
            print(f"  ✅ Загружено в Firestore (ID: {doc_id})\n")
            success_count += 1
            
        except Exception as e:
            print(f"  ❌ Ошибка: {e}\n")
            fail_count += 1
    
    print("═══════════════════════════════════════")
    print("📊 ИТОГИ")
    print("═══════════════════════════════════════")
    print(f"✅ Успешно: {success_count}")
    print(f"❌ Ошибки: {fail_count}")
    
    if success_count > 0:
        print("\n🎉 Пресеты доступны в приложении!")


if __name__ == '__main__':
    main()
