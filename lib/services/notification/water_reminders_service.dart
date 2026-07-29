import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reminder_service.dart';
import '../../utils/app_logger.dart';
import '../../main.dart';
import '../localization/app_localization_service.dart';

/// Сервис напоминаний о приёме воды (ежедневно, в заданное пользователем время)
class WaterRemindersService {
  // Singleton
  static final WaterRemindersService _instance =
      WaterRemindersService._internal();
  factory WaterRemindersService() => _instance;
  WaterRemindersService._internal();

  // Ключи SharedPreferences
  static const String _prefKeyWaterReminderId = 'water_reminder_id';
  static const String _prefKeyWaterHadReminder = 'had_water_reminder';
  static const String _prefKeyWaterHour = 'water_hour';
  static const String _prefKeyWaterMinute = 'water_minute';

  final ReminderService _reminderService = ReminderService();

  String? _waterReminderId;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _reminderService.initialize();
    await _loadSavedReminder();
    _isInitialized = true;
    appLog(localizeMessage('water_reminders_service_initialized'),
        tag: 'FLUTTER', level: LogLevel.debug);
  }

  Future<void> _loadSavedReminder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _waterReminderId = prefs.getString(_prefKeyWaterReminderId);
      appLog(localizeMessage('loaded_saved_water_reminder'),
          tag: 'FLUTTER', level: LogLevel.debug);
    } catch (e) {
      appLog(localizeMessage('reminder_load_error', ['$e']),
          tag: 'FLUTTER', level: LogLevel.error);
    }
  }

  Future<void> _saveReminderId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_waterReminderId != null) {
        await prefs.setString(_prefKeyWaterReminderId, _waterReminderId!);
        await prefs.setBool(_prefKeyWaterHadReminder, true);
      }
    } catch (e) {
      debugPrint('Ошибка при сохранении ID напоминания воды: $e');
    }
  }

  Future<void> _clearSavedReminder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyWaterReminderId);
      await prefs.setBool(_prefKeyWaterHadReminder, false);
      await prefs.remove(_prefKeyWaterHour);
      await prefs.remove(_prefKeyWaterMinute);
    } catch (e) {
      debugPrint('Ошибка при очистке сохранённых напоминаний воды: $e');
    }
  }

  /// Включает/обновляет ежедневное напоминание о воде на указанное время
  Future<String> setupWaterReminder({
    int hour = 10,
    int minute = 0,
    IAppLocalizationService? localizationService,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Если уже было напоминание — отменим перед созданием нового
    if (_waterReminderId != null) {
      await _reminderService.cancelReminder(_waterReminderId!);
    }

    final now = DateTime.now();
    final reminderTime = DateTime(now.year, now.month, now.day, hour, minute);

    final title = localizationService?.translate('water_reminder_title') ??
        '💧 Пора пить воду!';
    final message = localizationService?.translate('water_reminder_message') ??
        'Поддерживайте водный баланс: отметьте воду в AI Video Maker.';

    _waterReminderId = await _reminderService.createDailyReminder(
      title: title,
      message: message,
      time: reminderTime,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyWaterHour, hour);
    await prefs.setInt(_prefKeyWaterMinute, minute);
    await prefs.setBool(_prefKeyWaterHadReminder, true);

    await _saveReminderId();
    debugPrint('Настроено ежедневное напоминание о воде в $hour:$minute');
    return _waterReminderId!;
  }

  /// Отключает напоминание о воде
  Future<void> cancelWaterReminder() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_waterReminderId != null) {
      await _reminderService.cancelReminder(_waterReminderId!);
      _waterReminderId = null;
    }
    await _clearSavedReminder();
  }

  /// Перепланирует напоминание на основе сохранённых настроек времени
  Future<void> rescheduleWaterReminder({
    IAppLocalizationService? localizationService,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final prefs = await SharedPreferences.getInstance();
    final had = prefs.getBool(_prefKeyWaterHadReminder) ?? false;
    if (!had) {
      debugPrint('Нет настроенного напоминания о воде для перепланирования');
      return;
    }

    final hour = prefs.getInt(_prefKeyWaterHour) ?? 10;
    final minute = prefs.getInt(_prefKeyWaterMinute) ?? 0;
    await setupWaterReminder(
      hour: hour,
      minute: minute,
      localizationService: localizationService,
    );
  }

  /// Возвращает true, если напоминание было настроено ранее
  bool areRemindersSet() {
    return _waterReminderId != null;
  }
}
