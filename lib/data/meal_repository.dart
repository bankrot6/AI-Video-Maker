import '../models/meal_model.dart';

/// Абстрактный интерфейс для репозитория приемов пищи
abstract class MealRepository {
  /// Получает список приемов пищи за указанный день
  Future<List<MealModel>> getMealsForDay(DateTime date);

  /// Получает прием пищи по идентификатору
  Future<MealModel?> getMealById(String id);

  /// Сохраняет прием пищи
  Future<void> saveMeal(MealModel meal);

  /// Обновляет прием пищи
  Future<void> updateMeal(MealModel meal);

  /// Удаляет прием пищи
  Future<void> deleteMeal(String id);

  /// Получает сумму нутриентов за день
  Future<MealNutrientsModel> getDailyNutrientsTotal(DateTime date);

  /// Получает историю приемов пищи за период
  Future<List<MealModel>> getMealHistory(DateTime startDate, DateTime endDate);
}
