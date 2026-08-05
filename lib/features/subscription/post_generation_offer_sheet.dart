import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'purchase_routes.dart';
import '../../providers/credit_providers.dart';
import '../../services/payment_providers.dart';
import '../../services/purchase_service.dart';
import '../../models/product_model.dart';
import '../../models/subscription_model.dart';
import '../../widgets/loading/loading_manager.dart';
import 'purchase_providers.dart';
import 'subscription_providers.dart';
import '../../services/credit_service.dart';
import 'yookassa_payment_sheet.dart' as payment_sheet;

/// Soft-paywall после первой успешной генерации для free пользователей.
/// Показывает результат с размытым превью без watermark и предлагает подписку.
class PostGenerationOfferSheet extends ConsumerStatefulWidget {
  final String? previewImageUrl;
  
  const PostGenerationOfferSheet({
    super.key,
    this.previewImageUrl,
  });

  @override
  ConsumerState<PostGenerationOfferSheet> createState() =>
      _PostGenerationOfferSheetState();
}

class _PostGenerationOfferSheetState
    extends ConsumerState<PostGenerationOfferSheet> {
  int _remainingSeconds = 600; // 10 минут
  Timer? _timer;
  bool _timerExpired = false;
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _timerExpired = true;
          timer.cancel();
        }
      });
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  void _openPaywall() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      paywallRoute(),
    );
  }

  /// Запускает процесс покупки годовой подписки с бесплатным пробным периодом
  /// Реализует ту же логику что и PaywallScreen._startSubscription() но только для годового плана
  Future<void> _startFreeTrialPurchase() async {
    if (_isPurchasing) return; // Предотвращаем двойное нажатие
    
    debugPrint('🟢 OFFER_SHEET: Начинаем процесс покупки годовой подписки');
    
    setState(() => _isPurchasing = true);
    
    try {
      // Debug-обход: активируем подписку локально без реальной покупки
      if (kDebugMode) {
        debugPrint('🟡 OFFER_SHEET: Debug-режим — активация триала без покупки');
        await _activateDebugTrial();
        return;
      }

      // Показываем индикатор загрузки
      _showLoadingOverlay(true);

      // Определяем тип платежной системы
      final paymentProviderType =
          await ref.read(paymentProviderTypeProvider.future);

      switch (paymentProviderType) {
        case PaymentProvider.rustore:
          debugPrint('🟢 OFFER_SHEET: Пользователь RuStore - покупка через RuStore');
          await _startRuStoreYearlySubscription();
          break;

        case PaymentProvider.yookassa:
          debugPrint('🟢 OFFER_SHEET: Российский пользователь - покупка через ЮКассу');
          await _startYookassaYearlySubscription();
          break;

        case PaymentProvider.standardIAP:
          debugPrint('🟢 OFFER_SHEET: Стандартная покупка через IAP');
          await _startStandardIAPYearlySubscription();
          break;
      }
    } catch (e) {
      debugPrint('🔴 OFFER_SHEET: Ошибка в _startFreeTrialPurchase: $e');
      if (mounted) {
        _hideLoadingOverlay();
        setState(() => _isPurchasing = false);
        _showErrorMessage('Ошибка покупки: $e');
      }
    }
  }

  /// Debug-активация триала без реальной покупки
  Future<void> _activateDebugTrial() async {
    try {
      await ref.read(subscriptionProvider.notifier).activateTrial();
      final creditService = CreditService();
      await creditService.activateSubscription(SubscriptionType.trial);
      await creditService.refreshFromServer();
      ref.invalidate(creditUsageNotifierProvider);

      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🟡 DEBUG: Триал активирован без покупки'),
          backgroundColor: Colors.orange,
        ),
      );
    } on TrialAlreadyUsedException {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showErrorMessage('Вы уже использовали бесплатный период');
    }
  }

  /// Покупка годовой подписки через RuStore
  Future<void> _startRuStoreYearlySubscription() async {
    try {
      final ruStoreService = ref.read(rustoreBillingServiceProvider);
      final isInitialized = await ruStoreService.initialize();

      if (!isInitialized) {
        throw Exception('Не удалось инициализировать RuStore');
      }

      // Продукт для годовой подписки в RuStore
      const productId = 'aivideomaker.yearly.rustore';
      
      final success = await ruStoreService.purchaseProduct(productId);

      if (!mounted) return;
      _hideLoadingOverlay();

      if (success) {
        debugPrint('🟢 OFFER_SHEET: Успешная покупка через RuStore');
        
        // Активируем подписку локально
        try {
          await ref.read(subscriptionProvider.notifier).activateYearly();
          await CreditService().activateSubscription(SubscriptionType.yearly);
          ref.invalidate(creditUsageNotifierProvider);

          // Верифицируем подписку на сервере, чтобы кредиты подписки попали в
          // серверный баланс — иначе при первой генерации они затрутся.
          await ref
              .read(purchaseControllerProvider)
              .reconcileRustoreSubscriptions(ruStoreService);
        } catch (e) {
          debugPrint('🔴 OFFER_SHEET: Ошибка активации подписки: $e');
        }

        // Закрываем offer sheet
        Navigator.of(context).pop();

        // Показываем успех
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Подписка активирована! 1 день бесплатно'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('🔴 OFFER_SHEET: Ошибка RuStore: $e');
      if (!mounted) return;
      _hideLoadingOverlay();
      _showErrorMessage('Ошибка покупки через RuStore: $e');
    }
  }

  /// Покупка годовой подписки через ЮКассу
  Future<void> _startYookassaYearlySubscription() async {
    try {
      _hideLoadingOverlay(); // YooKassa сам управляет индикаторами

      await payment_sheet.YooKassaPaymentService.startPayment(
        context: context,
        ref: ref,
        subscriptionType: SubscriptionType.yearly,
        onSuccess: (type) {
          debugPrint('🟢 OFFER_SHEET: Успешная оплата через ЮКассу');
          if (!mounted) return;
          
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 Подписка активирована!'),
              backgroundColor: Colors.green,
            ),
          );
        },
        onCancel: () {
          debugPrint('🟡 OFFER_SHEET: Оплата отменена');
        },
      );
    } catch (e) {
      debugPrint('🔴 OFFER_SHEET: Ошибка ЮКассы: $e');
      if (!mounted) return;
      _showErrorMessage('Ошибка оплаты через ЮКассу: $e');
    }
  }

  /// Покупка годовой подписки через стандартный IAP (App Store / Google Play)
  Future<void> _startStandardIAPYearlySubscription() async {
    try {
      final purchaseController = ref.read(purchaseControllerProvider);
      final productsAsyncValue = ref.read(productsProvider);
      final products = productsAsyncValue.asData?.value ?? [];

      debugPrint('🟢 OFFER_SHEET: Доступно продуктов: ${products.length}');

      // Находим годовой продукт
      final yearlyProductId = StoreProductIds.yearlyWithTrial;
      ProductModel? productToBuy;
      
      try {
        productToBuy = products.firstWhere((p) => p.id == yearlyProductId);
      } catch (e) {
        if (products.isNotEmpty) {
          productToBuy = products.first;
        }
      }

      if (productToBuy == null) {
        throw Exception('Продукты не найдены');
      }

      debugPrint('🟢 OFFER_SHEET: Покупаем продукт: ${productToBuy.id}');

      // Инициируем покупку
      await purchaseController.purchaseProduct(productToBuy);
      
      // Обновляем индикатор
      if (mounted) {
        LoadingManager().updateProcessingInfo(
          context,
          newText: 'Ожидание подтверждения...',
          newProcessingStep: 'Подтвердите покупку',
          newProgressValue: 0.6,
          animationPath: 'assets/animations/loading.json',
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        );
      }

      // Дальнейшая обработка через purchasesProvider listener в build методе
      
    } catch (e) {
      debugPrint('🔴 OFFER_SHEET: Ошибка IAP: $e');
      if (!mounted) return;
      _hideLoadingOverlay();
      setState(() => _isPurchasing = false);
      _showErrorMessage('Ошибка покупки: $e');
    }
  }

  void _showLoadingOverlay(bool show) {
    if (!mounted) return;
    if (show) {
      LoadingManager().showLoadingScreen(
        context,
        text: 'Обработка покупки...',
        animationPath: 'assets/animations/loading.json',
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        processingStepText: 'Не закрывайте приложение',
        progressValue: 0.5,
        animationHeight: MediaQuery.of(context).size.height * 0.4,
      );
    }
  }

  void _hideLoadingOverlay() {
    if (mounted) {
      LoadingManager().hideLoadingScreen();
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Слушаем изменения покупок для автоматического закрытия при успехе
    ref.listen<AsyncValue<List<PurchaseDetails>>>(purchasesProvider,
        (previous, next) {
      next.whenData((purchases) {
        for (final purchase in purchases) {
          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            // Покупка успешна - закрываем offer sheet
            if (mounted && _isPurchasing) {
              debugPrint('🟢 OFFER_SHEET: Покупка успешна, закрываем');
              _hideLoadingOverlay();
              Navigator.of(context).pop();
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🎉 Подписка активирована! 1 день бесплатно'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } else if (purchase.status == PurchaseStatus.error) {
            if (mounted && _isPurchasing) {
              debugPrint('🔴 OFFER_SHEET: Ошибка покупки');
              _hideLoadingOverlay();
              setState(() => _isPurchasing = false);
              _showErrorMessage('Ошибка покупки: ${purchase.error?.message ?? "Неизвестная ошибка"}');
            }
          }
        }
      });
    });

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomPadding + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Индикатор драга
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Иконка с градиентом
          Container(
            width: 64,
            height: 64,
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
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),

          // Заголовок
          Text(
            'Это была ваша бесплатная генерация',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: colors.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Описание
          Text(
            'Получите безлимитный доступ ко всем функциям и уберите watermark с результатов',
            style: TextStyle(
              fontSize: 15,
              color: colors.onSurface.withOpacity(0.7),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Таймер скидки (если не истёк)
          if (!_timerExpired) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 20,
                    color: colors.onPrimaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Специальная цена действует: ${_formatTime(_remainingSeconds)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Список преимуществ
          _buildBenefit(
            context,
            icon: Icons.auto_awesome_rounded,
            title: 'Безлимитные генерации',
            description: 'Создавайте сколько угодно AI-видео',
          ),
          const SizedBox(height: 12),
          _buildBenefit(
            context,
            icon: Icons.hd_rounded,
            title: 'Без watermark',
            description: 'Чистые результаты в высоком качестве',
          ),
          const SizedBox(height: 12),
          _buildBenefit(
            context,
            icon: Icons.palette_rounded,
            title: 'Все стили и пресеты',
            description: 'Полный доступ к библиотеке',
          ),
          const SizedBox(height: 24),

          // Основная кнопка - Оформить подписку
          FilledButton(
            onPressed: _isPurchasing ? null : _openPaywall,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Оформить подписку',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Кнопка "Продолжить бесплатно" - покупка годовой с триалом
          TextButton(
            onPressed: _isPurchasing ? null : _startFreeTrialPurchase,
            style: TextButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
            child: Text(
              _isPurchasing ? 'Обработка покупки...' : 'Продолжить бесплатно',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _isPurchasing 
                    ? colors.onSurface.withOpacity(0.3)
                    : colors.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefit(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final colors = Theme.of(context).colorScheme;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Показывает soft-paywall sheet если пользователь free и это его первая генерация
Future<void> showPostGenerationOfferIfNeeded({
  required BuildContext context,
  required WidgetRef ref,
  String? previewImageUrl,
}) async {
  // Показываем только для free пользователей
  final creditUsage = ref.read(creditUsageNotifierProvider).valueOrNull;
  if (creditUsage == null || !creditUsage.isFreeUser) return;

  // Показываем только если это была первая или вторая генерация
  if (creditUsage.freePhotosUsed > 1) return;

  // Даём пользователю 2 секунды насладиться результатом
  await Future.delayed(const Duration(seconds: 2));

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => PostGenerationOfferSheet(
      previewImageUrl: previewImageUrl,
    ),
  );
}

// Provider для отслеживания кредитов (импорт из credit_providers.dart)
// Определён в lib/providers/credit_providers.dart
