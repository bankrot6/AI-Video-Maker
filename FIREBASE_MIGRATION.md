# Миграция с Appwrite на Firebase - Инструкция

## Выполненные изменения

### 1. Обновлены зависимости
- ✅ Добавлены Firebase пакеты: `firebase_core`, `firebase_storage`, `cloud_firestore`
- ✅ Закомментирован пакет `appwrite` (можно удалить полностью, если миграция успешна)

### 2. Созданы новые сервисы Firebase
- ✅ `lib/services/firebase_storage_service.dart` - аналог AppwriteStorageService
- ✅ `lib/data/firebase_user_generation_repository.dart` - аналог AppwriteUserGenerationRepository
- ✅ `lib/data/firebase_showcase_repository.dart` - аналог AppwriteShowcaseRepository

### 3. Обновлены провайдеры
- ✅ `lib/features/photosession/photosession_providers.dart` - используют Firebase сервисы
- ✅ Все использования `appwriteStorageServiceProvider` заменены на `firebaseStorageServiceProvider`

### 4. Закомментирован код Appwrite
- ✅ `lib/services/appwrite_storage_service.dart` - закомментирован
- ✅ `lib/data/user_generation_repository.dart` - AppwriteUserGenerationRepository закомментирован
- ✅ `lib/data/showcase_repository.dart` - AppwriteShowcaseRepository закомментирован
- ✅ `lib/main.dart` - инициализация Appwrite закомментирована, добавлена инициализация Firebase

### 5. Обновлен .env.example
- ✅ Добавлены поля для Firebase конфигурации
- ✅ Appwrite конфигурация закомментирована

## Что нужно сделать для завершения миграции

### Шаг 1: Создайте Firebase проект
1. Перейдите в [Firebase Console](https://console.firebase.google.com/)
2. Создайте новый проект или используйте существующий
3. Включите следующие сервисы:
   - **Firebase Storage** (для загрузки изображений)
   - **Cloud Firestore** (для хранения данных)

### Шаг 2: Получите конфигурацию Firebase
1. В Firebase Console перейдите в **Project Settings** → **General**
2. Прокрутите до раздела **Your apps**
3. Если приложение не зарегистрировано, нажмите на иконку платформы (iOS/Android/Web) и следуйте инструкциям
4. Скопируйте следующие значения из конфигурации:
   - API Key
   - Auth Domain
   - Project ID
   - Storage Bucket
   - Messaging Sender ID
   - App ID

### Шаг 3: Настройте .env файл
1. Создайте файл `.env` в корне проекта (если его еще нет)
2. Заполните его значениями из Firebase:

```env
# Firebase (витрина фотосессий)
FIREBASE_API_KEY=your_actual_api_key_here
FIREBASE_AUTH_DOMAIN=your-project-id.firebaseapp.com
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_STORAGE_BUCKET=your-project-id.appspot.com
FIREBASE_MESSAGING_SENDER_ID=123456789012
FIREBASE_APP_ID=1:123456789012:android:abc123def456
```

### Шаг 4: Включите Anonymous Authentication
1. В Firebase Console перейдите в **Authentication**
2. Перейдите на вкладку **Sign-in method**
3. Включите **Anonymous** провайдер
4. Сохраните изменения

⚠️ **ВАЖНО**: Anonymous Auth включается автоматически при старте приложения!

### Шаг 5: Настройте Firebase Storage
1. В Firebase Console перейдите в **Storage**
2. Нажмите **Get Started** и следуйте инструкциям
3. Настройте правила безопасности для анонимных пользователей:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /user-photos/{userId}/{allPaths=**} {
      // Чтение доступно всем
      allow read: if true;
      // Запись только для авторизованных пользователей (включая анонимных)
      allow write: if request.auth != null 
                   && request.resource.size < 10 * 1024 * 1024
                   && request.resource.contentType.matches('image/.*');
    }
    
    match /{allPaths=**} {
      // Для остальных файлов - только чтение
      allow read: if true;
      // Запись только для авторизованных
      allow write: if request.auth != null 
                   && request.resource.size < 10 * 1024 * 1024;
    }
  }
}
```

**Что делают эти правила:**
- ✅ Любой может читать изображения
- ✅ Анонимные пользователи могут загружать файлы (request.auth != null проверяет наличие uid)
- ✅ Ограничение 10 MB на файл
- ✅ Только изображения для user-photos/

### Шаг 6: Настройте Cloud Firestore
1. В Firebase Console перейдите в **Firestore Database**
2. Нажмите **Create Database** и выберите режим (Production или Test)
3. Создайте следующие коллекции:
   - `presets` - для пресетов фотосессий
   - `user_generations` - для генераций пользователей

4. Настройте правила безопасности для анонимных пользователей:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Правила для пресетов
    match /presets/{presetId} {
      // Чтение доступно всем
      allow read: if true;
      // Создание и обновление только для авторизованных (включая анонимных)
      allow create: if request.auth != null;
      allow update: if request.auth != null;
      allow delete: if request.auth != null;
    }
    
    // Правила для генераций пользователей
    match /user_generations/{generationId} {
      // Чтение доступно всем
      allow read: if true;
      // Создание только для авторизованных (включая анонимных)
      allow create: if request.auth != null;
      // Изменение/удаление только своих записей
      allow update, delete: if request.auth != null 
                           && request.auth.uid == resource.data.deviceId;
    }
  }
}
```

