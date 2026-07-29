import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/subscription_model.dart';
import 'region_service.dart';
import 'yookassa_payment_service.dart';
import 'payment_result_handler.dart';
import 'subscription/subscription_storage_service.dart';
import 'subscription/subscription_validation_service.dart';
import 'subscription/subscription_renewal_service.dart';

import 'app_store_detection_service.dart';
import 'rustore_billing_service.dart';
import '../utils/app_logger.dart';
import 'token_purchase_service.dart';
import 'yookassa_token_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'purchase_service.dart';

/// Провайдер для сервиса региона
final regionServiceProvider = Provider<RegionService>((ref) {
  return RegionService();
});

/// Провайдер для сервиса ЮKassa
final yookassaServiceProvider = Provider<YooKassaPaymentService>((ref) {
  return YooKassaPaymentService();
});

/// Провайдер для сервиса RuStore биллинга
final rustoreBillingServiceProvider = Provider<RuStoreBillingService>((ref) {
  return RuStoreBillingService();
});

/// Провайдер для сервиса определения источника установки
final appStoreDetectionServiceProvider =
    Provider<AppStoreDetectionService>((ref) {
  return AppStoreDetectionService();
});

/// Провайдер для обработчика результатов платежей
final paymentResultHandlerProvider = Provider<PaymentResultHandler>((ref) {
  return PaymentResultHandler();
});

/// Провайдер для сервиса хранения подписок
final subscriptionStorageServiceProvider =
    Provider<SubscriptionStorageService>((ref) {
  return SubscriptionStorageService();
});

/// Провайдер для сервиса валидации подписки
final subscriptionValidationServiceProvider =
    Provider<SubscriptionValidationService>((ref) {
  return SubscriptionValidationService();
});

/// Провайдер для сервиса напоминаний о продлении подписки
final subscriptionRenewalServiceProvider =
    Provider<SubscriptionRenewalService>((ref) {
  return SubscriptionRenewalService();
});

/// Провайдер для определения типа платежной системы
enum PaymentProvider {
  /// Стандартные IAP (Google Play, App Store)
  standardIAP,

  /// ЮKassa (для российских пользователей из Google Play)
  yookassa,

  /// RuStore (для пользователей из RuStore)
  rustore,
}

/// Провайдер для определения типа платежной системы
final paymentProviderTypeProvider =
    FutureProvider<PaymentProvider>((ref) async {
  try {
    // Определяем источник установки приложения (без сети RuStore не вызываем)
    final storeDetectionService = AppStoreDetectionService();
    final installationSource =
        await storeDetectionService.getInstallationSource();

    // Логика выбора провайдера платежей:
    // 1. Если установлено из RuStore -> используем RuStore billing
    // 2. Если установлено из Google Play и пользователь в России -> используем YooKassa
    // 3. Во всех остальных случаях -> используем стандартные IAP

    // Дополнительное логирование для production
    final forcedSource = storeDetectionService.getForcedSourceForTesting();
    if (forcedSource != null) {
      AppLogger.log(
          '🏪 PAYMENT_PROVIDER: [DEBUG] Используется принудительный источник: $forcedSource');
    }

    AppLogger.log(
        '🏪 PAYMENT_PROVIDER: Определение провайдера для источника: $installationSource');

    switch (installationSource) {
      case AppStoreType.ruStore:
        AppLogger.log(
            '🏪 PAYMENT_PROVIDER: ✅ Используем RuStore billing для пользователей RuStore');
        AppLogger.log(
            '🏪 PAYMENT_PROVIDER: [ANALYTICS] source=rustore, provider=rustore');
        return PaymentProvider.rustore;

      case AppStoreType.googlePlay:
        // Для Google Play определяем валюту ТОЛЬКО по Google Play ProductDetails
        try {
          final productIds = StoreProductIds.allAndroid;
          final response =
              await InAppPurchase.instance.queryProductDetails(productIds);

          if (response.error != null) {
            AppLogger.log(
                '🏪 PAYMENT_PROVIDER: Google Play details error: ${response.error}',
                level: LogLevel.warning);
          }

          final currencies = response.productDetails
              .map((p) => p.currencyCode)
              .where((c) => c.isNotEmpty)
              .toSet();

          AppLogger.log(
              '🏪 PAYMENT_PROVIDER: Google Play currencies detected: ${currencies.join(', ')}');

          final bool isRub = currencies.contains('RUB');

          if (isRub) {
            AppLogger.log(
                '🏪 PAYMENT_PROVIDER: ✅ Валюта RUB в Google Play → YooKassa');
            AppLogger.log(
                '🏪 PAYMENT_PROVIDER: [ANALYTICS] source=googleplay, provider=yookassa, currency=RUB');
            return PaymentProvider.yookassa;
          }

          AppLogger.log(
              '🏪 PAYMENT_PROVIDER: ✅ Валюта не RUB в Google Play → стандартные IAP');
          AppLogger.log(
              '🏪 PAYMENT_PROVIDER: [ANALYTICS] source=googleplay, provider=standard, currencies=${currencies.join(', ')}');
          return PaymentProvider.standardIAP;
        } catch (e) {
          AppLogger.log(
              '🏪 PAYMENT_PROVIDER: Ошибка при определении валюты через Google Play: $e',
              level: LogLevel.error);
          // Если не смогли определить валюту из ProductDetails, безопасный фолбэк — стандартные IAP
          return PaymentProvider.standardIAP;
        }

      case AppStoreType.appStore:
        AppLogger.log(
            '🏪 PAYMENT_PROVIDER: ✅ Используем стандартные IAP для пользователей App Store');
        AppLogger.log(
            '🏪 PAYMENT_PROVIDER: [ANALYTICS] source=appstore, provider=standard');
        return PaymentProvider.standardIAP;

      case AppStoreType.unknown:
      default:
        AppLogger.log(
            '🏪 PAYMENT_PROVIDER: ⚠️ Используем стандартные IAP для неизвестного источника: $installationSource');
        AppLogger.log(
            '🏪 PAYMENT_PROVIDER: [ANALYTICS] source=unknown, provider=standard');
        return PaymentProvider.standardIAP;
    }
  } catch (e, st) {
    AppLogger.log(
        '🏪 PAYMENT_PROVIDER: Ошибка определения провайдера (нет сети?): $e',
        level: LogLevel.warning);
    AppLogger.log('$st', level: LogLevel.debug);
    return PaymentProvider.standardIAP;
  }
});

