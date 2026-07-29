# 🚀 БЫСТРАЯ НАСТРОЙКА APPWRITE

## Шаг 1: Создание API ключа

1. **Откройте в браузере:**
   ```
   http://158.160.254.66/console/project-project-default-6a66f25200139fc454e7/settings/keys
   ```

2. **Нажмите "Create API Key"**

3. **Заполните:**
   - **Name**: `Migration Key`
   - **Scopes**: отметьте ВСЕ галочки:
     - ✅ `databases.read`
     - ✅ `databases.write` 
     - ✅ `documents.read`
     - ✅ `documents.write`
     - ✅ `files.read`
     - ✅ `files.write`
     - ✅ `buckets.read`

4. **Нажмите "Create"**

5. **Скопируйте созданный ключ** (начинается с `standard_...`)

## Шаг 2: Обновление .env

Откройте файл `.env` и найдите строку:
```
APPWRITE_API_KEY=
```

Вставьте ваш скопированный ключ:
```
APPWRITE_API_KEY=standard_ваш_ключ_здесь
```

Сохраните файл.

## Шаг 3: Автоматическое создание ресурсов

Выполните в терминале:
```bash
cd /Volumes/External_Storage/Projects/Photosession-AI
node scripts/create_appwrite_resources.js
```

## Шаг 4: Запуск миграции

```bash
./scripts/migrate_presets.sh migrate
```

---

**Всё готово!** После этого ваши пресеты из Firebase будут перенесены в Appwrite! 🎉