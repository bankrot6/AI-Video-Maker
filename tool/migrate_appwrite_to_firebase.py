#!/usr/bin/env python3
"""
Скрипт миграции данных из Appwrite в Firebase
Переносит пресеты и генерации пользователей
"""

import os
import sys
import requests
import json
from datetime import datetime
from typing import List, Dict, Optional
import firebase_admin
from firebase_admin import credentials, firestore, storage
from dotenv import load_dotenv

# Загружаем .env файл
import pathlib
env_path = pathlib.Path(__file__).parent.parent / '.env'
load_dotenv(env_path)

class AppwriteToFirebaseMigrator:
    def __init__(self):
        # Appwrite конфигурация
        self.appwrite_endpoint = os.getenv('APPWRITE_ENDPOINT')
        self.appwrite_project_id = os.getenv('APPWRITE_PROJECT_ID')
        self.appwrite_api_key = os.getenv('APPWRITE_API_KEY')
        self.appwrite_database_id = os.getenv('APPWRITE_DATABASE_ID')
        self.appwrite_presets_collection = os.getenv('APPWRITE_PRESETS_COLLECTION_ID')
        self.appwrite_generations_collection = os.getenv('APPWRITE_GENERATIONS_COLLECTION_ID')
        
        # Firebase конфигурация
        self.firebase_project_id = os.getenv('FIREBASE_PROJECT_ID')
        self.firebase_api_key = os.getenv('FIREBASE_API_KEY')
        
        # Инициализация Firebase
        self._init_firebase()
        
        # Счетчики
        self.stats = {
            'presets_migrated': 0,
            'presets_failed': 0,
            'generations_migrated': 0,
            'generations_failed': 0,
            'files_migrated': 0,
            'files_failed': 0
        }
    
    def _init_firebase(self):
        """Инициализация Firebase Admin SDK"""
        try:
            # Создаем временный credentials файл
            cred_dict = {
                "type": "service_account",
                "project_id": self.firebase_project_id,
                "private_key_id": "dummy",
                "private_key": "-----BEGIN PRIVATE KEY-----\nDUMMY\n-----END PRIVATE KEY-----\n",
                "client_email": f"firebase-adminsdk@{self.firebase_project_id}.iam.gserviceaccount.com",
                "client_id": "dummy",
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
                "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs"
            }
            
            # Используем REST API вместо Admin SDK для простоты
            print("✓ Firebase REST API готов к использованию")
            
        except Exception as e:
            print(f"⚠ Будем использовать Firebase REST API: {e}")
    
    def _get_appwrite_headers(self) -> Dict[str, str]:
        """Получить заголовки для Appwrite API"""
        return {
            'X-Appwrite-Project': self.appwrite_project_id,
            'X-Appwrite-Key': self.appwrite_api_key,
            'Content-Type': 'application/json'
        }
    
    def get_appwrite_presets(self) -> List[Dict]:
        """Получить все пресеты из Appwrite"""
        print("\n📥 Загрузка пресетов из Appwrite...")
        
        url = f"{self.appwrite_endpoint}/databases/{self.appwrite_database_id}/collections/{self.appwrite_presets_collection}/documents"
        headers = self._get_appwrite_headers()
        
        all_documents = []
        offset = 0
        limit = 100
        
        while True:
            try:
                params = {'limit': limit, 'offset': offset}
                response = requests.get(url, headers=headers, params=params, timeout=30)
                response.raise_for_status()
                
                data = response.json()
                documents = data.get('documents', [])
                
                if not documents:
                    break
                
                all_documents.extend(documents)
                print(f"  Загружено {len(all_documents)} пресетов...")
                
                if len(documents) < limit:
                    break
                    
                offset += limit
                
            except Exception as e:
                print(f"❌ Ошибка загрузки пресетов: {e}")
                break
        
        print(f"✓ Всего загружено {len(all_documents)} пресетов")
        return all_documents
    
    def get_appwrite_generations(self) -> List[Dict]:
        """Получить все генерации из Appwrite"""
        print("\n📥 Загрузка генераций из Appwrite...")
        
        url = f"{self.appwrite_endpoint}/databases/{self.appwrite_database_id}/collections/{self.appwrite_generations_collection}/documents"
        headers = self._get_appwrite_headers()
        
        all_documents = []
        offset = 0
        limit = 100
        
        while True:
            try:
                params = {'limit': limit, 'offset': offset}
                response = requests.get(url, headers=headers, params=params, timeout=30)
                response.raise_for_status()
                
                data = response.json()
                documents = data.get('documents', [])
                
                if not documents:
                    break
                
                all_documents.extend(documents)
                print(f"  Загружено {len(all_documents)} генераций...")
                
                if len(documents) < limit:
                    break
                    
                offset += limit
                
            except Exception as e:
                print(f"❌ Ошибка загрузки генераций: {e}")
                break
        
        print(f"✓ Всего загружено {len(all_documents)} генераций")
        return all_documents
    
    def migrate_preset_to_firebase(self, preset: Dict) -> bool:
        """Мигрировать один пресет в Firebase Firestore"""
        try:
            # Подготовка данных
            preset_id = preset.get('$id')
            data = {
                'prompt': preset.get('prompt', ''),
                'previewImageUrl': preset.get('previewImageUrl', ''),
                'title': preset.get('title'),
                'tags': preset.get('tags', []),
                'createdAt': preset.get('createdAt', preset.get('$createdAt', datetime.now().isoformat())),
                'ownerId': preset.get('ownerId')
            }
            
            # Удаляем None значения
            data = {k: v for k, v in data.items() if v is not None}
            
            # Отправка в Firebase Firestore через REST API
            url = f"https://firestore.googleapis.com/v1/projects/{self.firebase_project_id}/databases/(default)/documents/presets/{preset_id}"
            
            firebase_data = {
                "fields": {
                    key: self._convert_to_firebase_value(value)
                    for key, value in data.items()
                }
            }
            
            params = {'key': self.firebase_api_key}
            response = requests.patch(url, json=firebase_data, params=params, timeout=30)
            
            if response.status_code in [200, 201]:
                self.stats['presets_migrated'] += 1
                return True
            else:
                print(f"  ⚠ Ошибка миграции пресета {preset_id}: {response.status_code}")
                self.stats['presets_failed'] += 1
                return False
                
        except Exception as e:
            print(f"  ❌ Ошибка миграции пресета: {e}")
            self.stats['presets_failed'] += 1
            return False
    
    def migrate_generation_to_firebase(self, generation: Dict) -> bool:
        """Мигрировать одну генерацию в Firebase Firestore"""
        try:
            # Подготовка данных
            gen_id = generation.get('$id')
            data = {
                'presetId': generation.get('presetId', ''),
                'userImageUrl': generation.get('userImageUrl', ''),
                'resultImageUrl': generation.get('resultImageUrl', ''),
                'deviceId': generation.get('deviceId', ''),
                'createdAt': generation.get('createdAt', generation.get('$createdAt', datetime.now().isoformat()))
            }
            
            # Удаляем пустые значения
            data = {k: v for k, v in data.items() if v}
            
            # Отправка в Firebase Firestore через REST API
            url = f"https://firestore.googleapis.com/v1/projects/{self.firebase_project_id}/databases/(default)/documents/user_generations/{gen_id}"
            
            firebase_data = {
                "fields": {
                    key: self._convert_to_firebase_value(value)
                    for key, value in data.items()
                }
            }
            
            params = {'key': self.firebase_api_key}
            response = requests.patch(url, json=firebase_data, params=params, timeout=30)
            
            if response.status_code in [200, 201]:
                self.stats['generations_migrated'] += 1
                return True
            else:
                print(f"  ⚠ Ошибка миграции генерации {gen_id}: {response.status_code}")
                self.stats['generations_failed'] += 1
                return False
                
        except Exception as e:
            print(f"  ❌ Ошибка миграции генерации: {e}")
            self.stats['generations_failed'] += 1
            return False
    
    def _convert_to_firebase_value(self, value):
        """Конвертировать значение в формат Firebase Firestore"""
        if isinstance(value, str):
            return {"stringValue": value}
        elif isinstance(value, bool):
            return {"booleanValue": value}
        elif isinstance(value, int):
            return {"integerValue": str(value)}
        elif isinstance(value, float):
            return {"doubleValue": value}
        elif isinstance(value, list):
            return {
                "arrayValue": {
                    "values": [self._convert_to_firebase_value(v) for v in value]
                }
            }
        elif value is None:
            return {"nullValue": None}
        else:
            return {"stringValue": str(value)}
    
    def migrate_all(self, migrate_presets: bool = True, migrate_generations: bool = True):
        """Выполнить полную миграцию"""
        print("\n" + "="*60)
        print("🚀 МИГРАЦИЯ ДАННЫХ ИЗ APPWRITE В FIREBASE")
        print("="*60)
        
        # Проверка конфигурации
        if not all([self.appwrite_endpoint, self.appwrite_project_id, self.appwrite_api_key]):
            print("❌ Ошибка: не настроены Appwrite ключи в .env файле")
            return
        
        if not all([self.firebase_project_id, self.firebase_api_key]):
            print("❌ Ошибка: не настроены Firebase ключи в .env файле")
            return
        
        print(f"\nAppwrite: {self.appwrite_endpoint}")
        print(f"Firebase: {self.firebase_project_id}")
        
        # Миграция пресетов
        if migrate_presets:
            presets = self.get_appwrite_presets()
            
            if presets:
                print(f"\n📤 Миграция {len(presets)} пресетов в Firebase...")
                for i, preset in enumerate(presets, 1):
                    self.migrate_preset_to_firebase(preset)
                    if i % 10 == 0:
                        print(f"  Обработано {i}/{len(presets)} пресетов...")
        
        # Миграция генераций
        if migrate_generations:
            generations = self.get_appwrite_generations()
            
            if generations:
                print(f"\n📤 Миграция {len(generations)} генераций в Firebase...")
                for i, generation in enumerate(generations, 1):
                    self.migrate_generation_to_firebase(generation)
                    if i % 10 == 0:
                        print(f"  Обработано {i}/{len(generations)} генераций...")
        
        # Статистика
        self.print_stats()
    
    def print_stats(self):
        """Вывести статистику миграции"""
        print("\n" + "="*60)
        print("📊 РЕЗУЛЬТАТЫ МИГРАЦИИ")
        print("="*60)
        print(f"✓ Пресетов мигрировано: {self.stats['presets_migrated']}")
        print(f"✗ Пресетов с ошибками: {self.stats['presets_failed']}")
        print(f"✓ Генераций мигрировано: {self.stats['generations_migrated']}")
        print(f"✗ Генераций с ошибками: {self.stats['generations_failed']}")
        print("="*60)
        
        total_success = self.stats['presets_migrated'] + self.stats['generations_migrated']
        total_failed = self.stats['presets_failed'] + self.stats['generations_failed']
        
        if total_failed == 0:
            print("🎉 Миграция завершена успешно!")
        else:
            print(f"⚠ Миграция завершена с {total_failed} ошибками")


def main():
    """Главная функция"""
    print("Скрипт миграции данных Appwrite → Firebase")
    print("-" * 60)
    
    # Создание мигратора
    migrator = AppwriteToFirebaseMigrator()
    
    # Запуск миграции
    try:
        migrator.migrate_all(
            migrate_presets=True,
            migrate_generations=True
        )
    except KeyboardInterrupt:
        print("\n\n⚠ Миграция прервана пользователем")
        migrator.print_stats()
    except Exception as e:
        print(f"\n❌ Критическая ошибка: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
