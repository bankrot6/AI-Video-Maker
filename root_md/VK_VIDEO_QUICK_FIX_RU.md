# Быстрое решение проблемы с VK Video

## Проблема
Видео из ВКонтакте не отображаются в карточках упражнений, несмотря на добавленный ключ в `.env`.

## Найденные проблемы

1. ❌ **Файл `.env` не был создан** (он в `.gitignore`)
2. ❌ **Нет fallback для VK токена** в `main.dart`
3. ❌ **Недостаточное логирование** для диагностики

## Что было исправлено

### 1. Обновлен `main.dart`
Добавлены fallback значения для VK токенов:
```dart
dotenv.env['VKVIDEO_SERVICE_KEY'] = 'test_vk_key';
dotenv.env['VK_API_TOKEN'] = 'test_vk_key';
dotenv.env['VK_VIDEO_API_TOKEN'] = 'test_vk_key';
```

### 2. Улучшено логирование в `vk_api_client.dart`
Теперь показывает детальные ошибки VK API:
- Код ошибки 5: неверный токен
- Код ошибки 15: недостаточно прав доступа

### 3. Улучшено логирование в `video_aggregator_service.dart`
Добавлены детальные логи:
- Проверка наличия токена
- Результаты поиска по каждому запросу
- Итоговый список отобранных видео

### 4. Созданы файлы документации
- `.env.example` - пример конфигурации
- `VK_VIDEO_API_SETUP_RU.md` - подробная инструкция
- `VK_VIDEO_QUICK_FIX_RU.md` - это краткое руководство

## Как исправить (3 простых шага)

### Шаг 1: Создайте файл `.env`

```bash
cd /Volumes/External_Storage/Projects/ChatCoach
cp .env.example .env
```

### Шаг 2: Получите токен VK API

1. Откройте: https://vk.com/apps?act=manage
2. Создайте "Standalone-приложение" с названием "ChatCoach"
3. Скопируйте **сервисный ключ** из настроек приложения

### Шаг 3: Добавьте токен в `.env`

Откройте файл `.env` и добавьте ваш токен:
```env
VKVIDEO_SERVICE_KEY=ваш_сервисный_ключ_здесь
```

## Проверка работы

1. **Перезапустите приложение:**
   ```bash
   flutter run
   ```

2. **Откройте любое упражнение** (например, "Приседания")

3. **Проверьте логи** (должны увидеть):
   ```
   🔍 AGGREGATOR: Начало поиска видео для: Приседания
   🔑 AGGREGATOR: VK API token present: true
   🔍 AGGREGATOR: Поиск VK видео по запросу: "Приседания техника выполнения"
      Найдено результатов: 15
   ✅ AGGREGATOR: Отобрано 4 видео из 48 кандидатов
   ```

4. **В карточке упражнения:**
   - Должна появиться карусель с точками внизу
   - Свайп вправо → видео из VK
   - Нажмите на видео для воспроизведения

## Частые ошибки

### "VK API токен отсутствует"
```
⚠️ AGGREGATOR: VK API токен отсутствует! Видео не будут загружены.
💡 AGGREGATOR: Добавьте VKVIDEO_SERVICE_KEY в файл .env
```

**Решение:** Создайте файл `.env` и добавьте токен.

### "Неверный токен доступа"
```
❌ VK_API error: User authorization failed (код: 5)
   💡 Неверный токен доступа! Проверьте VKVIDEO_SERVICE_KEY в .env
```

**Решение:** Получите новый сервисный ключ на https://vk.com/apps?act=manage

### "Доступ запрещен"
```
❌ VK_API error: Access denied (код: 15)
   💡 Доступ запрещен! Токен не имеет прав на video.search
```

**Решение:** Используйте **сервисный ключ**, а не пользовательский токен.

## Альтернатива: использование веб-скрейпинга

Если не хотите создавать приложение VK, можно переключиться на старый метод:

1. Откройте `lib/features/exercise/exercise_details_screen.dart`
2. Найдите метод `_searchVideo()`
3. Замените:
   ```dart
   // Было:
   final aggregator = ref.read(videoAggregatorServiceProvider);
   final candidates = await aggregator.searchCandidates(exerciseName);
   
   // На:
   final vkSearch = ref.read(vkVideoSearchServiceProvider);
   final videoData = await vkSearch.searchVideo(exerciseName);
   ```

**Минусы:** Менее надежный, только 1 видео вместо 4.

## Дополнительная помощь

Подробная инструкция: `VK_VIDEO_API_SETUP_RU.md`

## Резюме изменений

**Измененные файлы:**
- ✅ `lib/main.dart` - добавлены VK токены в fallback
- ✅ `lib/services/vk_api_client.dart` - улучшено логирование ошибок
- ✅ `lib/services/video_aggregator_service.dart` - детальные логи поиска

**Новые файлы:**
- ✅ `.env.example` - пример конфигурации
- ✅ `VK_VIDEO_API_SETUP_RU.md` - подробная инструкция
- ✅ `VK_VIDEO_QUICK_FIX_RU.md` - это руководство

---

**Дата:** 14 октября 2025  
**Статус:** ✅ Готово к использованию

