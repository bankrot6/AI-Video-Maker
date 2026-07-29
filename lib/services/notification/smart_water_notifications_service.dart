import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_notification_service.dart';
import 'notification_service_interface.dart';
import 'reminder_service.dart';
import 'water_reminders_service.dart';
import '../../utils/app_logger.dart';
import '../../main.dart';
import '../localization/app_localization_service.dart';

/// Умный сервис уведомлений о приёме воды
///
/// Минимальная реализация: несколько ежедневных напоминаний, равномерно
/// распределённых по окну бодрствования. Состояние хранится в SharedPreferences.
class SmartWaterNotificationsService {
  // Singleton
  static final SmartWaterNotificationsService _instance =
      SmartWaterNotificationsService._internal();
  factory SmartWaterNotificationsService() => _instance;
  SmartWaterNotificationsService._internal();

  // Pref keys
  static const String _prefEnabled = 'smart_water_enabled';
  static const String _prefIds = 'smart_water_ids'; // JSON List<String>
  static const String _prefTimes =
      'smart_water_times'; // JSON List<String> "HH:MM"
  static const String _prefStartH = 'smart_water_start_h';
  static const String _prefStartM = 'smart_water_start_m';
  static const String _prefEndH = 'smart_water_end_h';
  static const String _prefEndM = 'smart_water_end_m';
  static const String _prefCount = 'smart_water_count';

  // Defaults
  static const int _defaultStartHour = 8;
  static const int _defaultStartMinute = 0;
  static const int _defaultEndHour = 22;
  static const int _defaultEndMinute = 0;
  static const int _defaultCount = 8; // 8 напоминаний/день

  final ReminderService _reminderService = ReminderService();
  final LocalNotificationService _localNotificationService =
      LocalNotificationService();
  bool _initialized = false;
  bool _isScheduling = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await _reminderService.initialize();
    await _localNotificationService.initialize();
    _initialized = true;
    appLog('SmartWaterNotificationsService initialized',
        tag: 'SMART_WATER', level: LogLevel.info);

    // Гарантируем дефолтную авто-настройку при первом запуске
    await _ensureDefaults();

