import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
// import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'subscription_providers.dart';
import 'purchase_providers.dart';
import 'yookassa_payment_sheet.dart' as payment_sheet;
import '../../models/product_model.dart';
import '../../models/subscription_model.dart';
import '../../services/purchase_service.dart';
import '../../services/payment_providers.dart';
// import '../../widgets/loading/loading_screen.dart';
import '../../widgets/loading/loading_manager.dart';
import '../../services/localization/app_localization_service.dart'; // Добавляем импорт сервиса локализации
import '../../models/rustore_purchase_info.dart';
import '../../providers/token_providers.dart' as token_providers;
import '../../providers/credit_providers.dart';
import '../../services/credit_service.dart';
import '../../config/credit_config.dart';
import '../../services/android_system_ui_controller.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import 'dart:io';
import '../../services/yookassa_payment_service.dart' as service_yookassa;
import '../../services/rustore_pricing.dart';
// import '../../services/rustore_billing_service.dart';
import 'package:flutter/foundation.dart';
import '../../utils/app_logger.dart';
import '../../services/paywall_preloader_service.dart';
import '../../services/subscription/subscription_storage_service.dart';
import '../../services/rustore_purchase_verification_service.dart';
import '../../services/analytics/mytracker_analytics_service.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../photosession/theme/photosession_palette.dart';

/// Провайдер для хранения процента скидки
final discountPercentProvider = StateProvider<int>((ref) => 50);

/// Экран Paywall для отображения платных подписок
class PaywallScreen extends ConsumerStatefulWidget {
  /// Функция, вызываемая при закрытии экрана
  final VoidCallback? onClose;

