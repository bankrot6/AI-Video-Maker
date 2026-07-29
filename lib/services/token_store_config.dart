import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/credit_config.dart';
import 'payment_providers.dart';

/// Конфигурация продуктов токенов для разных магазинов
class TokenStoreConfig {
  // iOS App Store идентификаторы для токенов
  static const String _smallTokensIOS = 'aivideomaker.25k';
  static const String _mediumTokensIOS = 'aivideomaker.75k';
  static const String _largeTokensIOS = 'aivideomaker.200k';

  // Android Google Play идентификаторы для токенов
  static const String _smallTokensAndroid = 'aivideomaker.tokens.small.android';
  static const String _mediumTokensAndroid = 'aivideomaker.tokens.medium.android';
  static const String _largeTokensAndroid = 'aivideomaker.tokens.large.android';

  // RuStore — разовые пакеты кредитов (совпадают с CreditPackageType.credits)
  static const String _smallTokensRuStore = 'aivideomaker.credits.50.rustore';
  static const String _mediumTokensRuStore =
      'aivideomaker.credits.200.rustore';
  static const String _largeTokensRuStore =
      'aivideomaker.credits.600.rustore';

  // ЮMoney идентификаторы для токенов (для веб-платежей)
  static const String _smallTokensYooMoney = 'aivideomaker.tokens.small.yoomoney';
  static const String _mediumTokensYooMoney = 'aivideomaker.tokens.medium.yoomoney';
  static const String _largeTokensYooMoney = 'aivideomaker.tokens.large.yoomoney';

  static String ruStoreCreditsPackageProductId(CreditPackageType package) {
    switch (package) {
      case CreditPackageType.small:
        return _smallTokensRuStore;
      case CreditPackageType.medium:
        return _mediumTokensRuStore;
      case CreditPackageType.large:
        return _largeTokensRuStore;
    }
  }

  /// Малый пакет — автоопределение магазина
  static Future<String> getSmallTokens(WidgetRef ref) async {
    final paymentProvider = await ref.read(paymentProviderTypeProvider.future);
    return _getTokenIdByProvider(paymentProvider, 'small');
  }

  /// Средний пакет — автоопределение магазина
  static Future<String> getMediumTokens(WidgetRef ref) async {
    final paymentProvider = await ref.read(paymentProviderTypeProvider.future);
    return _getTokenIdByProvider(paymentProvider, 'medium');
  }

  /// Большой пакет — автоопределение магазина
  static Future<String> getLargeTokens(WidgetRef ref) async {
    final paymentProvider = await ref.read(paymentProviderTypeProvider.future);
    return _getTokenIdByProvider(paymentProvider, 'large');
  }

  /// Получает ID токена по провайдеру и типу
  static String _getTokenIdByProvider(
      PaymentProvider provider, String tokenType) {
    switch (provider) {
      case PaymentProvider.rustore:
        return getRuStoreProductId(tokenType);
      case PaymentProvider.yookassa:
      case PaymentProvider.standardIAP:
        // Для стандартных IAP используем платформенную логику
        switch (tokenType) {
          case 'small':
            return Platform.isIOS ? _smallTokensIOS : _smallTokensAndroid;
          case 'medium':
            return Platform.isIOS ? _mediumTokensIOS : _mediumTokensAndroid;
          case 'large':
            return Platform.isIOS ? _largeTokensIOS : _largeTokensAndroid;
          default:
            throw ArgumentError('Unknown token type: $tokenType');
        }
    }
  }

  /// Устаревшие синхронные методы (для обратной совместимости)
  @Deprecated('Используйте getSmallTokens(ref) для автоопределения магазина')
  static String get smallTokens =>
      Platform.isIOS ? _smallTokensIOS : _smallTokensAndroid;

  @Deprecated('Используйте getMediumTokens(ref) для автоопределения магазина')
  static String get mediumTokens =>
      Platform.isIOS ? _mediumTokensIOS : _mediumTokensAndroid;

  @Deprecated('Используйте getLargeTokens(ref) для автоопределения магазина')
  static String get largeTokens =>
      Platform.isIOS ? _largeTokensIOS : _largeTokensAndroid;

  /// Получает ID продукта для RuStore
  static String getRuStoreProductId(String tokenType) {
    switch (tokenType) {
      case 'small':
        return _smallTokensRuStore;
      case 'medium':
        return _mediumTokensRuStore;
      case 'large':
        return _largeTokensRuStore;
      default:
        throw ArgumentError('Unknown token type: $tokenType');
    }
  }