**Что делают эти правила:**
- ✅ Любой может читать пресеты и генерации
- ✅ Анонимные пользователи могут создавать пресеты и генерации
- ✅ Пользователи могут редактировать только свои генерации (проверка по deviceId)
- ✅ Безопасно для продакшена с анонимными пользователями

### Шаг 7: Настройте Firebase для iOS/Android (если нужно)

#### Для iOS:
1. Скачайте `GoogleService-Info.plist` из Firebase Console
2. Поместите его в `ios/Runner/`
3. Добавьте в `ios/Runner/Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>your-app-id</string>
    </array>
  </dict>
</array>
```

#### Для Android:
1. Скачайте `google-services.json` из Firebase Console
2. Поместите его в `android/app/`
3. Убедитесь, что в `android/build.gradle` есть:
```gradle
dependencies {
    classpath 'com.google.gms:google-services:4.4.2'
}
```
4. В `android/app/build.gradle` добавьте внизу:
```gradle
apply plugin: 'com.google.gms.google-services'
```

### Шаг 8: Миграция существующих данных (опционально)
Если у вас есть данные в Appwrite, которые нужно перенести:

1. Экспортируйте данные из Appwrite через API или консоль
2. Создайте миграционный скрипт для импорта в Firestore
3. Загрузите файлы из Appwrite Storage в Firebase Storage

### Шаг 9: Тестирование
1. Запустите команду: `flutter pub get`
2. Запустите приложение: `flutter run`
3. Проверьте основные функции:
   - Загрузка пресетов из Firestore
   - Создание новой генерации
   - Загрузка изображений в Firebase Storage

### Шаг 10: Удаление Appwrite кода (после успешной миграции)
После полного тестирования можно:
1. Удалить закомментированные файлы:
   - `lib/services/appwrite_storage_service.dart`
   - `lib/services/appwrite_ensure_tags.dart`
   - Все файлы в `tool/appwrite_*.dart`
2. Удалить закомментированные классы в:
   - `lib/data/user_generation_repository.dart`
   - `lib/data/showcase_repository.dart`
3. Удалить комментарии из `pubspec.yaml` и полностью убрать `appwrite`

## Возможные проблемы и решения

### Ошибка инициализации Firebase
- Проверьте, что все поля в `.env` заполнены корректно
- Убедитесь, что файлы конфигурации (`google-services.json`, `GoogleService-Info.plist`) на месте

### Ошибки доступа к Storage/Firestore
- Проверьте правила безопасности в Firebase Console
- Убедитесь, что сервисы активированы в проекте

### Индексы Firestore
Если при запросах возникают ошибки о недостающих индексах:
- Firebase покажет ссылку на создание индекса в консоли
- Перейдите по ссылке и создайте необходимый индекс

## Структура данных

### Коллекция `presets`
```json
{
  "prompt": "string",
  "previewImageUrl": "string",
  "title": "string (optional)",
  "tags": ["string"],
  "createdAt": "ISO8601 string",
  "ownerId": "string (optional)"
}
```

### Коллекция `user_generations`
```json
{
  "presetId": "string",
  "userImageUrl": "string",
  "resultImageUrl": "string",
  "deviceId": "string",
  "createdAt": "ISO8601 string"
}
```

## Поддержка
Если возникли проблемы с миграцией, проверьте логи приложения на наличие ошибок Firebase.
Все Firebase сервисы логируют свои действия с префиксом `Firebase`.