  const PaywallScreen({
    super.key,
    this.onClose,
  });

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen>
    with WidgetsBindingObserver {
  /// Выбранный план подписки (по умолчанию - пробный)
  int _selectedPlanIndex = 0;

  /// Флаг загрузки при покупке
  bool _isPurchasing = false;

  /// Флаг для показа полноэкранного индикатора загрузки
  bool _showLoadingOverlay = false;

  /// Группа авторазмера для ссылок внизу, чтобы шрифт совпадал
  final AutoSizeGroup _bottomLinksGroup = AutoSizeGroup();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidSystemUiController.showNavigationBar();
    _initializePurchases();
    debugPrint('🟢 PAYWALL: Экран подписки инициализирован');
    unawaited(MyTrackerAnalyticsService.instance.trackPaywallOpened());

    // Логируем начальное значение провайдера скидки
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initialDiscount = ref.read(discountPercentProvider);
      debugPrint(
          '🔍 PAYWALL: Начальное значение провайдера скидки: $initialDiscount%');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AndroidSystemUiController.hideNavigationBar();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && _isPurchasing) {
      unawaited(_recoverPendingPurchaseState());
    }
  }

  Future<void> _recoverPendingPurchaseState() async {
    final overlayNotifier = ref.read(creditBalanceOverlayProvider.notifier);
    overlayNotifier.show();
    try {
      debugPrint('🟢 PAYWALL: resume во время покупки — проверяем статус');

      final purchaseController = ref.read(purchaseControllerProvider);
      final synced = await purchaseController.syncSubscriptionStatus();
      if (!mounted) return;

      if (synced) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        _setLoadingOverlay(false);
        setState(() {
          _isPurchasing = false;
        });
        if (widget.onClose != null) {
          widget.onClose!();
        } else {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/home',
            (route) => false,
            arguments: {'subscription_activated': true},
          );
        }
        return;
      }

      final paymentProviderType =
          await ref.read(paymentProviderTypeProvider.future);
      if (!mounted) return;

      if (paymentProviderType == PaymentProvider.yookassa) {
        final paymentHandler = ref.read(paymentResultHandlerProvider);
        final lastPaymentId = await paymentHandler.getLastPaymentId();
        if (lastPaymentId != null && lastPaymentId.isNotEmpty) {
          final yookassaService = service_yookassa.YooKassaPaymentService();
          await yookassaService.initialize();
          final success =
              await yookassaService.checkPaymentStatus(lastPaymentId);
          if (!mounted) return;

          if (success) {
            await purchaseController.syncSubscriptionStatus();
            if (!mounted) return;
            await Future<void>.delayed(const Duration(milliseconds: 250));
            _setLoadingOverlay(false);
            setState(() {
              _isPurchasing = false;
            });
            if (widget.onClose != null) {
              widget.onClose!();
            } else {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/home',
                (route) => false,
                arguments: {'subscription_activated': true},
              );
            }
            return;
          }
        }
      }

      _setLoadingOverlay(false);
      setState(() {
        _isPurchasing = false;
      });
    } catch (e) {
      debugPrint('🔴 PAYWALL: Ошибка восстановления состояния покупки: $e');
      _setLoadingOverlay(false);
      if (!mounted) return;
      setState(() {
        _isPurchasing = false;
      });
    } finally {
      overlayNotifier.hide();
    }
  }

  /// Инициализация покупок
  Future<void> _initializePurchases() async {
    debugPrint('🟢 PAYWALL: Инициализация сервиса покупок');
    final purchaseController = ref.read(purchaseControllerProvider);
    try {
      await purchaseController.initialize();
      debugPrint('🟢 PAYWALL: Сервис покупок инициализирован успешно');

      // Проверим доступность продуктов
      final productsAsyncValue = ref.read(productsProvider);
      if (productsAsyncValue.hasValue) {
        debugPrint(
            '🟢 PAYWALL: Найдено ${productsAsyncValue.value!.length} продуктов:');
        for (var product in productsAsyncValue.value!) {
          debugPrint(
              '🟢 PAYWALL: - ${product.id}: ${product.title}, ${product.price}');
        }
      } else if (productsAsyncValue.hasError) {
        debugPrint(
            '🔴 PAYWALL: Ошибка получения продуктов: ${productsAsyncValue.error}');
      } else {
        debugPrint('🟡 PAYWALL: Загрузка продуктов...');
      }
    } catch (e) {
      debugPrint('🔴 PAYWALL: Ошибка инициализации сервиса покупок: $e');
    }
  }

  /// Метод для расчета и обновления процента скидки
  Future<void> _calculateAndUpdateDiscount(List<ProductModel> products) async {
    debugPrint(
        '🔍 PAYWALL: Вызван метод _calculateAndUpdateDiscount с ${products.length} продуктами');

    if (products.isEmpty) {
      debugPrint('🟡 PAYWALL: Нет продуктов для расчета скидки');
      return;
    }

    ProductModel? yearlyProduct;
    ProductModel? monthlyProduct;

    // Ищем годовой и месячный продукты с учётом используемого стора
    final paymentProviderType =
        await ref.read(paymentProviderTypeProvider.future);

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
      try {
        double yearlyPrice;
        double monthlyPrice;

        // Определяем тип платежной системы
        final paymentProviderType =
            await ref.read(paymentProviderTypeProvider.future);

        switch (paymentProviderType) {
          case PaymentProvider.rustore:
            debugPrint('🟢 PAYWALL: Пользователь RuStore – цены фиксированы');

            // Фиксированные значения из единого источника
            yearlyPrice = RuStorePricing.yearly;
            monthlyPrice = RuStorePricing.monthly;

            break;

          case PaymentProvider.yookassa:
            debugPrint(
                '🟢 PAYWALL: Российский пользователь Google Play, используем цены ЮКассы');

            // Используем цены из YooKassaPaymentService для российских пользователей
            yearlyPrice = service_yookassa.YooKassaPaymentService
                .getPriceForSubscriptionType(SubscriptionType.yearly);
            monthlyPrice = service_yookassa.YooKassaPaymentService
                .getPriceForSubscriptionType(SubscriptionType.monthly);

            debugPrint(
                '🟢 PAYWALL: Цены ЮКассы - годовая: $yearlyPrice₽, месячная: $monthlyPrice₽');
            break;

          case PaymentProvider.standardIAP:
            // Для других валют используем стандартную логику
            debugPrint(
                '🟢 PAYWALL: Стандартные пользователи, используем цены из App Store/Google Play');
            yearlyPrice = _extractNumericPrice(yearlyProduct.price);
            monthlyPrice = _extractNumericPrice(monthlyProduct.price);
            break;
        }

        final double yearCostByMonthly = monthlyPrice * 12;
        final double discountValue =
            ((yearCostByMonthly - yearlyPrice) / yearCostByMonthly) * 100;
        final int discountPercent = discountValue.round();

        debugPrint('🟢 PAYWALL: Расчет скидки:');
        debugPrint('🟢 PAYWALL: - Годовая цена: $yearlyPrice');
        debugPrint('🟢 PAYWALL: - Месячная цена: $monthlyPrice');
        debugPrint('🟢 PAYWALL: - Стоимость 12 месяцев: $yearCostByMonthly');
        debugPrint(
            '🟢 PAYWALL: - Скидка: ${discountValue.toStringAsFixed(2)}%');
        debugPrint('🟢 PAYWALL: - Округленная скидка: $discountPercent%');

        // Обновляем провайдер с рассчитанным значением
        ref.read(discountPercentProvider.notifier).state = discountPercent;
        debugPrint('🟢 PAYWALL: Провайдер скидки обновлен: $discountPercent%');
      } catch (e) {
        debugPrint('🔴 PAYWALL: Ошибка при расчете скидки: $e');
        // В случае ошибки оставляем значение по умолчанию
        ref.read(discountPercentProvider.notifier).state = 50;
      }
    } else {
      debugPrint('🟡 PAYWALL: Не найдены продукты для расчета скидки');
      debugPrint('🟡 PAYWALL: - Годовой продукт: ${yearlyProduct?.id}');
      debugPrint('🟡 PAYWALL: - Месячный продукт: ${monthlyProduct?.id}');

      // Если продукты не найдены, оставляем значение по умолчанию
      ref.read(discountPercentProvider.notifier).state = 50;
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🟢 PAYWALL: Построение Paywall экрана');
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final shadowColor = theme.shadowColor.withOpacity(isDark ? 0.4 : 0.08);

    // Признак маленького экрана по высоте
    final double screenHeight0 = MediaQuery.of(context).size.height;
    final bool isSmallScreen = screenHeight0 < 700;

    // Отслеживаем покупки
    ref.listen<AsyncValue<List<PurchaseDetails>>>(purchasesProvider,
        (previous, next) {
      debugPrint('🟢 PAYWALL: Получен callback listener для purchasesProvider');
      debugPrint(
          '🟢 PAYWALL: Предыдущее состояние: ${previous?.toString() ?? "null"}');
      debugPrint('🟢 PAYWALL: Новое состояние: ${next.toString()}');

      next.when(
        data: (purchases) {
          debugPrint(
              '🟢 PAYWALL: Получено ${purchases.length} покупок в listener');

          if (purchases.isEmpty) {
            debugPrint('🟢 PAYWALL: Список покупок пуст');
            // Если нет покупок и активен экран загрузки более 10 секунд, скрываем его
            if (_showLoadingOverlay && _isPurchasing) {
              Future.delayed(const Duration(seconds: 10), () {
                if (mounted && _showLoadingOverlay && _isPurchasing) {
                  _setLoadingOverlay(false);
                  setState(() {
                    _isPurchasing = false;
                  });
                  _showMessage(context.tr('unknown_error'), isError: true);
                  debugPrint(
                      '🟡 PAYWALL: Автоматически сбросили экран загрузки из-за отсутствия данных');
                }
              });
            }
            return;
          }

          for (final purchase in purchases) {
            debugPrint(
                '🟢 PAYWALL: Покупка: ${purchase.productID}, статус: ${purchase.status}');

            switch (purchase.status) {
              case PurchaseStatus.pending:
                // Покупка в процессе, и должно отображаться нативное окно
                // Делаем наш экран загрузки полупрозрачным, но НЕ СКРЫВАЕМ его
                debugPrint(
                    '🟢 PAYWALL: Получен статус pending для покупки: ${purchase.productID}');
                // Экран загрузки оставляем видимым, но делаем его более прозрачным
                if (_showLoadingOverlay) {
                  LoadingManager().updateProcessingInfo(
                    context,
                    newText: context.tr('waiting_confirmation'),
                    newProcessingStep: context.tr('confirm_purchase'),
                    newProgressValue: 0.6,
                    animationPath: 'assets/animations/loading.json',
                    backgroundColor: theme.scaffoldBackgroundColor,
                  );
                }
                break;

              case PurchaseStatus.purchased:
              case PurchaseStatus.restored:
                // Скрываем экран загрузки и обрабатываем успешную покупку
                debugPrint(
                    '🟢 PAYWALL: Получен статус успешной покупки: ${purchase.productID}');
                _setLoadingOverlay(false);
                _handleSuccessfulPurchase(purchase);
                break;

              case PurchaseStatus.error:
                // Скрываем экран загрузки и показываем ошибку
                debugPrint(
                    '🔴 PAYWALL: Получен статус ошибки для покупки: ${purchase.productID}, ошибка: ${purchase.error?.message}');
                _setLoadingOverlay(false);
                setState(() {
                  _isPurchasing = false;
                });
                unawaited(
                  MyTrackerAnalyticsService.instance.trackSubscriptionFailed(
                    paymentProvider: 'standard_iap',
                    productId: purchase.productID,
                    error: purchase.error?.message ?? 'purchase_error',
                  ),
                );
                _showErrorMessage(
                    '${context.tr('purchase_failed')}: ${purchase.error?.message ?? context.tr('unknown_error')}');
                break;

              case PurchaseStatus.canceled:
                // Покупка отменена пользователем
                debugPrint(
                    '🟢 PAYWALL: Покупка отменена пользователем: ${purchase.productID}');
                _setLoadingOverlay(false);
                setState(() {
                  _isPurchasing = false;
                });
                unawaited(
                  MyTrackerAnalyticsService.instance.trackSubscriptionCancelled(
                    paymentProvider: 'standard_iap',
                    productId: purchase.productID,
                  ),
                );
                // Убираем отображение сообщения, так как оно показывается в другом месте
                break;
            }
          }
        },
        loading: () {
          debugPrint('🟢 PAYWALL: Состояние покупок: loading');
        },
        error: (error, stack) {
          debugPrint('🔴 PAYWALL: Ошибка в состоянии покупок: $error');
          debugPrint('🔴 PAYWALL: Stack trace: $stack');
          _setLoadingOverlay(false);
          setState(() {
            _isPurchasing = false;
          });
          _showErrorMessage('${context.tr('purchase_failed')}: $error');
        },
      );
    });

    // Проверяем наличие доступных продуктов
    final productsAsyncValue = ref.watch(productsProvider);
    productsAsyncValue.whenData((products) {
      if (products.isNotEmpty && products.length >= 3) {
        debugPrint('🟢 PAYWALL: В билде доступно ${products.length} продуктов');
        debugPrint(
            '🟢 PAYWALL: Недельный: ${products[2].id}, ${products[2].price}');
        debugPrint(
            '🟢 PAYWALL: Месячный: ${products[1].id}, ${products[1].price}');
        debugPrint(
            '🟢 PAYWALL: Годовой: ${products[0].id}, ${products[0].price}');

        // Проверяем, была ли уже выполнена предзагрузка
        final paywallPreloader = ref.read(paywallPreloaderServiceProvider);
        if (paywallPreloader.isInitialized) {
          debugPrint(
              '🎯 PAYWALL: Предзагрузка уже выполнена, пропускаем пересчет скидки');
        } else {
          debugPrint(
              '🎯 PAYWALL: Предзагрузка не выполнена, рассчитываем скидку');
          // Рассчитываем и обновляем скидку асинхронно
          _calculateAndUpdateDiscount(products);
        }
      }
    });

    // Получаем размер экрана для адаптивной верстки

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: theme.scaffoldBackgroundColor,
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: null,
          floatingActionButtonLocation: null,
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Рассчитываем доступное пространство (без доп. переменных)
                // final double screenHeight = constraints.maxHeight;

                return Column(
                  children: [
                    // Заголовок с иконкой фотосессии и кнопкой закрытия
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final screenHeight = MediaQuery.of(context).size.height;
                        final titleFontSize = screenHeight > 700 ? 24.0 : 20.0;
                        final titlePadding = screenHeight > 700 ? 24.0 : 16.0;
                        final verticalPadding =
                            screenHeight > 700 ? 24.0 : 16.0;

                        return Padding(
                          padding: EdgeInsets.only(
                              top: 8.0,
                              bottom: verticalPadding,
                              left: titlePadding,
                              right: titlePadding),
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            colors.primary,
                                            colors.primary.withOpacity(0.7),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Icon(
                                        Icons.auto_awesome_rounded,
                                        color: colors.onPrimary,
                                        size: 28,
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.close,
                                          color:
                                              colors.onSurface.withOpacity(0.4),
                                          size: 24,
                                        ),
                                        onPressed: () {
                                          if (widget.onClose != null) {
                                            widget.onClose!();
                                          } else {
                                            Navigator.of(context).pop();
                                          }
                                        },
                                        padding: const EdgeInsets.all(4.0),
                                        constraints: const BoxConstraints(),
                                        splashRadius: 24.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: screenHeight > 700 ? 12 : 8),
                              Text(
                                context.tr('unlimited_access'),
                                style: TextStyle(
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: colors.onSurface,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Основной контент с планами подписки
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                            top: 8.0, left: 24.0, right: 24.0),
                        child: Builder(builder: (context) {
                          final paymentProviderType = ref
                                  .read(paymentProviderTypeProvider)
                                  .valueOrNull ??
                              PaymentProvider.standardIAP;
                          final isRussianUser = paymentProviderType ==
                                  PaymentProvider.yookassa ||
                              paymentProviderType == PaymentProvider.rustore;
                          final String yearlyTitle =
                              paymentProviderType == PaymentProvider.rustore
                                  ? context.tr('7day_free_trial')
                                  : (isRussianUser
                                      ? context.tr('1_year')
                                      : context.tr('7day_free_trial'));

                          if (isSmallScreen) {
                            // Маленькие экраны: скроллим, высоты карточек — естественные
                            return SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      _buildSubscriptionPlan(
                                        index: 0,
                                        title: yearlyTitle,
                                        subtitle:
                                            context.tr('then_yearly_price'),
                                        isSelected: _selectedPlanIndex == 0,
                                      ),
                                      Positioned(
                                        top: -12,
                                        right: 16,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10.0, vertical: 5.0),
                                          decoration: BoxDecoration(
                                            color: colors.surface,
                                            borderRadius:
                                                BorderRadius.circular(18.0),
                                            boxShadow: [
                                              BoxShadow(
                                                color: shadowColor,
                                                blurRadius: 18,
                                                offset: const Offset(0, 10),
                                              ),
                                            ],
                                          ),
                                          child: Consumer(
                                              builder: (context, ref, _) {
                                            final discountPercent = ref
                                                .watch(discountPercentProvider);
                                            return Text(
                                              context.tr('save_50').replaceAll(
                                                  '50', '$discountPercent'),
                                              style: TextStyle(
                                                color: colors.onSurface,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            );
                                          }),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSubscriptionPlan(
                                    index: 1,
                                    title: context.tr('1_month'),
                                    subtitle:
                                        context.tr('monthly_subscription'),
                                    isSelected: _selectedPlanIndex == 1,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSubscriptionPlan(
                                    index: 2,
                                    title: context.tr('week'),
                                    subtitle: context.tr('weekly_subscription'),
                                    isSelected: _selectedPlanIndex == 2,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildBottomLinksRow(context),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            );
                          } else {
                            // Большие экраны: прежняя раскладка с Flexible
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                // План 1: Годовой
                                Flexible(
                                  flex: 4,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      _buildSubscriptionPlan(
                                        index: 0,
                                        title: yearlyTitle,
                                        subtitle:
                                            context.tr('then_yearly_price'),
                                        isSelected: _selectedPlanIndex == 0,
                                      ),
                                      Positioned(
                                        top: -16,
                                        right: 20,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12.0, vertical: 6.0),
                                          decoration: BoxDecoration(
                                            color: colors.surface,
                                            borderRadius:
                                                BorderRadius.circular(20.0),
                                            boxShadow: [
                                              BoxShadow(
                                                color: shadowColor,
                                                blurRadius: 18,
                                                offset: const Offset(0, 10),
                                              ),
                                            ],
                                          ),
                                          child: Consumer(
                                              builder: (context, ref, _) {
                                            final discountPercent = ref
                                                .watch(discountPercentProvider);
                                            return Text(
                                              context.tr('save_50').replaceAll(
                                                  '50', '$discountPercent'),
                                              style: TextStyle(
                                                color: colors.onSurface,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            );
                                          }),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(flex: 1),
                                Flexible(
                                  flex: 4,
                                  child: _buildSubscriptionPlan(
                                    index: 1,
                                    title: context.tr('1_month'),
                                    subtitle:
                                        context.tr('monthly_subscription'),
                                    isSelected: _selectedPlanIndex == 1,
                                  ),
                                ),
                                const Spacer(flex: 1),
                                Flexible(
                                  flex: 4,
                                  child: _buildSubscriptionPlan(
                                    index: 2,
                                    title: context.tr('week'),
                                    subtitle: context.tr('weekly_subscription'),
                                    isSelected: _selectedPlanIndex == 2,
                                  ),
                                ),
                                const Spacer(flex: 1),
                                _buildBottomLinksRow(context),
                                const SizedBox(height: 8),
                              ],
                            );
                          }
                        }),
                      ),
                    ),

                    // Кнопка подписки всегда внизу
                    SafeArea(
                      top: false,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Адаптивные размеры для кнопки
                          final screenHeight =
                              MediaQuery.of(context).size.height;
                          final buttonPadding =
                              screenHeight > 700 ? 16.0 : 12.0;
                          final buttonFontSize =
                              screenHeight > 700 ? 18.0 : 16.0;

                          return Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                horizontal: 24.0, vertical: buttonPadding),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: colors.primary,
                                    borderRadius: BorderRadius.circular(30.0),
                                    boxShadow: [
                                      BoxShadow(
                                        color: shadowColor,
                                        blurRadius: 18,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(30.0),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: _isPurchasing
                                          ? null
                                          : _startSubscription,
                                      child: SizedBox(
                                        width: double.infinity,
                                        height:
                                            screenHeight > 700 ? 56.0 : 48.0,
                                        child: Center(
                                          child: _isPurchasing
                                              ? SizedBox(
                                                  height: 28,
                                                  width: 28,
                                                  child: Lottie.asset(
                                                    'assets/animations/loading.json',
                                                    fit: BoxFit.contain,
                                                    animate: true,
                                                    repeat: true,
                                                  ),
                                                )
                                              : FutureBuilder<String>(
                                                  future: _getButtonTextAsync(
                                                      context),
                                                  builder: (context, snapshot) {
                                                    return Text(
                                                      snapshot.data ??
                                                          context
                                                              .tr('subscribe'),
                                                      style: TextStyle(
                                                        color: colors.onPrimary,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize:
                                                            buttonFontSize,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    );
                                                  },
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                    height: screenHeight > 700 ? 4.0 : 2.0),
                                Text(
                                  context.tr('easy_to_cancel'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontSize: screenHeight > 700 ? 12.0 : 10.0,
                                    fontWeight: FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // Полноэкранный индикатор загрузки
        if (_showLoadingOverlay)
          Container(), // Пустой контейнер, так как теперь используем LoadingManager
      ],
    );
  }

  /// Создание карточки плана подписки
  Widget _buildSubscriptionPlan({
    required int index,
    required String title,
    required String subtitle,
    required bool isSelected,
  }) {
    // Получаем продукты из стора один раз через переменную в классе
    final productsValue = ref.watch(productsProvider).valueOrNull;

    // Получаем соответствующий ID продукта с учётом используемого стора
    final paymentProviderType =
        ref.read(paymentProviderTypeProvider).valueOrNull ??
            PaymentProvider.standardIAP;

    String productId;

    switch (index) {
      case 0:
        productId = paymentProviderType == PaymentProvider.rustore
            ? StoreProductIds.yearlyRuStore
            : StoreProductIds.yearlyWithTrial;
        break;
      case 1:
        productId = paymentProviderType == PaymentProvider.rustore
            ? StoreProductIds.monthlyRuStore
            : StoreProductIds.monthly;
        break;
      case 2:
        productId = paymentProviderType == PaymentProvider.rustore
            ? StoreProductIds.weeklyRuStore
            : StoreProductIds.weekly;
        break;
      default:
        productId = paymentProviderType == PaymentProvider.rustore
            ? StoreProductIds.yearlyRuStore
            : StoreProductIds.yearlyWithTrial;
    }

    // Находим соответствующий продукт
    ProductModel? currentProduct;
    ProductModel? yearlyProduct;
    ProductModel? monthlyProduct;

    if (productsValue != null && productsValue.isNotEmpty) {
      // Находим все нужные продукты для расчетов
      for (final product in productsValue) {
        if (product.id == StoreProductIds.yearlyWithTrial) {
          yearlyProduct = product;
        } else if (product.id == StoreProductIds.monthly) {
          monthlyProduct = product;
        }

        if (product.id == productId) {
          currentProduct = product;
        }
      }
    }

    // Строим виджет с текстом по умолчанию
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final shadowColor = theme.shadowColor.withOpacity(isDark ? 0.4 : 0.08);
        // Адаптивные размеры в зависимости от доступного пространства
        final double availableHeight = constraints.maxHeight;
        final double screenHeight = MediaQuery.of(context).size.height;

        final double padding = availableHeight > 80 ? 16.0 : 12.0;
        final double titleFontSize = screenHeight > 700 ? 18.0 : 16.0;
        final double subtitleFontSize = screenHeight > 700 ? 14.0 : 12.0;

        final borderRadius = BorderRadius.circular(16.0);
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
            border: isSelected
                ? Border.all(
                    color: colors.primary,
                    width: 1.5,
                  )
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: borderRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedPlanIndex = index;
                });
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: padding, vertical: padding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment
                      .center, // Центрируем элементы по вертикали
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment
                            .start, // Выравниваем по левому краю
                        mainAxisAlignment:
                            MainAxisAlignment.start, // Начинаем сверху
                        children: [
                          // Заголовок с автоматическим масштабированием
                          Flexible(
                            child: AutoSizeText(
                              title,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              minFontSize: 12,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                              height: screenHeight > 700
                                  ? 16.0
                                  : 14.0), // Увеличиваем отступ
                          // Подзаголовок (информация о цене)
                          Flexible(
                            child: _buildSubscriptionPriceText(
                                context,
                                index,
                                subtitle,
                                subtitleFontSize,
                                currentProduct,
                                yearlyProduct,
                                monthlyProduct),
                          ),

                          // Подсказка с количеством доступных запросов к ИИ-Гиду
                          SizedBox(height: screenHeight > 700 ? 10.0 : 8.0),
                          AutoSizeText(
                            _getAiRequestsHintText(context, index),
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: screenHeight > 700 ? 12.0 : 11.0,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            minFontSize: 9,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Иконка выбора
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(
                          right: 4.0), // Добавляем небольшой отступ справа
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? colors.primary
                              : colors.outline.withOpacity(0.7),
                          width: 2,
                        ),
                        color: isSelected ? colors.primary : Colors.transparent,
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              color: colors.onPrimary,
                              size: 16,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Нижние ссылки (Восстановить покупку • Условия использования)
  Widget _buildBottomLinksRow(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final double linkHeight = screenHeight > 700 ? 56.0 : 44.0;
    final double baseFontSize =
        screenHeight > 800 ? 22.0 : (screenHeight > 700 ? 20.0 : 16.0);

    return SizedBox(
      height: linkHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: CupertinoButton(
              padding:
                  const EdgeInsets.symmetric(vertical: 6.0, horizontal: 0.0),
              onPressed: _isPurchasing ? null : _restorePurchases,
              minimumSize: Size(40, 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: AutoSizeText(
                      context.tr('restore_purchase'),
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: baseFontSize,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      minFontSize: 11,
                      maxFontSize: 48,
                      stepGranularity: 0.5,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      group: _bottomLinksGroup,
                    ),
                  ),
                  if (_isPurchasing)
                    Padding(
                      padding: const EdgeInsets.only(left: 6.0),
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: Lottie.asset(
                          'assets/animations/loading.json',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text('•',
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: baseFontSize,
                  fontWeight: FontWeight.w700,
                )),
          ),
          Expanded(
            child: CupertinoButton(
              padding:
                  const EdgeInsets.symmetric(vertical: 6.0, horizontal: 0.0),
              onPressed: () {
                _launchURL(
                    'https://docs.google.com/document/d/1NbFXhPTSAg9uJZs8Krz0DygqcVPaSe-dMN_Q8mNrAHU/edit?usp=sharing');
              },
              minimumSize: Size(40, 40),
              child: AutoSizeText(
                context.tr('terms_of_service'),
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: baseFontSize,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                minFontSize: 11,
                maxFontSize: 48,
                stepGranularity: 0.5,
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
                group: _bottomLinksGroup,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Создает текст с информацией о цене подписки
  Widget _buildSubscriptionPriceText(
      BuildContext context,
      int index,
      String defaultSubtitle,
      double fontSize,
      ProductModel? currentProduct,
      ProductModel? yearlyProduct,
      ProductModel? monthlyProduct) {
    final colors = Theme.of(context).colorScheme;
    // Используем значение, которое уже получено в начале build метода
    final paymentProviderType =
        ref.read(paymentProviderTypeProvider).valueOrNull ??
            PaymentProvider.standardIAP;
    final isRussianUser = paymentProviderType == PaymentProvider.yookassa ||
        paymentProviderType == PaymentProvider.rustore;

    final textStyle = TextStyle(
      color: colors.onSurface,
      fontSize: fontSize,
      height: 1.3,
    );

    // Если нет данных продукта и это не RuStore, показываем дефолтный текст
    if (currentProduct == null &&
        paymentProviderType != PaymentProvider.rustore) {
      return AutoSizeText(
        defaultSubtitle,
        style: textStyle,
        maxLines: 4,
        minFontSize: 10,
        overflow: TextOverflow.ellipsis,
      );
    }

    // В зависимости от типа подписки, формируем соответствующий текст
    String priceText;

    switch (index) {
      case 0: // Годовая подписка
        if (paymentProviderType == PaymentProvider.rustore) {
          // Простая фиксированная строка: год целым числом, месяц с 1 знаком после запятой
          final String currencySymbol = RuStorePricing.currencySymbol;
          final int yearlyInt = RuStorePricing.yearly.round();
          final String monthlyFromYear =
              (RuStorePricing.yearly / 12).toStringAsFixed(1);

          priceText =
              '${context.tr('then')} $currencySymbol$yearlyInt/${context.tr('year')}. ${context.tr('total')} $currencySymbol$monthlyFromYear/${context.tr('month')}.';
        } else if (yearlyProduct != null && monthlyProduct != null) {
          if (isRussianUser) {
            // Для российских пользователей - без упоминания бесплатного периода
            try {
              double yearlyPrice;
              String currencySymbol;

              if (paymentProviderType == PaymentProvider.rustore) {
                // Для RuStore используем фиксированные цены
                yearlyPrice = RuStorePricing.yearly;
                currencySymbol = RuStorePricing.currencySymbol;
              } else {
                // Для пользователей YooKassa используем цены YooKassa
                yearlyPrice = service_yookassa.YooKassaPaymentService
                    .getPriceForSubscriptionType(SubscriptionType.yearly);
                currencySymbol =
                    service_yookassa.YooKassaPaymentService.getCurrencySymbol();
              }

              final monthlyPriceByYearly = yearlyPrice / 12;
              final int roundedMonthlyPrice = monthlyPriceByYearly.round();

              // Форматируем цены
              String yearlyPriceFormatted =
                  '$currencySymbol${yearlyPrice.round()}';
              String monthlyPriceFormatted =
                  '$currencySymbol$roundedMonthlyPrice';

              // Формируем итоговый текст
              priceText =
                  '${context.tr('then')} $yearlyPriceFormatted/${context.tr('year')}. ${context.tr('total')} $monthlyPriceFormatted/${context.tr('month')}.';

              debugPrint(
                  '💰 PAYWALL: Сформирован текст цены для российского пользователя ($paymentProviderType): $priceText');
            } catch (e) {
              debugPrint(
                  '🔴 PAYWALL: Ошибка при формировании цены для российского пользователя: $e');
              priceText = context.tr('yearly_subscription');
            }
          } else {
            // Для остальных пользователей - с бесплатным периодом
            try {
              // Получаем строки с ценами из магазина приложений
              final String yearlyPriceString = yearlyProduct.price;
              final String monthlyPriceString = monthlyProduct.price;

              // Извлекаем числовые значения
              final double yearlyPrice =
                  _extractNumericPrice(yearlyPriceString);

              // Рассчитываем месячную цену на основе годовой (делим на 12)
              final double monthlyPriceByYearly = yearlyPrice / 12;
              final int roundedMonthlyPrice = monthlyPriceByYearly.round();

              // Определяем код валюты из строки цены
              String currencyCode = _extractCurrencyCode(yearlyPriceString);
              debugPrint('💰 PAYWALL: Определен код валюты: $currencyCode');

              // Обрабатываем специальный случай для турецкой лиры
              String formattedYearlyPrice = yearlyPriceString;
              String formattedMonthlyPrice = monthlyPriceString;

              if (yearlyPriceString.contains('T') &&
                  !yearlyPriceString.contains('TRY')) {
                formattedYearlyPrice = yearlyPriceString.replaceAll('T', 'TRY');
              }

              // Заменяем числовые значения в строках цен
              final RegExp numericRegex = RegExp(r'\d+[.,]?\d*');

              // Если есть числовые значения в строках, заменяем их
              if (numericRegex.hasMatch(formattedMonthlyPrice)) {
                formattedMonthlyPrice = formattedMonthlyPrice.replaceFirst(
                    numericRegex, roundedMonthlyPrice.toString());
              } else {
                // Если по какой-то причине не нашли числовое значение,
                // используем простое форматирование
                formattedMonthlyPrice = '$roundedMonthlyPrice $currencyCode';
              }

              // Убеждаемся, что используется полный код валюты
              if (currencyCode == 'TRY' &&
                  !formattedMonthlyPrice.contains('TRY') &&
                  formattedMonthlyPrice.contains('T')) {
                formattedMonthlyPrice =
                    formattedMonthlyPrice.replaceAll('T', 'TRY');
              }
              if (currencyCode == 'TRY' &&
                  !formattedYearlyPrice.contains('TRY') &&
                  formattedYearlyPrice.contains('T')) {
                formattedYearlyPrice =
                    formattedYearlyPrice.replaceAll('T', 'TRY');
              }

              // Формируем итоговый текст
              priceText =
                  '${context.tr('then')} $formattedYearlyPrice/${context.tr('year')}. ${context.tr('total')} $formattedMonthlyPrice/${context.tr('month')}.';

              debugPrint(
                  '💰 PAYWALL: Сформирован текст цены для не-российского пользователя: $priceText');
            } catch (e) {
              debugPrint(
                  '🔴 PAYWALL: Ошибка при формировании цены для не-российского пользователя: $e');
              priceText =
                  '${context.tr('then')} ${yearlyProduct.price}/${context.tr('year')}.';
            }
          }
        } else {
          priceText = defaultSubtitle;
        }
        break;

      case 1: // Месячная подписка
        try {
          if (isRussianUser) {
            // Для российских пользователей используем соответствующий сервис
            double price;
            String currencySymbol;

            if (paymentProviderType == PaymentProvider.rustore) {
              price = RuStorePricing.monthly;
              currencySymbol = RuStorePricing.currencySymbol;
            } else {
              price = service_yookassa.YooKassaPaymentService
                  .getPriceForSubscriptionType(SubscriptionType.monthly);
              currencySymbol =
                  service_yookassa.YooKassaPaymentService.getCurrencySymbol();
            }

            final int priceValue = price.round();

            // Форматируем цену с валютой в начале
            priceText =
                '$currencySymbol$priceValue/${context.tr('month')}. ${context.tr('cancel_anytime')}.';
          } else {
            // Для всех остальных пользователей - просто берем цену из стора и добавляем период
            priceText =
                '${currentProduct?.price ?? ''}/${context.tr('month')}. ${context.tr('cancel_anytime')}.';
          }
        } catch (e) {
          // Fallback вариант
          priceText =
              '${currentProduct?.price ?? ''}/${context.tr('month')}. ${context.tr('cancel_anytime')}.';
        }
        break;

      case 2: // Недельная подписка
        try {
          if (isRussianUser) {
            // Для российских пользователей используем соответствующий сервис
            double price;
            String currencySymbol;

            if (paymentProviderType == PaymentProvider.rustore) {
              price = RuStorePricing.weekly;
              currencySymbol = RuStorePricing.currencySymbol;
            } else {
              price = service_yookassa.YooKassaPaymentService
                  .getPriceForSubscriptionType(SubscriptionType.weekly);
              currencySymbol =
                  service_yookassa.YooKassaPaymentService.getCurrencySymbol();
            }

            final int priceValue = price.round();

            // Форматируем цену с валютой в начале
            priceText = '$currencySymbol$priceValue/${context.tr('week')}.';
          } else {
            // Для всех остальных пользователей - просто берем цену из стора и добавляем период
            priceText = '${currentProduct?.price ?? ''}/${context.tr('week')}.';
          }
        } catch (e) {
          // Fallback вариант
          priceText = '${currentProduct?.price ?? ''}/${context.tr('week')}.';
        }
        break;

      default:
        priceText = defaultSubtitle;
    }

    // Используем AutoSizeText для автоматического масштабирования текста
    return AutoSizeText(
      priceText,
      style: textStyle,
      maxLines: 4,
      minFontSize: 10,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Получение текста для кнопки в зависимости от выбранного плана
  Future<String> _getButtonTextAsync(BuildContext context) async {
    try {
      // Определяем тип платежной системы
      final paymentProviderType =
          await ref.read(paymentProviderTypeProvider.future);
      final isRussianUser = paymentProviderType == PaymentProvider.yookassa ||
          paymentProviderType == PaymentProvider.rustore;

      if (isRussianUser) {
        // Тексты для российских пользователей (YooKassa и RuStore)
        switch (_selectedPlanIndex) {
          case 0: // Годовая
            return paymentProviderType == PaymentProvider.rustore
                ? context.tr('start_free_trial')
                : context.tr('subscribe_yearly');
          case 1: // Месячная
            return context.tr('subscribe_monthly'); // "Подписаться на месяц"
          case 2: // Недельная
            return context.tr('subscribe_weekly'); // "Подписаться на неделю"
          default:
            return context.tr('subscribe');
        }
      } else {
        // Тексты для остальных пользователей (с бесплатным периодом)
        switch (_selectedPlanIndex) {
          case 0: // Годовая с пробным периодом
            return context.tr('start_free_trial');
          case 1: // Месячная без пробного периода
            return context.tr('subscribe_monthly');
          case 2: // Недельная без пробного периода
            return context.tr('subscribe_weekly');
          default:
            return context.tr('subscribe');
        }
      }
    } catch (e) {
      debugPrint('🔴 PAYWALL: Ошибка при получении текста кнопки: $e');
      // Fallback на стандартные тексты
      switch (_selectedPlanIndex) {
        case 0:
          return context.tr('start_free_trial');
        case 1:
          return context.tr('subscribe_monthly');
        case 2:
          return context.tr('subscribe_weekly');
        default:
          return context.tr('subscribe');
      }
    }
  }

  /// Получить соответствующий ID продукта для текущего выбранного индекса
  String _getProductIdForSelectedIndex() {
    switch (_selectedPlanIndex) {
      case 0: // Годовая с пробным периодом
        return StoreProductIds.yearlyWithTrial;
      case 1: // Месячная
        return StoreProductIds.monthly;
      case 2: // Недельная
        return StoreProductIds.weekly;
      default:
        return StoreProductIds.yearlyWithTrial;
    }
  }

  /// Метод для активации подписки через ЮКассу (для российских пользователей)
  Future<void> _startYookassaSubscription() async {
    debugPrint('🟢 PAYWALL: Начинаем процесс подписки через ЮКассу');

    try {
      // Определяем тип подписки на основе выбранного плана
      SubscriptionType subscriptionType;
      switch (_selectedPlanIndex) {
        case 0: // Годовая с пробным периодом
          subscriptionType = SubscriptionType.yearly;
          break;
        case 1: // Месячная
          subscriptionType = SubscriptionType.monthly;
          break;
        case 2: // Недельная
          subscriptionType = SubscriptionType.weekly;
          break;
        default:
          subscriptionType = SubscriptionType.yearly;
      }

      debugPrint('🟢 PAYWALL: Выбран тип подписки ЮКассы: $subscriptionType');

      // НЕ показываем экран загрузки здесь - YooKassaPaymentService сам управляет индикаторами

      // Вызываем функцию оплаты через ЮКассу
      await payment_sheet.YooKassaPaymentService.startPayment(
        context: context,
        ref: ref,
        subscriptionType: subscriptionType,
        onSuccess: (type) {
          debugPrint('🟢 PAYWALL: Успешная оплата через ЮКассу: $type');
          unawaited(
            MyTrackerAnalyticsService.instance.trackSubscriptionPurchase(
              plan: type,
              paymentProvider: 'yookassa',
            ),
          );

          // Закрываем экран paywall
          if (widget.onClose != null) {
            widget.onClose!();
          } else {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/home',
              (route) => false,
              arguments: {'subscription_activated': true},
            );
          }
        },
        onCancel: () {
          debugPrint('🟡 PAYWALL: Оплата через ЮКассу отменена');
          unawaited(
            MyTrackerAnalyticsService.instance.trackSubscriptionCancelled(
              paymentProvider: 'yookassa',
            ),
          );
          setState(() {
            _isPurchasing = false;
          });
        },
      );
    } catch (e) {
      debugPrint('🔴 PAYWALL: Ошибка при оплате через ЮКассу: $e');
      unawaited(
        MyTrackerAnalyticsService.instance.trackSubscriptionFailed(
          paymentProvider: 'yookassa',
          error: e.toString(),
        ),
      );
      _showErrorMessage('${context.tr('purchase_failed')}: $e');
      setState(() {
        _isPurchasing = false;
      });
    }
  }

  /// Метод для активации подписки через RuStore (для пользователей RuStore)
  Future<void> _startRuStoreSubscription() async {
    debugPrint('🟢 PAYWALL: Начинаем процесс подписки через RuStore');
    AppLogger.log('🛒 RUSTORE_BILLING: Инициализация покупки через RuStore');
    final overlayNotifier = ref.read(creditBalanceOverlayProvider.notifier);
    overlayNotifier.show();

    try {
      // Определяем продукт RuStore на основе выбранного плана
      String productId;
      switch (_selectedPlanIndex) {
        case 0: // Годовая
          productId = 'aivideomaker.yearly.rustore';
          break;
        case 1: // Месячная
          productId = 'aivideomaker.monthly.rustore';
          break;
        case 2: // Недельная
          productId = 'aivideomaker.weekly.rustore';
          break;
        default:
          productId = 'aivideomaker.yearly.rustore';
      }

      debugPrint('🟢 PAYWALL: Выбран продукт RuStore: $productId');

      // Инициализируем RuStore сервис через провайдер (переиспользуем экземпляр)
      final ruStoreService = ref.read(rustoreBillingServiceProvider);
      final isInitialized = await ruStoreService.initialize();

      if (!isInitialized) {
        throw Exception(context.tr('rustore_sdk_init_failed'));
      }

      // Показываем экран загрузки
      _setLoadingOverlay(true);

      final success = await ruStoreService.purchaseProduct(productId);

      if (success) {
        debugPrint('🟢 PAYWALL: Успешная оплата через RuStore: $productId');

        // Обновляем локальную информацию о подписке, чтобы скрыть баннер на главном экране
        try {
          final subscriptionNotifier = ref.read(subscriptionProvider.notifier);
          SubscriptionType subType;
          switch (_selectedPlanIndex) {
            case 0:
              await subscriptionNotifier.activateYearly();
              subType = SubscriptionType.yearly;
              unawaited(
                MyTrackerAnalyticsService.instance.trackTrialStarted(
                  paymentProvider: 'rustore',
                  productId: productId,
                ),
              );
              break;
            case 1:
              await subscriptionNotifier.activateMonthly();
              subType = SubscriptionType.monthly;
              break;
            case 2:
              await subscriptionNotifier.activateWeekly();
              subType = SubscriptionType.weekly;
              break;
            default:
              await subscriptionNotifier.activateWeekly();
              subType = SubscriptionType.weekly;
          }
          unawaited(
            MyTrackerAnalyticsService.instance.trackSubscriptionPurchase(
              plan: subType,
              paymentProvider: 'rustore',
              productId: productId,
            ),
          );
          // Доход в MyTracker отправляется на сервере (verify-rustore-purchase)
          // по фактической сумме платежа и идемпотентно по purchaseId — здесь
          // выручку не дублируем. На клиенте остаётся только событие воронки
          // trackSubscriptionPurchase выше.
          await CreditService().activateSubscription(subType);
          ref.invalidate(creditUsageNotifierProvider);
          await Future<void>.delayed(const Duration(milliseconds: 250));

          // Верифицируем подписку на сервере: кредиты подписки должны попасть
          // в серверный баланс (device_registry.currentBalance) — иначе при
          // первой генерации локальные кредиты затрутся серверным балансом.
          try {
            final purchaseController = ref.read(purchaseControllerProvider);
            await purchaseController
                .reconcileRustoreSubscriptions(ruStoreService);
          } catch (e) {
            debugPrint(
                '🔴 PAYWALL: Не удалось верифицировать подписку на сервере: $e');
          }
        } catch (e) {
          debugPrint('🔴 PAYWALL: Не удалось обновить локальную подписку: $e');
        }

        _setLoadingOverlay(false);
        if (mounted) {
          setState(() => _isPurchasing = false);
        }

        if (!mounted) {
          return;
        }
        if (widget.onClose != null) {
          widget.onClose!();
        } else {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/home',
            (route) => false,
            arguments: {'subscription_activated': true},
          );
        }
      } else {
        throw Exception(context.tr('rustore_purchase_failed'));
      }
    } catch (e) {
      debugPrint('🔴 PAYWALL: Ошибка при оплате через RuStore: $e');
      AppLogger.log('🔴 PAYWALL: ❌ Ошибка RuStore: $e', level: LogLevel.error);
      unawaited(
        MyTrackerAnalyticsService.instance.trackSubscriptionFailed(
          paymentProvider: 'rustore',
          error: e.toString(),
        ),
      );

      // Скрываем экран загрузки
      _setLoadingOverlay(false);

      _showErrorMessage('${context.tr('purchase_failed')}: $e');
      setState(() {
        _isPurchasing = false;
      });
    } finally {
      overlayNotifier.hide();
    }
  }

  /// Метод для активации подписки в зависимости от выбранного плана
  Future<void> _activateDebugSubscription() async {
    final creditService = CreditService();
    SubscriptionType subType;
    switch (_selectedPlanIndex) {
      case 0:
        try {
          await ref.read(subscriptionProvider.notifier).activateTrial();
        } on TrialAlreadyUsedException catch (e) {
          debugPrint('🔴 PAYWALL: Триал уже использован: $e');
          if (mounted) {
            setState(() => _isPurchasing = false);
            _showErrorMessage(
              'Вы уже использовали бесплатный период на этом устройстве. '
              'Выберите подходящий план подписки.',
            );
          }
          return;
        }
        subType = SubscriptionType.trial;
        unawaited(
          MyTrackerAnalyticsService.instance.trackTrialStarted(
            paymentProvider: 'debug',
          ),
        );
        break;
      case 1:
        await ref.read(subscriptionProvider.notifier).activateMonthly();
        subType = SubscriptionType.monthly;
        break;
      case 2:
        await ref.read(subscriptionProvider.notifier).activateWeekly();
        subType = SubscriptionType.weekly;
        break;
      default:
        await ref.read(subscriptionProvider.notifier).activateWeekly();
        subType = SubscriptionType.weekly;
    }
    await creditService.activateSubscription(subType);
    await creditService.refreshFromServer();
    ref.invalidate(creditUsageNotifierProvider);
    if (subType != SubscriptionType.trial) {
      unawaited(
        MyTrackerAnalyticsService.instance.trackSubscriptionPurchase(
          plan: subType,
          paymentProvider: 'debug',
        ),
      );
    }

    debugPrint('🟢 PAYWALL: Debug-подписка ${subType.name} активирована');

    if (mounted) {
      setState(() => _isPurchasing = false);
      if (widget.onClose != null) {
        widget.onClose!();
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/home',
          (route) => false,
          arguments: {'subscription_activated': true},
        );
      }
    }
  }

  Future<void> _startSubscription() async {
    debugPrint('🟢 PAYWALL: Начинаем процесс подписки');
    try {
      setState(() {
        _isPurchasing = true;
      });
      debugPrint('🟢 PAYWALL: Статус покупки: _isPurchasing = true');

      if (kDebugMode) {
        final selectedPlan = _getSelectedSubscriptionType();
        unawaited(
          MyTrackerAnalyticsService.instance.trackSubscriptionStart(
            plan: selectedPlan,
            paymentProvider: 'debug',
          ),
        );
      }

      // Debug-обход: активируем подписку локально без реальной покупки
      if (kDebugMode) {
        debugPrint('🟡 PAYWALL: Debug-режим — активация без покупки');
        await _activateDebugSubscription();
        return;
      }

      // Определяем тип платежной системы
      try {
        final paymentProviderType =
            await ref.read(paymentProviderTypeProvider.future);
        final selectedPlan = _getSelectedSubscriptionType();
        unawaited(
          MyTrackerAnalyticsService.instance.trackSubscriptionStart(
            plan: selectedPlan,
            paymentProvider: _paymentProviderName(paymentProviderType),
          ),
        );

        switch (paymentProviderType) {
          case PaymentProvider.rustore:
            debugPrint(
                '🟢 PAYWALL: Пользователь RuStore - используем RuStore биллинг');
            AppLogger.log(
                '🛒 PAYWALL: Запуск покупки через RuStore для пользователей RuStore');
            try {
              await _startRuStoreSubscription();
              return; // Важно: выходим из функции после успешного запуска RuStore
            } catch (ruStoreError) {
              AppLogger.log(
                  '🔴 PAYWALL: ❌ Ошибка при покупке через RuStore: $ruStoreError',
                  level: LogLevel.error);
              _showErrorMessage(
                  '${context.tr('purchase_failed')}: $ruStoreError');
              return; // Важно: НЕ переходим к стандартным платежам для RuStore пользователей
            }

          case PaymentProvider.yookassa:
            debugPrint(
                '🟢 PAYWALL: Российский пользователь Google Play - используем ЮКассу');
            AppLogger.log(
                '�� PAYWALL: Запуск покупки через YooKassa для российских пользователей Google Play');
            try {
              final yookassaService = service_yookassa.YooKassaPaymentService();
              await yookassaService.initialize();
              await _startYookassaSubscription();
              return; // Важно: выходим из функции после успешного запуска YooKassa
            } catch (yookassaError) {
              AppLogger.log(
                  '🔴 PAYWALL: ❌ Ошибка при покупке через YooKassa: $yookassaError',
                  level: LogLevel.error);
              debugPrint(
                  '🟡 PAYWALL: Используем стандартные платежи как запасной вариант для YooKassa');
              // Для YooKassa разрешаем fallback к стандартным платежам
            }
            break;

          case PaymentProvider.standardIAP:
            if (Platform.isIOS) {
              debugPrint(
                  '🟢 PAYWALL: iOS - всегда используем стандартные платежи');
            } else {
              debugPrint(
                  '🟢 PAYWALL: Стандартные пользователи - используем стандартные платежи');
            }
            break;
        }
      } catch (providerError) {
        // Если возникла ошибка при определении способа оплаты,
        // логируем и используем стандартные платежи
        debugPrint(
            '🔴 PAYWALL: Ошибка при определении способа оплаты: $providerError');
        debugPrint(
            '🟡 PAYWALL: Используем стандартные платежи как запасной вариант');
      }

      final purchaseController = ref.read(purchaseControllerProvider);

      // Получаем все продукты
      final productsAsyncValue = ref.read(productsProvider);
      final products = productsAsyncValue.asData?.value ?? [];
      debugPrint('🟢 PAYWALL: Доступных продуктов: ${products.length}');

      // Находим нужный продукт по ID
      final String productId = _getProductIdForSelectedIndex();
      debugPrint('🟢 PAYWALL: Выбран продукт с ID: $productId');

      final ProductModel? productToBuy = products.isNotEmpty
          ? products.firstWhere((p) => p.id == productId,
              orElse: () => products.first)
          : null;

      if (productToBuy != null) {
        debugPrint(
            '🟢 PAYWALL: Продукт найден: ${productToBuy.id}, ${productToBuy.title}, ${productToBuy.price}');

        // Показываем экран загрузки перед началом процесса покупки
        debugPrint('🟢 PAYWALL: Показываем экран загрузки');
        _setLoadingOverlay(true);

        // Небольшая задержка для гарантированного показа экрана загрузки
        await Future.delayed(const Duration(milliseconds: 300));

        // Вызываем метод покупки
        debugPrint('🟢 PAYWALL: Вызываем метод покупки');
        try {
          // Создаем таймер, который сбросит состояние, если процесс зависнет
          Timer? timeoutTimer = Timer(const Duration(seconds: 20), () {
            debugPrint('🔴 PAYWALL: Таймаут процесса покупки');
            if (mounted) {
              _setLoadingOverlay(false);
              _showErrorMessage(context.tr('timeout_error'));
              setState(() {
                _isPurchasing = false;
              });
            }
          });

          // Инициируем процесс покупки
          await purchaseController.purchaseProduct(productToBuy);
          debugPrint(
              '🟢 PAYWALL: Метод покупки выполнен успешно, ожидаем нативное окно');

          // Отменяем таймер, если процесс начался нормально
          timeoutTimer.cancel();

          // Обновляем информацию на экране загрузки
          if (_showLoadingOverlay) {
            LoadingManager().updateProcessingInfo(
              context,
              newText: context.tr('waiting_confirmation'),
              newProcessingStep: context.tr('confirm_purchase'),
              newProgressValue: 0.6,
              animationPath: 'assets/animations/loading.json',
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            );
          }

          // Дальнейшая обработка через listener purchasesProvider в build методе
        } catch (e) {
          debugPrint('🔴 PAYWALL: Ошибка при вызове purchaseProduct: $e');
          _setLoadingOverlay(false);
          _showErrorMessage('${context.tr('purchase_failed')}: $e');
        }
      } else {
        debugPrint('🟡 PAYWALL: Продукт не найден, используем тестовую логику');
        await _activateDebugSubscription();
      }
    } catch (e) {
      debugPrint('🔴 PAYWALL: Ошибка в _startSubscription: $e');
      unawaited(
        MyTrackerAnalyticsService.instance.trackSubscriptionFailed(
          paymentProvider: 'paywall',
          error: e.toString(),
        ),
      );
      _showErrorMessage('${context.tr('purchase_failed')}: $e');
      // Скрываем экран загрузки в случае ошибки
      _setLoadingOverlay(false);
    } finally {
      if (mounted) {
        setState(() {
          _isPurchasing = false;
          debugPrint(
              '🟢 PAYWALL: Статус покупки сброшен: _isPurchasing = false');
        });
      }
    }
  }

  /// Восстановление покупок с поддержкой RuStore
  Future<void> _restorePurchases() async {
    try {
      setState(() {
        _isPurchasing = true;
      });

      // Показываем экран загрузки
      _setLoadingOverlay(true);

      // Создаем таймер, который сбросит состояние, если процесс зависнет
      Timer? timeoutTimer = Timer(const Duration(seconds: 20), () {
        debugPrint('🔴 PAYWALL: Таймаут процесса восстановления покупок');
        if (mounted) {
          _setLoadingOverlay(false);
          _showErrorMessage(context.tr('timeout_error'));
          setState(() {
            _isPurchasing = false;
          });
        }
      });

      // Определяем провайдера платежей
      final paymentProviderType =
          await ref.read(paymentProviderTypeProvider.future);

      bool restoredSuccessfully = false;
      List<dynamic> restoredPurchases = [];

      switch (paymentProviderType) {
        case PaymentProvider.rustore:
          // Восстановление через RuStore
          debugPrint('🔄 PAYWALL: Восстановление покупок через RuStore');
          final ruStoreService = ref.read(rustoreBillingServiceProvider);
          final initialized = await ruStoreService.initialize();

          if (initialized) {
            final purchases = await ruStoreService.restorePurchases();
            restoredPurchases = purchases;
            restoredSuccessfully = purchases.isNotEmpty;

            if (restoredSuccessfully) {
              debugPrint(
                  '🟢 PAYWALL: Найдено ${purchases.length} активных покупок RuStore');

              // Обновляем локальную подписку на основе найденных покупок
              final subscriptionNotifier =
                  ref.read(subscriptionProvider.notifier);

              // Обрабатываем найденные покупки
              await _processRestoredRuStorePurchases(
                  purchases, subscriptionNotifier);
            }
          } else {
            debugPrint(
                '🔴 PAYWALL: Не удалось инициализировать RuStore для восстановления');
          }
          break;

        case PaymentProvider.yookassa:
          // Восстановление через YooKassa (подписки и токены)
          debugPrint('🔄 PAYWALL: ${context.tr('restore_tokens_yookassa')}');

          // 1) Пытаемся восстановить подписку из локального хранилища ЮKassa
          final storageService = SubscriptionStorageService();
          final isActive = await storageService.isSubscriptionActive();
          if (isActive) {
            final info = await storageService.getSubscription();
            if (info != null) {
              final subscriptionNotifier =
                  ref.read(subscriptionProvider.notifier);
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
              restoredSuccessfully = true;
            }
          } else {
            // 2) Если локально нет активной — пробуем проверить последний платеж у ЮKassa
            final paymentHandler = ref.read(paymentResultHandlerProvider);
            final lastPaymentId = await paymentHandler.getLastPaymentId();
            if (lastPaymentId != null && lastPaymentId.isNotEmpty) {
              final yookassaService = service_yookassa.YooKassaPaymentService();
              final ok =
                  await yookassaService.checkPaymentStatus(lastPaymentId);
              if (ok) {
                // После успешной проверки PaymentResultHandler сохранит подписку,
                // поэтому перечитаем и активируем
                final updated = await storageService.getSubscription();
                if (updated != null) {
                  final subscriptionNotifier =
                      ref.read(subscriptionProvider.notifier);
                  switch (updated.type) {
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
                  restoredSuccessfully = true;
                }
              }
            }
          }

          // 3) Всегда пробуем восстановить токены YooKassa
          try {
            final yookassaTokenService = ref.read(yookassaTokenServiceProvider);
            final yookassaTokenPurchases =
                await yookassaTokenService.restoreTokenPurchases();
            if (yookassaTokenPurchases.isNotEmpty) {
              int totalTokens = 0;
              for (final purchase in yookassaTokenPurchases) {
                totalTokens += purchase.tokenCount;
              }
              if (totalTokens > 0) {
                await ref
                    .read(token_providers.tokenUsageNotifierProvider.notifier)
                    .addPurchasedTokens(totalTokens);
                debugPrint(
                    '🟢 PAYWALL: Восстановлено токенов YooKassa: $totalTokens');
              }
            }
          } catch (_) {}
          break;

        case PaymentProvider.standardIAP:
          // Стандартное восстановление через IAP
          debugPrint('🔄 PAYWALL: ${context.tr('restore_tokens_iap')}');
          final subscriptionController = ref.read(purchaseControllerProvider);
          await subscriptionController.restorePurchases();

          // Дополнительно восстанавливаем токены через IAP
          final tokenService = ref.read(tokenPurchaseServiceProvider);
          final initialized = await tokenService.initialize();

          if (initialized) {
            final tokenPurchases = await tokenService.restoreTokenPurchases();

            if (tokenPurchases.isNotEmpty) {
              int totalTokens = 0;
              for (final purchase in tokenPurchases) {
                final tokenCount =
                    tokenService.getTokenCountFromProductId(purchase.productID);
                totalTokens += tokenCount;
              }

              if (totalTokens > 0) {
                await ref
                    .read(token_providers.tokenUsageNotifierProvider.notifier)
                    .addPurchasedTokens(totalTokens);
                debugPrint(
                    '🟢 PAYWALL: Восстановлено токенов IAP: $totalTokens');
              }
            }
          }

          restoredSuccessfully = true;
          break;
      }

      timeoutTimer.cancel();
      _setLoadingOverlay(false);

      if (restoredSuccessfully) {
        if (restoredPurchases.isNotEmpty) {
          _showMessage(
              '${context.tr('restore_successful')} (${restoredPurchases.length})',
              isError: false);
        } else {
          _showMessage(context.tr('restore_successful'), isError: false);
        }

        // Проверяем, активировалась ли подписка
        Future.delayed(const Duration(seconds: 1), () async {
          if (!mounted) return;
          final subscriptionAsyncValue = ref.read(subscriptionProvider);
          if (subscriptionAsyncValue.hasValue &&
              subscriptionAsyncValue.value!.isActive) {
            debugPrint(
                '🟢 PAYWALL: Подписка активирована после восстановления');

            // Закрываем paywall если подписка активна
            if (widget.onClose != null) {
              widget.onClose!();
            } else {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/home',
                (route) => false,
                arguments: {'subscription_restored': true},
              );
            }
          }
        });
      } else {
        _showMessage(context.tr('no_purchases_to_restore'), isError: false);
      }
    } catch (e) {
      _showErrorMessage('${context.tr('restore_failed')}: $e');
      _setLoadingOverlay(false);
    } finally {
      if (mounted) {
        setState(() {
          _isPurchasing = false;
        });
      }
    }
  }

  /// Находит наиболее выгодную подписку RuStore (приоритет: годовая > месячная > недельная)
  RuStorePurchaseInfo? _findBestRuStorePurchase(
      List<RuStorePurchaseInfo> purchases) {
    if (purchases.isEmpty) return null;

    // Сортируем по приоритету
    final sortedPurchases = [...purchases];
    sortedPurchases.sort((a, b) {
      final priorityA = _getRuStorePurchasePriority(a.productId);
      final priorityB = _getRuStorePurchasePriority(b.productId);
      return priorityB.compareTo(priorityA); // Больший приоритет вперед
    });

    return sortedPurchases.first;
  }

  /// Получает приоритет подписки RuStore (больше = лучше)
  int _getRuStorePurchasePriority(String productId) {
    switch (productId) {
      case 'aivideomaker.yearly.rustore':
        return 3;
      case 'aivideomaker.monthly.rustore':
        return 2;
      case 'aivideomaker.weekly.rustore':
        return 1;
      default:
        return 0;
    }
  }

  /// Обрабатывает восстановленные покупки RuStore (подписки и токены)
  Future<void> _processRestoredRuStorePurchases(
      List<RuStorePurchaseInfo> purchases, dynamic subscriptionNotifier) async {
    // Разделяем покупки на подписки и токены
    final subscriptions = <RuStorePurchaseInfo>[];
    final tokens = <RuStorePurchaseInfo>[];

    for (final purchase in purchases) {
      final productId = purchase.productId;
      if (productId.contains('yearly') ||
          productId.contains('monthly') ||
          productId.contains('weekly')) {
        subscriptions.add(purchase);
      } else if (productId.contains('.credits.50.') ||
          productId.contains('.credits.200.') ||
          productId.contains('.credits.600.') ||
          productId.contains('.100k.') ||
          productId.contains('.300k.') ||
          productId.contains('.800k.')) {
        tokens.add(purchase);
      }
    }

    // Активируем лучшую подписку, если есть
    if (subscriptions.isNotEmpty) {
      final bestPurchase = _findBestRuStorePurchase(subscriptions);
      if (bestPurchase != null) {
        SubscriptionType? restoredSubType;
        switch (bestPurchase.productId) {
          case 'aivideomaker.yearly.rustore':
            await subscriptionNotifier.activateYearly();
            restoredSubType = SubscriptionType.yearly;
            break;
          case 'aivideomaker.monthly.rustore':
            await subscriptionNotifier.activateMonthly();
            restoredSubType = SubscriptionType.monthly;
            break;
          case 'aivideomaker.weekly.rustore':
            await subscriptionNotifier.activateWeekly();
            restoredSubType = SubscriptionType.weekly;
            break;
        }
        if (restoredSubType != null) {
          await CreditService().activateSubscription(restoredSubType);
          ref.invalidate(creditUsageNotifierProvider);
        }
        if (bestPurchase.fromLegacySdk) {
          try {
            await RustorePurchaseVerificationService.instance
                .linkLegacySubscription(
              purchaseId: bestPurchase.purchaseId,
              productId: bestPurchase.productId,
              invoiceId: bestPurchase.invoiceId,
              purchaseState: bestPurchase.purchaseState,
              expirationDate: bestPurchase.expirationDate,
            );
          } catch (e) {
            debugPrint('⚠️ PAYWALL: link_legacy_subscription failed: $e');
          }
        }
        await subscriptionNotifier.refreshSubscription();
      }
    }

    // Восстанавливаем токены
    if (tokens.isNotEmpty) {
      final reconcileInput = tokens
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

      if (reconcileInput.isNotEmpty) {
        final reconcileResult = await RustorePurchaseVerificationService
            .instance
            .reconcilePurchases(
          reconcileInput,
        );
        RustorePurchaseVerificationResult? latestSnapshot;
        final ruStoreService = ref.read(rustoreBillingServiceProvider);

        for (final item in reconcileResult.items) {
          if (!item.success) continue;
          latestSnapshot = item;
          if (item.needsClientConfirm) {
            final confirmed =
                await ruStoreService.confirmPurchase(item.purchaseId);
            if (confirmed) {
              await RustorePurchaseVerificationService.instance
                  .markConfirmed(item.purchaseId);
            }
          }
        }

        if (latestSnapshot != null) {
          await ref.read(creditServiceProvider).applyServerPurchaseSnapshot(
                purchasedCredits: latestSnapshot.purchasedCredits,
                currentBalance: latestSnapshot.currentBalance,
              );
          ref.invalidate(creditUsageNotifierProvider);
          debugPrint(
            '🟢 PAYWALL: Кредиты RuStore восстановлены через серверный reconcile',
          );
        }
      }
    }
  }

  /// Обработка успешной покупки
  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchase) async {
    // Используем статическую переменную для предотвращения повторной обработки
    String? lastProcessedPurchaseId;

    if (lastProcessedPurchaseId == purchase.purchaseID) {
      debugPrint(
          'Покупка ${purchase.productID} уже была обработана, пропускаем');
      return;
    }

    try {
      debugPrint('Начинаем обработку успешной покупки: ${purchase.productID}');
      lastProcessedPurchaseId = purchase.purchaseID;

      // Не показываем экран загрузки снова, так как он уже должен быть показан
      // и обработан через LoadingManager

      // Обновляем состояние подписки через контроллер
      final purchaseController = ref.read(purchaseControllerProvider);
      await purchaseController.updateSubscriptionFromPurchase(purchase);

      // Активируем кредиты для новой подписки
      final productId = purchase.productID;
      SubscriptionType? purchasedSubType;
      if (productId.contains('yearly')) {
        purchasedSubType = SubscriptionType.yearly;
      } else if (productId.contains('monthly')) {
        purchasedSubType = SubscriptionType.monthly;
      } else if (productId.contains('weekly')) {
        purchasedSubType = SubscriptionType.weekly;
      }
      if (purchasedSubType != null) {
        unawaited(
          MyTrackerAnalyticsService.instance.trackSubscriptionPurchase(
            plan: purchasedSubType,
            paymentProvider: 'standard_iap',
            productId: productId,
          ),
        );
        if (_selectedPlanIndex == 0) {
          unawaited(
            MyTrackerAnalyticsService.instance.trackTrialStarted(
              paymentProvider: 'standard_iap',
              productId: productId,
            ),
          );
        }
        await CreditService().activateSubscription(purchasedSubType);
        ref.invalidate(creditUsageNotifierProvider);
      }

      debugPrint('Подписка успешно обновлена в системе');

      // Небольшая задержка перед навигацией
      await Future.delayed(const Duration(milliseconds: 300));

      // Скрываем экран загрузки перед навигацией
      _setLoadingOverlay(false);

      // Сообщение об успешной активации будет показано на главном экране
      // Убираем показ сообщения здесь, чтобы избежать дублирования

      // Закрываем экран после успешной покупки и возвращаемся на главный экран
      if (mounted) {
        // Предотвращаем повторное выполнение обработки покупки
        setState(() {
          _isPurchasing = false;
          _showLoadingOverlay = false;
        });

        // Возвращаемся на главный экран корректным образом
        if (widget.onClose != null) {
          debugPrint('Вызываем onClose коллбэк');
          widget.onClose!();
        } else {
          debugPrint('Переходим на главный экран');
          // Используем pushAndRemoveUntil для надежного перехода на главный экран
          // и передаем аргумент об успешной подписке
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/home',
            (route) => false,
            arguments: {'subscription_activated': true},
          );
        }
      }

      debugPrint('Обработка успешной покупки завершена');
    } catch (e) {
      debugPrint('Ошибка при обработке покупки: $e');
      unawaited(
        MyTrackerAnalyticsService.instance.trackSubscriptionFailed(
          paymentProvider: 'standard_iap',
          productId: purchase.productID,
          error: e.toString(),
        ),
      );
      _showErrorMessage('${context.tr('purchase_failed')}: $e');

      // Скрываем экран загрузки в случае ошибки
      if (mounted) {
        _setLoadingOverlay(false);
        setState(() {
          _showLoadingOverlay = false;
          _isPurchasing = false;
        });
      }
    }
  }

  /// Установка состояния экрана загрузки
  void _setLoadingOverlay(bool show) {
    debugPrint('${show ? "Показываем" : "Скрываем"} экран загрузки');

    if (show) {
      if (!mounted) {
        return;
      }
      // Показываем экран загрузки через LoadingManager
      LoadingManager().showLoadingScreen(
        context,
        text: context.tr('purchase_processing'),
        animationPath: 'assets/animations/loading.json',
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        processingStepText: context.tr('do_not_close_app'),
        progressValue: 0.5,
        animationHeight: MediaQuery.of(context).size.height * 0.4,
      );
    } else {
      // Скрываем даже если виджет уже размонтирован (гонка с resume/навигацией)
      LoadingManager().hideLoadingScreen();
    }

    if (mounted) {
      setState(() {
        _showLoadingOverlay = show;
      });
    } else {
      _showLoadingOverlay = show;
    }
  }

  /// Показ сообщения (успех или ошибка)
  void _showMessage(String message, {bool isError = true}) {
    final palette = PhotosessionPalette.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        backgroundColor: isError ? palette.danger : palette.success,
      ),
    );
  }

  /// Показ сообщения об ошибке
  void _showErrorMessage(String message) {
    _showMessage(message, isError: true);
  }

  /// Метод для открытия URL-адресов
  void _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('url_launch_error'))),
        );
      }
    }
  }

  /// Извлекает числовое значение цены из строки цены
  double _extractNumericPrice(String priceString) {
    // Убираем все символы валюты и пробелы
    final String numericPart = priceString.replaceAll(RegExp(r'[^\d.,]'), '');

    // Заменяем запятую на точку для правильного парсинга
    final String normalizedNumeric = numericPart.replaceAll(',', '.');

    return double.parse(normalizedNumeric);
  }

  /// Извлекает код валюты из строки цены
  String _extractCurrencyCode(String priceString) {
    // Проверяем специальные случаи для известных валют
    if (priceString.contains('₽') || priceString.contains('руб')) return 'RUB';
    if (priceString.contains('\$')) return 'USD';
    if (priceString.contains('€')) return 'EUR';
    if (priceString.contains('£')) return 'GBP';

    // Ищем трехбуквенные коды валют
    final RegExp currencyPattern = RegExp(r'[A-Z]{3}');
    final match = currencyPattern.firstMatch(priceString);
    if (match != null) {
      return match.group(0) ?? '';
    }

    // Обрабатываем специальный случай для турецкой лиры, где может быть только "T"
    if (priceString.contains('T') && !priceString.contains('TRY')) {
      return 'TRY';
    }

    // Если не нашли код, возвращаем пустую строку
    return '';
  }

  // Удалено: _formatPrice не используется

  String _getAiRequestsHintText(BuildContext context, int index) {
    final CreditPlan plan;
    switch (index) {
      case 0:
        plan = CreditPlan.yearly;
        break;
      case 1:
        plan = CreditPlan.monthly;
        break;
      case 2:
      default:
        plan = CreditPlan.weekly;
        break;
    }
    final premium = plan.approximatePremiumPhotos;
    final standard = plan.approximateStandardPhotos;
    final economy = plan.approximateEconomyPhotos;
    return '${plan.totalCredits} кредитов: ~$economy эконом / ~$standard стандарт / ~$premium премиум фото';
  }

  SubscriptionType _getSelectedSubscriptionType() {
    switch (_selectedPlanIndex) {
      case 0:
        return SubscriptionType.yearly;
      case 1:
        return SubscriptionType.monthly;
      case 2:
        return SubscriptionType.weekly;
      default:
        return SubscriptionType.yearly;
    }
  }

  String _paymentProviderName(PaymentProvider provider) {
    switch (provider) {
      case PaymentProvider.rustore:
        return 'rustore';
      case PaymentProvider.yookassa:
        return 'yookassa';
      case PaymentProvider.standardIAP:
        return 'standard_iap';
    }
  }
}