/// Проверка использования оплаты через ЮKassa (для обратной совместимости)
final useYookassaPaymentProvider = FutureProvider<bool>((ref) async {
  final paymentProvider = await ref.watch(paymentProviderTypeProvider.future);
  return paymentProvider == PaymentProvider.yookassa;
});

/// Проверка использования оплаты через RuStore
final useRustorePaymentProvider = FutureProvider<bool>((ref) async {
  final paymentProvider = await ref.watch(paymentProviderTypeProvider.future);
  return paymentProvider == PaymentProvider.rustore;
});

/// Провайдер для событий успешных платежей
final paymentSuccessStreamProvider = StreamProvider<String>((ref) {
  final handler = ref.watch(paymentResultHandlerProvider);
  return handler.onPaymentSuccess;
});

/// Проверка активности подписки через ЮKassa
final yookassaSubscriptionActiveProvider = FutureProvider<bool>((ref) async {
  final storageService = ref.watch(subscriptionStorageServiceProvider);
  return await storageService.isSubscriptionActive();
});

/// Получение типа активной подписки
final activeSubscriptionTypeProvider =
    FutureProvider<SubscriptionType>((ref) async {
  final validationService = ref.watch(subscriptionValidationServiceProvider);
  return await validationService.getActiveSubscriptionType();
});

/// Получение информации о подписке
final subscriptionInfoProvider = FutureProvider<SubscriptionInfo?>((ref) async {
  final validationService = ref.watch(subscriptionValidationServiceProvider);
  return await validationService.getSubscriptionInfo();
});

/// Получение количества дней до окончания подписки
final daysLeftProvider = FutureProvider<int>((ref) async {
  final validationService = ref.watch(subscriptionValidationServiceProvider);
  return await validationService.getDaysLeft();
});

/// Провайдер для получения последнего использованного типа подписки
final lastSubscriptionTypeProvider =
    FutureProvider<SubscriptionType?>((ref) async {
  final renewalService = ref.watch(subscriptionRenewalServiceProvider);
  return await renewalService.getLastSubscriptionType();
});

/// Провайдер для проверки статуса напоминаний о продлении
final renewalRemindersEnabledProvider = FutureProvider<bool>((ref) async {
  final renewalService = ref.watch(subscriptionRenewalServiceProvider);
  return await renewalService.isReminderEnabled();
});

/// Провайдер для сервиса токенных покупок через IAP
final tokenPurchaseServiceProvider = Provider<TokenPurchaseService>((ref) {
  return TokenPurchaseService();
});

/// Провайдер для сервиса токенов YooKassa
final yookassaTokenServiceProvider = Provider<YooKassaTokenService>((ref) {
  return YooKassaTokenService();
});
