# Руководство по генерации фотосессий

## Обзор

В приложении реализована система генерации изображений для фотосессий с автоматическим переключением между сервисами.

## Архитектура

### Основные компоненты

1. **PhotosessionGenerationRouter** - маршрутизатор, который управляет выбором сервиса генерации
2. **GoogleDirectPhotosessionService** - прямой вызов Google Vertex AI (Gemini API)
3. **PiapiPhotosessionService** - обёртка над PiAPI сервисом

### Логика работы

Система работает по принципу **приоритетного выбора с fallback**:

1. **Первая попытка**: Используется **Google Vertex AI напрямую**
   - Меньше задержек (нет промежуточного прокси)
   - Прямой доступ к Google Gemini API
   - Более стабильная работа

2. **Fallback**: При ошибке автоматически переключается на **PiAPI**
   - Используется если Google API недоступен
   - Резервный вариант для обеспечения бесперебойной работы

## Настройка

### Google Vertex AI (Приоритетный)

В файле `.env` настройте следующие параметры:

```env
# Google Gemini API (Приоритетный для генерации фотосессий)
NANO_BANANA_API_KEY=your_google_api_key_here
NANO_BANANA_PROJECT_ID=your_google_cloud_project_id
NANO_BANANA_MODEL=gemini-2.5-flash-image
NANO_BANANA_LOCATION=global
NANO_BANANA_STREAM=true
```

**Где получить ключи:**

1. Перейдите в [Google Cloud Console](https://console.cloud.google.com/)
2. Создайте или выберите проект
3. Активируйте Vertex AI API
4. Создайте API ключ в разделе "APIs & Services" → "Credentials"

### PiAPI (Резервный)

```env
# PiAPI (используется как fallback)
PIAPI_API_KEY=your_piapi_api_key_here
PIAPI_TASK_URL=https://api.piapi.ai/api/v1/task
```

## Использование в коде

Сервис автоматически используется через провайдер:

```dart
final nanoBanana = ref.read(nanoBananaServiceProvider);

final result = await nanoBanana.generateWithFace(
  userImageUrl: userImageUrl,
  scenePrompt: englishPrompt,
  resolution: '2K',
  aspectRatio: '3:4',
);

if (result.isSuccess && result.imageUrl != null) {
  // Изображение успешно сгенерировано
  print('URL изображения: ${result.imageUrl}');
} else {
  // Обработка ошибки
  print('Ошибка: ${result.errorMessage}');
}
```

## Методы

### `generateWithFace()`

Генерирует изображение с лицом пользователя (image-to-image).

**Параметры:**
- `userImageUrl` - URL фото пользователя
- `scenePrompt` - описание сцены на английском языке
- `resolution` - разрешение ('2K', '4K')
- `aspectRatio` - соотношение сторон ('3:4', '16:9' и т.д.)

### `generateImage()`

Генерирует изображение по текстовому описанию (text-to-image).

**Параметры:**
- `prompt` - текстовое описание
- `resolution` - разрешение
- `aspectRatio` - соотношение сторон

## Мониторинг

Для отслеживания работы сервисов используйте логи:

- `🔀 ROUTER:` - логи маршрутизатора
- `🟢 GOOGLE_DIRECT:` - логи Google API
- `🟣 PIAPI:` - логи PiAPI

Пример логов:
```
🔀 ROUTER: доступность Google=true, Piapi=true
🔀 ROUTER: пробуем Google API для generateWithFace
🟢 GOOGLE_DIRECT: генерация с лицом
🔀 ROUTER: Google API успешно
```

## Преимущества новой архитектуры

1. **Надёжность**: Автоматическое переключение при сбоях
2. **Производительность**: Приоритет прямому API без посредников
3. **Гибкость**: Легко добавить новые провайдеры
4. **Совместимость**: Интерфейс не изменился, код работает как раньше

## Устранение проблем

### Google API не работает

1. Проверьте правильность API ключа
2. Убедитесь что Vertex AI API активирован в проекте
3. Проверьте квоты в Google Cloud Console

### Оба сервиса недоступны

Проверьте `.env` файл и убедитесь что хотя бы один из ключей настроен правильно:
- `NANO_BANANA_API_KEY` для Google
- `PIAPI_API_KEY` для PiAPI

### Ошибки в логах

При ошибках в логах будет указан конкретный сервис и причина:
```
🟢 GOOGLE_DIRECT: ошибка HTTP 401
🔀 ROUTER: переключаемся на Piapi для generateWithFace
```

## Файлы

- `lib/services/photosession_generation_router.dart` - основная логика маршрутизации
- `lib/features/photosession/photosession_providers.dart` - провайдеры Riverpod
- `lib/services/piapi_nano_banana_service.dart` - PiAPI сервис (старый)
- `lib/services/nano_banana_image_generation_service.dart` - Google API сервис (старый, не используется напрямую)