  /// Получает ID продукта для ЮMoney
  static String getYooMoneyProductId(String tokenType) {
    switch (tokenType) {
      case 'small':
        return _smallTokensYooMoney;
      case 'medium':
        return _mediumTokensYooMoney;
      case 'large':
        return _largeTokensYooMoney;
      default:
        throw ArgumentError('Unknown token type: $tokenType');
    }
  }

  /// Список всех идентификаторов продуктов токенов (для текущей платформы)
  static Set<String> get allTokenProducts => {
        Platform.isIOS ? _smallTokensIOS : _smallTokensAndroid,
        Platform.isIOS ? _mediumTokensIOS : _mediumTokensAndroid,
        Platform.isIOS ? _largeTokensIOS : _largeTokensAndroid,
      };

  /// Список всех идентификаторов продуктов токенов для iOS
  static Set<String> get allTokenProductsiOS => {
        _smallTokensIOS,
        _mediumTokensIOS,
        _largeTokensIOS,
      };

  /// Список всех идентификаторов продуктов токенов для Android
  static Set<String> get allTokenProductsAndroid => {
        _smallTokensAndroid,
        _mediumTokensAndroid,
        _largeTokensAndroid,
      };

  /// Список всех идентификаторов продуктов токенов для RuStore
  static Set<String> get allTokenProductsRuStore => {
        _smallTokensRuStore,
        _mediumTokensRuStore,
        _largeTokensRuStore,
      };

  /// Список всех идентификаторов продуктов токенов для ЮMoney
  static Set<String> get allTokenProductsYooMoney => {
        _smallTokensYooMoney,
        _mediumTokensYooMoney,
        _largeTokensYooMoney,
      };

  /// Получает тип токенов по ID продукта
  static String? getTokenTypeFromProductId(String productId) {
    // iOS
    if (productId == _smallTokensIOS) return 'small';
    if (productId == _mediumTokensIOS) return 'medium';
    if (productId == _largeTokensIOS) return 'large';

    // Android
    if (productId == _smallTokensAndroid) return 'small';
    if (productId == _mediumTokensAndroid) return 'medium';
    if (productId == _largeTokensAndroid) return 'large';

    // RuStore
    if (productId == _smallTokensRuStore) return 'small';
    if (productId == _mediumTokensRuStore) return 'medium';
    if (productId == _largeTokensRuStore) return 'large';

    // ЮMoney
    if (productId == _smallTokensYooMoney) return 'small';
    if (productId == _mediumTokensYooMoney) return 'medium';
    if (productId == _largeTokensYooMoney) return 'large';

    return null;
  }

  /// Получает количество токенов по ID продукта
  static int? getTokenCountFromProductId(String productId) {
    if (productId == _smallTokensRuStore) {
      return CreditPackageType.small.credits;
    }
    if (productId == _mediumTokensRuStore) {
      return CreditPackageType.medium.credits;
    }
    if (productId == _largeTokensRuStore) {
      return CreditPackageType.large.credits;
    }
    if (productId == 'aivideomaker.100k.rustore') {
      return CreditPackageType.small.credits;
    }
    if (productId == 'aivideomaker.300k.rustore') {
      return CreditPackageType.medium.credits;
    }
    if (productId == 'aivideomaker.800k.rustore') {
      return CreditPackageType.large.credits;
    }

    final tokenType = getTokenTypeFromProductId(productId);
    if (tokenType == null) return null;

    switch (tokenType) {
      case 'small':
        return 100000;
      case 'medium':
        return 300000;
      case 'large':
        return 800000;
      default:
        return null;
    }
  }

  /// Получает цену в рублях по ID продукта (для RuStore и ЮMoney)
  static double? getPriceInRubFromProductId(String productId) {
    if (productId == _smallTokensRuStore) {
      return CreditPackageType.small.priceRub.toDouble();
    }
    if (productId == _mediumTokensRuStore) {
      return CreditPackageType.medium.priceRub.toDouble();
    }
    if (productId == _largeTokensRuStore) {
      return CreditPackageType.large.priceRub.toDouble();
    }

    final tokenType = getTokenTypeFromProductId(productId);
    if (tokenType == null) return null;

    switch (tokenType) {
      case 'small':
        return 99.0;
      case 'medium':
        return 199.0;
      case 'large':
        return 499.0;
      default:
        return null;
    }
  }

