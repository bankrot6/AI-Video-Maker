/// Модель для продуктов из магазина (RuStore, Google Play, App Store)
class StoreProductModel {
  /// ID продукта в магазине
  final String id;

  /// Название продукта
  final String title;

  /// Период подписки (weekly, monthly, yearly)
  final String period;

  /// Цена в формате строки (например, "159 ₽")
  final String price;

  /// Первоначальная цена (для отображения скидки)
  final String originalPrice;

  /// Код валюты
  final String currency;

  /// Числовое значение цены
  final double priceValue;

  /// Описание продукта
  final String description;

  /// Является ли продукт популярным
  final bool isPopular;

  const StoreProductModel({
    required this.id,
    required this.title,
    required this.period,
    required this.price,
    required this.originalPrice,
    required this.currency,
    required this.priceValue,
    required this.description,
    this.isPopular = false,
  });

  /// Создает копию модели с обновленными параметрами
  StoreProductModel copyWith({
    String? id,
    String? title,
    String? period,
    String? price,
    String? originalPrice,
    String? currency,
    double? priceValue,
    String? description,
    bool? isPopular,
  }) {
    return StoreProductModel(
      id: id ?? this.id,
      title: title ?? this.title,
      period: period ?? this.period,
      price: price ?? this.price,
      originalPrice: originalPrice ?? this.originalPrice,
      currency: currency ?? this.currency,
      priceValue: priceValue ?? this.priceValue,
      description: description ?? this.description,
      isPopular: isPopular ?? this.isPopular,
    );
  }

  @override
  String toString() {
    return 'StoreProductModel(id: $id, title: $title, period: $period, price: $price)';
  }
}
