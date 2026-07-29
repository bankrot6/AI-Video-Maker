import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings_model.dart';

/// Интерфейс репозитория настроек приложения
abstract class SettingsRepository {
  /// Получает текущие настройки приложения
  Future<AppSettingsModel> getSettings();

  /// Сохраняет настройки приложения
  Future<void> saveSettings(AppSettingsModel settings);

  /// Обновляет флаг использования Google Vision
  Future<void> setUseGoogleVision(bool useGoogleVision);

  /// Обновляет флаг загрузки изображений блюд
  Future<void> setLoadDishImages(bool loadDishImages);

  /// Обновляет флаг включения напоминаний о продлении подписки
  Future<void> setEnableRenewalReminders(bool enableRenewalReminders);
}

/// Реализация репозитория настроек с использованием SharedPreferences
class SharedPrefsSettingsRepository implements SettingsRepository {
  // Ключ для доступа к данным в SharedPreferences
  static const String _settingsKey = 'app_settings';

  final SharedPreferences _prefs;

  // Конструктор с внедрением зависимости SharedPreferences
  SharedPrefsSettingsRepository(this._prefs);

  // Фабричный метод для создания репозитория
  static Future<SharedPrefsSettingsRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPrefsSettingsRepository(prefs);
  }

  @override
  Future<AppSettingsModel> getSettings() async {
    final settingsJson = _prefs.getString(_settingsKey);
    if (settingsJson == null) {
      // Возвращаем настройки по умолчанию, если настройки не найдены
      return AppSettingsModel.defaults();
    }

    try {
      final Map<String, dynamic> settingsMap = json.decode(settingsJson);
      return AppSettingsModel.fromJson(settingsMap);
    } catch (e) {
      // Обработка ошибок десериализации
      print('Ошибка при десериализации настроек: $e');
      return AppSettingsModel.defaults();
    }
  }

  @override
  Future<void> saveSettings(AppSettingsModel settings) async {
    final settingsJson = json.encode(settings.toJson());
    await _prefs.setString(_settingsKey, settingsJson);
  }

  @override
  Future<void> setUseGoogleVision(bool useGoogleVision) async {
    final currentSettings = await getSettings();
    final updatedSettings = currentSettings.copyWith(
      useGoogleVision: useGoogleVision,
    );
    await saveSettings(updatedSettings);
  }

  @override
  Future<void> setLoadDishImages(bool loadDishImages) async {
    final currentSettings = await getSettings();
    final updatedSettings = currentSettings.copyWith(
      loadDishImages: loadDishImages,
    );
    await saveSettings(updatedSettings);
  }

  @override
  Future<void> setEnableRenewalReminders(bool enableRenewalReminders) async {
    final currentSettings = await getSettings();
    final updatedSettings = currentSettings.copyWith(
      enableRenewalReminders: enableRenewalReminders,
    );
    await saveSettings(updatedSettings);
  }
}
