import '../../models/meal_model.dart';

/// Репозиторий для работы с данными о питании
abstract class MealRepository {
  /// Получает информацию о питательной ценности продукта по его названию
  /// Возвращает null, если информация не найдена
  Future<MealNutrientsModel?> getFoodNutrients(String foodName);

  /// Сохраняет информацию о приеме пищи
  Future<void> saveMeal(MealModel meal);

  /// Получает список приемов пищи за указанный день
  Future<List<MealModel>> getMealsForDay(DateTime date);
}

/// Реализация репозитория с мок-данными
class MockMealRepository implements MealRepository {
  // Словарь с информацией о питательной ценности продуктов
  final Map<String, MealNutrientsModel> _foodDatabase = {
    'яблоко': MealNutrientsModel(
      calories: 52,
      proteins: 0.3,
      fats: 0.4,
      carbs: 14.0,
      fiber: 2.4,
      sugar: 10.3,
    ),
    'банан': MealNutrientsModel(
      calories: 89,
      proteins: 1.1,
      fats: 0.3,
      carbs: 22.8,
      fiber: 2.6,
      sugar: 12.2,
    ),
    'овощи': MealNutrientsModel(
      calories: 65,
      proteins: 2.0,
      fats: 0.6,
      carbs: 13.0,
      fiber: 3.8,
      sugar: 3.2,
    ),
  };

  final List<MealModel> _meals = [];

  @override
  Future<MealNutrientsModel?> getFoodNutrients(String foodName) async {
    // Имитируем задержку сети
    await Future.delayed(const Duration(milliseconds: 300));
    return _foodDatabase[foodName.toLowerCase()];
  }

  @override
  Future<void> saveMeal(MealModel meal) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _meals.add(meal);
  }

  @override
  Future<List<MealModel>> getMealsForDay(DateTime date) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _meals
        .where((meal) =>
            meal.dateTime.year == date.year &&
            meal.dateTime.month == date.month &&
            meal.dateTime.day == date.day)
        .toList();
  }
}
