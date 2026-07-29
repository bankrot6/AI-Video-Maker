import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mytracker_sdk/mytracker_sdk.dart';

import '../../models/subscription_model.dart';
import '../../utils/app_logger.dart';

class MyTrackerAnalyticsService {
  MyTrackerAnalyticsService._();

  static final MyTrackerAnalyticsService instance =
      MyTrackerAnalyticsService._();

  static const MethodChannel _purchaseChannel =
      MethodChannel('com.aivideomaker.app/mytracker_purchase');

  bool _isInitialized = false;
  String? _appId;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    final appId = _resolveAppId();
    if (appId == null || appId.isEmpty) {
      AppLogger.log(
        'MYTRACKER: app id отсутствует, трекинг отключен',
        tag: 'ANALYTICS',
        level: LogLevel.warning,
      );
      return;
    }

    try {
      if (kDebugMode) {
        await MyTracker.setDebugMode(true);
      }
      // Отключаем автотрекинг покупок Google Play — приложение использует
      // RuStore, доход отправляется вручную через S2S customRevenue.
      // Установить нужно строго до MyTracker.init().
      await _setAutotrackingPurchaseEnabled(false);
      await MyTracker.init(appId);
      _appId = appId;
      _isInitialized = true;
      AppLogger.log(
        'MYTRACKER: инициализация выполнена (platform=${Platform.operatingSystem}, debug=$kDebugMode)',
        tag: 'ANALYTICS',
        level: LogLevel.info,
      );
    } catch (e) {
      AppLogger.log(
        'MYTRACKER: ошибка инициализации: $e',
        tag: 'ANALYTICS',
        level: LogLevel.error,
      );
    }
  }

  Future<void> trackFirstInstall({
    required String platform,
    required DateTime firstInstallDate,
  }) async {
    await _trackAndFlush(
      'app_install',
      {
        'platform': platform,
        'first_install_date': firstInstallDate.toIso8601String(),
      },
    );
  }

  Future<void> trackPaywallOpened() async {
    await _trackAndFlush('paywall_open', _baseParams());
  }

  Future<void> trackSubscriptionStart({
    required SubscriptionType plan,
    required String paymentProvider,
  }) async {
    await _trackAndFlush(
      'subscription_start',
      {
        ..._baseParams(),
        'plan': plan.name,
        'payment_provider': paymentProvider,
      },
    );
  }

  Future<void> trackSubscriptionPurchase({
    required SubscriptionType plan,
    required String paymentProvider,
    String? productId,
  }) async {
    await _trackAndFlush(
      'subscription_purchase',
      {
        ..._baseParams(),
        'plan': plan.name,
        'payment_provider': paymentProvider,
        if (productId != null && productId.isNotEmpty) 'product_id': productId,
      },
    );
  }

  Future<void> trackTrialStarted({
    required String paymentProvider,
    String? productId,
  }) async {
    await _trackAndFlush(
      'trial_started',
      {
        ..._baseParams(),
        'payment_provider': paymentProvider,
        if (productId != null && productId.isNotEmpty) 'product_id': productId,
      },
    );
  }

  Future<void> trackSubscriptionCancelled({
    required String paymentProvider,
    String? productId,
  }) async {
    await trackEvent(
      'subscription_cancelled',
      {
        ..._baseParams(),
        'payment_provider': paymentProvider,
        if (productId != null && productId.isNotEmpty) 'product_id': productId,
      },
    );
  }

  Future<void> trackSubscriptionFailed({
    required String paymentProvider,
    required String error,
    String? productId,
  }) async {
    await trackEvent(
      'subscription_failed',
      {
        ..._baseParams(),
        'payment_provider': paymentProvider,
        if (productId != null && productId.isNotEmpty) 'product_id': productId,
        'error': _truncate(error),
      },
    );
  }

  Future<void> trackCreditsPurchase({
    required int credits,
    required String paymentProvider,
    String? packageId,
    String? amount,
    String? currency,
  }) async {
    await _trackAndFlush(
      'credits_purchase',
      {
        ..._baseParams(),
        'credits': credits.toString(),
        'payment_provider': paymentProvider,
        if (packageId != null && packageId.isNotEmpty) 'package_id': packageId,
        if (amount != null && amount.isNotEmpty) 'amount': amount,
        if (currency != null && currency.isNotEmpty) 'currency': currency,
      },
    );
  }

  Future<void> trackCreditsPurchaseFailed({
    required String paymentProvider,
    required String error,
    String? packageId,
  }) async {
    await trackEvent(
      'credits_purchase_failed',
      {
        ..._baseParams(),
        'payment_provider': paymentProvider,
        if (packageId != null && packageId.isNotEmpty) 'package_id': packageId,
        'error': _truncate(error),
      },
    );
  }

  Future<void> trackEvent(String name, [Map<String, String>? params]) async {
    if (!_isInitialized) {
      AppLogger.log(
        'MYTRACKER: пропуск события $name — SDK не инициализирован',
        tag: 'ANALYTICS',
        level: LogLevel.warning,
      );
      return;
    }

    final normalizedName = _truncate(name);
    final normalizedParams = <String, String>{};
    params?.forEach((key, value) {
      if (key.isEmpty || value.isEmpty) return;
      normalizedParams[_truncate(key)] = _truncate(value);
    });

    try {
      AppLogger.log(
        'MYTRACKER: отправка события $normalizedName params=$normalizedParams',
        tag: 'ANALYTICS',
        level: LogLevel.info,
      );
      await MyTracker.trackEvent(normalizedName, normalizedParams);
      AppLogger.log(
        'MYTRACKER: событие $normalizedName отправлено',
        tag: 'ANALYTICS',
        level: LogLevel.info,
      );
    } catch (e) {
      AppLogger.log(
        'MYTRACKER: ошибка отправки события $normalizedName: $e',
        tag: 'ANALYTICS',
        level: LogLevel.warning,
      );
    }
  }

  Future<void> flush() async {
    if (!_isInitialized) {
      AppLogger.log(
        'MYTRACKER: flush пропущен — SDK не инициализирован',
        tag: 'ANALYTICS',
        level: LogLevel.warning,
      );
      return;
    }
    try {
      AppLogger.log(
        'MYTRACKER: flush start',
        tag: 'ANALYTICS',
        level: LogLevel.info,
      );
      await MyTracker.flush();
      AppLogger.log(
        'MYTRACKER: flush done',
        tag: 'ANALYTICS',
        level: LogLevel.info,
      );
    } catch (e) {
      AppLogger.log(
        'MYTRACKER: ошибка flush: $e',
        tag: 'ANALYTICS',
        level: LogLevel.warning,
      );
    }
  }

  Future<void> _trackAndFlush(String name, Map<String, String> params) async {
    await trackEvent(name, params);
    await flush();
  }

  Future<void> _setAutotrackingPurchaseEnabled(bool enabled) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _purchaseChannel
          .invokeMethod('setAutotrackingPurchaseEnabled', {'enabled': enabled});
    } catch (e) {
      AppLogger.log(
        'MYTRACKER: не удалось задать autotrackingPurchaseEnabled=$enabled: $e',
        tag: 'ANALYTICS',
        level: LogLevel.warning,
      );
    }
  }

  /// S2S-идентификатор устройства MyTracker. Используется серверной функцией
  /// верификации покупок (verify-rustore-purchase) для отправки дохода
  /// RuStore как «Универсального дохода» (customRevenue) с привязкой к
  /// устройству и источнику установки (VK Ads). Доход признаётся на сервере
  /// по фактической сумме платежа и идемпотентно по purchaseId — поэтому
  /// клиент сам выручку не отправляет.
  Future<String?> getInstanceId() async {
    if (!_isInitialized) {
      return null;
    }
    try {
      return await MyTracker.getInstanceId();
    } catch (e) {
      AppLogger.log(
        'MYTRACKER: не удалось получить instanceId: $e',
        tag: 'ANALYTICS',
        level: LogLevel.warning,
      );
      return null;
    }
  }

  Map<String, String> _baseParams() {
    return {
      'platform':
          Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other'),
      if (_appId != null) 'tracker_id': _appId!,
      if (kDebugMode) 'build_mode': 'debug' else 'build_mode': 'release',
    };
  }

  String? _resolveAppId() {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return null;
    }

    final envAndroid = dotenv.env['MYTRACKER_ANDROID_APP_ID']?.trim();
    final envIos = dotenv.env['MYTRACKER_IOS_APP_ID']?.trim();

    const defineAndroid = String.fromEnvironment('MYTRACKER_ANDROID_APP_ID');
    const defineIos = String.fromEnvironment('MYTRACKER_IOS_APP_ID');

    if (Platform.isAndroid) {
      return (envAndroid != null && envAndroid.isNotEmpty)
          ? envAndroid
          : defineAndroid;
    }

    return (envIos != null && envIos.isNotEmpty) ? envIos : defineIos;
  }

  String _truncate(String value) {
    if (value.length <= 255) {
      return value;
    }
    return value.substring(0, 255);
  }
}
