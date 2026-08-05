import 'dart:async';

import 'package:flutter_rustore_pay/api/flutter_rustore_pay_client.dart';
import 'package:flutter_rustore_pay/model/preferred_purchase_type.dart';
import 'package:flutter_rustore_pay/model/product.dart' as pay;
import 'package:flutter_rustore_pay/model/product_type.dart';
import 'package:flutter_rustore_pay/model/purchase.dart';
import 'package:flutter_rustore_pay/model/purchase_availability.dart';
import 'package:flutter_rustore_pay/model/purchase_result.dart';
import 'package:flutter_rustore_pay/model/purchase_type.dart';
import 'package:flutter_rustore_pay/model/ru_store_exception.dart';
import 'package:flutter_rustore_pay/model/sdk_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/credit_config.dart';
import '../models/rustore_purchase_info.dart';
import '../models/store_product_model.dart';
import '../utils/app_logger.dart';
import 'rustore_legacy_billing_bridge.dart';
import 'rustore_pricing.dart';

class RuStoreResolvedPendingTokenPurchase {
  final String productId;
  final String purchaseId;
  final int tokenCount;

  const RuStoreResolvedPendingTokenPurchase({
    required this.productId,
    required this.purchaseId,
    required this.tokenCount,
  });
}

class RustoreConsumablePurchaseResult {
  const RustoreConsumablePurchaseResult({
    required this.success,
    required this.productId,
    this.purchaseId,
    this.invoiceId,
    this.orderId,
    this.finishCode,
    this.errorCode,
    this.errorMessage,
  });

  final bool success;
  final String productId;
  final String? purchaseId;
  final String? invoiceId;
  final String? orderId;
  final String? finishCode;
  final int? errorCode;
  final String? errorMessage;
}

class RustoreSubscriptionPurchaseResult {
  const RustoreSubscriptionPurchaseResult({
    required this.success,
    required this.productId,
    this.purchaseId,
    this.invoiceId,
    this.orderId,
    this.finishCode,
    this.purchaseState,
    this.errorCode,
    this.errorMessage,
  });

  final bool success;
  final String productId;
  final String? purchaseId;
  final String? invoiceId;
  final String? orderId;
  final String? finishCode;
  final String? purchaseState;
  final int? errorCode;
  final String? errorMessage;
}

/// Сервис платежей RuStore на базе Pay SDK + legacy BillingClient.
///
/// - Новые покупки (подписки и токены) — Pay SDK (`ONE_STEP`).
/// - Старые подписки BillingClient — через [RuStoreLegacyBillingBridge]
///   (официальная dual-SDK схема из docs/pay/migration).
/// Инициализация Pay: AndroidManifest (`console_app_id_value`).
class RuStoreBillingService {
  static const String _logPrefix = '🛒 RUSTORE_PAY';
  static const String _pendingInvoiceIdKey = 'rustore_pending_invoice_id';
  static const String _pendingProductIdKey = 'rustore_pending_product_id';
  static const String _processedTokenPurchaseIdsKey =
      'rustore_processed_token_purchase_ids';

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

  // Продукты RuStore - подписки
  static const Map<String, String> rustoreSubscriptionIds = {
    'weekly': 'aivideomaker.weekly.rustore',
    'monthly': 'aivideomaker.monthly.rustore',
    'yearly': 'aivideomaker.yearly.rustore',
  };

  // Продукты RuStore - токены
  static const Map<String, String> _rustoreTokenIds = {
    'small': 'aivideomaker.credits.40.rustore',
    'medium': 'aivideomaker.credits.150.rustore',
    'large': 'aivideomaker.credits.400.rustore',
  };

  // Легаси идентификаторы токенов (старые product ID в RuStore Console)
  static const Set<String> _legacyRuStoreCreditProductIds = {
    'aivideomaker.credits.50.rustore',
    'aivideomaker.credits.200.rustore',
    'aivideomaker.credits.600.rustore',
    'aivideomaker.100k.rustore',
    'aivideomaker.300k.rustore',
    'aivideomaker.800k.rustore',
  };

  final RuStorePayClient _payClient = RuStorePayClient.instance;
  final RuStoreLegacyBillingBridge _legacyBridge = RuStoreLegacyBillingBridge();

  bool _isInitialized = false;
  List<pay.Product> _products = [];

  static bool get isRuStoreForcedByDefine {
    const bool isRuStoreBuild = bool.fromEnvironment('RUSTORE');
    return isRuStoreBuild;
  }

  bool _isSubscriptionProduct(String productId) =>
      rustoreSubscriptionIds.values.contains(productId);

  bool _isTokenProduct(String productId) =>
      _rustoreTokenIds.values.contains(productId) ||
      _legacyRuStoreCreditProductIds.contains(productId);

  Future<void> _savePendingPurchase(String invoiceId, String productId) async {
    final normalizedInvoiceId = _nullIfEmpty(invoiceId);
    final normalizedProductId = _nullIfEmpty(productId);
    if (normalizedInvoiceId == null || normalizedProductId == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingInvoiceIdKey, normalizedInvoiceId);
    await prefs.setString(_pendingProductIdKey, normalizedProductId);
    AppLogger.log(
      '$_logPrefix Сохранена ожидающая invoice-покупка: '
      'productId=$normalizedProductId, invoiceId=$normalizedInvoiceId',
    );
  }

