import 'meal_model.dart';

/// Модель избранного блюда (шаблон), которую можно быстро добавить в историю
class FavoriteMealModel {
  final String id;
  final String name;
  final String? imagePath;
  final List<IngredientModel> ingredients;
  final MealNutrientsModel nutrients;
  final double healthiness;

  const FavoriteMealModel({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.ingredients,
    required this.nutrients,
    this.healthiness = 0,
  });

  FavoriteMealModel copyWith({
    String? id,
    String? name,
    String? imagePath,
    List<IngredientModel>? ingredients,
    MealNutrientsModel? nutrients,
    double? healthiness,
  }) {
    return FavoriteMealModel(
      id: id ?? this.id,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      ingredients: ingredients ?? this.ingredients,
      nutrients: nutrients ?? this.nutrients,
      healthiness: healthiness ?? this.healthiness,
    );
  }

  factory FavoriteMealModel.fromMeal(MealModel meal) {
    return FavoriteMealModel(
      id: meal.id,
      name: meal.name,
      imagePath: meal.imagePath,
      ingredients: meal.ingredients,
      nutrients: meal.nutrients,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imagePath': imagePath,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'nutrients': nutrients.toJson(),
        'healthiness': healthiness,
      };

  factory FavoriteMealModel.fromJson(Map<String, dynamic> json) {
    return FavoriteMealModel(
      id: json['id'] as String,
      name: json['name'] as String,
      imagePath: json['imagePath'] as String?,
      ingredients: (json['ingredients'] as List<dynamic>)
          .map((e) => IngredientModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      nutrients: MealNutrientsModel.fromJson(
          json['nutrients'] as Map<String, dynamic>),
      healthiness: (json['healthiness'] as num?)?.toDouble() ?? 0,
    );
  }
}