  /// Проверяет, является ли ID продукта токенным продуктом
  static bool isTokenProduct(String productId) {
    return getTokenTypeFromProductId(productId) != null;
  }

  /// Получает магазин по ID продукта
  static String? getStoreFromProductId(String productId) {
    if (allTokenProductsiOS.contains(productId)) return 'ios';
    if (allTokenProductsAndroid.contains(productId)) return 'android';
    if (allTokenProductsRuStore.contains(productId)) return 'rustore';
    if (allTokenProductsYooMoney.contains(productId)) return 'yoomoney';
    return null;
  }

  /// Получает список продуктов для текущей платформы
  static List<Map<String, dynamic>> getProductsForCurrentPlatform() {
    final products = <Map<String, dynamic>>[];

    if (Platform.isIOS) {
      products.addAll([
        {
          'id': _smallTokensIOS,
          'type': 'small',
          'tokens': 100000,
          'title': 'Стартовый пакет',
          'description': '100,000 токенов\n~200 подробных запросов',
        },
        {
          'id': _mediumTokensIOS,
          'type': 'medium',
          'tokens': 300000,
          'title': 'Популярный пакет',
          'description': '300,000 токенов\n~600 подробных запросов',
        },
        {
          'id': _largeTokensIOS,
          'type': 'large',
          'tokens': 800000,
          'title': 'Максимальный пакет',
          'description': '800,000 токенов\n~1600 подробных запросов',
        },
      ]);
    } else {
      products.addAll([
        {
          'id': _smallTokensAndroid,
          'type': 'small',
          'tokens': 100000,
          'title': 'Стартовый пакет',
          'description': '100,000 токенов\n~200 подробных запросов',
        },
        {
          'id': _mediumTokensAndroid,
          'type': 'medium',
          'tokens': 300000,
          'title': 'Популярный пакет',
          'description': '300,000 токенов\n~600 подробных запросов',
        },
        {
          'id': _largeTokensAndroid,
          'type': 'large',
          'tokens': 800000,
          'title': 'Максимальный пакет',
          'description': '800,000 токенов\n~1600 подробных запросов',
        },
      ]);
    }

    return products;
  }

  /// Получает список продуктов для RuStore с ценами
  static List<Map<String, dynamic>> getRuStoreProducts() {
    return [
      {
        'id': _smallTokensRuStore,
        'type': 'small',
        'credits': CreditPackageType.small.credits,
        'price': CreditPackageType.small.priceRub.toDouble(),
        'currency': 'RUB',
        'title': 'Малый пакет кредитов',
        'description': '${CreditPackageType.small.credits} кредитов',
      },
      {
        'id': _mediumTokensRuStore,
        'type': 'medium',
        'credits': CreditPackageType.medium.credits,
        'price': CreditPackageType.medium.priceRub.toDouble(),
        'currency': 'RUB',
        'title': 'Средний пакет кредитов',
        'description': '${CreditPackageType.medium.credits} кредитов',
      },
      {
        'id': _largeTokensRuStore,
        'type': 'large',
        'credits': CreditPackageType.large.credits,
        'price': CreditPackageType.large.priceRub.toDouble(),
        'currency': 'RUB',
        'title': 'Большой пакет кредитов',
        'description': '${CreditPackageType.large.credits} кредитов',
      },
    ];
  }

  /// Получает список продуктов для ЮMoney с ценами
  static List<Map<String, dynamic>> getYooMoneyProducts() {
    return [
      {
        'id': _smallTokensYooMoney,
        'type': 'small',
        'tokens': 100000,
        'price': 99.0,
        'currency': 'RUB',
        'title': 'Стартовый пакет',
        'description': '100,000 токенов\n~200 подробных запросов',
      },
      {
        'id': _mediumTokensYooMoney,
        'type': 'medium',
        'tokens': 300000,
        'price': 199.0,
        'currency': 'RUB',
        'title': 'Популярный пакет',
        'description': '300,000 токенов\n~600 подробных запросов',
      },
      {
        'id': _largeTokensYooMoney,
        'type': 'large',
        'tokens': 800000,
        'price': 499.0,
        'currency': 'RUB',
        'title': 'Максимальный пакет',
        'description': '800,000 токенов\n~1600 подробных запросов',
      },
    ];
  }
}
