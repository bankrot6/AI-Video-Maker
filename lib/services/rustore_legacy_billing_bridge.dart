import 'dart:io';

import 'package:flutter/services.dart';

import '../models/rustore_purchase_info.dart';
import '../utils/app_logger.dart';

/// Dart-обёртка над нативным BillingClient (MethodChannel).
///
/// Нужна, чтобы на время миграции читать статус подписок,
/// оформленных до перехода на Pay SDK (см. rustore.ru/help/sdk/pay/migration).
class RuStoreLegacyBillingBridge {
  static const String _logPrefix = '🛒 RUSTORE_LEGACY';
  static const MethodChannel _channel =
      MethodChannel('com.aivideomaker.app/rustore_legacy_billing');

  static const String _productionConsoleApplicationId = '2063737207';
  static const String _productionDeeplinkScheme = 'aivideomaker';

  static const String _consoleApplicationId = String.fromEnvironment(
    'RUSTORE_APP_ID',
    defaultValue: _productionConsoleApplicationId,
  );
  static const String _deeplinkScheme = String.fromEnvironment(
    'RUSTORE_SCHEME',
    defaultValue: _productionDeeplinkScheme,
  );

  bool _isInitialized = false;

  Future<bool> initialize() async {
    if (!Platform.isAndroid) return false;
    if (_isInitialized) return true;

    try {
      final ok = await _channel.invokeMethod<bool>('initialize', {
        'consoleApplicationId': _consoleApplicationId,
        'deeplinkScheme': _deeplinkScheme,
      });
      _isInitialized = ok == true;
      AppLogger.log(
        '$_logPrefix BillingClient bridge: ${_isInitialized ? "OK" : "fail"}',
      );
      return _isInitialized;
    } catch (e) {
      AppLogger.log('$_logPrefix initialize error: $e');
      return false;
    }
  }

  /// Подписки BillingClient со статусами CONFIRMED / PAUSED.
  Future<List<RuStorePurchaseInfo>> getLegacySubscriptions() async {
    if (!Platform.isAndroid) return [];
    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) return [];
    }

    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getLegacySubscriptions',
      );
      if (raw == null) return [];

      final result = <RuStorePurchaseInfo>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final stateName = (map['purchaseState'] as String?) ?? '';
        final state = switch (stateName) {
          'CONFIRMED' => RuStorePurchaseState.active,
          'PAUSED' => RuStorePurchaseState.paused,
          _ => RuStorePurchaseState.other,
        };
        if (state == RuStorePurchaseState.other) continue;

        final productId = (map['productId'] as String?) ?? '';
        if (productId.isEmpty) continue;

        result.add(
          RuStorePurchaseInfo(
            purchaseId: (map['purchaseId'] as String?) ?? '',
            productId: productId,
            invoiceId: map['invoiceId'] as String?,
            orderId: map['orderId'] as String?,
            kind: RuStoreProductKind.subscription,
            state: state,
            fromLegacySdk: true,
          ),
        );
      }

      AppLogger.log('$_logPrefix Legacy-подписок: ${result.length}');
      return result;
    } catch (e) {
      AppLogger.log('$_logPrefix getLegacySubscriptions error: $e');
      return [];
    }
  }
}
