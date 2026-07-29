import 'dart:async';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'notification_service_interface.dart';
import '../../main.dart';
import '../../utils/app_logger.dart';

/// Константы для каналов уведомлений
const String _mainChannelKey = 'aivideomaker_main_channel';
const String _mainChannelName = 'AI Video Maker уведомления';
const String _mainChannelDescription =
    'Основные уведомления от приложения AI Video Maker';

/// Реализация сервиса локальных уведомлений
///
/// Использует пакет awesome_notifications для отправки
/// уведомлений на устройстве пользователя без серверной части.
class LocalNotificationService implements NotificationServiceInterface {
  // Singleton паттерн
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  void Function(String? payload)? _onNotificationReceived;
  void Function(String? payload)? _onNotificationTapped;

  static String? pendingTapPayload;

  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Инициализация часовых поясов для планирования уведомлений
    tz.initializeTimeZones();
    appLog(localizeMessage('timezones_initialized'),
        tag: 'FLUTTER', level: LogLevel.debug);

    // Определяем список каналов уведомлений
    List<NotificationChannel> notificationChannels = [
      // Основной канал для большинства уведомлений
      NotificationChannel(
        channelKey: _mainChannelKey,
        channelName: _mainChannelName,
        channelDescription: _mainChannelDescription,
        defaultColor: Colors.blue,
        ledColor: Colors.blue,
        importance: NotificationImportance.High,
        channelShowBadge: true,
        playSound: true,
        enableVibration: true,
        icon: 'resource://drawable/push_logo',
      ),
      // Канал для критических уведомлений
      NotificationChannel(
        channelKey: 'aivideomaker_critical_channel',
        channelName: 'AI Video Maker критические уведомления',
        channelDescription: 'Критически важные уведомления',
        defaultColor: Colors.red,
        ledColor: Colors.red,
        importance: NotificationImportance.Max,
        channelShowBadge: true,
        playSound: true,
        enableVibration: true,
        vibrationPattern: lowVibrationPattern,
        icon: 'resource://drawable/push_logo',
      ),
    ];

    // Инициализация AwesomeNotifications
    await AwesomeNotifications().initialize(
      'resource://drawable/push_logo',
      notificationChannels,
      debug: kDebugMode,
    );

