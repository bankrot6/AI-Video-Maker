# Миграция данных из Appwrite в Firebase

Этот скрипт автоматически переносит все данные из Appwrite в Firebase Firestore.

## 🎯 Что мигрирует:

- ✅ **Пресеты фотосессий** (коллекция `presets`)
- ✅ **Генерации пользователей** (коллекция `user_generations`)

## 📋 Подготовка

### 1. Установите Python зависимости:

```bash
cd tool
pip3 install -r requirements.txt
```

Или используйте виртуальное окружение:

```bash
python3 -m venv venv
source venv/bin/activate  # для macOS/Linux
# или venv\Scripts\activate для Windows
pip install -r requirements.txt
```

### 2. Убедитесь, что `.env` файл заполнен

Скрипт использует ключи из `.env` файла в корне проекта:

**Appwrite:**
- `APPWRITE_ENDPOINT`
- `APPWRITE_PROJECT_ID`
- `APPWRITE_API_KEY`
- `APPWRITE_DATABASE_ID`
- `APPWRITE_PRESETS_COLLECTION_ID`
- `APPWRITE_GENERATIONS_COLLECTION_ID`

**Firebase:**
- `FIREBASE_PROJECT_ID`
- `FIREBASE_API_KEY`

### 3. Настройте Firestore правила (если еще не сделали)

В Firebase Console → Firestore → Rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /presets/{presetId} {
      allow read: if true;
      allow write: if true;  // Для миграции
    }
    
    match /user_generations/{generationId} {
      allow read: if true;
      allow write: if true;  // Для миграции
    }
  }
}
```

## 🚀 Запуск миграции

### Запустите скрипт:

```bash
cd tool
python3 migrate_appwrite_to_firebase.py
```

## 📊 Что происходит во время миграции:

1. **Загрузка данных из Appwrite**
   - Скрипт получает все документы из обеих коллекций
   - Показывает прогресс загрузки

2. **Миграция в Firebase**
   - Каждый документ конвертируется в формат Firestore
   - Данные загружаются через REST API
   - Показывается прогресс каждые 10 документов

3. **Статистика**
   - В конце выводится отчет о мигрированных и проблемных документах

## 📝 Формат данных

### Пресет (presets):
```json
{
  "prompt": "string",
  "previewImageUrl": "string",
  "title": "string (optional)",
  "tags": ["string"],
  "createdAt": "ISO8601",
  "ownerId": "string (optional)"
}
```

### Генерация (user_generations):
```json
{
  "presetId": "string",
  "userImageUrl": "string",
  "resultImageUrl": "string",
  "deviceId": "string",
  "createdAt": "ISO8601"
}
```

## ⚠️ Важные замечания

### 1. Безопасность
- Скрипт использует ваш Firebase API Key для записи данных
- После миграции **обязательно** ужесточите правила Firestore
- Не делитесь `.env` файлом с API ключами

### 2. ID документов
- Сохраняются оригинальные ID из Appwrite
- Это позволяет избежать дублирования при повторном запуске

### 3. Повторный запуск
- Скрипт можно запускать многократно
- Существующие документы будут обновлены (не продублированы)
- Используется метод `PATCH` для безопасного обновления

### 4. Файлы (изображения)
- **Текущая версия НЕ мигрирует файлы** из Appwrite Storage
- URL изображений сохраняются как есть
- Изображения продолжат работать, пока Appwrite активен
- Новые изображения будут загружаться в Firebase Storage

## 🔍 Проверка результатов

После миграции проверьте данные в Firebase Console:

1. Откройте **Firebase Console** → **Firestore Database**
2. Найдите коллекции:
   - `presets` - должны быть все пресеты
   - `user_generations` - все генерации пользователей
3. Откройте любой документ и проверьте поля

## 🐛 Решение проблем

### Ошибка: "Permission denied"
- Проверьте правила Firestore (должны разрешать запись)
- Убедитесь, что Firebase API Key правильный

### Ошибка: "Invalid API key"
- Проверьте `FIREBASE_API_KEY` в `.env`
- Убедитесь, что ключ активен в Firebase Console

### Ошибка подключения к Appwrite
- Проверьте `APPWRITE_ENDPOINT` и `APPWRITE_API_KEY`
- Убедитесь, что API Key имеет права на чтение

### Скрипт зависает
- Нажмите Ctrl+C для остановки
- Скрипт покажет статистику уже мигрированных данных
- Можно запустить снова - продолжит с момента остановки

## 📈 Производительность

- Примерная скорость: **~50-100 документов в минуту**
- Для 1000 документов: **~10-20 минут**
- Зависит от размера документов и скорости интернета

## 🎉 После успешной миграции

1. Проверьте данные в Firebase Console
2. Запустите приложение и убедитесь, что все работает
3. Опционально: отключите Appwrite после полного тестирования
4. Ужесточите правила Firestore для продакшена

## 🔄 Откат

Если нужно вернуться к Appwrite:
- Данные в Appwrite не изменяются
- Просто раскомментируйте Appwrite код в приложении
- Firebase данные можно удалить через консоль

## 💡 Советы

- Запустите миграцию в нерабочее время (если у вас есть пользователи)
- Сделайте бэкап Appwrite данных перед миграцией
- Проверьте небольшую выборку данных перед полным переходом на Firebase
