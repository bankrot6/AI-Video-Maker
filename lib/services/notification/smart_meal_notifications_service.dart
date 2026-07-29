import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/meal_model.dart';
import '../../repositories/meal_repository.dart';
import 'local_notification_service.dart';
import 'notification_service_interface.dart';
import '../../main.dart';
import '../../utils/app_logger.dart';
import '../localization/app_localization_service.dart';

/// Умный сервис уведомлений о приеме пищи
///
/// Реализует best practices для мобильных уведомлений:
/// - Не отправляет уведомления если пользователь недавно добавил еду (1-2 часа)
/// - Использует стандартные времена приемов пищи
/// - Минимизирует переписывание графика уведомлений
/// - Централизованно управляет всеми напоминаниями о еде
class SmartMealNotificationsService {
  // Singleton паттерн
  static final SmartMealNotificationsService _instance =
      SmartMealNotificationsService._internal();
  factory SmartMealNotificationsService() => _instance;
  SmartMealNotificationsService._internal();

  // Стандартные времена уведомлений (лучшие практики)
  static const Map<String, Map<String, int>> _standardMealTimes = {
    'breakfast': {'hour': 8, 'minute': 0}, // 8:00 утра
    'lunch': {'hour': 13, 'minute': 0}, // 13:00 дня
    'dinner': {'hour': 19, 'minute': 0}, // 19:00 вечера
  };

  // ID уведомлений (постоянные для избежания дублей)
  static const Map<String, int> _notificationIds = {
    'breakfast': 1001,
    'lunch': 1002,
    'dinner': 1003,
  };

  // Константы для настроек
  static const String _prefKeyNotificationsEnabled =
      'smart_notifications_enabled';
  static const String _prefKeyNotificationsSetup =
      'smart_notifications_setup_completed';

  // Окно времени для проверки недавнего приема пищи (1-2 часа)
  static const Duration _recentMealWindow = Duration(hours: 1, minutes: 30);

  final LocalNotificationService _notificationService =
      LocalNotificationService();
  bool _isInitialized = false;
  bool _notificationsEnabled = false;

  /// Инициализирует сервис умных уведомлений
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _notificationService.initialize();
    await _loadSettings();

