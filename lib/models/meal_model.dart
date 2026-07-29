import 'package:equatable/equatable.dart';

/// Константы единиц измерения для ингредиентов
class IngredientUnits {
  /// Граммы
  static const String GRAMS = 'g';

  /// Миллилитры
  static const String MILLILITERS = 'ml';

  /// Штуки
  static const String PIECES = 'pcs';

  /// Приватный конструктор для запрета создания экземпляров
  IngredientUnits._();
}

class MealModel extends Equatable {
  final String id;
  final String name;
  final DateTime dateTime;
  final String? imagePath;
  final List<IngredientModel> ingredients;
  final MealNutrientsModel nutrients;
  final double healthiness; // 0..5, оценка полезности блюда

  const MealModel({
    required this.id,
    required this.name,
    required this.dateTime,
    this.imagePath,
    required this.ingredients,
    required this.nutrients,
    this.healthiness = 0,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        dateTime,
        imagePath,
        ingredients,
        nutrients,
        healthiness,
      ];

  factory MealModel.fromJson(Map<String, dynamic> json) {
    return MealModel(
      id: json['id'] as String,
      name: json['name'] as String,
      dateTime: DateTime.parse(json['dateTime'] as String),
      imagePath: json['imagePath'] as String?,
      ingredients: (json['ingredients'] as List<dynamic>)
          .map((e) => IngredientModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      nutrients: MealNutrientsModel.fromJson(
          json['nutrients'] as Map<String, dynamic>),
      healthiness: (json['healthiness'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'dateTime': dateTime.toIso8601String(),
      'imagePath': imagePath,
      'ingredients': ingredients.map((e) => e.toJson()).toList(),
      'nutrients': nutrients.toJson(),
      'healthiness': healthiness,
    };
  }
}

class IngredientModel extends Equatable {
  final String name;
  final double quantity; // грамм
  final String unit;

  const IngredientModel({
    required this.name,
    required this.quantity,
    this.unit = IngredientUnits.GRAMS,
  });

  @override
  List<Object?> get props => [
        name,
        quantity,
        unit,
      ];

  factory IngredientModel.fromJson(Map<String, dynamic> json) {
    return IngredientModel(
      name: json['name'] as String,
      quantity: json['quantity'] as double,
      unit: json['unit'] as String? ?? IngredientUnits.GRAMS,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
    };
  }
}

class MealNutrientsModel extends Equatable {
  final int calories;
  final double proteins;
  final double fats;
  final double carbs;
  final double fiber;
  final double sugar;
  final DateTime? dateTime;

  const MealNutrientsModel({
    required this.calories,
    required this.proteins,
    required this.fats,
    required this.carbs,
    this.fiber = 0,
    this.sugar = 0,
    this.dateTime,
  });

  @override
  List<Object?> get props => [
        calories,
        proteins,
        fats,
        carbs,
        fiber,
        sugar,
        dateTime,
      ];

  /// Создает пустой объект с нулевыми значениями
  factory MealNutrientsModel.empty() {
    return const MealNutrientsModel(
      calories: 0,
      proteins: 0,
      fats: 0,
      carbs: 0,
      fiber: 0,
      sugar: 0,
    );
  }

  factory MealNutrientsModel.fromJson(Map<String, dynamic> json) {
    return MealNutrientsModel(
      calories: json['calories'] as int,
      proteins: json['proteins'] as double,
      fats: json['fats'] as double,
      carbs: json['carbs'] as double,
      fiber: json['fiber'] as double? ?? 0,
      sugar: json['sugar'] as double? ?? 0,
      dateTime: json['dateTime'] != null
          ? DateTime.parse(json['dateTime'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'calories': calories,
      'proteins': proteins,
      'fats': fats,
      'carbs': carbs,
      'fiber': fiber,
      'sugar': sugar,
      'dateTime': dateTime?.toIso8601String(),
    };
  }

  /// Создает копию объекта с возможностью изменения отдельных полей
  MealNutrientsModel copyWith({
    int? calories,
    double? proteins,
    double? fats,
    double? carbs,
    double? fiber,
    double? sugar,
    DateTime? dateTime,
  }) {
    return MealNutrientsModel(
      calories: calories ?? this.calories,
      proteins: proteins ?? this.proteins,
      fats: fats ?? this.fats,
      carbs: carbs ?? this.carbs,
      fiber: fiber ?? this.fiber,
      sugar: sugar ?? this.sugar,
      dateTime: dateTime ?? this.dateTime,
    );
  }
}
