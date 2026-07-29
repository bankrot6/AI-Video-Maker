import '../models/meal_model.dart';

/// Абстрактный интерфейс для репозитория питательных веществ
abstract class NutrientsRepository {
  /// Получение питательной ценности по названию продукта
  Future<MealNutrientsModel?> getNutrientsByFoodName(String foodName);

  /// Проверка, является ли строка названием продукта
  bool isFoodItem(String foodName);

  /// Получение предложений для автозаполнения на основе частичного ввода
  List<String> getFoodSuggestions(String partial);

  /// Получение категории продукта
  String? getFoodCategory(String foodName);

  /// Получение синонимов/альтернативных названий продукта
  List<String> getFoodSynonyms(String foodName);

  /// Расчет питательной ценности для списка ингредиентов
  MealNutrientsModel calculateNutrientsForIngredients(
      List<IngredientModel> ingredients);

  /// Получение рекомендуемой дневной нормы питательных веществ
  Future<MealNutrientsModel> getRecommendedDailyNutrients();
}
