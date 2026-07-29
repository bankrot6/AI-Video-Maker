import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../config/credit_config.dart';
import '../../services/payment_providers.dart';
import '../../utils/app_logger.dart';

class CreditPriceInfo {
  final double price;
  final String currencyCode;
  final String? formattedPrice;

  const CreditPriceInfo({
    required this.price,
    required this.currencyCode,
    this.formattedPrice,
  });
}

final creditPricesProvider =
    FutureProvider<Map<CreditPackageType, CreditPriceInfo>>((ref) async {
  try {
    final paymentProvider = await ref.watch(paymentProviderTypeProvider.future);

    switch (paymentProvider) {
      case PaymentProvider.rustore:
      case PaymentProvider.yookassa:
        return <CreditPackageType, CreditPriceInfo>{
          CreditPackageType.small: CreditPriceInfo(
            price: CreditPackageType.small.priceRub.toDouble(),
            currencyCode: 'RUB',
            formattedPrice: '${CreditPackageType.small.priceRub} ₽',
          ),
          CreditPackageType.medium: CreditPriceInfo(
            price: CreditPackageType.medium.priceRub.toDouble(),
            currencyCode: 'RUB',
            formattedPrice: '${CreditPackageType.medium.priceRub} ₽',
          ),
          CreditPackageType.large: CreditPriceInfo(
            price: CreditPackageType.large.priceRub.toDouble(),
            currencyCode: 'RUB',
            formattedPrice: '${CreditPackageType.large.priceRub} ₽',
          ),
        };

      case PaymentProvider.standardIAP:
        AppLogger.log('💰 CREDIT_PRICES: Стандартные IAP — запрашиваем цены',
            level: LogLevel.debug);

        final ids = {
          for (final p in CreditPackageType.values) p.id,
        };
        final response = await InAppPurchase.instance.queryProductDetails(ids);

        if (response.error != null) {
          AppLogger.log(
              '🔴 CREDIT_PRICES: Ошибка запроса продуктов: ${response.error}',
              level: LogLevel.error);
        }

        final Map<CreditPackageType, CreditPriceInfo> result = {};
        for (final product in response.productDetails) {
          final matchedType = CreditPackageType.values
              .where((t) => t.id == product.id)
              .firstOrNull;
          if (matchedType == null) continue;

          result[matchedType] = CreditPriceInfo(
            price: product.rawPrice,
            currencyCode: product.currencyCode,
            formattedPrice: product.price,
          );
        }

        if (result.isEmpty) {
          AppLogger.log('🟡 CREDIT_PRICES: Продукты не найдены, дефолт',
              level: LogLevel.warning);
          final String currency = Platform.isIOS ? 'USD' : 'USD';
          return <CreditPackageType, CreditPriceInfo>{
            CreditPackageType.small:
                CreditPriceInfo(price: 0.99, currencyCode: currency),
            CreditPackageType.medium:
                CreditPriceInfo(price: 2.49, currencyCode: currency),
            CreditPackageType.large:
                CreditPriceInfo(price: 4.99, currencyCode: currency),
          };
        }

        return result;
    }
  } catch (e, st) {
    AppLogger.log('🔴 CREDIT_PRICES: Ошибка: $e', level: LogLevel.error);
    if (kDebugMode) {
      debugPrint(st.toString());
    }
    return <CreditPackageType, CreditPriceInfo>{
      CreditPackageType.small: CreditPriceInfo(
        price: CreditPackageType.small.priceRub.toDouble(),
        currencyCode: 'RUB',
        formattedPrice: '${CreditPackageType.small.priceRub} ₽',
      ),
      CreditPackageType.medium: CreditPriceInfo(
        price: CreditPackageType.medium.priceRub.toDouble(),
        currencyCode: 'RUB',
        formattedPrice: '${CreditPackageType.medium.priceRub} ₽',
      ),
      CreditPackageType.large: CreditPriceInfo(
        price: CreditPackageType.large.priceRub.toDouble(),
        currencyCode: 'RUB',
        formattedPrice: '${CreditPackageType.large.priceRub} ₽',
      ),
    };
  }
});