    // Настройка обработчиков событий
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onActionReceivedMethod,
      onNotificationCreatedMethod: _onNotificationCreatedMethod,
      onNotificationDisplayedMethod: _onNotificationDisplayedMethod,
      onDismissActionReceivedMethod: _onDismissActionReceivedMethod,
    );

    _isInitialized = true;
    appLog(localizeMessage('local_notification_service_initialized'),
        tag: 'FLUTTER', level: LogLevel.debug);
  }

  @override
  Future<bool> requestPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Запрос разрешений у пользователя
    final result =
        await AwesomeNotifications().requestPermissionToSendNotifications();
    debugPrint('Результат запроса разрешений: $result');
    return result;
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Проверка разрешений
    final result = await AwesomeNotifications().isNotificationAllowed();
    debugPrint('Статус разрешений на уведомления: $result');
    return result;
  }

  @override
  Future<void> registerDevice() async {
    // Для локальных уведомлений не требуется регистрация на сервере
    debugPrint('Регистрация устройства для локальных уведомлений не требуется');
  }

  @override
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    NotificationType type = NotificationType.info,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    debugPrint(
        'Подготовка к отправке локального уведомления... id=$id, title=$title');

    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: _getChannelKeyFromType(type),
          title: title,
          body: body,
          payload: payload != null ? {'data': payload} : null,
          notificationLayout: NotificationLayout.Default,
          color: _getColorFromType(type),
          backgroundColor: _getColorFromType(type).withOpacity(0.1),
          category: NotificationCategory.Message,
          icon: 'resource://drawable/push_logo',
        ),
      );

      debugPrint('Успешно отправлено локальное уведомление: $title');

      // Вызываем callback если он установлен
      if (_onNotificationReceived != null) {
        _onNotificationReceived!(payload);
      }
    } catch (e) {
      debugPrint('ОШИБКА при отправке уведомления: $e');
    }
  }

  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
    NotificationType type = NotificationType.info,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final timeZone =
          await AwesomeNotifications().getLocalTimeZoneIdentifier();
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: _getChannelKeyFromType(type),
          title: title,
          body: body,
          payload: payload != null ? {'data': payload} : null,
          notificationLayout: NotificationLayout.Default,
          color: _getColorFromType(type),
          category: NotificationCategory.Message,
          icon: 'resource://drawable/push_logo',
        ),
        schedule: NotificationCalendar(
          year: scheduledDate.year,
          month: scheduledDate.month,
          day: scheduledDate.day,
          hour: scheduledDate.hour,
          minute: scheduledDate.minute,
          second: scheduledDate.second,
          preciseAlarm: true,
          allowWhileIdle: true,
          timeZone: timeZone,
        ),
      );

      debugPrint('Запланировано уведомление на $scheduledDate: $title');
    } catch (e) {
      debugPrint('ОШИБКА при планировании уведомления: $e');
    }
  }

  @override
  Future<void> periodicallyShowNotification({
    required int id,
    required String title,
    required String body,
    required Duration interval,
    String? payload,
    NotificationType type = NotificationType.info,
    DateTime? initialDateTime,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Если initialDateTime не указан, используем текущее время
      final now = DateTime.now();

      // Создаем schedule в зависимости от наличия initialDateTime
      NotificationSchedule schedule;

      if (initialDateTime != null) {
        // Если время уже прошло сегодня, планируем на завтра
        if (initialDateTime.isBefore(now)) {
          initialDateTime = DateTime(
            now.year,
            now.month,
            now.day + 1,
            initialDateTime.hour,
            initialDateTime.minute,
          );
        }

        // Создаем расписание с интервалом и начальным временем
        schedule = NotificationCalendar(
          hour: initialDateTime.hour,
          minute: initialDateTime.minute,
          second: 0,
          repeats: true,
          preciseAlarm: true,
          timeZone: await AwesomeNotifications().getLocalTimeZoneIdentifier(),
        );

        debugPrint(
            'Настроено периодическое уведомление с начальным временем ${initialDateTime.hour}:${initialDateTime.minute}');
      } else {
        // Используем интервальное расписание
        schedule = NotificationInterval(
          interval: Duration(seconds: interval.inSeconds),
          repeats: true,
          preciseAlarm: true,
          timeZone: await AwesomeNotifications().getLocalTimeZoneIdentifier(),
        );

        debugPrint(
            'Настроено периодическое уведомление с интервалом ${interval.inMinutes} минут');
      }

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: id,
          channelKey: _getChannelKeyFromType(type),
          title: title,
          body: body,
          payload: payload != null ? {'data': payload} : null,
          notificationLayout: NotificationLayout.Default,
          color: _getColorFromType(type),
          category: NotificationCategory.Reminder,
          icon: 'resource://drawable/push_logo',
        ),
        schedule: schedule,
      );

      debugPrint('Настроено периодическое уведомление: $title');
    } catch (e) {
      debugPrint('ОШИБКА при настройке периодического уведомления: $e');
    }
  }

  @override
  Future<void> cancelNotification(int id) async {
    await AwesomeNotifications().cancel(id);
    debugPrint('Отменено уведомление с ID: $id');
  }

  @override
  Future<void> cancelAllNotifications() async {
    await AwesomeNotifications().cancelAll();
    // ВАЖНО: Сбрасываем badge count при отмене всех уведомлений
    await resetBadgeCount();
    appLog(localizeMessage('all_notifications_cancelled'),
        tag: 'FLUTTER', level: LogLevel.debug);
  }

  @override
  void setOnNotificationReceived(
      void Function(String? payload) onNotificationReceived) {
    _onNotificationReceived = onNotificationReceived;
  }

  @override
  void setOnNotificationTapped(
      void Function(String? payload) onNotificationTapped) {
    _onNotificationTapped = onNotificationTapped;
  }

  @override
  Future<void> handleNotificationPayload(String? payload) async {
    // Обработка полезной нагрузки уведомления
    debugPrint('Обработка payload: $payload');
  }

  /// Сбрасывает badge count (красную цифру на иконке приложения)
  ///
  /// Это критически важно для iOS, так как badge count накапливается
  /// и НЕ сбрасывается автоматически когда пользователь очищает уведомления
  Future<void> resetBadgeCount() async {
    try {
      await AwesomeNotifications().resetGlobalBadge();
      debugPrint('✅ Badge count сброшен до 0');
    } catch (e) {
      debugPrint('❌ Ошибка сброса badge count: $e');
    }
  }

  /// Устанавливает конкретное значение badge count
  Future<void> setBadgeCount(int count) async {
    try {
      await AwesomeNotifications().setGlobalBadgeCounter(count);
      debugPrint('✅ Badge count установлен в $count');
    } catch (e) {
      debugPrint('❌ Ошибка установки badge count: $e');
    }
  }

  /// Получает текущее значение badge count
  Future<int> getBadgeCount() async {
    try {
      final count = await AwesomeNotifications().getGlobalBadgeCounter();
      debugPrint('ℹ️ Текущий badge count: $count');
      return count;
    } catch (e) {
      debugPrint('❌ Ошибка получения badge count: $e');
      return 0;
    }
  }

  // Обработчик события создания уведомления
  @pragma('vm:entry-point')
  static Future<void> _onNotificationCreatedMethod(
      ReceivedNotification receivedNotification) async {
    debugPrint('Уведомление создано: ${receivedNotification.id}');
  }

  // Обработчик события отображения уведомления
  @pragma('vm:entry-point')
  static Future<void> _onNotificationDisplayedMethod(
      ReceivedNotification receivedNotification) async {
    debugPrint('Уведомление отображено: ${receivedNotification.id}');
  }

  @pragma('vm:entry-point')
  static Future<void> _onActionReceivedMethod(
      ReceivedAction receivedAction) async {
    debugPrint('Действие с уведомлением: ${receivedAction.id}');

    final payload = receivedAction.payload?['data'];
    if (_instance._onNotificationTapped != null) {
      _instance._onNotificationTapped!(payload);
    } else if (payload != null) {
      pendingTapPayload = payload;
    }
  }

  // Обработчик события закрытия уведомления
  @pragma('vm:entry-point')
  static Future<void> _onDismissActionReceivedMethod(
      ReceivedAction receivedAction) async {
    debugPrint('Уведомление закрыто: ${receivedAction.id}');
  }

  // Вспомогательные методы

  // Получение ключа канала из типа уведомления
  String _getChannelKeyFromType(NotificationType type) {
    switch (type) {
      case NotificationType.info:
      case NotificationType.reminder:
      case NotificationType.warning:
        return _mainChannelKey;
      case NotificationType.critical:
        return 'aivideomaker_critical_channel';
    }
  }

  // Получение цвета уведомления из типа
  Color _getColorFromType(NotificationType type) {
    switch (type) {
      case NotificationType.info:
        return Colors.blue;
      case NotificationType.reminder:
        return Colors.orange;
      case NotificationType.warning:
        return Colors.amber;
      case NotificationType.critical:
        return Colors.red;
    }
  }

  /// Отправляет уведомление с высоким приоритетом, настроенное для показа на переднем плане
  Future<void> sendForegroundNotification() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Генерируем уникальный ID для уведомления
      final int notificationId = DateTime.now().millisecondsSinceEpoch % 100000;
      final String title = "⚠️ Важное уведомление";
      final String body =
          "Это специальное уведомление для переднего плана (${DateTime.now().toString().substring(11, 19)})";

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notificationId,
          channelKey: 'aivideomaker_critical_channel',
          title: title,
          body: body,
          payload: {'data': 'foreground_notification'},
          notificationLayout: NotificationLayout.Default,
          color: Colors.red,
          backgroundColor: Colors.red.withOpacity(0.1),
          category: NotificationCategory.Alarm,
          wakeUpScreen: true,
          fullScreenIntent: true,
          autoDismissible: false,
          icon: 'resource://drawable/push_logo',
        ),
      );

      debugPrint('✅ Успешно отправлено уведомление для переднего плана');
    } catch (e) {
      debugPrint('❌ ОШИБКА при отправке уведомления для переднего плана: $e');
      rethrow;
    }
  }

  /// Отправляет отладочное уведомление с максимальным приоритетом
  Future<void> sendDebugNotification() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Генерируем уникальный ID
      final int notificationId = DateTime.now().millisecondsSinceEpoch % 100000;

      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notificationId,
          channelKey: 'aivideomaker_critical_channel',
          title: '⚠️ ОТЛАДКА',
          body:
              'Это тестовое отладочное уведомление с высоким приоритетом! Время: ${DateTime.now().toString()}',
          notificationLayout: NotificationLayout.Default,
          color: Colors.purple,
          backgroundColor: Colors.purple.withOpacity(0.1),
          category: NotificationCategory.Status,
          wakeUpScreen: true,
          icon: 'resource://drawable/push_logo',
        ),
      );

      debugPrint('✅ Отладочное уведомление отправлено');
    } catch (e) {
      debugPrint('❌ ОШИБКА при отправке отладочного уведомления: $e');
    }
  }
}
