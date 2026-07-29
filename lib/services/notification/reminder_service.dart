import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/notification_model.dart';
import 'notification_manager.dart';
import 'notification_service_interface.dart';
import '../../main.dart'; // Импортируем для использования appLog и localizeMessage
import '../../utils/app_logger.dart'; // Импортируем LogLevel

/// Сервис для управления напоминаниями
///
/// Предоставляет упрощенный интерфейс для создания и управления
/// напоминаниями для пользователя.
class ReminderService {
  // Singleton паттерн
  static final ReminderService _instance = ReminderService._internal();
  factory ReminderService() => _instance;
  ReminderService._internal();

  // Менеджер уведомлений
  final NotificationManager _notificationManager = NotificationManager();

  // Обработчик для действий с напоминаниями
  final _reminderTappedController =
      StreamController<NotificationModel>.broadcast();

  // Стрим для подписки на событие тапа по напоминанию
  Stream<NotificationModel> get onReminderTapped =>
      _reminderTappedController.stream;

  // Флаг инициализации
  bool _isInitialized = false;

  /// Инициализирует сервис напоминаний
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Инициализация менеджера уведомлений
    await _notificationManager.initialize();

    // Убираем автоматический запрос разрешений при инициализации
    // await _notificationManager.requestPermissions();

    // Подписка на события от уведомлений
    _notificationManager.onNotificationTapped.listen(_handleReminderTapped);

    _isInitialized = true;
    debugPrint('ReminderService инициализирован');
  }

  /// Создает простое напоминание на указанное время
  ///
  /// [title] - заголовок напоминания
  /// [message] - текст напоминания
  /// [time] - время, когда должно быть отправлено напоминание
  Future<String> createReminder({
    required String title,
    required String message,
    required DateTime time,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final notification = await _notificationManager.scheduleNotification(
      title: title,
      body: message,
      scheduledDate: time,
      type: NotificationType.reminder,
    );

    debugPrint('Создано напоминание на ${time.toString()}: $title');
    return notification.id;
  }

  /// Создает ежедневное напоминание
  ///
  /// [title] - заголовок напоминания
  /// [message] - текст напоминания
  /// [time] - время дня, когда должно быть отправлено напоминание
  Future<String> createDailyReminder({
    required String title,
    required String message,
    required DateTime time,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Создаем дату с указанным временем дня
    final now = DateTime.now();
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    // Если время уже прошло сегодня, планируем на завтра
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    // Создаем ОДНО повторяющееся напоминание, которое будет срабатывать в заданное время каждый день
    final notification =
        await _notificationManager.scheduleRepeatingNotification(
      title: title,
      body: message,
      interval: const Duration(days: 1),
      type: NotificationType.reminder,
      initialDateTime: scheduledDate,
    );

    debugPrint(
        'Создано ежедневное напоминание в ${time.hour}:${time.minute}: $title');
    return notification.id;
  }

  /// Создает еженедельное напоминание
  ///
  /// [title] - заголовок напоминания
  /// [message] - текст напоминания
  /// [dayOfWeek] - день недели (1-7, где 1 - понедельник)
  /// [time] - время дня, когда должно быть отправлено напоминание
  Future<String> createWeeklyReminder({
    required String title,
    required String message,
    required int dayOfWeek,
    required DateTime time,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Проверяем корректность дня недели
    if (dayOfWeek < 1 || dayOfWeek > 7) {
      throw ArgumentError('День недели должен быть от 1 до 7');
    }

    // Получаем текущую дату
    final now = DateTime.now();

    // Вычисляем, сколько дней нужно добавить, чтобы получить нужный день недели
    // Преобразуем день недели к формату DateTime, где 1 - понедельник, а 7 - воскресенье
    // DateTime использует 1 - Monday, 2 - Tuesday, ..., 7 - Sunday
    final currentDayOfWeek = now.weekday;

    // Вычисляем сколько дней нужно добавить
    int daysToAdd = dayOfWeek - currentDayOfWeek;
    if (daysToAdd < 0) {
      daysToAdd += 7; // Переходим на следующую неделю
    }

    // Если сегодня нужный день недели, но время уже прошло, переходим на следующую неделю
    if (daysToAdd == 0 && time.hour < now.hour ||
        (time.hour == now.hour && time.minute <= now.minute)) {
      daysToAdd = 7;
    }

    // Создаем запланированную дату
    final scheduledDate = DateTime(
      now.year,
      now.month,
      now.day + daysToAdd,
      time.hour,
      time.minute,
    );

    // Создаем повторяющееся напоминание с интервалом в 7 дней
    final notification =
        await _notificationManager.scheduleRepeatingNotification(
      title: title,
      body: message,
      interval: const Duration(days: 7),
      type: NotificationType.reminder,
      initialDateTime: scheduledDate,
    );

    debugPrint('Создано еженедельное напоминание на день $dayOfWeek: $title');
    return notification.id;
  }

  /// Напоминание о приложении
  ///
  /// Создает напоминание о приложении, которое будет отправлено через указанное количество дней
  Future<String> createAppReminder({
    String title = 'Используйте AI Video Maker',
    String message = 'Не забудьте открыть приложение AI Video Maker сегодня!',
    int daysLater = 3,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Создаем дату напоминания (текущая дата + указанное количество дней в полдень)
    final now = DateTime.now();
    final reminderDate = DateTime(
      now.year,
      now.month,
      now.day + daysLater,
      12, // Полдень
      0,
    );

    // Создаем напоминание
    final notification = await _notificationManager.scheduleNotification(
      title: title,
      body: message,
      scheduledDate: reminderDate,
      type: NotificationType.info,
    );

    debugPrint('Создано напоминание о приложении через $daysLater дней');
    return notification.id;
  }

  /// Отмена напоминания по его ID
  Future<void> cancelReminder(String reminderId) async {
    if (!_isInitialized) {
      await initialize();
    }

    await _notificationManager.cancelNotification(reminderId);
    debugPrint('Отменено напоминание: $reminderId');
  }

  /// Отмена всех напоминаний
  Future<void> cancelAllReminders() async {
    if (!_isInitialized) {
      await initialize();
    }

    await _notificationManager.cancelAllNotifications();
    appLog(localizeMessage('all_reminders_cancelled'),
        tag: 'FLUTTER', level: LogLevel.debug);
  }

  /// Получение списка всех активных напоминаний
  List<NotificationModel> getAllReminders() {
    return _notificationManager.getAllNotifications();
  }

  /// Обработчик нажатия на напоминание
  void _handleReminderTapped(NotificationModel notification) {
    _reminderTappedController.add(notification);
    debugPrint('Обработано нажатие на напоминание: ${notification.title}');
  }
}
