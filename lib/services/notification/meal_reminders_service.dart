import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service_interface.dart';
import 'reminder_service.dart';
import 'notification_manager.dart';
import 'local_notification_service.dart';
import '../../main.dart'; // Импортируем для использования appLog и localizeMessage
import '../../utils/app_logger.dart'; // Импортируем LogLevel
import '../localization/app_localization_service.dart';

/// Сервис для отправки напоминаний о приемах пищи
///
/// Предоставляет методы для настройки напоминаний о завтраке, обеде и ужине,
/// а также тестовое уведомление для демонстрации функциональности
class MealRemindersService {
  // Singleton паттерн
  static final MealRemindersService _instance =
      MealRemindersService._internal();
  factory MealRemindersService() => _instance;
  MealRemindersService._internal();

  // Константы для хранения ключей SharedPreferences
  static const String _prefKeyBreakfast = 'breakfast_reminder_id';
  static const String _prefKeyLunch = 'lunch_reminder_id';
  static const String _prefKeyDinner = 'dinner_reminder_id';
  static const String _prefKeyRemindersEnabled =
      'reminders_enabled'; // Новый ключ для статуса

  // Внутренний сервис напоминаний
  final ReminderService _reminderService = ReminderService();

  // ID для уведомлений о приемах пищи
  String? _breakfastReminderId;
  String? _lunchReminderId;
  String? _dinnerReminderId;
  bool _remindersEnabled = false; // Флаг, указывающий что напоминания активны

  // Флаг инициализации
  bool _isInitialized = false;

  /// Инициализирует сервис напоминаний о приемах пищи
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Инициализируем базовый сервис напоминаний
    await _reminderService.initialize();

    // Загружаем сохраненные ID напоминаний
    await _loadSavedReminderIds();

    // ВАЖНО: ставим флаг инициализации ДО автоконфигурации,
    // чтобы исключить рекурсию initialize() → setupAll... → initialize()
    _isInitialized = true;