    _isInitialized = true;
    appLog('SmartMealNotificationsService инициализирован',
        tag: 'SMART_NOTIFICATIONS', level: LogLevel.info);
  }

  /// Загружает сохраненные настройки
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled =
          prefs.getBool(_prefKeyNotificationsEnabled) ?? false;

      appLog('Настройки уведомлений загружены: enabled=$_notificationsEnabled',
          tag: 'SMART_NOTIFICATIONS', level: LogLevel.debug);
    } catch (e) {
      appLog('Ошибка загрузки настроек уведомлений: $e',
          tag: 'SMART_NOTIFICATIONS', level: LogLevel.error);
    }
  }

  /// Настраивает умные уведомления о приемах пищи
  ///
  /// Этот метод вызывается ТОЛЬКО ОДИН РАЗ при первой настройке
  /// или когда пользователь явно включает уведомления
  Future<bool> setupSmartNotifications({
    IAppLocalizationService? localizationService,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // Проверяем разрешения
      final hasPermissions =
          await _notificationService.areNotificationsEnabled();
      if (!hasPermissions) {
        appLog('Нет разрешений на уведомления',
            tag: 'SMART_NOTIFICATIONS', level: LogLevel.warning);
        return false;
      }

      // Отменяем любые существующие уведомления перед созданием новых
      await _cancelAllMealNotifications();

      // Создаем уведомления для каждого приема пищи
      for (final mealType in _standardMealTimes.keys) {
        await _scheduleSmartMealNotification(
          mealType: mealType,
          localizationService: localizationService,
        );
      }

      // Сохраняем настройки
      await _saveSettings(enabled: true, setupCompleted: true);
      _notificationsEnabled = true;

      appLog('Умные уведомления настроены успешно',
          tag: 'SMART_NOTIFICATIONS', level: LogLevel.info);
      return true;
    } catch (e) {
      appLog('Ошибка настройки умных уведомлений: $e',
          tag: 'SMART_NOTIFICATIONS', level: LogLevel.error);
      return false;
    }
  }

  /// Создает умное уведомление для конкретного приема пищи
  Future<void> _scheduleSmartMealNotification({
    required String mealType,
    IAppLocalizationService? localizationService,
  }) async {
    final timeConfig = _standardMealTimes[mealType];
    if (timeConfig == null) return;

    final notificationId = _notificationIds[mealType];
    if (notificationId == null) return;

    // Получаем локализованные тексты
    final title = _getMealNotificationTitle(mealType, localizationService);
    final body = _getMealNotificationBody(mealType, localizationService);

    // Создаем повторяющееся уведомление с умной логикой
    await _notificationService.periodicallyShowNotification(
      id: notificationId,
      title: title,
      body: body,
      interval: const Duration(days: 1), // Ежедневно
      type: NotificationType.reminder,
      payload: 'smart_meal_$mealType',
      initialDateTime:
          _getNextMealTime(timeConfig['hour']!, timeConfig['minute']!),
    );

    appLog(
        'Настроено умное уведомление для $mealType в ${timeConfig['hour']}:${timeConfig['minute']}',
        tag: 'SMART_NOTIFICATIONS',
        level: LogLevel.debug);
  }

  /// Получает время следующего уведомления
  DateTime _getNextMealTime(int hour, int minute) {
    final now = DateTime.now();
    var mealTime = DateTime(now.year, now.month, now.day, hour, minute);

    // Если время уже прошло сегодня, планируем на завтра
    if (mealTime.isBefore(now)) {
      mealTime = mealTime.add(const Duration(days: 1));
    }

    return mealTime;
  }

  /// Проверяет, должно ли быть отправлено уведомление
  ///
  /// Возвращает false если пользователь недавно добавил еду (умная логика)
  Future<bool> shouldSendNotification({
    required String mealType,
    required MealRepository mealRepository,
  }) async {
    try {
      // Получаем приемы пищи за последние несколько часов
      final now = DateTime.now();
      final checkPeriodStart = now.subtract(_recentMealWindow);

      // Получаем приемы пищи за сегодня
      final todayMeals = await mealRepository.getMealsForDay(now);

      // Фильтруем недавние приемы пищи (в пределах окна времени)
      final recentMeals = todayMeals.where((meal) {
        final timeDifference = now.difference(meal.dateTime);
        return timeDifference.isNegative
            ? false
            : timeDifference <= _recentMealWindow;
      }).toList();

      // Если есть недавние приемы пищи, не отправляем уведомление
      if (recentMeals.isNotEmpty) {
        appLog(
            'Найдены недавние приемы пищи (${recentMeals.length}), '
            'уведомление о $mealType подавлено',
            tag: 'SMART_NOTIFICATIONS',
            level: LogLevel.info);
        return false;
      }

      // Дополнительная проверка: для обеда и ужина проверяем приемы пищи сегодня
      if (mealType == 'lunch' || mealType == 'dinner') {
        // Используем уже полученные данные todayMeals

        // Логика для обеда: если уже был завтрак сегодня в последние 4 часа
        if (mealType == 'lunch' && todayMeals.isNotEmpty) {
          final recentBreakfast = todayMeals
              .where((meal) => now.difference(meal.dateTime).inHours < 4)
              .isNotEmpty;
          if (recentBreakfast) {
            appLog('Найден недавний завтрак, уведомление об обеде подавлено',
                tag: 'SMART_NOTIFICATIONS', level: LogLevel.info);
            return false;
          }
        }

        // Логика для ужина: если уже был обед сегодня в последние 5 часов
        if (mealType == 'dinner' && todayMeals.isNotEmpty) {
          final recentLunch = todayMeals
              .where((meal) => now.difference(meal.dateTime).inHours < 5)
              .isNotEmpty;
          if (recentLunch) {
            appLog('Найден недавний обед, уведомление об ужине подавлено',
                tag: 'SMART_NOTIFICATIONS', level: LogLevel.info);
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      appLog('Ошибка при проверке недавних приемов пищи: $e',
          tag: 'SMART_NOTIFICATIONS', level: LogLevel.error);
      // В случае ошибки разрешаем отправку уведомления
      return true;
    }
  }

  /// Отменяет все уведомления о приемах пищи
  Future<void> _cancelAllMealNotifications() async {
    for (final notificationId in _notificationIds.values) {
      await _notificationService.cancelNotification(notificationId);
    }
    appLog('Отменены все уведомления о приемах пищи',
        tag: 'SMART_NOTIFICATIONS', level: LogLevel.debug);
  }

  /// Отключает умные уведомления
  Future<void> disableNotifications() async {
    if (!_isInitialized) {
      await initialize();
    }

    await _cancelAllMealNotifications();
    await _saveSettings(enabled: false, setupCompleted: false);
    _notificationsEnabled = false;

    appLog('Умные уведомления отключены',
        tag: 'SMART_NOTIFICATIONS', level: LogLevel.info);
  }

  /// Сохраняет настройки
  Future<void> _saveSettings({
    required bool enabled,
    required bool setupCompleted,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyNotificationsEnabled, enabled);
      await prefs.setBool(_prefKeyNotificationsSetup, setupCompleted);
    } catch (e) {
      appLog('Ошибка сохранения настроек: $e',
          tag: 'SMART_NOTIFICATIONS', level: LogLevel.error);
    }
  }

  /// Проверяет, включены ли уведомления
  bool get isEnabled => _notificationsEnabled;

  /// Проверяет, настроены ли уведомления
  Future<bool> get isSetupCompleted async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefKeyNotificationsSetup) ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Получает заголовок уведомления
  String _getMealNotificationTitle(
      String mealType, IAppLocalizationService? localizationService) {
    switch (mealType) {
      case 'breakfast':
        return localizationService?.translate('breakfast_reminder_title') ??
            '🍳 Время завтрака!';
      case 'lunch':
        return localizationService?.translate('lunch_reminder_title') ??
            '🍲 Время обеда!';
      case 'dinner':
        return localizationService?.translate('dinner_reminder_title') ??
            '🍽️ Время ужина!';
      default:
        return 'Время приема пищи!';
    }
  }

  /// Получает текст уведомления
  String _getMealNotificationBody(
      String mealType, IAppLocalizationService? localizationService) {
    switch (mealType) {
      case 'breakfast':
        return localizationService?.translate('breakfast_reminder_message') ??
            'Доброе утро! Не забудьте отследить калории и БЖУ завтрака в приложении AI Video Maker.';
      case 'lunch':
        return localizationService?.translate('lunch_reminder_message') ??
            'Не забудьте отследить калории обеда в AI Video Maker. Знание БЖУ помогает поддерживать сбалансированное питание.';
      case 'dinner':
        return localizationService?.translate('dinner_reminder_message') ??
            'Завершите день правильно! Отследите калории и БЖУ ужина в AI Video Maker для контроля дневного рациона.';
      default:
        return 'Отследите ваш прием пищи в AI Video Maker!';
    }
  }

  /// Проверяет разрешения на уведомления
  Future<bool> checkNotificationPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }
    return await _notificationService.areNotificationsEnabled();
  }

  /// Запрашивает разрешения на уведомления
  Future<bool> requestNotificationPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }
    return await _notificationService.requestPermissions();
  }

  /// Отправляет тестовое уведомление
  Future<void> sendTestNotification() async {
    if (!_isInitialized) {
      await initialize();
    }

    await _notificationService.showLocalNotification(
      id: 9999,
      title: '🔔 Тест умных уведомлений',
      body:
          'Если вы видите это уведомление, значит умные уведомления AI Video Maker работают корректно!',
      type: NotificationType.info,
    );

    appLog('Отправлено тестовое уведомление',
        tag: 'SMART_NOTIFICATIONS', level: LogLevel.info);
  }

  /// Получает статус службы
  Future<Map<String, dynamic>> getServiceStatus() async {
    if (!_isInitialized) {
      await initialize();
    }

    final hasPermissions = await checkNotificationPermissions();
    final isSetup = await isSetupCompleted;

    return {
      'initialized': _isInitialized,
      'enabled': _notificationsEnabled,
      'has_permissions': hasPermissions,
      'setup_completed': isSetup,
      'standard_times': _standardMealTimes,
    };
  }

  /// Сбрасывает badge count (красную цифру на иконке приложения)
  Future<void> resetBadgeCount() async {
    if (!_isInitialized) {
      await initialize();
    }

    await _notificationService.resetBadgeCount();
    appLog('Badge count сброшен через умный сервис',
        tag: 'SMART_NOTIFICATIONS', level: LogLevel.info);
  }

  /// Получает текущий badge count
  Future<int> getBadgeCount() async {
    if (!_isInitialized) {
      await initialize();
    }

    return await _notificationService.getBadgeCount();
  }

  /// Устанавливает badge count
  Future<void> setBadgeCount(int count) async {
    if (!_isInitialized) {
      await initialize();
    }

    await _notificationService.setBadgeCount(count);
    appLog('Badge count установлен в $count через умный сервис',
        tag: 'SMART_NOTIFICATIONS', level: LogLevel.info);
  }
}
