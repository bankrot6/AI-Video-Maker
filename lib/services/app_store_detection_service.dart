import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';

/// Enum для определения источника установки приложения
enum AppStoreType {
  /// Установлено из Google Play Store
  googlePlay,

  /// Установлено из RuStore
  ruStore,

  /// Установлено из App Store (iOS)
  appStore,

  /// Установлено из TestFlight (iOS)
  testFlight,

  /// Установлено из других источников (Huawei, Samsung, etc.)
  otherStore,

  /// Установлено локально (sideload)
  localSource,

  /// Неизвестный источник
  unknown,
}

/// Сервис для определения источника установки приложения
class AppStoreDetectionService {
  // Singleton
  static final AppStoreDetectionService _instance =
      AppStoreDetectionService._internal();
  factory AppStoreDetectionService() => _instance;
  AppStoreDetectionService._internal();

  AppStoreType? _cachedSource;
  AppStoreType? _forcedSourceForTesting; // Для принудительного тестирования

  static const String _logPrefix = '[AppStoreDetectionService]';

  /// Принудительно устанавливает источник для тестирования (только в debug режиме)
  void setForcedSourceForTesting(AppStoreType? source) {
    if (kDebugMode) {
      _forcedSourceForTesting = source;
      _cachedSource = null; // Сбрасываем кэш
      AppLogger.log(
          '$_logPrefix Принудительно установлен источник для тестирования: $source');
    }
  }

  /// Получает принудительно установленный источник для тестирования
  AppStoreType? getForcedSourceForTesting() {
    return _forcedSourceForTesting;
  }

  /// Получает источник установки приложения
  Future<AppStoreType> getInstallationSource() async {
    // 1) Если передан флаг --dart-define=RUSTORE=true — используем RuStore
    const bool isRuStoreBuild = bool.fromEnvironment('RUSTORE');
    if (isRuStoreBuild) {
      _cachedSource = AppStoreType.ruStore;
      AppLogger.log(
          '$_logPrefix Обнаружен флаг сборки RUSTORE=true — принудительно используем RuStore');
      debugPrint(
          '🏪 STORE_DETECTION: Источник установки определен по флагу: ruStore');
      return _cachedSource!;
    }

    // 2) В debug можно принудительно задать источник
    if (kDebugMode && _forcedSourceForTesting != null) {
      AppLogger.log(
          '$_logPrefix Используется принудительный источник для тестирования: $_forcedSourceForTesting');
      return _forcedSourceForTesting!;
    }

    // 3) Кэш
    if (_cachedSource != null) {
      return _cachedSource!;
    }

    // 4) На iOS — App Store
    if (Platform.isIOS) {
      _cachedSource = AppStoreType.appStore;
    } else if (Platform.isAndroid) {
      // Сборка с RUSTORE уже обработана выше по флагу. Здесь только не-RuStore.
      _cachedSource = AppStoreType.googlePlay;
    } else {
      _cachedSource = AppStoreType.unknown;
    }

    debugPrint(
        '🏪 STORE_DETECTION: Источник установки определен (по платформе): $_cachedSource');
    return _cachedSource!;
  }

  /// Проверяет, установлено ли приложение из RuStore
  Future<bool> isInstalledFromRuStore() async {
    final source = await getInstallationSource();
    return source == AppStoreType.ruStore;
  }

  /// Проверяет, установлено ли приложение из Google Play Store
  Future<bool> isInstalledFromGooglePlay() async {
    final source = await getInstallationSource();
    return source == AppStoreType.googlePlay;
  }

  /// Проверяет, установлено ли приложение из App Store (iOS)
  Future<bool> isInstalledFromAppStore() async {
    final source = await getInstallationSource();
    return source == AppStoreType.appStore;
  }

  /// Проверяет, можно ли использовать стандартные IAP (не RuStore)
  Future<bool> canUseStandardIAP() async {
    final source = await getInstallationSource();
    return source == AppStoreType.googlePlay ||
        source == AppStoreType.appStore ||
        source == AppStoreType.testFlight;
  }

  /// Получает человеко-читаемое название источника установки
  String getSourceDisplayName(AppStoreType source) {
    switch (source) {
      case AppStoreType.googlePlay:
        return 'Google Play Store';
      case AppStoreType.ruStore:
        return 'RuStore';
      case AppStoreType.appStore:
        return 'App Store';
      case AppStoreType.testFlight:
        return 'TestFlight';
      case AppStoreType.otherStore:
        return 'Другой магазин приложений';
      case AppStoreType.localSource:
        return 'Локальная установка';
      case AppStoreType.unknown:
        return 'Неизвестный источник';
    }
  }

  /// Сбрасывает кэшированное значение (для тестирования)
  void clearCache() {
    _cachedSource = null;
  }
}