    // Дефолт: включено. Если первый запуск или включено, но нет ID — создаём.
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasFlag = prefs.containsKey(_prefKeyRemindersEnabled);
      final enabled =
          prefs.getBool(_prefKeyRemindersEnabled) ?? true; // дефолт: вкл
      final hasAny = _breakfastReminderId != null ||
          _lunchReminderId != null ||
          _dinnerReminderId != null;
      if (!hasFlag) {
        await setupAllMealReminders();
      } else if (enabled && !hasAny) {
        await setupAllMealReminders();
      }
    } catch (_) {}
    appLog(localizeMessage('meal_reminders_service_initialized'),
        tag: 'FLUTTER', level: LogLevel.debug);
  }

  /// Загружает сохраненные ID напоминаний из SharedPreferences
  Future<void> _loadSavedReminderIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      _breakfastReminderId = prefs.getString(_prefKeyBreakfast);
      _lunchReminderId = prefs.getString(_prefKeyLunch);
      _dinnerReminderId = prefs.getString(_prefKeyDinner);
      _remindersEnabled = prefs.getBool(_prefKeyRemindersEnabled) ?? false;

      appLog(localizeMessage('loaded_saved_reminders'),
          tag: 'FLUTTER', level: LogLevel.debug);
      appLog(
          localizeMessage('breakfast_reminder',
              [_breakfastReminderId ?? localizeMessage('not_configured')]),
          tag: 'FLUTTER',
          level: LogLevel.debug);
      appLog(
          localizeMessage('lunch_reminder',
              [_lunchReminderId ?? localizeMessage('not_configured')]),
          tag: 'FLUTTER',
          level: LogLevel.debug);
      appLog(
          localizeMessage('dinner_reminder',
              [_dinnerReminderId ?? localizeMessage('not_configured')]),
          tag: 'FLUTTER',
          level: LogLevel.debug);
      appLog(
          localizeMessage('reminders_status', [
            _remindersEnabled
                ? localizeMessage('enabled')
                : localizeMessage('disabled')
          ]),
          tag: 'FLUTTER',
          level: LogLevel.debug);
    } catch (e) {
      appLog(localizeMessage('reminder_load_error', ['$e']),
          tag: 'FLUTTER', level: LogLevel.error);
    }
  }

  /// Сохраняет ID напоминаний в SharedPreferences
  Future<void> _saveReminderIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_breakfastReminderId != null) {
        await prefs.setString(_prefKeyBreakfast, _breakfastReminderId!);
      }

      if (_lunchReminderId != null) {
        await prefs.setString(_prefKeyLunch, _lunchReminderId!);
      }

      if (_dinnerReminderId != null) {
        await prefs.setString(_prefKeyDinner, _dinnerReminderId!);
      }

      // Обновляем флаг статуса напоминаний
      final hasAnyReminders = _breakfastReminderId != null ||
          _lunchReminderId != null ||
          _dinnerReminderId != null;

      await prefs.setBool(_prefKeyRemindersEnabled, hasAnyReminders);
      _remindersEnabled = hasAnyReminders;

      debugPrint(
          'Сохранены ID напоминаний, статус: ${hasAnyReminders ? "включены" : "выключены"}');
    } catch (e) {
      debugPrint('Ошибка при сохранении ID напоминаний: $e');
    }
  }

  /// Очищает сохраненные ID напоминаний в SharedPreferences
  Future<void> _clearSavedReminderIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove(_prefKeyBreakfast);
      await prefs.remove(_prefKeyLunch);
      await prefs.remove(_prefKeyDinner);
      await prefs.setBool(_prefKeyRemindersEnabled, false);
      _remindersEnabled = false;

      debugPrint('Очищены сохраненные ID напоминаний');
    } catch (e) {
      debugPrint('Ошибка при очистке сохраненных ID напоминаний: $e');
    }
  }

  /// Запрашивает разрешение на отправку уведомлений
  ///
  /// Возвращает true, если разрешения предоставлены
  Future<bool> requestNotificationPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Запрашиваем разрешения напрямую через менеджер уведомлений
    final notificationManager = NotificationManager();
    return await notificationManager.requestPermissions();
  }

  /// Проверяет, включены ли уведомления в настройках системы
  ///
  /// Возвращает true, если разрешения на уведомления предоставлены
  Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Проверяем статус разрешений через менеджер уведомлений
    final notificationManager = NotificationManager();
    return await notificationManager.areNotificationsEnabled();
  }

  /// Проверяет статус разрешений на уведомления и текущие настройки
  ///
  /// Возвращает строку с детальной информацией о состоянии уведомлений
  Future<String> checkNotificationStatus() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final notificationManager = NotificationManager();
      final bool hasPermissions =
          await notificationManager.areNotificationsEnabled();

      // Получаем информацию о платформе
      final String platform = Platform.isIOS
          ? 'iOS ${Platform.operatingSystemVersion}'
          : Platform.isAndroid
              ? 'Android ${Platform.operatingSystemVersion}'
              : 'Другая платформа';

      // Проверяем, настроены ли напоминания
      final bool areRemindersConfigured = areRemindersSet();

      // Формируем отчет
      final StringBuffer report = StringBuffer();
      report.writeln('Платформа: $platform');
      report.writeln(
          'Разрешения на уведомления: ${hasPermissions ? "Да" : "Нет"}');
      report.writeln(
          'Напоминания настроены: ${areRemindersConfigured ? "Да" : "Нет"}');

      if (areRemindersConfigured) {
        if (_breakfastReminderId != null) report.writeln('- Завтрак: Да');
        if (_lunchReminderId != null) report.writeln('- Обед: Да');
        if (_dinnerReminderId != null) report.writeln('- Ужин: Да');
      }

      debugPrint('Отчет о состоянии уведомлений:');
      debugPrint(report.toString());

      return report.toString();
    } catch (e) {
      debugPrint('Ошибка при проверке статуса уведомлений: $e');
      return 'Ошибка при проверке статуса: $e';
    }
  }

  /// Отправляет тестовое уведомление через 10 секунд
  Future<String> sendTestNotification() async {
    if (!_isInitialized) {
      await initialize();
    }

    debugPrint('Отправка тестового уведомления...');

    // Используем прямой вызов через NotificationManager для мгновенного уведомления
    final notificationManager = NotificationManager();

    // Отправляем мгновенное уведомление
    final notification = await notificationManager.sendNotification(
      title: '🔔 ТЕСТ AI Video Maker - Немедленное!',
      body:
          'Это немедленное тестовое уведомление. Если вы его видите, значит уведомления работают!',
      type: NotificationType.critical, // Используем критический приоритет
    );

    debugPrint('Отправлено мгновенное тестовое уведомление');

    // Также отправляем отложенное уведомление через 5 секунд
    final now = DateTime.now().add(const Duration(seconds: 5));
    await _reminderService.createReminder(
      title: '⏰ ТЕСТ AI Video Maker - Отложенное!',
      message:
          'Это отложенное тестовое уведомление (5 сек). Отслеживайте калории и БЖУ с AI Video Maker!',
      time: now,
    );

    debugPrint('Запланировано тестовое уведомление через 5 секунд');
    return notification.id; // Возвращаем ID мгновенного уведомления
  }

  /// Отправляет немедленное уведомление, предназначенное для показа на переднем плане
  ///
  /// Подходит для тестирования, когда приложение открыто
  Future<String> sendImmediateNotification() async {
    if (!_isInitialized) {
      await initialize();
    }

    debugPrint('Отправка немедленного уведомления для переднего плана...');

    // Используем сервис локальных уведомлений напрямую с новым методом
    final localNotificationService = LocalNotificationService();
    try {
      await localNotificationService.sendForegroundNotification();
      debugPrint('✅ Успешно отправлено уведомление для переднего плана');
    } catch (e) {
      debugPrint('❌ Ошибка при отправке уведомления для переднего плана: $e');
    }

    // Также используем уведомление через NotificationManager как запасной вариант
    final notificationManager = NotificationManager();
    final notification = await notificationManager.sendNotification(
      title: '🔔 ТЕСТ - Видимость на переднем плане',
      body:
          'Тестирование видимости уведомлений когда приложение открыто. Время: ${DateTime.now().toString()}',
      type: NotificationType.critical,
    );

    debugPrint('Отправлено уведомление для переднего плана');
    return notification.id;
  }

  /// Отправляет немедленное реальное напоминание о ближайшем приёме пищи
  Future<void> sendImmediateRealReminder({
    IAppLocalizationService? localizationService,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Определяем ближайший тип приёма пищи по сохранённым или дефолтным временам
    final prefs = await SharedPreferences.getInstance();
    final int bh = prefs.getInt('breakfast_hour') ?? 8;
    final int bm = prefs.getInt('breakfast_minute') ?? 0;
    final int lh = prefs.getInt('lunch_hour') ?? 13;
    final int lm = prefs.getInt('lunch_minute') ?? 0;
    final int dh = prefs.getInt('dinner_hour') ?? 19;
    final int dm = prefs.getInt('dinner_minute') ?? 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final times = <String, DateTime>{
      'breakfast': DateTime(today.year, today.month, today.day, bh, bm),
      'lunch': DateTime(today.year, today.month, today.day, lh, lm),
      'dinner': DateTime(today.year, today.month, today.day, dh, dm),
    };
    // Находим ближайшее следующее время
    String selected = 'dinner';
    Duration minDelta = const Duration(days: 1);
    times.forEach((type, dt) {
      var target = dt;
      if (target.isBefore(now)) target = target.add(const Duration(days: 1));
      final diff = target.difference(now);
      if (diff < minDelta) {
        minDelta = diff;
        selected = type;
      }
    });

    String title;
    String body;
    switch (selected) {
      case 'breakfast':
        title = localizationService?.translate('breakfast_reminder_title') ??
            '🍳 Время завтрака!';
        body = localizationService?.translate('breakfast_reminder_message') ??
            'Доброе утро! Не забудьте отследить калории и БЖУ завтрака в AI Video Maker.';
        break;
      case 'lunch':
        title = localizationService?.translate('lunch_reminder_title') ??
            '🍲 Пора обедать!';
        body = localizationService?.translate('lunch_reminder_message') ??
            'Не забудьте отследить калории обеда в AI Video Maker.';
        break;
      default:
        title = localizationService?.translate('dinner_reminder_title') ??
            '🍽️ Время ужина!';
        body = localizationService?.translate('dinner_reminder_message') ??
            'Завершите день правильно! Отследите ужин в AI Video Maker.';
    }

    final local = LocalNotificationService();
    await local.showLocalNotification(
      id: 7711,
      title: title,
      body: body,
      type: NotificationType.reminder,
      payload: 'meal_immediate_$selected',
    );
  }

  /// Настраивает ежедневное напоминание о завтраке
  ///
  /// [hour] - час дня для отправки напоминания (по умолчанию 8:00)
  /// [minute] - минута для отправки напоминания
  /// [localizationService] - сервис локализации для получения переводов
  Future<String> setupBreakfastReminder({
    int hour = 8,
    int minute = 0,
    IAppLocalizationService? localizationService,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Если напоминание уже настроено, отменяем его перед созданием нового
    if (_breakfastReminderId != null) {
      await _reminderService.cancelReminder(_breakfastReminderId!);
    }

    // Создаем время для напоминания
    final reminderTime = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      hour,
      minute,
    );

    // Получаем локализованные строки
    final title = localizationService?.translate('breakfast_reminder_title') ??
        '🍳 Time for breakfast!';
    final message = localizationService
            ?.translate('breakfast_reminder_message') ??
        'Good morning! Track the calories and macros of your breakfast in the AI Video Maker app. This will help control your nutrition.';

    // Создаем ежедневное напоминание о завтраке
    _breakfastReminderId = await _reminderService.createDailyReminder(
      title: title,
      message: message,
      time: reminderTime,
    );

    // Сохраняем настройки времени и флаг
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('breakfast_hour', hour);
    await prefs.setInt('breakfast_minute', minute);
    await prefs.setBool('had_breakfast_reminder', true);

    // Сохраняем ID напоминания
    await _saveReminderIds();

    debugPrint('Настроено ежедневное напоминание о завтраке в $hour:$minute');
    return _breakfastReminderId!;
  }

  /// Настраивает ежедневное напоминание об обеде
  ///
  /// [hour] - час дня для отправки напоминания (по умолчанию 13:00)
  /// [minute] - минута для отправки напоминания
  /// [localizationService] - сервис локализации для получения переводов
  Future<String> setupLunchReminder({
    int hour = 13,
    int minute = 0,
    IAppLocalizationService? localizationService,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Если напоминание уже настроено, отменяем его перед созданием нового
    if (_lunchReminderId != null) {
      await _reminderService.cancelReminder(_lunchReminderId!);
    }

    // Создаем время для напоминания
    final reminderTime = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      hour,
      minute,
    );

    // Получаем локализованные строки
    final title = localizationService?.translate('lunch_reminder_title') ??
        '🍲 Time for lunch!';
    final message = localizationService?.translate('lunch_reminder_message') ??
        'Don\'t forget to track the calories of your lunch in AI Video Maker. Knowing the macros helps maintain balanced nutrition.';

    // Создаем ежедневное напоминание об обеде
    _lunchReminderId = await _reminderService.createDailyReminder(
      title: title,
      message: message,
      time: reminderTime,
    );

    // Сохраняем настройки времени и флаг
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lunch_hour', hour);
    await prefs.setInt('lunch_minute', minute);
    await prefs.setBool('had_lunch_reminder', true);

    // Сохраняем ID напоминания
    await _saveReminderIds();

    debugPrint('Настроено ежедневное напоминание об обеде в $hour:$minute');
    return _lunchReminderId!;
  }

  /// Настраивает ежедневное напоминание об ужине
  ///
  /// [hour] - час дня для отправки напоминания (по умолчанию 19:00)
  /// [minute] - минута для отправки напоминания
  /// [localizationService] - сервис локализации для получения переводов
  Future<String> setupDinnerReminder({
    int hour = 19,
    int minute = 0,
    IAppLocalizationService? localizationService,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Если напоминание уже настроено, отменяем его перед созданием нового
    if (_dinnerReminderId != null) {
      await _reminderService.cancelReminder(_dinnerReminderId!);
    }

    // Создаем время для напоминания
    final reminderTime = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      hour,
      minute,
    );

    // Получаем локализованные строки
    final title = localizationService?.translate('dinner_reminder_title') ??
        '🍽️ Time for dinner!';
    final message = localizationService?.translate('dinner_reminder_message') ??
        'End the day right! Track the calories and macros of your dinner in AI Video Maker to control your daily diet.';

    // Создаем ежедневное напоминание об ужине
    _dinnerReminderId = await _reminderService.createDailyReminder(
      title: title,
      message: message,
      time: reminderTime,
    );

    // Сохраняем настройки времени и флаг
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dinner_hour', hour);
    await prefs.setInt('dinner_minute', minute);
    await prefs.setBool('had_dinner_reminder', true);

    // Сохраняем ID напоминания
    await _saveReminderIds();

    debugPrint('Настроено ежедневное напоминание об ужине в $hour:$minute');
    return _dinnerReminderId!;
  }

  /// Настраивает все напоминания о приемах пищи со стандартными значениями времени
  ///
  /// [localizationService] - сервис локализации для получения переводов
  Future<void> setupAllMealReminders({
    IAppLocalizationService? localizationService,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    await setupBreakfastReminder(localizationService: localizationService);
    await setupLunchReminder(localizationService: localizationService);
    await setupDinnerReminder(localizationService: localizationService);

    // Проверяем и сохраняем статус напоминаний
    await _saveReminderIds();

    debugPrint('Настроены все напоминания о приемах пищи');
  }

  /// Отменяет все напоминания о приемах пищи
  Future<void> cancelAllMealReminders() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_breakfastReminderId != null) {
      await _reminderService.cancelReminder(_breakfastReminderId!);
      _breakfastReminderId = null;
    }

    if (_lunchReminderId != null) {
      await _reminderService.cancelReminder(_lunchReminderId!);
      _lunchReminderId = null;
    }

    if (_dinnerReminderId != null) {
      await _reminderService.cancelReminder(_dinnerReminderId!);
      _dinnerReminderId = null;
    }

    // Очищаем сохраненные ID и флаги
    await _clearSavedReminderIds();

    // Дополнительно очищаем флаги напоминаний
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('had_breakfast_reminder', false);
    await prefs.setBool('had_lunch_reminder', false);
    await prefs.setBool('had_dinner_reminder', false);

    debugPrint('Отменены все напоминания о приемах пищи');
  }

  /// Перепланирует все существующие напоминания о приемах пищи на следующие дни
  ///
  /// Этот метод должен вызываться периодически, например, раз в день или
  /// при запуске приложения, чтобы обеспечить наличие уведомлений на будущие дни
  ///
  /// [localizationService] - сервис локализации для получения переводов
  Future<void> rescheduleAllReminders({
    IAppLocalizationService? localizationService,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Проверяем, настроены ли уведомления
    if (!areRemindersSet()) {
      debugPrint('Нет настроенных напоминаний для перепланирования');
      return;
    }

    debugPrint('🔄 Начинаем перепланирование напоминаний...');

    // Сначала ПОЛНОСТЬЮ очищаем все существующие напоминания
    await cancelAllMealReminders();

    // Загружаем сохраненные настройки времени из SharedPreferences
    final prefs = await SharedPreferences.getInstance();

    // Получаем сохраненные времена или используем значения по умолчанию
    final breakfastHour = prefs.getInt('breakfast_hour') ?? 8;
    final breakfastMinute = prefs.getInt('breakfast_minute') ?? 0;
    final lunchHour = prefs.getInt('lunch_hour') ?? 13;
    final lunchMinute = prefs.getInt('lunch_minute') ?? 0;
    final dinnerHour = prefs.getInt('dinner_hour') ?? 19;
    final dinnerMinute = prefs.getInt('dinner_minute') ?? 0;

    // Проверяем, какие напоминания были настроены ранее
    final hadBreakfast = prefs.getBool('had_breakfast_reminder') ?? false;
    final hadLunch = prefs.getBool('had_lunch_reminder') ?? false;
    final hadDinner = prefs.getBool('had_dinner_reminder') ?? false;

    // Пересоздаем только те напоминания, которые были настроены ранее
    if (hadBreakfast) {
      _breakfastReminderId = await setupBreakfastReminder(
        hour: breakfastHour,
        minute: breakfastMinute,
        localizationService: localizationService,
      );
    }

    if (hadLunch) {
      _lunchReminderId = await setupLunchReminder(
        hour: lunchHour,
        minute: lunchMinute,
        localizationService: localizationService,
      );
    }

    if (hadDinner) {
      _dinnerReminderId = await setupDinnerReminder(
        hour: dinnerHour,
        minute: dinnerMinute,
        localizationService: localizationService,
      );
    }

    debugPrint('✅ Все напоминания о приемах пищи успешно перепланированы');
  }

  /// Проверяет, настроены ли напоминания о приемах пищи
  bool areRemindersSet() {
    // Проверяем как флаг, так и наличие ID напоминаний
    return _remindersEnabled ||
        _breakfastReminderId != null ||
        _lunchReminderId != null ||
        _dinnerReminderId != null;
  }

  /// Полностью очищает все уведомления и сбрасывает состояние сервиса
  ///
  /// Этот метод следует использовать для решения проблем с дублированием уведомлений
  Future<void> resetAllNotifications() async {
    if (!_isInitialized) {
      await initialize();
    }

    appLog(localizeMessage('reset_notifications_start'),
        tag: 'FLUTTER', level: LogLevel.debug);

    // Отменяем все уведомления через базовый сервис
    await _reminderService.cancelAllReminders();

    // Очищаем локальные переменные
    _breakfastReminderId = null;
    _lunchReminderId = null;
    _dinnerReminderId = null;
    _remindersEnabled = false;

    // Полностью очищаем SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyBreakfast);
    await prefs.remove(_prefKeyLunch);
    await prefs.remove(_prefKeyDinner);
    await prefs.setBool(_prefKeyRemindersEnabled, false);

    // Очищаем флаги напоминаний
    await prefs.setBool('had_breakfast_reminder', false);
    await prefs.setBool('had_lunch_reminder', false);
    await prefs.setBool('had_dinner_reminder', false);

    // Очищаем настройки времени (опционально)
    await prefs.remove('breakfast_hour');
    await prefs.remove('breakfast_minute');
    await prefs.remove('lunch_hour');
    await prefs.remove('lunch_minute');
    await prefs.remove('dinner_hour');
    await prefs.remove('dinner_minute');

    appLog(localizeMessage('reset_notifications_complete'),
        tag: 'FLUTTER', level: LogLevel.debug);
  }
}
