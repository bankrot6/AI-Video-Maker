import '../models/meal_model.dart';

/// Класс для работы с базой данных продуктов и их питательной ценности
///
/// В реальном приложении здесь была бы интеграция с внешним API, например, Spoonacular
/// или локальная база данных. Для демонстрации используем упрощенный вариант с
/// ограниченным набором продуктов.
class FoodNutrientsDatabase {
  // Хэш-таблица для хранения питательной ценности продуктов
  // Ключ - название продукта, значение - информация о питательной ценности
  final Map<String, MealNutrientsModel> _nutrientsData = {
    'apple': MealNutrientsModel(
      calories: 52,
      proteins: 0.3,
      fats: 0.2,
      carbs: 14.0,
      fiber: 2.4,
      sugar: 10.3,
    ),
    'banana': MealNutrientsModel(
      calories: 89,
      proteins: 1.1,
      fats: 0.3,
      carbs: 22.8,
      fiber: 2.6,
      sugar: 12.2,
    ),
    'chicken': MealNutrientsModel(
      calories: 165,
      proteins: 31.0,
      fats: 3.6,
      carbs: 0.0,
    ),
    'rice': MealNutrientsModel(
      calories: 130,
      proteins: 2.7,
      fats: 0.3,
      carbs: 28.0,
      fiber: 0.4,
    ),
    'bread': MealNutrientsModel(
      calories: 265,
      proteins: 9.0,
      fats: 3.2,
      carbs: 49.0,
      fiber: 2.7,
    ),
    'egg': MealNutrientsModel(
      calories: 155,
      proteins: 12.6,
      fats: 10.6,
      carbs: 1.1,
    ),
    'milk': MealNutrientsModel(
      calories: 42,
      proteins: 3.4,
      fats: 1.0,
      carbs: 5.0,
      sugar: 5.0,
    ),
    'carrot': MealNutrientsModel(
      calories: 41,
      proteins: 0.9,
      fats: 0.2,
      carbs: 10.0,
      fiber: 2.8,
      sugar: 4.7,
    ),
    'tomato': MealNutrientsModel(
      calories: 18,
      proteins: 0.9,
      fats: 0.2,
      carbs: 3.9,
      fiber: 1.2,
      sugar: 2.6,
    ),
    'cheese': MealNutrientsModel(
      calories: 402,
      proteins: 25.0,
      fats: 33.0,
      carbs: 1.3,
      sugar: 0.1,
    ),
    'potato': MealNutrientsModel(
      calories: 77,
      proteins: 2.0,
      fats: 0.1,
      carbs: 17.0,
      fiber: 2.2,
    ),
    'beef': MealNutrientsModel(
      calories: 250,
      proteins: 26.0,
      fats: 17.0,
      carbs: 0.0,
    ),
    'pasta': MealNutrientsModel(
      calories: 158,
      proteins: 5.8,
      fats: 0.9,
      carbs: 31.0,
      fiber: 1.8,
    ),
    'cucumber': MealNutrientsModel(
      calories: 15,
      proteins: 0.7,
      fats: 0.1,
      carbs: 3.6,
      fiber: 0.5,
      sugar: 1.7,
    ),
    'orange': MealNutrientsModel(
      calories: 47,
      proteins: 0.9,
      fats: 0.1,
      carbs: 11.8,
      fiber: 2.4,
      sugar: 9.4,
    ),
  };

