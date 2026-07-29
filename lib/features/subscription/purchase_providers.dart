import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:io';
import '../../services/purchase_service.dart';
import '../../models/product_model.dart';
import '../../models/subscription_model.dart';
import '../../services/payment_providers.dart';
import 'subscription_providers.dart';
import 'package:flutter/foundation.dart';
import '../../services/subscription/subscription_storage_service.dart';
import '../../services/localization/app_localization_service.dart';
import '../../services/trial_server_service.dart';
import '../../services/rustore_purchase_verification_service.dart';
import '../../services/rustore_billing_service.dart';
import '../../models/rustore_purchase_info.dart';
import '../../providers/credit_providers.dart';

/// Провайдер сервиса покупок
final purchaseServiceProvider = Provider<IPurchaseService>((ref) {
  return InAppPurchaseService();
});

/// Провайдер для проверки доступности магазина приложений
final storeAvailabilityProvider = FutureProvider<bool>((ref) async {
  final purchaseService = ref.watch(purchaseServiceProvider);
  return await purchaseService.isAvailable;
});

/// Провайдер для получения продуктов из магазина
final productsProvider = FutureProvider<List<ProductModel>>((ref) async {
  try {
    // Определяем тип платежной системы
    final paymentProviderType =
        await ref.watch(paymentProviderTypeProvider.future);

    switch (paymentProviderType) {
      case PaymentProvider.rustore:
        // Для пользователей RuStore получаем продукты из RuStore
        debugPrint('🛒 PRODUCTS: Загружаем продукты из RuStore');
        final rustoreService = ref.watch(rustoreBillingServiceProvider);

        // Для отображения используем статический список, SDK не требуется
        final storeProducts = await rustoreService.getProducts();
        debugPrint(
            '🛒 PRODUCTS: Получено ${storeProducts.length} продуктов из RuStore (статично)');

        // Конвертируем StoreProductModel в ProductModel
        return storeProducts
            .map((storeProduct) => ProductModel.fromStoreProduct(storeProduct))
            .toList();

      case PaymentProvider.yookassa:
      case PaymentProvider.standardIAP:
        // Для остальных пользователей используем стандартные IAP
        debugPrint('🛒 PRODUCTS: Загружаем продукты из стандартных IAP');
        final purchaseService = ref.watch(purchaseServiceProvider);

        // Инициализация сервиса
        await purchaseService.initialize();

        // Получение продуктов из магазина
        final productDetails = await purchaseService.getProducts();

        // Преобразование в модели продуктов
        return productDetails
            .map((details) => ProductModel.fromProductDetails(details))
            .toList();
    }
  } catch (e) {
    // Логирование ошибки
    debugPrint('🔴 PRODUCTS: Ошибка при получении продуктов: $e');
    return [];
  }
});

/// Провайдер для текущего выбранного продукта
final selectedProductProvider = StateProvider<ProductModel?>((ref) => null);

/// Провайдер для отслеживания покупок
final purchasesProvider = StreamProvider<List<PurchaseDetails>>((ref) {
  final purchaseService = ref.watch(purchaseServiceProvider);
  return purchaseService.purchaseStream;
});

/// Провайдер для управления покупками
final purchaseControllerProvider = Provider<PurchaseController>((ref) {
  debugPrint('🔵 PROVIDERS: Создание PurchaseController');
  return PurchaseController(ref);
});

/// Контроллер для управления покупками - реализует бизнес-логику
class PurchaseController {
  final Ref _ref;

  PurchaseController(this._ref) {
    debugPrint('🔵 CONTROLLER: PurchaseController создан');
  }

