import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Сервис для определения производительности устройства
/// Используется для автоматического выбора оптимальных настроек графики
class DevicePerformanceService {
  static DevicePerformanceService? _instance;
  static DevicePerformanceService get instance {
    _instance ??= DevicePerformanceService._();
    return _instance!;
  }

  DevicePerformanceService._();

  PerformanceLevel? _cachedLevel;

  /// Уровень производительности устройства
  Future<PerformanceLevel> getPerformanceLevel() async {
    // Возвращаем кэшированное значение, если есть
    if (_cachedLevel != null) {
      return _cachedLevel!;
    }

    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _cachedLevel = _detectAndroidPerformance(androidInfo);
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _cachedLevel = _detectIOSPerformance(iosInfo);
      } else {
        // Для других платформ используем средний уровень по умолчанию
        _cachedLevel = PerformanceLevel.medium;
      }

      debugPrint('🎮 Производительность устройства: ${_cachedLevel?.name}');
      return _cachedLevel!;
    } catch (e) {
      debugPrint('⚠️ Ошибка определения производительности: $e');
      // В случае ошибки используем средний уровень
      _cachedLevel = PerformanceLevel.medium;
      return _cachedLevel!;
    }
  }

  /// Определяет производительность Android устройства
  PerformanceLevel _detectAndroidPerformance(AndroidDeviceInfo info) {
    // Проверяем версию Android
    final sdkInt = info.version.sdkInt;

    // Android 11+ (API 30+) с хорошими характеристиками
    if (sdkInt >= 30) {
      // Проверяем наличие высокопроизводительных чипсетов в названии
      final model = info.model.toLowerCase();
      final manufacturer = info.manufacturer.toLowerCase();

      // Флагманские устройства
      if (_isHighEndAndroid(model, manufacturer)) {
        return PerformanceLevel.high;
      }

      // Средний уровень для относительно новых устройств
      return PerformanceLevel.medium;
    }

    // Android 9-10 (API 28-29)
    if (sdkInt >= 28) {
      return PerformanceLevel.medium;
    }

    // Старые версии Android
    return PerformanceLevel.low;
  }

  /// Определяет производительность iOS устройства
  PerformanceLevel _detectIOSPerformance(IosDeviceInfo info) {
    final model = info.utsname.machine.toLowerCase();

    // iPhone 12 и новее (высокая производительность)
    if (_isHighEndiPhone(model)) {
      return PerformanceLevel.high;
    }

    // iPhone X, XR, 11 (средняя производительность)
    if (_isMidRangeiPhone(model)) {
      return PerformanceLevel.medium;
    }

    // Старые модели
    return PerformanceLevel.low;
  }

  /// Проверяет, является ли Android устройство высокопроизводительным
  bool _isHighEndAndroid(String model, String manufacturer) {
    // Флагманские Samsung
    if (manufacturer.contains('samsung')) {
      if (model.contains('s22') ||
          model.contains('s23') ||
          model.contains('s24') ||
          model.contains('fold') ||
          model.contains('flip')) {
        return true;
      }
    }

    // Google Pixel 6+
    if (manufacturer.contains('google')) {
      if (model.contains('pixel 6') ||
          model.contains('pixel 7') ||
          model.contains('pixel 8')) {
        return true;
      }
    }

    // Xiaomi флагманы
    if (manufacturer.contains('xiaomi')) {
      if (model.contains('13') || model.contains('14')) {
        return true;
      }
    }

    // OnePlus флагманы
    if (manufacturer.contains('oneplus')) {
      if (model.contains('10') ||
          model.contains('11') ||
          model.contains('12')) {
        return true;
      }
    }

    return false;
  }

  /// Проверяет, является ли iPhone высокопроизводительным
  bool _isHighEndiPhone(String model) {
    // iPhone 12 и новее
    return model.contains('iphone13') || // iPhone 12
        model.contains('iphone14') || // iPhone 13
        model.contains('iphone15') || // iPhone 14
        model.contains('iphone16'); // iPhone 15
  }

  /// Проверяет, является ли iPhone средней производительности
  bool _isMidRangeiPhone(String model) {
    return model.contains('iphone10') || // iPhone X
        model.contains('iphone11') || // iPhone XR/XS
        model.contains('iphone12'); // iPhone 11
  }

  /// Быстрая проверка: можно ли использовать полный эффект LiquidGlass
  Future<bool> canUseFullGlassEffect() async {
    final level = await getPerformanceLevel();
    return level == PerformanceLevel.high;
  }

  /// Быстрая проверка: нужно ли использовать облегченную версию
  Future<bool> shouldUseLightGlassEffect() async {
    final level = await getPerformanceLevel();
    return level == PerformanceLevel.medium;
  }

  /// Быстрая проверка: нужно ли использовать минимальный эффект
  Future<bool> shouldUseMinimalEffect() async {
    final level = await getPerformanceLevel();
    return level == PerformanceLevel.low;
  }

  /// Получает рекомендованные настройки LiquidGlass для устройства
  Future<GlassPerformanceSettings> getRecommendedSettings() async {
    final level = await getPerformanceLevel();

    switch (level) {
      case PerformanceLevel.high:
        return GlassPerformanceSettings.high();
      case PerformanceLevel.medium:
        return GlassPerformanceSettings.medium();
      case PerformanceLevel.low:
        return GlassPerformanceSettings.low();
    }
  }

  /// Сброс кэша (для тестирования)
  void resetCache() {
    _cachedLevel = null;
  }
}

/// Уровень производительности устройства
enum PerformanceLevel {
  low, // Слабые устройства - минимальные эффекты
  medium, // Средние устройства - облегченные эффекты
  high, // Мощные устройства - полные эффекты
}

/// Рекомендованные настройки для разных уровней производительности
class GlassPerformanceSettings {
  final double thickness;
  final double lightIntensity;
  final double saturation;
  final bool useFullEffect;
  final String description;

  const GlassPerformanceSettings({
    required this.thickness,
    required this.lightIntensity,
    required this.saturation,
    required this.useFullEffect,
    required this.description,
  });

  /// Настройки для высокопроизводительных устройств
  factory GlassPerformanceSettings.high() {
    return const GlassPerformanceSettings(
      thickness: 5.0,
      lightIntensity: 1.2,
      saturation: 1.05,
      useFullEffect: true,
      description: 'Полный эффект жидкого стекла',
    );
  }

  /// Настройки для устройств средней производительности
  factory GlassPerformanceSettings.medium() {
    return const GlassPerformanceSettings(
      thickness: 3.0,
      lightIntensity: 1.0,
      saturation: 1.0,
      useFullEffect: true,
      description: 'Облегченный эффект жидкого стекла',
    );
  }

  /// Настройки для слабых устройств
  factory GlassPerformanceSettings.low() {
    return const GlassPerformanceSettings(
      thickness: 0.0, // Не используем эффект
      lightIntensity: 0.0,
      saturation: 1.0,
      useFullEffect: false,
      description: 'Без эффекта - простой контейнер',
    );
  }

  @override
  String toString() {
    return 'GlassPerformanceSettings(thickness: $thickness, '
        'lightIntensity: $lightIntensity, saturation: $saturation, '
        'useFullEffect: $useFullEffect, description: $description)';
  }
}