  Future<Map<String, String>?> _loadPendingPurchase() async {
    final prefs = await SharedPreferences.getInstance();
    final invoiceId = _nullIfEmpty(prefs.getString(_pendingInvoiceIdKey));
    final productId = _nullIfEmpty(prefs.getString(_pendingProductIdKey));

    if (invoiceId == null || productId == null) {
      return null;
    }

    return {
      'invoiceId': invoiceId,
      'productId': productId,
    };
  }

  Future<void> _clearPendingPurchase() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingInvoiceIdKey);
    await prefs.remove(_pendingProductIdKey);
    AppLogger.log('$_logPrefix Очищена ожидающая invoice-покупка RuStore');
  }

  Future<bool> hasPendingSubscriptionPurchase() async {
    final pendingPurchase = await _loadPendingPurchase();
    return pendingPurchase != null &&
        _isSubscriptionProduct(pendingPurchase['productId']!);
  }

  Future<bool> hasPendingTokenPurchase() async {
    final pendingPurchase = await _loadPendingPurchase();
    return pendingPurchase != null &&
        _isTokenProduct(pendingPurchase['productId']!);
  }

  Future<Set<String>> _loadProcessedTokenPurchaseIds() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_processedTokenPurchaseIdsKey) ?? [];
    return values.where((id) => id.isNotEmpty).toSet();
  }

  Future<bool> _isTokenPurchaseProcessed(String purchaseId) async {
    final ids = await _loadProcessedTokenPurchaseIds();
    return ids.contains(purchaseId);
  }

  Future<void> _markTokenPurchaseProcessed(String purchaseId) async {
    final normalizedPurchaseId = _nullIfEmpty(purchaseId);
    if (normalizedPurchaseId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final ids = await _loadProcessedTokenPurchaseIds();
    ids.add(normalizedPurchaseId);
    await prefs.setStringList(_processedTokenPurchaseIdsKey, ids.toList());
    AppLogger.log(
      '$_logPrefix Покупка токенов отмечена как примененная: $normalizedPurchaseId',
    );
  }

  Future<void> markTokenPurchaseApplied(String purchaseId) async {
    await _markTokenPurchaseProcessed(purchaseId);
  }

  /// Инициализация RuStore Pay SDK.
  Future<bool> initialize() async {
    if (_isInitialized) {
      AppLogger.log(
          '$_logPrefix SDK уже готов, пропускаем повторную инициализацию');
      return true;
    }

    try {
      AppLogger.log('$_logPrefix Инициализация RuStore Pay SDK...');
      AppLogger.log(
        '$_logPrefix consoleApplicationId=$_consoleApplicationId, '
        'deeplinkScheme=$_deeplinkScheme',
      );

      if (isRuStoreForcedByDefine) {
        AppLogger.log(
            '$_logPrefix RUSTORE=true — пропускаем isRuStoreInstalled()');
      } else {
        final installed = await _payClient.ruStoreUtils
            .isRuStoreInstalled()
            .timeout(const Duration(seconds: 3), onTimeout: () => false);
        AppLogger.log('$_logPrefix RuStore установлен: $installed');
        if (!installed) {
          AppLogger.log('$_logPrefix RuStore не установлен на устройстве');
          return false;
        }
      }

      try {
        final availability =
            await _payClient.purchaseInteractor.getPurchaseAvailability();
        switch (availability) {
          case Available():
            AppLogger.log('$_logPrefix Платежи доступны');
          case Unavailable(:final errorMessage):
            AppLogger.log(
              '$_logPrefix Платежи временно недоступны: $errorMessage',
            );
        }
      } catch (e) {
        AppLogger.log('$_logPrefix getPurchaseAvailability: $e');
      }

      // Dual-SDK: поднимаем BillingClient только для чтения старых подписок
      await _legacyBridge.initialize();

      _isInitialized = true;
      AppLogger.log('$_logPrefix Инициализация успешна');
      return true;
    } on TimeoutException {
      AppLogger.log('$_logPrefix Пропуск инициализации RuStore без сети');
      return false;
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка инициализации: $e');
      if (isRuStoreForcedByDefine) {
        _isInitialized = true;
        return true;
      }
      return false;
    }
  }

  /// Каталог подписок: сначала Pay SDK, иначе статичные цены.
  Future<List<StoreProductModel>> getProducts() async {
    AppLogger.log('$_logPrefix Загрузка продуктов...');

    final fallback = _staticSubscriptionProducts();

    if (!_isInitialized) {
      AppLogger.log('$_logPrefix SDK не готов — статичный каталог');
      return fallback;
    }

    try {
      final products = await _payClient.productInteractor
          .getProducts(rustoreSubscriptionIds.values.toList());
      _products = products;

      if (products.isEmpty) {
        AppLogger.log('$_logPrefix Пустой ответ SDK — статичный каталог');
        return fallback;
      }

      final mapped = <StoreProductModel>[];
      for (final product in products) {
        final period = _periodFromProductId(product.productId);
        if (period == null) continue;

        final rawPrice = product.price ?? 0;
        final priceValue = rawPrice / 100.0;
        final priceLabel = product.amountLabel.isNotEmpty
            ? product.amountLabel
            : _fallbackPriceLabel(period);

        mapped.add(
          StoreProductModel(
            id: product.productId,
            title: product.title.isNotEmpty
                ? product.title
                : _fallbackTitle(period),
            period: period,
            price: priceLabel,
            originalPrice: priceLabel,
            currency: product.currency.isNotEmpty
                ? product.currency
                : RuStorePricing.currencyCode,
            priceValue:
                priceValue > 0 ? priceValue : _fallbackPriceValue(period),
            description: product.description ?? '',
            isPopular: period == 'monthly',
          ),
        );
      }

      if (mapped.isEmpty) {
        return fallback;
      }

      mapped.sort((a, b) {
        const order = {'yearly': 0, 'monthly': 1, 'weekly': 2};
        return (order[a.period] ?? 9).compareTo(order[b.period] ?? 9);
      });

      AppLogger.log('$_logPrefix Загружено продуктов из SDK: ${mapped.length}');
      return mapped;
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка getProducts: $e — статичный каталог');
      return fallback;
    }
  }

  /// Покупка подписки или токенов (совместимость со старым API).
  Future<bool> purchaseProduct(String productId) async {
    if (_isSubscriptionProduct(productId)) {
      final result = await purchaseSubscriptionProduct(productId);
      return result.success;
    }

    final result = await purchaseConsumableProduct(productId);
    return result.success;
  }

  Future<RustoreSubscriptionPurchaseResult> purchaseSubscriptionProduct(
    String productId,
  ) async {
    if (!_isInitialized) {
      AppLogger.log('$_logPrefix Сервис не инициализирован');
      return RustoreSubscriptionPurchaseResult(
        success: false,
        productId: productId,
        errorMessage: 'service_not_initialized',
      );
    }

    try {
      AppLogger.log('$_logPrefix Покупка подписки: $productId');

      final result = await _purchaseViaPay(productId);
      final purchaseId = _nullIfEmpty(_stringValue(result.purchaseId));
      final invoiceId = _nullIfEmpty(_stringValue(result.invoiceId));
      final orderId = _nullIfEmpty(_stringValue(result.orderId));

      if (result.purchaseType == PurchaseType.twoStep && invoiceId != null) {
        await _savePendingPurchase(invoiceId, productId);
      }

      if (result.purchaseType == PurchaseType.twoStep && purchaseId != null) {
        await _confirmIfNeeded(purchaseId);
      }

      final resolvedPurchase = await _resolveSubscriptionPurchase(
        productId: productId,
        purchaseId: purchaseId,
        invoiceId: invoiceId,
      );

      if (resolvedPurchase != null) {
        if (resolvedPurchase.isPausedSubscription ||
            resolvedPurchase.state == RuStorePurchaseState.cancelled) {
          await _clearPendingPurchase();
          return RustoreSubscriptionPurchaseResult(
            success: false,
            productId: resolvedPurchase.productId,
            purchaseId: _nullIfEmpty(resolvedPurchase.purchaseId),
            invoiceId: resolvedPurchase.invoiceId,
            orderId: resolvedPurchase.orderId ?? orderId,
            finishCode: result.purchaseType.name,
            purchaseState: resolvedPurchase.purchaseState,
            errorMessage: 'subscription_not_active',
          );
        }

        if (resolvedPurchase.isActiveSubscription ||
            resolvedPurchase.purchaseState == 'CONFIRMED') {
          await _clearPendingPurchase();
          return RustoreSubscriptionPurchaseResult(
            success: true,
            productId: resolvedPurchase.productId,
            purchaseId: _nullIfEmpty(resolvedPurchase.purchaseId) ?? purchaseId,
            invoiceId: resolvedPurchase.invoiceId ?? invoiceId,
            orderId: resolvedPurchase.orderId ?? orderId,
            finishCode: result.purchaseType.name,
            purchaseState: resolvedPurchase.purchaseState,
          );
        }
      }

      return RustoreSubscriptionPurchaseResult(
        success: purchaseId != null && invoiceId != null,
        productId: _nullIfEmpty(_stringValue(result.productId)) ?? productId,
        purchaseId: purchaseId,
        invoiceId: invoiceId,
        orderId: orderId,
        finishCode: result.purchaseType.name,
        purchaseState: purchaseId != null ? 'CONFIRMED' : null,
        errorMessage: purchaseId != null && invoiceId != null
            ? null
            : 'purchase_not_resolved',
      );
    } on RuStorePurchaseCancelledException catch (e) {
      AppLogger.log('$_logPrefix Покупка подписки отменена: $e');
      return _recoverCancelledSubscriptionPurchase(productId, e);
    } on RuStoreProductPurchaseException catch (e) {
      AppLogger.log('$_logPrefix Ошибка покупки подписки: $e');
      return _recoverFailedSubscriptionPurchase(productId, e);
    } catch (e) {
      AppLogger.log('$_logPrefix Неожиданная ошибка покупки подписки: $e');
      return RustoreSubscriptionPurchaseResult(
        success: false,
        productId: productId,
        errorMessage: e.toString(),
      );
    }
  }

  Future<RustoreConsumablePurchaseResult> purchaseConsumableProduct(
    String productId, {
    String? developerPayload,
    String? orderId,
  }) async {
    if (!_isInitialized) {
      AppLogger.log('$_logPrefix Сервис не инициализирован');
      return RustoreConsumablePurchaseResult(
        success: false,
        productId: productId,
        errorMessage: 'service_not_initialized',
      );
    }

    try {
      AppLogger.log(
        '$_logPrefix Покупка consumable: productId=$productId orderId=$orderId',
      );

      final result = await _purchaseViaPay(
        productId,
        quantity: 1,
        orderId: orderId,
        developerPayload: developerPayload,
      );

      final purchaseId = _nullIfEmpty(_stringValue(result.purchaseId));
      final invoiceId = _nullIfEmpty(_stringValue(result.invoiceId));
      final resolvedOrderId =
          _nullIfEmpty(_stringValue(result.orderId)) ?? _nullIfEmpty(orderId);

      if (result.purchaseType == PurchaseType.twoStep && invoiceId != null) {
        await _savePendingPurchase(invoiceId, productId);
      }

      if (result.purchaseType == PurchaseType.twoStep && purchaseId != null) {
        await _confirmIfNeeded(purchaseId);
      }

      final resolvedPurchase = await _resolveConsumablePurchase(
        productId: productId,
        purchaseId: purchaseId,
        invoiceId: invoiceId,
      );

      if (resolvedPurchase != null) {
        if (resolvedPurchase.state == RuStorePurchaseState.cancelled ||
            resolvedPurchase.state == RuStorePurchaseState.paused) {
          await _clearPendingPurchase();
          return RustoreConsumablePurchaseResult(
            success: false,
            productId: resolvedPurchase.productId,
            purchaseId: _nullIfEmpty(resolvedPurchase.purchaseId),
            invoiceId: resolvedPurchase.invoiceId ?? invoiceId,
            orderId: resolvedPurchase.orderId ?? resolvedOrderId,
            finishCode: result.purchaseType.name,
            errorMessage: 'purchase_cancelled',
          );
        }

        if (resolvedPurchase.isRestorableToken ||
            resolvedPurchase.state == RuStorePurchaseState.confirmed) {
          await _clearPendingPurchase();
          return RustoreConsumablePurchaseResult(
            success: true,
            productId: resolvedPurchase.productId,
            purchaseId: _nullIfEmpty(resolvedPurchase.purchaseId) ?? purchaseId,
            invoiceId: resolvedPurchase.invoiceId ?? invoiceId,
            orderId: resolvedPurchase.orderId ?? resolvedOrderId,
            finishCode: result.purchaseType.name,
          );
        }
      }

      return RustoreConsumablePurchaseResult(
        success: purchaseId != null && invoiceId != null,
        productId: _nullIfEmpty(_stringValue(result.productId)) ?? productId,
        purchaseId: purchaseId,
        invoiceId: invoiceId,
        orderId: resolvedOrderId,
        finishCode: result.purchaseType.name,
        errorMessage: purchaseId != null && invoiceId != null
            ? null
            : 'purchase_not_resolved',
      );
    } on RuStorePurchaseCancelledException catch (e) {
      AppLogger.log('$_logPrefix Покупка consumable отменена: $e');
      return _recoverCancelledConsumablePurchase(
        productId: productId,
        fallbackOrderId: orderId,
        exception: e,
      );
    } on RuStoreProductPurchaseException catch (e) {
      AppLogger.log('$_logPrefix Ошибка consumable покупки: $e');
      return _recoverFailedConsumablePurchase(
        productId: productId,
        fallbackOrderId: orderId,
        exception: e,
      );
    } catch (e) {
      AppLogger.log('$_logPrefix Неожиданная ошибка consumable покупки: $e');
      return RustoreConsumablePurchaseResult(
        success: false,
        productId: productId,
        errorMessage: e.toString(),
      );
    }
  }

  Future<ProductPurchaseResult> _purchaseViaPay(
    String productId, {
    int? quantity,
    String? orderId,
    String? developerPayload,
  }) {
    return _payClient.purchaseInteractor.purchase(
      productId,
      quantity: quantity,
      orderId: orderId,
      developerPayload: developerPayload,
      preferredPurchaseType: PreferredPurchaseType.oneStep,
      sdkTheme: SdkTheme.light,
    );
  }

  Future<RuStorePurchaseInfo?> _resolveSubscriptionPurchase({
    required String productId,
    String? purchaseId,
    String? invoiceId,
    Duration maxWait = const Duration(seconds: 45),
  }) async {
    final direct = await _getPayPurchaseById(purchaseId);
    if (direct != null) {
      if (direct.isActiveSubscription ||
          direct.isPausedSubscription ||
          direct.state == RuStorePurchaseState.cancelled) {
        return direct;
      }
    }

    return _waitForPurchase(
      productId: productId,
      invoiceId: invoiceId,
      purchaseId: purchaseId,
      includeLegacy: false,
      maxWait: maxWait,
      acceptPurchase: (purchase) =>
          purchase.isActiveSubscription ||
          purchase.isPausedSubscription ||
          purchase.state == RuStorePurchaseState.cancelled,
    );
  }

  Future<RuStorePurchaseInfo?> _resolveConsumablePurchase({
    required String productId,
    String? purchaseId,
    String? invoiceId,
    Duration maxWait = const Duration(seconds: 45),
  }) async {
    final direct = await _getPayPurchaseById(purchaseId);
    if (direct != null) {
      if (direct.kind == RuStoreProductKind.consumable &&
          (direct.isRestorableToken ||
              direct.state == RuStorePurchaseState.cancelled)) {
        return direct;
      }
    }

    return _waitForPurchase(
      productId: productId,
      invoiceId: invoiceId,
      purchaseId: purchaseId,
      includeLegacy: false,
      maxWait: maxWait,
      acceptPurchase: (purchase) =>
          purchase.kind == RuStoreProductKind.consumable &&
          (purchase.isRestorableToken ||
              purchase.state == RuStorePurchaseState.cancelled),
    );
  }

  Future<RustoreSubscriptionPurchaseResult>
      _recoverCancelledSubscriptionPurchase(
    String productId,
    RuStorePurchaseCancelledException exception,
  ) async {
    final purchaseId = _nullIfEmpty(_stringValue(exception.purchaseId));
    final resolved = await _resolveSubscriptionPurchase(
      productId: productId,
      purchaseId: purchaseId,
    );
    if (resolved != null && resolved.isActiveSubscription) {
      return RustoreSubscriptionPurchaseResult(
        success: true,
        productId: resolved.productId,
        purchaseId: _nullIfEmpty(resolved.purchaseId),
        invoiceId: resolved.invoiceId,
        orderId: resolved.orderId,
        purchaseState: resolved.purchaseState,
      );
    }

    return RustoreSubscriptionPurchaseResult(
      success: false,
      productId: productId,
      purchaseId: purchaseId,
      errorMessage: 'purchase_cancelled',
    );
  }

  Future<RustoreSubscriptionPurchaseResult> _recoverFailedSubscriptionPurchase(
    String productId,
    RuStoreProductPurchaseException exception,
  ) async {
    final purchaseId = _nullIfEmpty(_stringValue(exception.purchaseId));
    final resolved = await _resolveSubscriptionPurchase(
      productId: productId,
      purchaseId: purchaseId,
    );
    if (resolved != null && resolved.isActiveSubscription) {
      return RustoreSubscriptionPurchaseResult(
        success: true,
        productId: resolved.productId,
        purchaseId: _nullIfEmpty(resolved.purchaseId),
        invoiceId: resolved.invoiceId,
        orderId: resolved.orderId,
        purchaseState: resolved.purchaseState,
      );
    }

    return RustoreSubscriptionPurchaseResult(
      success: false,
      productId: productId,
      purchaseId: purchaseId,
      errorMessage: exception.toString(),
    );
  }

  Future<RustoreConsumablePurchaseResult> _recoverCancelledConsumablePurchase({
    required String productId,
    required String? fallbackOrderId,
    required RuStorePurchaseCancelledException exception,
  }) async {
    final purchaseId = _nullIfEmpty(_stringValue(exception.purchaseId));
    final resolved = await _resolveConsumablePurchase(
      productId: productId,
      purchaseId: purchaseId,
    );
    if (resolved != null && resolved.isRestorableToken) {
      return RustoreConsumablePurchaseResult(
        success: true,
        productId: resolved.productId,
        purchaseId: _nullIfEmpty(resolved.purchaseId),
        invoiceId: resolved.invoiceId,
        orderId: resolved.orderId ?? _nullIfEmpty(fallbackOrderId),
      );
    }

    return RustoreConsumablePurchaseResult(
      success: false,
      productId: productId,
      purchaseId: purchaseId,
      orderId: _nullIfEmpty(fallbackOrderId),
      errorMessage: 'purchase_cancelled',
    );
  }

  Future<RustoreConsumablePurchaseResult> _recoverFailedConsumablePurchase({
    required String productId,
    required String? fallbackOrderId,
    required RuStoreProductPurchaseException exception,
  }) async {
    final purchaseId = _nullIfEmpty(_stringValue(exception.purchaseId));
    final resolved = await _resolveConsumablePurchase(
      productId: productId,
      purchaseId: purchaseId,
    );
    if (resolved != null && resolved.isRestorableToken) {
      return RustoreConsumablePurchaseResult(
        success: true,
        productId: resolved.productId,
        purchaseId: _nullIfEmpty(resolved.purchaseId),
        invoiceId: resolved.invoiceId,
        orderId: resolved.orderId ?? _nullIfEmpty(fallbackOrderId),
      );
    }

    return RustoreConsumablePurchaseResult(
      success: false,
      productId: productId,
      purchaseId: purchaseId,
      orderId: _nullIfEmpty(fallbackOrderId),
      errorMessage: exception.toString(),
    );
  }

  Future<RuStorePurchaseInfo?> _getPayPurchaseById(String? purchaseId) async {
    final normalizedPurchaseId = _nullIfEmpty(purchaseId);
    if (normalizedPurchaseId == null) return null;

    try {
      final purchase =
          await _payClient.purchaseInteractor.getPurchase(normalizedPurchaseId);
      return _mapPayPurchase(purchase);
    } catch (e) {
      AppLogger.log(
        '$_logPrefix Не удалось получить покупку $normalizedPurchaseId: $e',
      );
      return null;
    }
  }

  Future<RuStorePurchaseInfo?> _waitForPurchase({
    required String productId,
    String? invoiceId,
    String? purchaseId,
    required bool includeLegacy,
    required bool Function(RuStorePurchaseInfo purchase) acceptPurchase,
    Duration maxWait = const Duration(seconds: 45),
  }) async {
    final attempts = (maxWait.inSeconds / 3).ceil().clamp(1, 60);

    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final purchases = await getPurchases(includeLegacy: includeLegacy);
        final matched = _findMatchingPurchase(
          purchases,
          productId: productId,
          invoiceId: invoiceId,
          purchaseId: purchaseId,
        );
        if (matched != null && acceptPurchase(matched)) {
          return matched;
        }
      } catch (e) {
        AppLogger.log('$_logPrefix Ошибка ожидания покупки $productId: $e');
      }

      if (attempt < attempts - 1) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }

    return null;
  }

  RuStorePurchaseInfo? _findMatchingPurchase(
    List<RuStorePurchaseInfo> purchases, {
    required String productId,
    String? invoiceId,
    String? purchaseId,
  }) {
    final normalizedInvoiceId = _nullIfEmpty(invoiceId);
    final normalizedPurchaseId = _nullIfEmpty(purchaseId);

    for (final purchase in purchases) {
      if (purchase.productId != productId) {
        continue;
      }

      final matchesInvoice = normalizedInvoiceId != null &&
          purchase.invoiceId != null &&
          purchase.invoiceId == normalizedInvoiceId;
      final matchesPurchaseId = normalizedPurchaseId != null &&
          purchase.purchaseId == normalizedPurchaseId;
      final fallbackSubscriptionMatch =
          _isSubscriptionProduct(productId) && purchase.productId == productId;

      if (matchesInvoice || matchesPurchaseId || fallbackSubscriptionMatch) {
        return purchase;
      }
    }

    return null;
  }

  /// Получение списка покупок (Pay SDK + legacy BillingClient).
  Future<List<RuStorePurchaseInfo>> getPurchases({
    bool includeLegacy = true,
  }) async {
    if (!_isInitialized) {
      AppLogger.log('$_logPrefix Сервис не инициализирован');
      return [];
    }

    // Dual-SDK: Pay и BillingClient читаем параллельно — старые week/month
    // из BillingClient не видны в Pay SDK, но должны учитываться сразу.
    final payFuture = _fetchPayPurchases();
    final legacyFuture = includeLegacy
        ? _legacyBridge.getLegacySubscriptions()
        : Future<List<RuStorePurchaseInfo>>.value(const []);

    final payPurchases = await payFuture;
    final legacyPurchases = await legacyFuture;

    final result = <RuStorePurchaseInfo>[...payPurchases];
    for (final purchase in legacyPurchases) {
      final alreadyHavePayVersion = result.any(
        (item) =>
            item.productId == purchase.productId &&
            item.kind == RuStoreProductKind.subscription &&
            !item.fromLegacySdk,
      );
      if (!alreadyHavePayVersion) {
        result.add(purchase);
        AppLogger.log('$_logPrefix Legacy: $purchase');
      }
    }

    return result;
  }

  Future<List<RuStorePurchaseInfo>> _fetchPayPurchases() async {
    try {
      final purchases = await _payClient.purchaseInteractor.getPurchases();
      final result = <RuStorePurchaseInfo>[];
      for (final purchase in purchases) {
        final mapped = _mapPayPurchase(purchase);
        if (mapped != null) {
          result.add(mapped);
          AppLogger.log('$_logPrefix Pay: $mapped');
        }
      }
      return result;
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка getPurchases Pay SDK: $e');
      return const [];
    }
  }

  /// Подтверждение покупки (для CONSUMABLE и TWO_STEP подписок).
  Future<bool> confirmPurchase(String purchaseId) async {
    if (!_isInitialized) {
      AppLogger.log('$_logPrefix Сервис не инициализирован');
      return false;
    }

    final normalizedPurchaseId = _nullIfEmpty(purchaseId);
    if (normalizedPurchaseId == null) {
      return false;
    }

    try {
      await _confirmIfNeeded(normalizedPurchaseId);
      return true;
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка подтверждения покупки: $e');
      return false;
    }
  }

  Future<void> _confirmIfNeeded(String purchaseId) async {
    try {
      AppLogger.log('$_logPrefix confirmTwoStepPurchase: $purchaseId');
      await _payClient.purchaseInteractor.confirmTwoStepPurchase(purchaseId);
    } catch (e) {
      AppLogger.log('$_logPrefix confirmTwoStepPurchase ошибка: $e');
      rethrow;
    }
  }

  /// Восстановление покупок RuStore (подписки + токены).
  Future<List<RuStorePurchaseInfo>> restorePurchases() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        AppLogger.log(
          '$_logPrefix Не удалось инициализировать для восстановления покупок',
        );
        return [];
      }
    }

    try {
      final purchases = await getPurchases();
      final activePurchases = <RuStorePurchaseInfo>[];

      for (final purchase in purchases) {
        if (purchase.isActiveSubscription) {
          activePurchases.add(purchase);
          continue;
        }
        if (purchase.isPausedSubscription) {
          continue;
        }
        if (_isTokenProduct(purchase.productId) && purchase.isRestorableToken) {
          if (purchase.state == RuStorePurchaseState.paid) {
            try {
              await _confirmIfNeeded(purchase.purchaseId);
            } catch (_) {}
          }
          activePurchases.add(purchase);
        }
      }

      AppLogger.log(
        '$_logPrefix Восстановлено покупок: ${activePurchases.length}',
      );
      return activePurchases;
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка восстановления покупок: $e');
      return [];
    }
  }

  /// Восстановление только токенов RuStore.
  Future<List<RuStorePurchaseInfo>> restoreTokenPurchases() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        AppLogger.log(
          '$_logPrefix Не удалось инициализировать для восстановления токенов',
        );
        return [];
      }
    }

    try {
      final purchases = await getPurchases(includeLegacy: false);
      final tokenPurchases = <RuStorePurchaseInfo>[];

      for (final purchase in purchases) {
        if (!_isTokenProduct(purchase.productId)) continue;
        if (!purchase.isRestorableToken) continue;

        if (purchase.state == RuStorePurchaseState.paid) {
          try {
            await _confirmIfNeeded(purchase.purchaseId);
          } catch (_) {}
        }

        tokenPurchases.add(purchase);
      }

      AppLogger.log(
        '$_logPrefix Восстановлено токенов: ${tokenPurchases.length}',
      );
      return tokenPurchases;
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка восстановления токенов: $e');
      return [];
    }
  }

  Future<List<RuStorePurchaseInfo>> getPendingConsumablePurchases() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        AppLogger.log(
          '$_logPrefix Не удалось инициализировать для получения pending consumables',
        );
        return [];
      }
    }

    final purchases = await getPurchases(includeLegacy: false);
    return purchases.where((purchase) {
      if (!_isTokenProduct(purchase.productId)) return false;
      return purchase.isRestorableToken;
    }).toList();
  }

  /// Получение количества токенов по product ID.
  int getTokenCountFromProductId(String productId) {
    switch (productId) {
      case 'aivideomaker.credits.40.rustore':
      case 'aivideomaker.credits.50.rustore':
      case 'aivideomaker.100k.rustore':
        return CreditPackageType.small.credits;
      case 'aivideomaker.credits.150.rustore':
      case 'aivideomaker.credits.200.rustore':
      case 'aivideomaker.300k.rustore':
        return CreditPackageType.medium.credits;
      case 'aivideomaker.credits.400.rustore':
      case 'aivideomaker.credits.600.rustore':
      case 'aivideomaker.800k.rustore':
        return CreditPackageType.large.credits;
      default:
        return 0;
    }
  }

  /// Обработка существующих покупок при запуске приложения.
  Future<void> handleExistingPurchases() async {
    try {
      final purchases = await getPurchases(includeLegacy: false);
      for (final purchase in purchases) {
        if (purchase.kind == RuStoreProductKind.consumable &&
            purchase.state == RuStorePurchaseState.paid) {
          try {
            await _confirmIfNeeded(purchase.purchaseId);
          } catch (_) {}
        }
      }
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка обработки существующих покупок: $e');
    }
  }

  /// Проверка активной подписки.
  Future<bool> hasActiveSubscription() async {
    try {
      final purchases = await getPurchases(includeLegacy: true);
      return purchases.any((purchase) => purchase.isActiveSubscription);
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка проверки активной подписки: $e');
      return false;
    }
  }

  Future<bool> syncPendingSubscriptionPurchase({
    Duration maxWait = const Duration(seconds: 45),
  }) async {
    final pendingPurchase = await _loadPendingPurchase();
    if (pendingPurchase == null) {
      return false;
    }

    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        AppLogger.log(
          '$_logPrefix Не удалось инициализировать RuStore для pending sync',
        );
        return false;
      }
    }

    final productId = pendingPurchase['productId']!;
    final invoiceId = pendingPurchase['invoiceId']!;
    if (!_isSubscriptionProduct(productId)) {
      return false;
    }

    final resolved = await _resolveSubscriptionPurchase(
      productId: productId,
      invoiceId: invoiceId,
      maxWait: maxWait,
    );

    if (resolved == null) {
      return false;
    }

    if (resolved.isActiveSubscription) {
      await _clearPendingPurchase();
      return true;
    }

    if (resolved.isPausedSubscription ||
        resolved.state == RuStorePurchaseState.cancelled) {
      await _clearPendingPurchase();
    }

    return false;
  }

  Future<RuStoreResolvedPendingTokenPurchase?> syncPendingTokenPurchase({
    Duration maxWait = const Duration(seconds: 45),
  }) async {
    final pendingPurchase = await _loadPendingPurchase();
    if (pendingPurchase == null) {
      return null;
    }

    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        AppLogger.log(
          '$_logPrefix Не удалось инициализировать RuStore для token pending sync',
        );
        return null;
      }
    }

    final productId = pendingPurchase['productId']!;
    final invoiceId = pendingPurchase['invoiceId']!;
    if (!_isTokenProduct(productId)) {
      return null;
    }

    final purchase = await _resolveConsumablePurchase(
      productId: productId,
      invoiceId: invoiceId,
      maxWait: maxWait,
    );
    if (purchase == null || !purchase.isRestorableToken) {
      return null;
    }

    final purchaseId = purchase.purchaseId;
    if (purchaseId.isEmpty) {
      AppLogger.log(
        '$_logPrefix У токенной покупки $productId отсутствует purchaseId',
      );
      return null;
    }

    if (await _isTokenPurchaseProcessed(purchaseId)) {
      AppLogger.log(
        '$_logPrefix Токенная покупка $purchaseId уже была применена ранее',
      );
      await _clearPendingPurchase();
      return null;
    }

    final tokenCount = getTokenCountFromProductId(productId);
    if (tokenCount <= 0) {
      AppLogger.log(
        '$_logPrefix Не удалось определить количество токенов для $productId',
      );
      return null;
    }

    return RuStoreResolvedPendingTokenPurchase(
      productId: productId,
      purchaseId: purchaseId,
      tokenCount: tokenCount,
    );
  }

  Future<void> completePendingTokenPurchase(String purchaseId) async {
    await _markTokenPurchaseProcessed(purchaseId);
    await _clearPendingPurchase();
  }

  /// Получение цены продукта по ID.
  String? getProductPrice(String productId) {
    try {
      final product =
          _products.firstWhere((item) => item.productId == productId);
      return product.amountLabel;
    } catch (_) {
      return null;
    }
  }

  /// Получение числовой цены продукта по ID в рублях.
  double? getProductPriceValue(String productId) {
    try {
      final product =
          _products.firstWhere((item) => item.productId == productId);
      final price = product.price;
      if (price == null) return null;
      return price / 100.0;
    } catch (_) {
      return null;
    }
  }

  double getWeeklyPrice() =>
      getProductPriceValue('aivideomaker.weekly.rustore') ??
      RuStorePricing.weekly;

  double getMonthlyPrice() =>
      getProductPriceValue('aivideomaker.monthly.rustore') ??
      RuStorePricing.monthly;

  double getYearlyPrice() =>
      getProductPriceValue('aivideomaker.yearly.rustore') ??
      RuStorePricing.yearly;

  String getCurrencySymbol() => RuStorePricing.currencySymbol;

  @Deprecated('Используйте purchaseProduct вместо createPayment')
  Future<Map<String, dynamic>?> createPayment({
    required String productId,
    required String title,
    required double amount,
    String? description,
  }) async {
    final success = await purchaseProduct(productId);
    return success ? {'status': 'success'} : null;
  }

  RuStorePurchaseInfo? _mapPayPurchase(Purchase purchase) {
    if (purchase is SubscriptionPurchase) {
      final state = switch (purchase.status) {
        SubscriptionPurchaseStatus.active => RuStorePurchaseState.active,
        SubscriptionPurchaseStatus.paused => RuStorePurchaseState.paused,
        SubscriptionPurchaseStatus.cancelled => RuStorePurchaseState.cancelled,
        _ => RuStorePurchaseState.other,
      };
      return RuStorePurchaseInfo(
        purchaseId: purchase.purchaseId,
        productId: purchase.productId,
        invoiceId: _nullIfEmpty(_stringValue(purchase.invoiceId)),
        orderId: _nullIfEmpty(_stringValue(purchase.orderId)),
        kind: RuStoreProductKind.subscription,
        state: state,
        expirationDate: _nullIfEmpty(_stringValue(purchase.expirationDate)),
      );
    }

    if (purchase is ProductPurchase) {
      final kind = switch (purchase.productType) {
        ProductType.consumable => RuStoreProductKind.consumable,
        ProductType.nonConsumable => RuStoreProductKind.nonConsumable,
        ProductType.subscription => RuStoreProductKind.subscription,
        ProductType.undefined => RuStoreProductKind.unknown,
      };
      final state = switch (purchase.status) {
        ProductPurchaseStatus.paid => RuStorePurchaseState.paid,
        ProductPurchaseStatus.confirmed => RuStorePurchaseState.confirmed,
        ProductPurchaseStatus.cancelled => RuStorePurchaseState.cancelled,
        _ => RuStorePurchaseState.other,
      };
      return RuStorePurchaseInfo(
        purchaseId: purchase.purchaseId,
        productId: purchase.productId,
        invoiceId: _nullIfEmpty(_stringValue(purchase.invoiceId)),
        orderId: _nullIfEmpty(_stringValue(purchase.orderId)),
        kind: kind,
        state: state,
      );
    }

    return null;
  }

  List<StoreProductModel> _staticSubscriptionProducts() {
    return [
      StoreProductModel(
        id: 'aivideomaker.weekly.rustore',
        title: 'Недельная подписка',
        period: 'weekly',
        price: RuStorePricing.formattedWeekly,
        originalPrice: RuStorePricing.formattedWeekly,
        currency: RuStorePricing.currencyCode,
        priceValue: RuStorePricing.weekly,
        description: '',
      ),
      StoreProductModel(
        id: 'aivideomaker.monthly.rustore',
        title: 'Месячная подписка',
        period: 'monthly',
        price: RuStorePricing.formattedMonthly,
        originalPrice: RuStorePricing.formattedMonthly,
        currency: RuStorePricing.currencyCode,
        priceValue: RuStorePricing.monthly,
        description: '',
        isPopular: true,
      ),
      StoreProductModel(
        id: 'aivideomaker.yearly.rustore',
        title: 'Годовая подписка',
        period: 'yearly',
        price: RuStorePricing.formattedYearly,
        originalPrice: RuStorePricing.formattedYearly,
        currency: RuStorePricing.currencyCode,
        priceValue: RuStorePricing.yearly,
        description: '',
      ),
    ];
  }

  String? _periodFromProductId(String productId) {
    if (productId.contains('yearly')) return 'yearly';
    if (productId.contains('monthly')) return 'monthly';
    if (productId.contains('weekly')) return 'weekly';
    return null;
  }

  String _fallbackTitle(String period) => switch (period) {
        'weekly' => 'Недельная подписка',
        'monthly' => 'Месячная подписка',
        'yearly' => 'Годовая подписка',
        _ => period,
      };

  String _fallbackPriceLabel(String period) => switch (period) {
        'weekly' => RuStorePricing.formattedWeekly,
        'monthly' => RuStorePricing.formattedMonthly,
        'yearly' => RuStorePricing.formattedYearly,
        _ => '',
      };

  double _fallbackPriceValue(String period) => switch (period) {
        'weekly' => RuStorePricing.weekly,
        'monthly' => RuStorePricing.monthly,
        'yearly' => RuStorePricing.yearly,
        _ => 0,
      };

  String _stringValue(Object? value) => value?.toString().trim() ?? '';

  String? _nullIfEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }
}