  /// Синхронизация локальной подписки со статусом покупок из StoreKit/Play Billing
  Future<bool> syncSubscriptionStatus() async {
    debugPrint('🔵 CONTROLLER: Синхронизация статуса подписки');

    try {
      // Получаем текущую подписку из репозитория
      final subscriptionNotifier = _ref.read(subscriptionProvider.notifier);
      final subscriptionAsyncValue = _ref.read(subscriptionProvider);

      // Проверяем, загружена ли подписка успешно
      if (subscriptionAsyncValue is AsyncData<SubscriptionModel>) {
        final SubscriptionModel subscription = subscriptionAsyncValue.value;

        // Получаем тип подписки и проверяем активность
        final SubscriptionType subscriptionType = subscription.type;
        final bool isSubscriptionActive = subscription.isActive;

        debugPrint(
            '🔵 CONTROLLER: Текущая подписка: тип=$subscriptionType, активна=$isSubscriptionActive');

        // Если у пользователя активная платная подписка в локальном хранилище
        if (isSubscriptionActive && subscriptionType != SubscriptionType.free) {
          debugPrint('🔵 CONTROLLER: Обнаружена активная локальная подписка');
          return true;
        }
      } else {
        debugPrint(
            '🔵 CONTROLLER: Подписка еще не загружена или ошибка загрузки');
      }

      // Если нет локальной активной подписки, определяем провайдера и синхронизируем
      final paymentProviderType =
          await _ref.read(paymentProviderTypeProvider.future);

      if (paymentProviderType == PaymentProvider.rustore) {
        debugPrint(
            '🔵 CONTROLLER: Провайдер RuStore — синхронизация через RuStore SDK');

        final ruStoreService = _ref.read(rustoreBillingServiceProvider);
        final initialized = await ruStoreService.initialize();

        if (initialized) {
          // Dual-SDK: сначала Pay + BillingClient → локальная активация.
          // Серверный reconcile/link_legacy не должен держать free-баннер.
          final purchases =
              await ruStoreService.getPurchases(includeLegacy: true);
          final activatedLocally = await _activateRustoreSubscriptionLocally(
            purchases: purchases,
            subscriptionNotifier: subscriptionNotifier,
          );

          await _reconcileRustoreConsumables(ruStoreService);
          await _reconcileRustoreSubscriptions(ruStoreService);

          if (activatedLocally) {
            return true;
          }

          // Повторная проверка после reconcile (на случай гонки Pay/legacy)
          final purchasesAfter =
              await ruStoreService.getPurchases(includeLegacy: true);
          return _activateRustoreSubscriptionLocally(
            purchases: purchasesAfter,
            subscriptionNotifier: subscriptionNotifier,
          );
        }
      } else if (paymentProviderType == PaymentProvider.yookassa) {
        // Синхронизация для YooKassa: проверяем локальное хранилище подписок
        debugPrint(
            '🔵 CONTROLLER: Провайдер YooKassa — синхронизация через локальное хранилище');

        try {
          final storage = SubscriptionStorageService();
          final active = await storage.isSubscriptionActive();
          if (active) {
            final info = await storage.getSubscription();
            if (info != null) {
              final subscriptionNotifier =
                  _ref.read(subscriptionProvider.notifier);
              switch (info.type) {
                case SubscriptionType.weekly:
                  await subscriptionNotifier.activateWeekly();
                  break;
                case SubscriptionType.monthly:
                  await subscriptionNotifier.activateMonthly();
                  break;
                case SubscriptionType.yearly:
                  await subscriptionNotifier.activateYearly();
                  break;
                default:
                  break;
              }
              await subscriptionNotifier.refreshSubscription();
              return true;
            }
          }

          // Фолбэк: пробуем стандартную IAP проверку (на всякий случай)
          final purchaseService = _ref.read(purchaseServiceProvider);
          await purchaseService.initialize();
          final hasActive = await purchaseService.checkActiveSubscription();
          if (hasActive) {
            final subscriptionNotifier =
                _ref.read(subscriptionProvider.notifier);
            await subscriptionNotifier.activateWeekly();
            await subscriptionNotifier.refreshSubscription();
            return true;
          }
        } catch (e) {
          debugPrint('🔴 CONTROLLER: Ошибка синхронизации YooKassa: $e');
        }

        return false;
      } else {
        // Стандартные IAP (App Store / Google Play)
        final purchaseService = _ref.read(purchaseServiceProvider);
        await purchaseService.initialize();

        debugPrint(
            '🔵 CONTROLLER: Проверка статуса подписки в StoreKit/Play Billing');
        final hasActiveSubscription =
            await purchaseService.checkActiveSubscription();

        if (hasActiveSubscription) {
          debugPrint(
              '🔵 CONTROLLER: Обнаружена активная подписка в StoreKit/Play Billing');

          // Проверяем, загружена ли подписка успешно
          if (subscriptionAsyncValue is AsyncData<SubscriptionModel>) {
            final SubscriptionModel subscription = subscriptionAsyncValue.value;
            final bool isSubscriptionActive = subscription.isActive;
            final SubscriptionType subscriptionType = subscription.type;

            // Необходимо обновить локальное хранилище, если в нем нет данных об активной подписке
            if (!isSubscriptionActive ||
                subscriptionType == SubscriptionType.free) {
              debugPrint(
                  '🔵 CONTROLLER: Обновляем локальную подписку на основе данных из магазина');
              // Здесь нужно активировать подписку в зависимости от продукта из магазина
              // В идеале нужно получить все покупки и выбрать наиболее подходящую
              await subscriptionNotifier.activateWeekly(); // временное решение
            }
          } else {
            // Если локальная подписка еще не загружена, просто активируем недельную как временное решение
            debugPrint(
                '🔵 CONTROLLER: Подписка не загружена, активируем временную');
            await subscriptionNotifier.activateWeekly();
          }

          return true;
        }
      }

      debugPrint('🔵 CONTROLLER: Активных подписок не обнаружено');
      return false;
    } catch (e) {
      debugPrint(
          '🔴 CONTROLLER: Ошибка при синхронизации статуса подписки: $e');
      return false;
    }
  }

