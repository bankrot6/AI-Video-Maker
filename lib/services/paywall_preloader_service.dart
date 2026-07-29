// removed unused: import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/subscription/purchase_providers.dart';
// removed unused: import '../features/subscription/subscription_providers.dart';
import '../features/subscription/paywall_screen.dart';
import '../services/payment_providers.dart';
import '../services/purchase_service.dart';
import '../services/yookassa_payment_service.dart';
import 'rustore_pricing.dart';
import '../models/subscription_model.dart';
import '../utils/app_logger.dart';

/// Сервис для предварительной загрузки данных Paywall
/// Инициализирует продукты и рассчитывает цены в фоне при запуске приложения
class PaywallPreloaderService {
  final Ref _ref;
  bool _isInitialized = false;
  bool _isInitializing = false;

  PaywallPreloaderService(this._ref);

  /// Проверяет, была ли выполнена инициализация
  bool get isInitialized => _isInitialized;

  /// Проверяет, выполняется ли инициализация в данный момент
  bool get isInitializing => _isInitializing;

  /// Выполняет предварительную загрузку данных Paywall
  Future<void> preloadPaywallData() async {
    if (_isInitialized || _isInitializing) {
      AppLogger.log(
        '🎯 PAYWALL_PRELOADER: Предзагрузка уже выполнена или выполняется',
        level: LogLevel.debug,
      );
      return;
    }

    _isInitializing = true;
    AppLogger.log(
      '🎯 PAYWALL_PRELOADER: Начинаем предварительную загрузку данных Paywall',
      level: LogLevel.info,
    );

    try {
      // 1. Определяем тип платежной системы
      AppLogger.log(
        '🎯 PAYWALL_PRELOADER: Определяем тип платежной системы',
        level: LogLevel.debug,
      );
      final paymentProviderType =
          await _ref.read(paymentProviderTypeProvider.future);
      AppLogger.log(
        '🎯 PAYWALL_PRELOADER: Тип платежной системы: $paymentProviderType',
        level: LogLevel.info,
      );

      // 2. Инициализируем сервис покупок
      AppLogger.log(
        '🎯 PAYWALL_PRELOADER: Инициализируем сервис покупок',
        level: LogLevel.debug,
      );
      final purchaseController = _ref.read(purchaseControllerProvider);
      await purchaseController.initialize();

      // 3. Загружаем продукты из магазина
      AppLogger.log(
        '🎯 PAYWALL_PRELOADER: Загружаем продукты из магазина',
        level: LogLevel.debug,
      );
      final products = await _ref.read(productsProvider.future);
      AppLogger.log(
        '🎯 PAYWALL_PRELOADER: Загружено ${products.length} продуктов',
        level: LogLevel.info,
      );

      // 4. Логируем информацию о продуктах
      for (final product in products) {
        AppLogger.log(
          '🎯 PAYWALL_PRELOADER: Продукт ${product.id}: ${product.title}, ${product.price}',
          level: LogLevel.debug,
        );
      }

      // 5. Если есть достаточно продуктов, предрассчитываем скидку
      if (products.length >= 2) {
        await _precalculateDiscount(products, paymentProviderType);
      }

      _isInitialized = true;
      AppLogger.log(
        '🎯 PAYWALL_PRELOADER: ✅ Предварительная загрузка завершена успешно',
        level: LogLevel.info,
      );
    } catch (e) {
      AppLogger.log(
        '🎯 PAYWALL_PRELOADER: ❌ Ошибка при предварительной загрузке: $e',
        level: LogLevel.error,
      );
    } finally {
      _isInitializing = false;
    }
  }

  /// Предрассчитывает скидку для продуктов
  Future<void> _precalculateDiscount(
    List<dynamic> products,
    PaymentProvider paymentProviderType,
  ) async {
    AppLogger.log(
      '🎯 PAYWALL_PRELOADER: Предрассчитываем скидку',
      level: LogLevel.debug,
    );

    try {
      dynamic yearlyProduct;
      dynamic monthlyProduct;

      // Ищем годовой и месячный продукты с учётом используемого стора
      for (final product in products) {
        if (paymentProviderType == PaymentProvider.rustore) {
          if (product.id == StoreProductIds.yearlyRuStore) {
            yearlyProduct = product;
          } else if (product.id == StoreProductIds.monthlyRuStore) {
            monthlyProduct = product;
          }
        } else {
          if (product.id == StoreProductIds.yearlyWithTrial) {
            yearlyProduct = product;
          } else if (product.id == StoreProductIds.monthly) {
            monthlyProduct = product;
          }
        }
      }

      if (yearlyProduct != null && monthlyProduct != null) {
        double yearlyPrice;
        double monthlyPrice;

        switch (paymentProviderType) {
          case PaymentProvider.rustore:
            AppLogger.log(
              '🎯 PAYWALL_PRELOADER: Пользователь RuStore – используем фиксированные цены',
              level: LogLevel.debug,
            );
            yearlyPrice = RuStorePricing.yearly;
            monthlyPrice = RuStorePricing.monthly;
            break;

          case PaymentProvider.yookassa:
            AppLogger.log(
              '🎯 PAYWALL_PRELOADER: Российский пользователь Google Play – используем цены ЮКассы',
              level: LogLevel.debug,
            );
            // Получаем цены из YooKassaPaymentService
            yearlyPrice = YooKassaPaymentService.getPriceForSubscriptionType(
                SubscriptionType.yearly);
            monthlyPrice = YooKassaPaymentService.getPriceForSubscriptionType(
                SubscriptionType.monthly);
            AppLogger.log(
              '🎯 PAYWALL_PRELOADER: Цены ЮКассы - годовая: $yearlyPrice₽, месячная: $monthlyPrice₽',
              level: LogLevel.debug,
            );
            break;

          case PaymentProvider.standardIAP:
            AppLogger.log(
              '🎯 PAYWALL_PRELOADER: Стандартные пользователи – извлекаем цены из магазина',
              level: LogLevel.debug,
            );
            yearlyPrice = _extractNumericPrice(yearlyProduct.price);
            monthlyPrice = _extractNumericPrice(monthlyProduct.price);
            break;
        }

        final double yearCostByMonthly = monthlyPrice * 12;
        final double savedAmount = yearCostByMonthly - yearlyPrice;
        final int discountPercent =
            ((savedAmount / yearCostByMonthly) * 100).round();

        AppLogger.log(
          '🎯 PAYWALL_PRELOADER: Рассчитанная скидка: $discountPercent%',
          level: LogLevel.info,
        );

        // Сохраняем рассчитанную скидку в провайдер
        _ref.read(discountPercentProvider.notifier).state = discountPercent;
      }
    } catch (e) {
      AppLogger.log(
        '🎯 PAYWALL_PRELOADER: Ошибка при предрасчете скидки: $e',
        level: LogLevel.error,
      );
    }
  }

  /// Извлекает числовое значение цены из строки
  double _extractNumericPrice(String priceString) {
    final RegExp numericRegex = RegExp(r'[\d,]+\.?\d*');
    final match = numericRegex.firstMatch(priceString);
    if (match != null) {
      String numericValue = match.group(0)!.replaceAll(',', '');
      return double.tryParse(numericValue) ?? 0.0;
    }
    return 0.0;
  }
}

/// Провайдер для сервиса предварительной загрузки Paywall
final paywallPreloaderServiceProvider =
    Provider<PaywallPreloaderService>((ref) {
  return PaywallPreloaderService(ref);
});
