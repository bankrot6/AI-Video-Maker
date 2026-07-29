# Руководство по тестированию новых функций

## Перед запуском:

1. **Убедись что в .env есть новые переменные:**
   ```bash
   APPWRITE_STORAGE_BUCKET_ID=user-photos
   APPWRITE_GENERATIONS_COLLECTION_ID=user_generations
   ```

2. **Appwrite настроен** (bucket и collection созданы через скрипт `tool/appwrite_setup_storage.dart`)

3. **Остановиостанови все запущенные Flutter процессы:**
   ```bash
   pkill -9 flutter
   pkill -9 dart
   ```

## Запуск приложения:

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI
flutter run
```

## Что тестировать:

### 1. Кэширование пресетов
- ✅ Первая загрузка - пресеты грузятся из Appwrite
- ✅ Повторный вход в экран - пресеты грузятся из кэша (быстро)
- ✅ Pull-to-refresh - принудительное обновление из Appwrite

**Проверь логи:**
```
PresetCache: загружено X пресетов из кэша (возраст Y мин)
```

### 2. Загрузка фото через Appwrite Storage
- ✅ Выбери пресет
- ✅ Нажми "Добавить своё фото"
- ✅ Выбери фото (PNG, HEIC, JPG - любой формат)
- ✅ Должно появиться "Загружаем ваше фото в Appwrite Storage..."

**Проверь логи:**
```
AppwriteStorage: начинаем загрузку ...
AppwriteStorage: конвертируем PNG в JPG...  (если был PNG/HEIC)
AppwriteStorage: успешно загружено, URL=https://fra.cloud.appwrite.io/storage/...
```

**Результат:** Нет таймаутов, быстрая загрузка!

### 3. Сохранение результатов
- ✅ После генерации должно появиться "Готово! Ваша фотосессия с вашим лицом"
- ✅ Прокрути вниз - увидишь секцию "Ваши предыдущие фотосессии:"
- ✅ Там сетка 2x со всеми твоими генерациями для этого пресета

**Проверь логи:**
```
UserGenerationRepo: создание gen_... для preset=...
NanoBanana: задача завершена, URL=...
UserGenerationRepo: загрузка для preset=...
UserGenerationRepo: получено X генераций
```

### 4. Полноэкранный просмотр с зумом
- ✅ Тапни на любое изображение (preview пресета или результат генерации)
- ✅ Откроется полноэкранный просмотр с черным фоном
- ✅ Pinch-to-zoom работает (до 3x увеличения)
- ✅ Pan для перемещения увеличенного изображения
- ✅ Кнопка "X" закрывает
- ✅ Кнопка "Download" (стрелка вниз) в AppBar

### 5. Сохранение в галерею
- ✅ В полноэкранном просмотре нажми кнопку "Download"
- ✅ При первом нажатии запросит разрешение на доступ к фото
- ✅ После сохранения: "Фото сохранено в галерею" (зеленый SnackBar)
- ✅ Проверь галерею устройства - фото должно быть там

**Android:** требуется разрешение Storage
**iOS:** требуется разрешение Photos

### 6. Кэшированные изображения
- ✅ При повторном входе в Showcase изображения загружаются из кэша
- ✅ Нет мерцания, instant отображение
- ✅ Используется `CachedNetworkImage` везде

## Проверка в Appwrite Console:

### Storage Bucket (user-photos):
https://fra.cloud.appwrite.io/console/project-69af8d3c00226006b31f/storage/bucket-user-photos

**Должно быть:**
- Название: User Photos
- Max size: 8 MB
- Extensions: jpg, jpeg, png, webp
- Permissions: create(any), read(any)

### Collection (user_generations):
https://fra.cloud.appwrite.io/console/project-69af8d3c00226006b31f/databases/database-69af9d64003bd1d3b07c/collection-user_generations

**Должно быть:**
- 4 атрибута: presetId, userImageUrl, resultImageUrl, createdAt
- Индекс: presetId_idx
- Permissions: create(any), read(any)

После каждой генерации в этой коллекции появляется новый документ!

## Известные проблемы:

Если видишь ошибку компиляции - проверь:
1. `flutter pub get` успешно завершился
2. Все импорты корректны
3. Нет конфликтующих версий пакетов

## Следующие шаги (опционально):

1. Добавить удаление сохраненных генераций (swipe-to-delete)
2. Добавить шаринг изображений через share_plus
3. Оптимизировать размер кэша (сейчас безлимитный)
4. Добавить индикатор количества сохраненных генераций на карточке пресета
