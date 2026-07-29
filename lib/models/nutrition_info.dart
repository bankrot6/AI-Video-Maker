import 'package:equatable/equatable.dart';
import 'ingredient.dart';

class NutritionInfo extends Equatable {
  final String dishName;
  final double calories;
  final double proteins;
  final double fats;
  final double carbs;
  final double healthiness; // 0..5
  final List<Ingredient> ingredients;
  final String? imagePath;
  final String? error;

  const NutritionInfo({
    required this.dishName,
    required this.calories,
    required this.proteins,
    required this.fats,
    required this.carbs,
    this.healthiness = 0,
    this.ingredients = const [],
    this.imagePath,
    this.error,
  });

  factory NutritionInfo.empty() {
    return const NutritionInfo(
      dishName: '',
      calories: 0,
      proteins: 0,
      fats: 0,
      carbs: 0,
      healthiness: 0,
      ingredients: [],
      imagePath: null,
      error: null,
    );
  }

  @override
  List<Object?> get props => [
        dishName,
        calories,
        proteins,
        fats,
        carbs,
        healthiness,
        ingredients,
        imagePath,
        error
      ];

  NutritionInfo copyWith({
    String? dishName,
    double? calories,
    double? proteins,
    double? fats,
    double? carbs,
    double? healthiness,
    List<Ingredient>? ingredients,
    String? imagePath,
    String? error,
  }) {
    return NutritionInfo(
      dishName: dishName ?? this.dishName,
      calories: calories ?? this.calories,
      proteins: proteins ?? this.proteins,
      fats: fats ?? this.fats,
      carbs: carbs ?? this.carbs,
      healthiness: healthiness ?? this.healthiness,
      ingredients: ingredients ?? this.ingredients,
      imagePath: imagePath ?? this.imagePath,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dishName': dishName,
      'calories': calories,
      'proteins': proteins,
      'fats': fats,
      'carbs': carbs,
      'healthiness': healthiness,
      'ingredients': ingredients.map((e) => e.toJson()).toList(),
      'imagePath': imagePath,
      'error': error,
    };
  }

  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    List<Ingredient> ingredients = [];
    if (json['ingredients'] != null) {
      ingredients = (json['ingredients'] as List)
          .map((item) => Ingredient.fromJson(item as Map<String, dynamic>))
          .toList();
    }

    return NutritionInfo(
      dishName: json['dishName'] ?? '',
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      proteins: (json['proteins'] as num?)?.toDouble() ?? 0,
      fats: (json['fats'] as num?)?.toDouble() ?? 0,
      carbs: (json['carbs'] as num?)?.toDouble() ?? 0,
      healthiness: (json['healthiness'] as num?)?.toDouble() ?? 0,
      ingredients: ingredients,
      imagePath: json['imagePath'],
      error: json['error'],
    );
  }
}
