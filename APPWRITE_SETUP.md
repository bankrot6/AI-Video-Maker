# Настройка Appwrite для AI Video Maker

## 1. Создание Storage Bucket

1. Открой Appwrite Console: https://fra.cloud.appwrite.io/console/project-69af8d3c00226006b31f
2. Перейди в **Storage**
3. Нажми **Create bucket**
4. Параметры:
   - **Bucket ID**: `user-photos`
   - **Name**: `User Photos`
   - **Permissions**:
     - Read: `Any`
     - Create: `Any`
   - **Maximum File Size**: `8 MB`
   - **Allowed File Extensions**: `jpg, jpeg, png, webp`
   - **Compression**: `gzip`
   - **Encryption**: включено
5. Нажми **Create**

## 2. Создание Collection для генераций

1. Перейди в **Databases** → выбери базу `69af9d64003bd1d3b07c`
2. Нажми **Create collection**
3. Параметры:
   - **Collection ID**: `user_generations`
   - **Name**: `User Generations`
   - **Permissions**:
     - Read: `Any`
     - Create: `Any`
4. Нажми **Create**

5. Добавь атрибуты (каждый через **Create attribute** → **String**):
   - `presetId` (размер: 100, required: true)
   - `userImageUrl` (размер: 500, required: true)
   - `resultImageUrl` (размер: 500, required: true)
   - `createdAt` (размер: 50, required: true)

6. Создай индекс:
   - **Indexes** → **Create index**
   - **Key**: `presetId_idx`
   - **Type**: `Key`
   - **Attributes**: `presetId` (ASC)

## 3. API Key для создания пресетов и загрузки списка

Чтобы работало **«Создать свою фотосессию»** (сохранение пресета в базу) и загрузка пресетов по API:

1. В Appwrite Console: **Project** → **API Keys** → **Create API Key**.
2. Выдай права: **Databases** (Read, Create).
3. Скопируй ключ и добавь в `.env`:

```
APPWRITE_API_KEY=секретный_ключ_из_консоли
```

Без `APPWRITE_API_KEY` создание пресета выдаст ошибку (401).

## 4. Проверка .env

Убедись что в `.env` есть:

```
APPWRITE_STORAGE_BUCKET_ID=user-photos
APPWRITE_GENERATIONS_COLLECTION_ID=user_generations
APPWRITE_API_KEY=...   # для создания пресетов и загрузки списка
```

## Готово!

После этого перезапусти приложение.
