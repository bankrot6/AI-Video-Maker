# Исправление проблемы дублирования пуш-уведомлений

## 🚨 Проблема

Пользователи на Android получали по 3 пуш-уведомления сразу, и с каждым днем количество дублей увеличивалось.

## 🔍 Причины проблемы

1. **Автоматическое перепланирование в провайдере** - `mealRemindersServiceProvider` автоматически вызывал `rescheduleAllReminders()` при каждой инициализации
2. **Неправильная логика перепланирования** - метод `rescheduleAllReminders()` не сохранял настройки времени и создавал новые уведомления поверх старых
3. **Отсутствие проверки дублей** - система не проверяла существующие уведомления перед созданием новых
4. **Множественная инициализация** - провайдер мог инициализироваться несколько раз в течение жизненного цикла приложения

## ✅ Исправления

### 1. Убрано автоматическое перепланирование из провайдера

**Файл:** `lib/services/providers.dart`

```dart
// БЫЛО:
mealRemindersService.initialize().then((_) {
  mealRemindersService.rescheduleAllReminders().catchError((error) {
    debugPrint('🍽️ Ошибка при перепланировании напоминаний о еде: $error');
  });
}).catchError((error) {
  debugPrint('🍽️ Ошибка при инициализации сервиса напоминаний о еде: $error');
});

// СТАЛО:
mealRemindersService.initialize().catchError((error) {
  debugPrint('🍽️ Ошибка при инициализации сервиса напоминаний о еде: $error');
});
```

### 2. Исправлена логика перепланирования

**Файл:** `lib/services/notification/meal_reminders_service.dart`

- Добавлено сохранение настроек времени в SharedPreferences
- Добавлены флаги для отслеживания настроенных напоминаний
- Полная очистка перед пересозданием уведомлений

### 3. Добавлена проверка дублей в NotificationManager

**Файл:** `lib/services/notification/notification_manager.dart`

- Проверка существующих уведомлений с тем же ID
- Автоматическая отмена дублей перед созданием новых

### 4. Добавлен метод полного сброса

**Файл:** `lib/services/notification/meal_reminders_service.dart`

```dart
/// Полностью очищает все уведомления и сбрасывает состояние сервиса
Future<void> resetAllNotifications() async {
  // Полная очистка всех уведомлений и настроек
}
```

## 🛠️ Рекомендации для разработчиков

### 1. Не используйте автоматическое перепланирование в провайдерах

```dart
// ❌ ПЛОХО
final provider = Provider<Service>((ref) {
  final service = Service();
  service.initialize().then((_) {
    service.rescheduleAll(); // Может вызываться многократно!
  });
  return service;
});

// ✅ ХОРОШО
final provider = Provider<Service>((ref) {
  final service = Service();
  service.initialize(); // Только инициализация
  return service;
});
```

### 2. Всегда сохраняйте состояние в SharedPreferences

```dart
// ✅ ХОРОШО
Future<String> setupReminder({int hour = 8, int minute = 0}) async {
  // Отменяем старое напоминание
  if (_reminderId != null) {
    await _service.cancelReminder(_reminderId!);
  }
  
  // Создаем новое
  _reminderId = await _service.createDailyReminder(...);
  
  // Сохраняем настройки
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('reminder_hour', hour);
  await prefs.setInt('reminder_minute', minute);
  await prefs.setBool('had_reminder', true);
  
  return _reminderId!;
}
```

### 3. Проверяйте дубли перед созданием уведомлений

```dart
// ✅ ХОРОШО
Future<void> scheduleNotification(int id, ...) async {
  // Проверяем существующие
  final existingIndex = _notifications.indexWhere((n) => n.numericId == id);
  if (existingIndex != -1) {
    await cancelNotification(id);
    _notifications.removeAt(existingIndex);
  }
  
  // Создаем новое
  await _service.createNotification(id, ...);
}
```

### 4. Предоставьте метод полного сброса

```dart
// ✅ ХОРОШО
Future<void> resetAllNotifications() async {
  // Отменяем все уведомления
  await _service.cancelAllNotifications();
  
  // Очищаем локальное состояние
  _reminderId = null;
  
  // Очищаем SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear(); // или удаляем конкретные ключи
}
```

## 🧪 Тестирование

Для проверки исправлений:

1. Установите приложение
2. Настройте напоминания о еде
3. Перезапустите приложение несколько раз
4. Проверьте, что приходит только по одному уведомлению в назначенное время
5. При необходимости используйте метод `resetAllNotifications()` для полной очистки

## 📱 Особенности Android

На Android особенно важно:
- Использовать уникальные ID для уведомлений
- Правильно отменять старые уведомления
- Учитывать ограничения системы на фоновые процессы
- Тестировать на разных версиях Android

## 🔄 Миграция существующих пользователей

Для пользователей, у которых уже есть дублирующиеся уведомления:

1. Добавить кнопку "Сбросить уведомления" в настройки
2. Вызывать `resetAllNotifications()` при первом запуске после обновления
3. Предложить пользователю заново настроить напоминания 