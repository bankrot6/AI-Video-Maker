/// Типы блюд для классификации
enum DishType {
  /// Супы
  soup,

  /// Салаты
  salad,

  /// Основные блюда
  mainCourse,

  /// Десерты
  dessert,

  /// Закуски
  appetizer,

  /// Напитки
  drink,

  /// Завтраки
  breakfast,

  /// Выпечка и хлеб
  bakery,

  /// Другое
  other;

  /// Возвращает локализованное название типа блюда
  String getLocalizedName() {
    switch (this) {
      case DishType.soup:
        return 'Суп';
      case DishType.salad:
        return 'Салат';
      case DishType.mainCourse:
        return 'Основное блюдо';
      case DishType.dessert:
        return 'Десерт';
      case DishType.appetizer:
        return 'Закуска';
      case DishType.drink:
        return 'Напиток';
      case DishType.breakfast:
        return 'Завтрак';
      case DishType.bakery:
        return 'Выпечка';
      case DishType.other:
        return 'Другое';
    }
  }

  /// Определяет тип блюда по его названию
  static DishType fromName(String name) {
    name = name.toLowerCase();

    if (name.contains('суп') ||
        name.contains('борщ') ||
        name.contains('щи') ||
        name.contains('уха')) {
      return DishType.soup;
    } else if (name.contains('салат')) {
      return DishType.salad;
    } else if (name.contains('торт') ||
        name.contains('пирожное') ||
        name.contains('мороженое') ||
        name.contains('десерт')) {
      return DishType.dessert;
    } else if (name.contains('закуска') ||
        name.contains('тарталетки') ||
        name.contains('канапе')) {
      return DishType.appetizer;
    } else if (name.contains('сок') ||
        name.contains('чай') ||
        name.contains('кофе') ||
        name.contains('напиток')) {
      return DishType.drink;
    } else if (name.contains('завтрак') ||
        name.contains('омлет') ||
        name.contains('яичница') ||
        name.contains('каша')) {
      return DishType.breakfast;
    } else if (name.contains('хлеб') ||
        name.contains('булочка') ||
        name.contains('пирог') ||
        name.contains('выпечка')) {
      return DishType.bakery;
    } else {
      return DishType.mainCourse; // По умолчанию считаем основным блюдом
    }
  }
}
