# Миграция на Google API с Fallback на PiAPI

## Что изменилось

### До
- Использовался только **PiAPI** для генерации фотосессий
- Частые ошибки "API перегружен"
- Нет резервных вариантов

### После
- **Приоритет**: Google Vertex AI (Gemini) напрямую
- **Fallback**: PiAPI при ошибках Google API
- Автоматическое переключение между сервисами

## Новые файлы

1. **`lib/services/photosession_generation_router.dart`**
   - `PhotosessionGenerationRouter` - маршрутизатор с логикой fallback
   - `GoogleDirectPhotosessionService` - прямой вызов Google API
   - `PiapiPhotosessionService` - обёртка над PiAPI

2. **`PHOTOSESSION_GENERATION_GUIDE.md`**
   - Полная документация по новой системе

3. **`PHOTOSESSION_MIGRATION.md`** (этот файл)
   - Краткая сводка изменений

## Изменённые файлы

### `lib/features/photosession/photosession_providers.dart`

**Было:**
```dart
final nanoBananaServiceProvider = Provider<PiApiNanoBananaService>((ref) {
  return PiApiNanoBananaService();
});
```

**Стало:**
```dart
final nanoBananaServiceProvider = Provider<PhotosessionGenerationService>((ref) {
  final googleService = GoogleDirectPhotosessionService(
    apiKey: dotenv.env['NANO_BANANA_API_KEY'],
    projectId: dotenv.env['NANO_BANANA_PROJECT_ID'],
    location: dotenv.env['NANO_BANANA_LOCATION'],
    model: dotenv.env['NANO_BANANA_MODEL'],
  );

  final piapiService = PiapiPhotosessionService(
    PiApiNanoBananaService(),
  );

  return PhotosessionGenerationRouter(
    googleService: googleService,
    piapiService: piapiService,
  );
});
```

### `.env.example`

Добавлена секция с комментариями о Google Gemini API:
```env
# Google Gemini API (Приоритетный для генерации фотосессий)
NANO_BANANA_API_KEY=your_google_api_key_here
NANO_BANANA_PROJECT_ID=your_google_cloud_project_id
NANO_BANANA_MODEL=gemini-2.5-flash-image
NANO_BANANA_LOCATION=global
```

## Код остался совместимым

Интерфейс не изменился! Все существующие экраны работают без изменений:

```dart
// Код в photosession_preset_screen.dart и custom_preset_creation_screen.dart
// остался точно таким же
final nanoBanana = ref.read(nanoBananaServiceProvider);
final result = await nanoBanana.generateWithFace(
  userImageUrl: userImageUrl,
  scenePrompt: englishPrompt,
  resolution: '2K',
  aspectRatio: '3:4',
);
```

## Как это работает

1. Запрос генерации изображения
2. ↓
3. **Попытка #1**: Google Vertex AI
   - ✅ Успех → возвращаем результат
   - ❌ Ошибка → переходим к шагу 4
4. **Попытка #2**: PiAPI
   - ✅ Успех → возвращаем результат
   - ❌ Ошибка → возвращаем ошибку

## Преимущества

1. ✅ **Меньше ошибок**: Если один сервис недоступен, используется другой
2. ✅ **Быстрее**: Google API обычно быстрее PiAPI (нет посредника)
3. ✅ **Надёжнее**: Два независимых сервиса вместо одного
4. ✅ **Совместимость**: Код не изменился, всё работает как раньше
5. ✅ **Гибкость**: Легко добавить новые провайдеры в будущем

## Настройка

### Уже работает в .env

Ваш текущий `.env` уже содержит все нужные ключи:
```
NANO_BANANA_API_KEY=AQ.Ab8RN...
NANO_BANANA_PROJECT_ID=enhanced-mote-485505-a8
NANO_BANANA_MODEL=gemini-2.5-flash-image
NANO_BANANA_LOCATION=global
```

Ничего дополнительно настраивать не нужно! Просто запустите приложение.

## Логи для мониторинга

Следите за работой системы в консоли:

```
🔀 ROUTER: доступность Google=true, Piapi=true
🔀 ROUTER: пробуем Google API для generateWithFace
🟢 GOOGLE_DIRECT: генерация с лицом
🔀 ROUTER: Google API успешно
```

Если Google API недоступен:
```
🔀 ROUTER: пробуем Google API для generateWithFace
🟢 GOOGLE_DIRECT: ошибка HTTP 429
🔀 ROUTER: переключаемся на Piapi для generateWithFace
🟣 PIAPI: задача создана (text-to-image), ID=...
```

## Возможные улучшения в будущем

1. **Переключатель в UI** - дать пользователю выбирать провайдер
2. **Кеширование** - сохранять результаты чтобы не генерировать повторно
3. **Метрики** - отслеживать какой провайдер чаще используется
4. **Умный выбор** - выбирать провайдер на основе истории ошибок

## Откат назад (если понадобится)

Если что-то пошло не так, можно легко вернуться к старой логике:

В `photosession_providers.dart`:
```dart
final nanoBananaServiceProvider = Provider<PiApiNanoBananaService>((ref) {
  return PiApiNanoBananaService();
});
```

И обновить тип в экранах с `PhotosessionGenerationService` на `PiApiNanoBananaService`.

Но это не должно понадобиться, так как новый код полностью совместим!