  /// Список синонимов и связанных слов для улучшения поиска
  final Map<String, List<String>> _synonyms = {
    'apple': ['яблоко', 'fruit', 'фрукт'],
    'banana': ['банан', 'fruit', 'фрукт'],
    'chicken': ['курица', 'chicken breast', 'куриная грудка', 'meat', 'мясо'],
    'rice': [
      'рис',
      'brown rice',
      'white rice',
      'бурый рис',
      'белый рис',
      'grain',
      'зерно'
    ],
    'bread': [
      'хлеб',
      'white bread',
      'wheat bread',
      'белый хлеб',
      'пшеничный хлеб'
    ],
    'egg': ['яйцо', 'eggs', 'яйца', 'boiled egg', 'вареное яйцо'],
    'milk': ['молоко', 'dairy', 'молочное'],
    'carrot': ['морковь', 'морковка', 'vegetable', 'овощ'],
    'tomato': ['помидор', 'томат', 'vegetable', 'овощ'],
    'cheese': ['сыр', 'dairy', 'молочное'],
    'potato': ['картофель', 'картошка', 'vegetable', 'овощ'],
    'beef': ['говядина', 'beef steak', 'говяжий стейк', 'meat', 'мясо'],
    'pasta': ['макароны', 'спагетти', 'паста', 'grain', 'зерно'],
    'cucumber': ['огурец', 'vegetable', 'овощ'],
    'orange': ['апельсин', 'fruit', 'фрукт'],
  };

  /// Список категорий продуктов для классификации
  final Map<String, List<String>> _categories = {
    'fruit': ['apple', 'banana', 'orange'],
    'vegetable': ['carrot', 'tomato', 'potato', 'cucumber'],
    'meat': ['chicken', 'beef'],
    'dairy': ['milk', 'cheese'],
    'grain': ['rice', 'bread', 'pasta'],
  };

  /// Проверяет, является ли данная строка названием продукта питания
  bool isFoodItem(String label) {
    // Приводим к нижнему регистру для унификации
    final normalizedLabel = label.toLowerCase();

    // Прямая проверка в базе данных
    if (_nutrientsData.containsKey(normalizedLabel)) {
      return true;
    }

    // Проверка по синонимам
    for (final entry in _synonyms.entries) {
      if (entry.value.contains(normalizedLabel)) {
        return true;
      }
    }

    // Проверка по категориям
    for (final entry in _categories.entries) {
      if (normalizedLabel == entry.key || normalizedLabel.contains(entry.key)) {
        return true;
      }
    }

    return false;
  }

  /// Получает питательную ценность продукта по его названию
  Future<MealNutrientsModel?> getNutritionData(String foodName) async {
    // Имитация задержки сетевого запроса
    await Future.delayed(const Duration(milliseconds: 200));

    // Приводим к нижнему регистру для унификации
    final normalizedName = foodName.toLowerCase();

    // Прямой поиск в базе данных
    if (_nutrientsData.containsKey(normalizedName)) {
      return _nutrientsData[normalizedName];
    }

    // Поиск по синонимам
    for (final entry in _synonyms.entries) {
      if (entry.value.contains(normalizedName)) {
        return _nutrientsData[entry.key];
      }
    }

    // Поиск по категориям
    for (final category in _categories.entries) {
      if (normalizedName == category.key ||
          normalizedName.contains(category.key)) {
        // Если найдена категория, возвращаем усредненные данные по этой категории
        return _getAverageNutrientsForCategory(category.key);
      }
    }

    // Если ничего не найдено, возвращаем null
    return null;
  }

  /// Вычисляет средние значения питательных веществ для категории продуктов
  MealNutrientsModel _getAverageNutrientsForCategory(String category) {
    final products = _categories[category];
    if (products == null || products.isEmpty) {
      return MealNutrientsModel(calories: 0, proteins: 0, fats: 0, carbs: 0);
    }

    int totalCalories = 0;
    double totalProteins = 0;
    double totalFats = 0;
    double totalCarbs = 0;
    double totalFiber = 0;
    double totalSugar = 0;

    for (final product in products) {
      final nutrient = _nutrientsData[product];
      if (nutrient != null) {
        totalCalories += nutrient.calories;
        totalProteins += nutrient.proteins;
        totalFats += nutrient.fats;
        totalCarbs += nutrient.carbs;
        totalFiber += nutrient.fiber ?? 0;
        totalSugar += nutrient.sugar ?? 0;
      }
    }

    final count = products.length;

    return MealNutrientsModel(
      calories: (totalCalories / count).round(),
      proteins: totalProteins / count,
      fats: totalFats / count,
      carbs: totalCarbs / count,
      fiber: totalFiber / count,
      sugar: totalSugar / count,
    );
  }
}
