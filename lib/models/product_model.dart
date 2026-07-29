import 'package:in_app_purchase/in_app_purchase.dart';
import 'subscription_model.dart';
import 'store_product_model.dart';

/// Модель для продукта в магазине приложений
class ProductModel {
  /// Детали продукта из магазина
  final ProductDetails productDetails;

  /// Соответствующий тип подписки
  final SubscriptionType subscriptionType;

  /// Длительность подписки в днях
  final int durationInDays;

  /// Есть ли у продукта пробный период
  final bool hasTrial;

  /// Длительность пробного периода в днях (если есть)
  final int trialDurationInDays;

  /// Число доступных запросов для данного продукта
  final int maxRequests;

  /// Является ли текущий продукт "рекомендуемым"
  final bool isRecommended;

  /// Конструктор модели продукта
  const ProductModel({
    required this.productDetails,
    required this.subscriptionType,
    required this.durationInDays,
    this.hasTrial = false,
    this.trialDurationInDays = 0,
    required this.maxRequests,
    this.isRecommended = false,
  });

  /// Цена продукта в виде строки
  String get price => productDetails.price;

  /// Идентификатор продукта
  String get id => productDetails.id;

  /// Название продукта
  String get title => productDetails.title;

  /// Описание продукта
  String get description => productDetails.description;

  /// Получение типа подписки на основе идентификатора продукта
  static SubscriptionType getSubscriptionTypeFromProductId(String productId) {
    switch (productId) {
      // iOS
      case 'aivideomakerWeek':
      // Android
      case 'aivideomaker.weekly.subscription':
        return SubscriptionType.weekly;

      // iOS
      case 'aivideomakerMonth':
      // Android
      case 'aivideomaker.monthly.subscription':
        return SubscriptionType.monthly;

      // iOS
      case 'aivideomakerYear':
      // Android
      case 'aivideomaker.yearly.subscription':
        return SubscriptionType.yearly;

      default:
        return SubscriptionType.free;
    }
  }

  /// Создание модели продукта из ProductDetails
  factory ProductModel.fromProductDetails(ProductDetails productDetails) {
    switch (productDetails.id) {
      // iOS weekly
      case 'aivideomakerWeek':
      // Android weekly
      case 'aivideomaker.weekly.subscription':
        return ProductModel(
          productDetails: productDetails,
          subscriptionType: SubscriptionType.weekly,
          durationInDays: 7,
          maxRequests: 100,
        );

      // iOS monthly
      case 'aivideomakerMonth':
      // Android monthly
      case 'aivideomaker.monthly.subscription':
        return ProductModel(
          productDetails: productDetails,
          subscriptionType: SubscriptionType.monthly,
          durationInDays: 30,
          maxRequests: 500,
          isRecommended: true,
        );

      // iOS yearly
      case 'aivideomakerYear':
      // Android yearly
      case 'aivideomaker.yearly.subscription':
        return ProductModel(
          productDetails: productDetails,
          subscriptionType: SubscriptionType.yearly,
          durationInDays: 365,
          hasTrial: true,
          trialDurationInDays: 7,
          maxRequests: 9999,
        );

      default:
        throw ArgumentError(
            'Неизвестный идентификатор продукта: ${productDetails.id}');
    }
  }

  /// Создание модели продукта из StoreProductModel (для RuStore)
  factory ProductModel.fromStoreProduct(StoreProductModel storeProduct) {
    // Создаем фиктивный ProductDetails для совместимости
    final fakeProductDetails = _FakeProductDetails(
      id: storeProduct.id,
      title: storeProduct.title,
      description: storeProduct.description,
      price: storeProduct.price,
    );

    SubscriptionType subscriptionType;
    int durationInDays;
    int maxRequests;
    bool isRecommended = false;
    bool hasTrial = false;
    int trialDurationInDays = 0;

    switch (storeProduct.period) {
      case 'weekly':
        subscriptionType = SubscriptionType.weekly;
        durationInDays = 7;
        maxRequests = 100;
        break;
      case 'monthly':
        subscriptionType = SubscriptionType.monthly;
        durationInDays = 30;
        maxRequests = 500;
        isRecommended = storeProduct.isPopular;
        break;
      case 'yearly':
        subscriptionType = SubscriptionType.yearly;
        durationInDays = 365;
        maxRequests = 9999;
        // Для российских пользователей RuStore не предоставляем пробный период
        hasTrial = false;
        trialDurationInDays = 0;
        break;
      default:
        subscriptionType = SubscriptionType.free;
        durationInDays = 0;
        maxRequests = 0;
    }

    return ProductModel(
      productDetails: fakeProductDetails,
      subscriptionType: subscriptionType,
      durationInDays: durationInDays,
      maxRequests: maxRequests,
      isRecommended: isRecommended,
      hasTrial: hasTrial,
      trialDurationInDays: trialDurationInDays,
    );
  }
}

/// Фиктивная реализация ProductDetails для совместимости с RuStore
class _FakeProductDetails implements ProductDetails {
  @override
  final String id;

  @override
  final String title;

  @override
  final String description;

  @override
  final String price;

  @override
  final double rawPrice;

  @override
  final String currencyCode;

  @override
  final String currencySymbol;

  _FakeProductDetails({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  })  : rawPrice = _parsePrice(price),
        currencyCode = 'RUB',
        currencySymbol = '₽';

  static double _parsePrice(String price) {
    // Извлекаем числовое значение из строки цены
    final numericString =
        price.replaceAll(RegExp(r'[^\d.,]'), '').replaceAll(',', '.');
    return double.tryParse(numericString) ?? 0.0;
  }
}