    // Миграция: отключаем старое одиночное напоминание о воде, если оно было настроено
    try {
      final legacy = WaterRemindersService();
      await legacy.initialize();
      await legacy.cancelWaterReminder();
    } catch (_) {
      // игнорируем сбои миграции
    }
  }

  Future<void> _ensureDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasEnabledKey = prefs.containsKey(_prefEnabled);
      final enabled = prefs.getBool(_prefEnabled) ?? true; // дефолт: включено
      final hasIds = prefs.getString(_prefIds)?.isNotEmpty == true;

      if (!hasEnabledKey) {
        // Первый запуск: включаем и создаём расписание по умолчанию
        await setupSmartNotifications();
        await prefs.setBool(_prefEnabled, true);
      } else if (enabled && !hasIds) {
        // Включено, но нет запланированных ID — пересоздаём
        await setupSmartNotifications();
      }
    } catch (_) {
      // тихо игнорируем сбои авто-настройки
    }
  }

  /// Текущие настройки умных напоминаний воды
  Future<SmartWaterSettings> getSettings() async {
    if (!_initialized) {
      await initialize();
    }
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefEnabled) ?? true; // дефолт: включено
    final sH = prefs.getInt(_prefStartH) ?? _defaultStartHour;
    final sM = prefs.getInt(_prefStartM) ?? _defaultStartMinute;
    final eH = prefs.getInt(_prefEndH) ?? _defaultEndHour;
    final eM = prefs.getInt(_prefEndM) ?? _defaultEndMinute;
    final count = prefs.getInt(_prefCount) ?? _defaultCount;
    final List<String> times = (() {
      try {
        final raw = prefs.getString(_prefTimes);
        if (raw == null) return <String>[];
        final decoded = json.decode(raw);
        if (decoded is List) {
          return List<String>.from(decoded.map((e) => e.toString()));
        }
        return <String>[];
      } catch (_) {
        return <String>[];
      }
    })();
    return SmartWaterSettings(
      enabled: enabled,
      startHour: sH,
      startMinute: sM,
      endHour: eH,
      endMinute: eM,
      remindersCount: count,
      timesPreview: times,
    );
  }

  /// Включает и настраивает умные напоминания о воде.
  ///
  /// Если [startHour]/[startMinute] не заданы — используются сохранённые или дефолтные.
  Future<void> setupSmartNotifications({
    int? startHour,
    int? startMinute,
    int? endHour,
    int? endMinute,
    int? remindersCount,
    IAppLocalizationService? localizationService,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    if (_isScheduling) {
      debugPrint('SmartWater: пропуск конкурирующей настройки расписания');
      return;
    }
    _isScheduling = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final sH = startHour ?? prefs.getInt(_prefStartH) ?? _defaultStartHour;
      final sM =
          startMinute ?? prefs.getInt(_prefStartM) ?? _defaultStartMinute;
      final eH = endHour ?? prefs.getInt(_prefEndH) ?? _defaultEndHour;
      final eM = endMinute ?? prefs.getInt(_prefEndM) ?? _defaultEndMinute;
      final count = remindersCount ?? prefs.getInt(_prefCount) ?? _defaultCount;

      // Отменяем старые
      await _cancelAllInternal(prefs);

      // Генерируем времена
      final times = _generateTimes(
        startHour: sH,
        startMinute: sM,
        endHour: eH,
        endMinute: eM,
        count: count,
      );

      // Локализованные тексты
      final title = localizationService?.translate('water_reminder_title') ??
          '💧 Пора пить воду!';
      final body = localizationService?.translate('water_reminder_message') ??
          'Поддерживайте водный баланс: отметьте воду в AI Video Maker.';

      // Планируем напоминания
      final List<String> ids = [];
      for (final t in times) {
        final now = DateTime.now();
        final dt = DateTime(now.year, now.month, now.day, t.$1, t.$2);
        final id = await _reminderService.createDailyReminder(
          title: title,
          message: body,
          time: dt,
        );
        ids.add(id);
      }

      // Сохраняем состояние
      await prefs.setBool(_prefEnabled, true);
      await prefs.setInt(_prefStartH, sH);
      await prefs.setInt(_prefStartM, sM);
      await prefs.setInt(_prefEndH, eH);
      await prefs.setInt(_prefEndM, eM);
      await prefs.setInt(_prefCount, count);
      await prefs.setString(_prefIds, json.encode(ids));
      await prefs.setString(
          _prefTimes,
          json.encode(times
              .map((e) =>
                  '${e.$1.toString().padLeft(2, '0')}:${e.$2.toString().padLeft(2, '0')}')
              .toList()));

      debugPrint('✅ Smart water reminders set: ${times.length} items');
    } finally {
      _isScheduling = false;
    }
  }

  /// Перепланировать на основе сохранённых настроек
  Future<void> reschedule(
      {IAppLocalizationService? localizationService}) async {
    if (!_initialized) {
      await initialize();
    }
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefEnabled) ?? false;
    if (!enabled) return;

    final sH = prefs.getInt(_prefStartH) ?? _defaultStartHour;
    final sM = prefs.getInt(_prefStartM) ?? _defaultStartMinute;
    final eH = prefs.getInt(_prefEndH) ?? _defaultEndHour;
    final eM = prefs.getInt(_prefEndM) ?? _defaultEndMinute;
    final count = prefs.getInt(_prefCount) ?? _defaultCount;
    await setupSmartNotifications(
      startHour: sH,
      startMinute: sM,
      endHour: eH,
      endMinute: eM,
      remindersCount: count,
      localizationService: localizationService,
    );
  }

  /// Отправляет немедленное тестовое уведомление о воде (для отладки)
  Future<void> sendImmediateTestNotification({
    IAppLocalizationService? localizationService,
  }) async {
    if (!_initialized) {
      await initialize();
    }
    final title = localizationService?.translate('water_reminder_title') ??
        '💧 Пора пить воду!';
    final body = localizationService?.translate('water_reminder_message') ??
        'Поддерживайте водный баланс: отметьте воду в AI Video Maker.';
    await _localNotificationService.showLocalNotification(
      id: 7701,
      title: title,
      body: body,
      type: NotificationType.reminder,
      payload: 'smart_water_immediate',
    );
  }

  /// Отключить и отменить все умные напоминания о воде
  Future<void> disable() async {
    if (!_initialized) {
      await initialize();
    }
    final prefs = await SharedPreferences.getInstance();
    await _cancelAllInternal(prefs);
    await prefs.setBool(_prefEnabled, false);
  }

  /// Генерация равномерно распределённых времен (включая начало и конец)
  List<(_H, _M)> _generateTimes({
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
    required int count,
  }) {
    final start = startHour * 60 + startMinute;
    final end = endHour * 60 + endMinute;
    final span = (end - start).clamp(0, 24 * 60);
    final safeCount = count.clamp(2, 12); // разумные пределы

    if (span <= 0) {
      // fallback: один раз в день — в start
      return [(startHour, startMinute)];
    }

    final step = (span / (safeCount - 1)).floor();
    final List<(_H, _M)> result = [];
    for (int i = 0; i < safeCount; i++) {
      final minutes = start + step * i;
      final h = (minutes ~/ 60).clamp(0, 23);
      final m = minutes % 60;
      result.add((h, m));
    }
    return result;
  }

  Future<void> _cancelAllInternal(SharedPreferences prefs) async {
    try {
      final idsJson = prefs.getString(_prefIds);
      if (idsJson != null && idsJson.isNotEmpty) {
        final List<dynamic> ids = json.decode(idsJson);
        for (final raw in ids) {
          final String id = raw as String;
          await _reminderService.cancelReminder(id);
        }
      }
    } catch (e) {
      debugPrint('Ошибка при отмене smart water reminders: $e');
    }

    await prefs.remove(_prefIds);
    await prefs.remove(_prefTimes);
  }
}

typedef _H = int;
typedef _M = int;

class SmartWaterSettings {
  final bool enabled;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final int remindersCount;
  final List<String> timesPreview;

  const SmartWaterSettings({
    required this.enabled,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.remindersCount,
    required this.timesPreview,
  });
}
