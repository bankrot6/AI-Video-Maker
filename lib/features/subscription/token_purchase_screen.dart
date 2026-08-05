import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:auto_size_text/auto_size_text.dart';

import '../../config/credit_config.dart';
import '../../models/credit_usage_model.dart';
import '../../providers/credit_providers.dart';
import '../../services/payment_providers.dart';
import '../../services/token_store_config.dart';
import '../../services/app_store_detection_service.dart';
import '../../services/android_system_ui_controller.dart';
import '../../utils/app_logger.dart';
import '../../services/rustore_purchase_verification_service.dart';
import '../../services/analytics/mytracker_analytics_service.dart';
import '../photosession/theme/photosession_palette.dart';
import 'token_purchase_providers.dart';

class TokenPurchaseScreen extends ConsumerStatefulWidget {
  const TokenPurchaseScreen({super.key});

  @override
  ConsumerState<TokenPurchaseScreen> createState() =>
      _TokenPurchaseScreenState();
}

class _TokenPurchaseScreenState extends ConsumerState<TokenPurchaseScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  CreditPackageType? selectedPackage;
  bool isPurchasing = false;

  @override
  void initState() {
    super.initState();
    AndroidSystemUiController.showNavigationBar();
    selectedPackage = CreditPackageType.medium;
    unawaited(
      MyTrackerAnalyticsService.instance.trackEvent(
        'credits_store_open',
        {'platform': defaultTargetPlatform.name},
      ),
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    AndroidSystemUiController.hideNavigationBar();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creditAsync = ref.watch(creditUsageNotifierProvider);
    final theme = Theme.of(context);

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: theme.scaffoldBackgroundColor,
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: creditAsync.when(
            data: (usage) => _buildContent(context, usage),
            loading: () => Center(
              child:
                  CircularProgressIndicator(color: theme.colorScheme.onSurface),
            ),
            error: (error, stack) => Center(
              child: Text(
                'Ошибка загрузки данных',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, CreditUsageModel usage) {
    final pricesAsync = ref.watch(creditPricesProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final screenHeight = MediaQuery.of(context).size.height;
    final titleFontSize = screenHeight > 700 ? 24.0 : 20.0;
    final subtitleFontSize = screenHeight > 700 ? 14.0 : 12.0;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colors.primary,
                          colors.primary.withOpacity(0.7)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.stars_rounded,
                      color: colors.onPrimary,
                      size: 24,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      icon: Icon(
                        Icons.close,
                        color: colors.onSurface.withOpacity(0.35),
                        size: 24,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: const EdgeInsets.all(4.0),
                      constraints: const BoxConstraints(),
                      splashRadius: 24.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Купить кредиты',
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
              color: colors.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Кредиты расходуются на генерацию видео',
            style: TextStyle(
              color: colors.onSurface.withOpacity(0.6),
              fontSize: subtitleFontSize,
            ),
            textAlign: TextAlign.center,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: pricesAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(color: colors.onSurface),
                ),
                error: (e, st) => _buildPackagesWithBalance(null, usage),
                data: (prices) => _buildPackagesWithBalance(prices, usage),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPurchaseButton(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentBalance(CreditUsageModel usage) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = PhotosessionPalette.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final remaining = usage.remainingCredits;
    final isLow = remaining < 20;
    final isCritical = remaining < 8;
    final color = isCritical
        ? palette.danger
        : isLow
            ? palette.warning
            : palette.success;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(isDark ? 0.4 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.stars_rounded,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Ваш баланс:',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          AutoSizeText(
            '$remaining кредитов',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            minFontSize: 12,
          ),
        ],
      ),
    );
  }

  Widget _buildPackagesWithBalance(
    Map<CreditPackageType, CreditPriceInfo>? prices,
    CreditUsageModel usage,
  ) {
    final types = CreditPackageType.values;
    return Column(
      children: [
        const Spacer(flex: 1),
        Expanded(flex: 2, child: _buildCurrentBalance(usage)),
        const Spacer(flex: 1),
        for (int i = 0; i < types.length; i++) ...[
          Expanded(flex: 4, child: _buildPackageCard(types[i], prices)),
          const Spacer(flex: 1),
        ],
      ],
    );
  }

  Widget _buildPackageCard(
    CreditPackageType packageType,
    Map<CreditPackageType, CreditPriceInfo>? prices,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = PhotosessionPalette.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final shadowColor = theme.shadowColor.withOpacity(isDark ? 0.4 : 0.08);
    final isSelected = selectedPackage == packageType;
    final isBestOffer = packageType == CreditPackageType.medium;
    final CreditPriceInfo? priceInfo = prices?[packageType];
    final String mainPriceText =
        priceInfo?.formattedPrice ?? '${packageType.priceRub} ₽';
    final savings = packageType.savingsLabel;

    final borderRadius = BorderRadius.circular(16.0);

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isSelected ? _scaleAnimation.value : 1.0,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
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
                      ? Border.all(color: colors.primary, width: 1.5)
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: borderRadius,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _selectPackage(packageType),
                    onTapDown: (_) => _scaleController.forward(),
                    onTapUp: (_) => _scaleController.reverse(),
                    onTapCancel: () => _scaleController.reverse(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _getIcon(packageType),
                              size: 20,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AutoSizeText(
                                  _getTitle(packageType),
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  minFontSize: 12,
                                ),
                                const SizedBox(height: 4),
                                AutoSizeText(
                                  '${_formatNumber(packageType.credits)} кредитов',
                                  style: TextStyle(
                                    color: colors.onSurface.withOpacity(0.6),
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  minFontSize: 12,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _getDescription(packageType),
                                  style: TextStyle(
                                    color: colors.onSurface.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AutoSizeText(
                                mainPriceText,
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                minFontSize: 12,
                              ),
                              if (savings.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: palette.success.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    savings,
                                    style: TextStyle(
                                      color: palette.success,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(width: 10),
                          _buildSelectionIndicator(isSelected),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (isBestOffer)
                Positioned(
                  top: -10,
                  right: 18,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: colors.outline.withOpacity(0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: shadowColor,
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Text(
                      'Лучшее предложение',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPurchaseButton() {
    final pricesAsync = ref.watch(creditPricesProvider);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bool isActive = selectedPackage != null && !isPurchasing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Opacity(
        opacity: isActive ? 1.0 : 0.6,
        child: Container(
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(30.0),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.15),
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
              onTap: isActive ? _purchaseCredits : null,
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: Center(
                  child: isPurchasing
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: colors.onPrimary,
                            strokeWidth: 2,
                          ),
                        )
                      : pricesAsync.when(
                          loading: () => _buildButtonText(null),
                          error: (e, st) => _buildButtonText(null),
                          data: (prices) => _buildButtonText(prices),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonText(Map<CreditPackageType, CreditPriceInfo>? prices) {
    final colors = Theme.of(context).colorScheme;
    if (selectedPackage == null) {
      return AutoSizeText(
        'Выберите пакет',
        style: TextStyle(
          color: colors.onPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        maxLines: 1,
        minFontSize: 14,
      );
    }
    final info = prices?[selectedPackage!];
    final text = info?.formattedPrice ?? '${selectedPackage!.priceRub} ₽';
    return AutoSizeText(
      'Купить за $text',
      style: TextStyle(
        color: colors.onPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      maxLines: 1,
      minFontSize: 14,
    );
  }

  Widget _buildSelectionIndicator(bool isSelected) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? colors.primary : colors.outline.withOpacity(0.5),
          width: 2,
        ),
        color: isSelected ? colors.primary : Colors.transparent,
      ),
      child: isSelected
          ? Icon(Icons.check, color: colors.onPrimary, size: 16)
          : null,
    );
  }

  void _selectPackage(CreditPackageType packageType) {
    setState(() {
      selectedPackage = packageType;
    });
  }

  Future<void> _purchaseCredits() async {
    if (selectedPackage == null) return;

    setState(() => isPurchasing = true);

    try {
      final paymentProviderType =
          await ref.read(paymentProviderTypeProvider.future);
      final paymentProvider = _paymentProviderName(paymentProviderType);
      unawaited(
        MyTrackerAnalyticsService.instance.trackEvent(
          'credits_purchase_start',
          {
            'payment_provider': paymentProvider,
            'package_id': selectedPackage!.name,
            'credits': selectedPackage!.credits.toString(),
          },
        ),
      );

      if (kDebugMode) {
        debugPrint(
            '🟡 CREDIT_PURCHASE: Debug-режим — покупка с синхронизацией на сервер');
        await ref
            .read(creditUsageNotifierProvider.notifier)
            .grantPurchasedCredits(selectedPackage!.credits);
        unawaited(
          MyTrackerAnalyticsService.instance.trackCreditsPurchase(
            credits: selectedPackage!.credits,
            paymentProvider: 'debug',
            packageId: selectedPackage!.name,
            amount: selectedPackage!.priceRub.toString(),
            currency: 'RUB',
          ),
        );

        AppLogger.log(
            '✅ CREDIT_PURCHASE: Debug — добавлено ${selectedPackage!.credits} кредитов');
        if (mounted) {
          _showSuccessDialog(selectedPackage!.credits);
        }
        return;
      }

      final storeDetection = ref.read(appStoreDetectionServiceProvider);
      final storeType = await storeDetection.getInstallationSource();
      final isRuStore = storeType == AppStoreType.ruStore;

      bool success = false;

      if (isRuStore) {
        success = await _purchaseViaRuStore(
          TokenStoreConfig.ruStoreCreditsPackageProductId(selectedPackage!),
          selectedPackage!,
        );
      } else {
        success = await _purchaseViaIAP(selectedPackage!.id);
      }

      if (success) {
        if (!isRuStore) {
          await ref
              .read(creditUsageNotifierProvider.notifier)
              .addPurchasedCredits(selectedPackage!.credits);
        }
        unawaited(
          MyTrackerAnalyticsService.instance.trackCreditsPurchase(
            credits: selectedPackage!.credits,
            paymentProvider: paymentProvider,
            packageId: selectedPackage!.name,
            amount: selectedPackage!.priceRub.toString(),
            currency: 'RUB',
          ),
        );
        // Доход RuStore отправляется на сервере (verify-rustore-purchase) по
        // фактической сумме платежа и идемпотентно по purchaseId — на клиенте
        // выручку не дублируем. Остаётся только событие воронки выше.

        AppLogger.log(
            '✅ CREDIT_PURCHASE: Добавлено ${selectedPackage!.credits} кредитов');
        if (mounted) {
          _showSuccessDialog(selectedPackage!.credits);
        }
      } else {
        unawaited(
          MyTrackerAnalyticsService.instance.trackCreditsPurchaseFailed(
            paymentProvider: paymentProvider,
            packageId: selectedPackage!.name,
            error: 'purchase_cancelled',
          ),
        );
        _showErrorSnackbar('Покупка была отменена');
      }
    } catch (e) {
      AppLogger.log('🔴 CREDIT_PURCHASE: Ошибка покупки: $e',
          level: LogLevel.error);
      unawaited(
        MyTrackerAnalyticsService.instance.trackCreditsPurchaseFailed(
          paymentProvider: 'unknown',
          packageId: selectedPackage?.name,
          error: e.toString(),
        ),
      );
      _showErrorSnackbar(e.toString());
    } finally {
      if (mounted) {
        setState(() => isPurchasing = false);
      }
    }
  }

  Future<bool> _purchaseViaRuStore(
    String productId,
    CreditPackageType packageType,
  ) async {
    final overlayNotifier = ref.read(creditBalanceOverlayProvider.notifier);
    overlayNotifier.show();
    try {
      final ruStoreService = ref.read(rustoreBillingServiceProvider);
      final creditService = ref.read(creditServiceProvider);
      final isInitialized = await ruStoreService.initialize();

      if (!isInitialized) {
        throw Exception('Не удалось инициализировать RuStore SDK');
      }

      final orderId = _buildRustoreOrderId(productId);
      final purchaseResult = await ruStoreService.purchaseConsumableProduct(
        productId,
        developerPayload: orderId,
        orderId: orderId,
      );

      if (!purchaseResult.success) {
        throw Exception(
          purchaseResult.errorMessage ??
              'Покупка RuStore не была завершена корректно',
        );
      }

      final purchaseId = purchaseResult.purchaseId;
      final invoiceId = purchaseResult.invoiceId;
      if (purchaseId == null || purchaseId.isEmpty) {
        throw Exception('RuStore не вернул purchaseId');
      }
      if (invoiceId == null || invoiceId.isEmpty) {
        throw Exception('RuStore не вернул invoiceId для серверной валидации');
      }

      final verification =
          await RustorePurchaseVerificationService.instance.verifyPurchase(
        purchaseId: purchaseId,
        invoiceId: invoiceId,
        productId: purchaseResult.productId,
        orderId: purchaseResult.orderId ?? orderId,
      );

      if (!verification.success) {
        throw Exception(
          verification.reason.isNotEmpty
              ? verification.reason
              : 'Сервер не подтвердил покупку RuStore',
        );
      }

      await creditService.applyServerPurchaseSnapshot(
        purchasedCredits: verification.purchasedCredits,
        currentBalance: verification.currentBalance,
      );
      ref.invalidate(creditUsageNotifierProvider);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      if (verification.needsClientConfirm) {
        final confirmOk = await ruStoreService.confirmPurchase(purchaseId);
        if (!confirmOk) {
          AppLogger.log(
            '⚠️ CREDIT_PURCHASE: confirm RuStore не удался purchaseId=$purchaseId',
            level: LogLevel.warning,
          );
        } else {
          await RustorePurchaseVerificationService.instance
              .markConfirmed(purchaseId);
        }
      }

      return true;
    } catch (e) {
      debugPrint('🔴 CREDIT_PURCHASE: Ошибка RuStore: $e');
      rethrow;
    } finally {
      overlayNotifier.hide();
    }
  }

  String _buildRustoreOrderId(String productId) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final cleanProductId = productId.replaceAll('.', '_');
    return 'rustore_${cleanProductId}_$micros';
  }

  Future<bool> _purchaseViaIAP(String productId) async {
    try {
      debugPrint('📱 CREDIT_PURCHASE: Покупка через IAP: $productId');
      await Future.delayed(const Duration(seconds: 2));
      return true;
    } catch (e) {
      debugPrint('🔴 CREDIT_PURCHASE: Ошибка IAP: $e');
      rethrow;
    }
  }

  void _showSuccessDialog(int credits) {
    final palette = PhotosessionPalette.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: palette.success, size: 28),
            const SizedBox(width: 8),
            const Text('Готово!'),
          ],
        ),
        content: Text(
          'Вам начислено ${_formatNumber(credits)} кредитов.',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackbar(String error) {
    if (!mounted) return;
    final palette = PhotosessionPalette.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ошибка: $error'),
        backgroundColor: palette.danger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  IconData _getIcon(CreditPackageType type) {
    switch (type) {
      case CreditPackageType.small:
        return Icons.stars_outlined;
      case CreditPackageType.medium:
        return Icons.stars_rounded;
      case CreditPackageType.large:
        return Icons.auto_awesome;
    }
  }

  String _getTitle(CreditPackageType type) {
    switch (type) {
      case CreditPackageType.small:
        return 'Стартовый';
      case CreditPackageType.medium:
        return 'Популярный';
      case CreditPackageType.large:
        return 'Максимальный';
    }
  }

  String _getDescription(CreditPackageType type) {
    final premium = type.credits ~/ CreditCost.advancedGeneration;
    final standard = type.credits ~/ CreditCost.standardGeneration;
    final economy = type.credits ~/ CreditCost.economyGeneration;
    return '~$economy эконом · $standard стандарт · $premium премиум видео';
  }

  String _formatNumber(int number) {
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    }
    return number.toString();
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