  Future<void> _reconcileRustoreConsumables(
    RuStoreBillingService ruStoreService,
  ) async {
    final overlayNotifier = _ref.read(creditBalanceOverlayProvider.notifier);
    overlayNotifier.show();
    try {
      final pendingPurchases = await ruStoreService.getPendingConsumablePurchases();
      if (pendingPurchases.isEmpty) {
        debugPrint('🔵 CONTROLLER: Pending consumable покупок RuStore нет');
        return;
      }

      final reconcileInput = pendingPurchases
          .where((purchase) =>
              purchase.purchaseId.isNotEmpty &&
              (purchase.invoiceId?.isNotEmpty ?? false) &&
              purchase.productId.isNotEmpty)
          .map(
            (purchase) => RustorePendingPurchase(
              purchaseId: purchase.purchaseId,
              invoiceId: purchase.invoiceId!,
              productId: purchase.productId,
              orderId: purchase.orderId,
            ),
          )
          .toList();

      if (reconcileInput.isEmpty) {
        debugPrint('🔵 CONTROLLER: Нет валидных pending consumable покупок');
        return;
      }

      final reconcileResult =
          await RustorePurchaseVerificationService.instance.reconcilePurchases(
        reconcileInput,
      );
      if (!reconcileResult.success) {
        debugPrint('🔴 CONTROLLER: Reconcile RuStore завершился без success');
        return;
      }

      RustorePurchaseVerificationResult? latestSnapshot;
      for (final item in reconcileResult.items) {
        if (!item.success) continue;
        latestSnapshot = item;
        if (item.needsClientConfirm) {
          final confirmed = await ruStoreService.confirmPurchase(item.purchaseId);
          if (confirmed) {
            await RustorePurchaseVerificationService.instance
                .markConfirmed(item.purchaseId);
          }
        }
      }

      if (latestSnapshot != null) {
        await _ref.read(creditServiceProvider).applyServerPurchaseSnapshot(
              purchasedCredits: latestSnapshot.purchasedCredits,
              currentBalance: latestSnapshot.currentBalance,
            );
        _ref.invalidate(creditUsageNotifierProvider);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } catch (e) {
      debugPrint('🔴 CONTROLLER: Ошибка reconcile RuStore consumables: $e');
    } finally {
      overlayNotifier.hide();
    }
  }

  /// Активирует лучшую подписку из списка Pay SDK + BillingClient локально.
  ///
  /// Dual-SDK: [RuStorePurchaseInfo.purchaseState] для legacy `active`
  /// мапится в `CONFIRMED`, поэтому обе ветки учитываются одинаково.
  Future<bool> _activateRustoreSubscriptionLocally({
    required List<RuStorePurchaseInfo> purchases,
    required SubscriptionNotifier subscriptionNotifier,
  }) async {
    final confirmedSubs = purchases.where((p) =>
        p.productType == 'SUBSCRIPTION' && p.purchaseState == 'CONFIRMED');
    final pausedSubs = purchases.where(
        (p) => p.productType == 'SUBSCRIPTION' && p.purchaseState == 'PAUSED');
    final terminatedSubs = purchases.where((p) =>
        p.productType == 'SUBSCRIPTION' &&
        (p.purchaseState == 'TERMINATED' ||
            p.purchaseState == 'CANCELLED' ||
            p.purchaseState == 'EXPIRED'));

    String? bestProductId;
    if (confirmedSubs
        .any((p) => p.productId == 'aivideomaker.yearly.rustore')) {
      bestProductId = 'aivideomaker.yearly.rustore';
    } else if (confirmedSubs
        .any((p) => p.productId == 'aivideomaker.monthly.rustore')) {
      bestProductId = 'aivideomaker.monthly.rustore';
    } else if (confirmedSubs
        .any((p) => p.productId == 'aivideomaker.weekly.rustore')) {
      bestProductId = 'aivideomaker.weekly.rustore';
    }

    if (bestProductId != null) {
      final source = purchases
          .where((p) => p.productId == bestProductId)
          .map((p) => p.fromLegacySdk ? 'BillingClient' : 'Pay SDK')
          .first;
      debugPrint(
          '🔵 CONTROLLER: Найдена активная подписка RuStore ($source): $bestProductId');
      switch (bestProductId) {
        case 'aivideomaker.yearly.rustore':
          await subscriptionNotifier.activateYearly();
          break;
        case 'aivideomaker.monthly.rustore':
          await subscriptionNotifier.activateMonthly();
          break;
        case 'aivideomaker.weekly.rustore':
          await subscriptionNotifier.activateWeekly();
          break;
      }
      await subscriptionNotifier.refreshSubscription();
      return true;
    }

    if (pausedSubs.isNotEmpty || terminatedSubs.isNotEmpty) {
      debugPrint(
          '🔵 CONTROLLER: Обнаружена PAUSED/TERMINATED подписка — переводим на free, блокируем триал');
      await subscriptionNotifier.activateFree();
      await TrialServerService().claimTrial();
      return false;
    }

    return false;
  }

  /// Верификация активных подписок RuStore на сервере.
  ///
  /// Кредиты подписки начисляются на сервере (device_registry.currentBalance)
  /// идемпотентно по purchaseId. Это закрывает баг, из-за которого кредиты
  /// подписки существовали только локально и обнулялись при первой генерации,
  /// и ретроактивно чинит уже купивших подписку пользователей: при запуске
  /// обновлённого приложения их активная подписка повторно верифицируется и
  /// кредиты доначисляются на сервер.
  Future<void> _reconcileRustoreSubscriptions(
    RuStoreBillingService ruStoreService,
  ) async {
    try {
      final purchases = await ruStoreService.getPurchases(includeLegacy: true);

      // Dual-SDK: подписки из legacy BillingClient не имеют invoiceId и
      // верифицируются отдельным серверным action'ом (без Pay-инвойса).
      final legacyActiveSubscriptions = purchases.where((purchase) =>
          purchase.fromLegacySdk &&
          purchase.productType == 'SUBSCRIPTION' &&
          (purchase.isActiveSubscription || purchase.isPausedSubscription) &&
          purchase.purchaseId.isNotEmpty &&
          purchase.productId.isNotEmpty);
      for (final purchase in legacyActiveSubscriptions) {
        try {
          final linked = await RustorePurchaseVerificationService.instance
              .linkLegacySubscription(
            purchaseId: purchase.purchaseId,
            productId: purchase.productId,
            invoiceId: purchase.invoiceId,
            purchaseState: purchase.purchaseState,
            expirationDate: purchase.expirationDate,
          );
          debugPrint(
              '🔵 CONTROLLER: link_legacy_subscription ${purchase.productId} -> $linked');
        } catch (e) {
          debugPrint('🔴 CONTROLLER: Ошибка link_legacy_subscription: $e');
        }
      }

      final reconcileInput = purchases
          .where((purchase) =>
              !purchase.fromLegacySdk &&
              purchase.productType == 'SUBSCRIPTION' &&
              (purchase.purchaseState == 'CONFIRMED' ||
                  purchase.purchaseState == 'PAID') &&
              purchase.purchaseId.isNotEmpty &&
              (purchase.invoiceId?.isNotEmpty ?? false) &&
              purchase.productId.isNotEmpty)
          .map(
            (purchase) => RustorePendingPurchase(
              purchaseId: purchase.purchaseId,
              invoiceId: purchase.invoiceId!,
              productId: purchase.productId,
              orderId: purchase.orderId,
            ),
          )
          .toList();

      if (reconcileInput.isEmpty) {
        debugPrint(
            '🔵 CONTROLLER: Активных Pay-подписок RuStore для верификации нет');
        await _ref.read(creditServiceProvider).refreshFromServer();
        _ref.invalidate(creditUsageNotifierProvider);
        return;
      }

      final reconcileResult =
          await RustorePurchaseVerificationService.instance.reconcilePurchases(
        reconcileInput,
      );
      if (!reconcileResult.success) {
        debugPrint('🔴 CONTROLLER: Reconcile подписок RuStore без success');
        return;
      }

      final granted = reconcileResult.items.where((item) => item.success).length;
      debugPrint(
          '🔵 CONTROLLER: Подписки RuStore верифицированы на сервере: $granted');

      // Подтягиваем актуальный серверный баланс в локальную модель.
      await _ref.read(creditServiceProvider).refreshFromServer();
      _ref.invalidate(creditUsageNotifierProvider);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } catch (e) {
      debugPrint('🔴 CONTROLLER: Ошибка reconcile подписок RuStore: $e');
    }
  }

  /// Публичная обёртка для верификации подписок RuStore сразу после покупки.
  Future<void> reconcileRustoreSubscriptions(
    RuStoreBillingService ruStoreService,
  ) =>
      _reconcileRustoreSubscriptions(ruStoreService);

  /// Инициализация сервиса покупок
  Future<void> initialize() async {
    debugPrint('🔵 CONTROLLER: Инициализация сервиса покупок');
    final purchaseService = _ref.read(purchaseServiceProvider);
    try {
      await purchaseService.initialize();
      debugPrint('🔵 CONTROLLER: Сервис покупок инициализирован успешно');
    } catch (e) {
      debugPrint('🔴 CONTROLLER: Ошибка инициализации сервиса покупок: $e');
      rethrow;
    }
  }

  /// Покупка выбранного продукта
  Future<void> purchaseSelectedProduct() async {
    debugPrint('🔵 CONTROLLER: Покупка выбранного продукта');
    final purchaseService = _ref.read(purchaseServiceProvider);
    final selectedProduct = _ref.read(selectedProductProvider);

    if (selectedProduct == null) {
      debugPrint('🔴 CONTROLLER: Продукт не выбран');
      final localizationService = _ref.read(appLocalizationServiceProvider);
      throw Exception(localizationService.translate('product_not_selected'));
    }

    debugPrint('🔵 CONTROLLER: Покупка продукта: ${selectedProduct.id}');
    await purchaseService.buyProduct(selectedProduct.productDetails);
  }

  /// Покупка конкретного продукта
  Future<void> purchaseProduct(ProductModel product) async {
    final purchaseService = _ref.read(purchaseServiceProvider);

    debugPrint('🔵 CONTROLLER: Начинаем покупку продукта в PurchaseController');
    debugPrint('🔵 CONTROLLER: Покупаем продукт: ${product.id}');

    // Подробная информация о продукте для отладки
    debugPrint('🔵 CONTROLLER: Информация о продукте:');
    debugPrint('🔵 CONTROLLER: - ID: ${product.id}');
    debugPrint('🔵 CONTROLLER: - Название: ${product.title}');
    debugPrint('🔵 CONTROLLER: - Цена: ${product.price}');
    debugPrint('🔵 CONTROLLER: - Тип подписки: ${product.subscriptionType}');
    debugPrint(
        '🔵 CONTROLLER: - Платформа: ${Platform.isIOS ? "iOS" : "Android"}');

    try {
      debugPrint('🔵 CONTROLLER: Вызываем метод buyProduct у purchaseService');
      await purchaseService.buyProduct(product.productDetails);
      debugPrint('🔵 CONTROLLER: Запрос на покупку успешно инициирован');
    } catch (e) {
      debugPrint('🔴 CONTROLLER: Ошибка при инициировании покупки: $e');
      rethrow;
    }
  }

  /// Восстановление покупок
  Future<void> restorePurchases() async {
    debugPrint('🔵 CONTROLLER: Восстановление покупок');
    final purchaseService = _ref.read(purchaseServiceProvider);
    try {
      await purchaseService.restorePurchases();
      debugPrint('🔵 CONTROLLER: Запрос на восстановление покупок отправлен');
    } catch (e) {
      debugPrint('🔴 CONTROLLER: Ошибка восстановления покупок: $e');
      rethrow;
    }
  }

  /// Обновление подписки после успешной покупки
  Future<void> updateSubscriptionFromPurchase(PurchaseDetails purchase) async {
    debugPrint(
        '🔵 CONTROLLER: Обновляем подписку из покупки: ${purchase.productID}, статус: ${purchase.status}');

    final subscriptionType =
        ProductModel.getSubscriptionTypeFromProductId(purchase.productID);

    debugPrint(
        '🔵 CONTROLLER: Определен тип подписки: ${subscriptionType.toString()}');

    // Активируем соответствующую подписку через подписочный провайдер
    final subscriptionNotifier = _ref.read(subscriptionProvider.notifier);

    switch (subscriptionType) {
      case SubscriptionType.weekly:
        debugPrint('🔵 CONTROLLER: Активируем недельную подписку');
        await subscriptionNotifier.activateWeekly();
        break;
      case SubscriptionType.monthly:
        debugPrint('🔵 CONTROLLER: Активируем месячную подписку');
        await subscriptionNotifier.activateMonthly();
        break;
      case SubscriptionType.yearly:
        debugPrint('🔵 CONTROLLER: Активируем годовую подписку');
        await subscriptionNotifier.activateYearly();
        break;
      default:
        debugPrint('🔵 CONTROLLER: Неизвестный тип подписки, не активируем');
        // Для всех остальных случаев не делаем ничего
        break;
    }

    // После активации подписки обновляем состояние
    await subscriptionNotifier.refreshSubscription();

    debugPrint('🔵 CONTROLLER: Подписка успешно обновлена');
  }
}
