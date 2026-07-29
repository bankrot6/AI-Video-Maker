import 'package:flutter/foundation.dart';

enum MealType { breakfast, lunch, dinner, snack }

class MealItem {
  final MealType type;
  final String name;
  final int calories;
  final String imageUrl;

  MealItem({
    required this.type,
    required this.name,
    required this.calories,
    required this.imageUrl,
  });

  factory MealItem.fromJson(Map<String, dynamic> json) {
    return MealItem(
      type: _parseMealType(json['type']),
      name: json['name'] ?? '',
      calories: json['calories'] ?? 0,
      imageUrl: json['imageUrl'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': describeEnum(type),
      'name': name,
      'calories': calories,
      'imageUrl': imageUrl,
    };
  }

  static MealType _parseMealType(dynamic value) {
    // Если значение null, возвращаем breakfast по умолчанию
    if (value == null) return MealType.breakfast;

    // Преобразуем в строку для безопасного сравнения
    final String typeStr = value.toString().toLowerCase().trim();

    // Проверяем все возможные варианты
    if (typeStr.contains('break') || typeStr == 'b' || typeStr == 'завтрак') {
      return MealType.breakfast;
    } else if (typeStr.contains('lunch') ||
        typeStr == 'l' ||
        typeStr == 'обед') {
      return MealType.lunch;
    } else if (typeStr.contains('dinn') ||
        typeStr == 'd' ||
        typeStr == 'ужин') {
      return MealType.dinner;
    } else if (typeStr.contains('snack') ||
        typeStr == 's' ||
        typeStr == 'перекус') {
      return MealType.snack;
    }

    // Если ничего не подошло, возвращаем breakfast по умолчанию
    return MealType.breakfast;
  }
}

class MealPlanModel {
  final int totalCalories;
  final List<MealItem> meals;

  MealPlanModel({
    required this.totalCalories,
    required this.meals,
  });

  factory MealPlanModel.fromJson(Map<String, dynamic> json) {
    // Безопасное получение списка блюд
    List<MealItem> parsedMeals = [];

    try {
      if (json['meals'] != null) {
        if (json['meals'] is List) {
          parsedMeals = (json['meals'] as List)
              .map((mealJson) => MealItem.fromJson(
                  mealJson is Map<String, dynamic> ? mealJson : {}))
              .toList();
        }
      }
    } catch (e) {
      // В случае ошибки возвращаем пустой список
      parsedMeals = [];
    }

    // Если список пуст, создаем значения по умолчанию
    if (parsedMeals.isEmpty) {
      // Добавляем стандартные блюда, если список пуст
      final calories = json['totalCalories'] as int? ?? 2000;
      final breakfastCal = (calories * 0.25).round();
      final lunchCal = (calories * 0.35).round();
      final dinnerCal = (calories * 0.25).round();
      final snackCal = (calories * 0.15).round();

      parsedMeals = [
        MealItem(
          type: MealType.breakfast,
          name: 'Цельнозерновые блины с кленовым сиропом',
          calories: breakfastCal,
          imageUrl: '',
        ),
        MealItem(
          type: MealType.lunch,
          name: 'Куриный салат Цезарь с гриля',
          calories: lunchCal,
          imageUrl: '',
        ),
        MealItem(
          type: MealType.dinner,
          name: 'Запеченный лосось с киноа и брокколи',
          calories: dinnerCal,
          imageUrl: '',
        ),
        MealItem(
          type: MealType.snack,
          name: 'Кукурузные чипсы с сальсой',
          calories: snackCal,
          imageUrl: '',
        ),
      ];
    }

    return MealPlanModel(
      totalCalories: json['totalCalories'] as int? ?? 2000,
      meals: parsedMeals,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalCalories': totalCalories,
      'meals': meals.map((meal) => meal.toJson()).toList(),
    };
  }

  /// Возвращает план питания по умолчанию
  static MealPlanModel getDefaultMealPlan() {
    return MealPlanModel(
      totalCalories: 2000,
      meals: [
        MealItem(
          type: MealType.breakfast,
          name: 'Овсянка с фруктами',
          calories: 350,
          imageUrl: '',
        ),
        MealItem(
          type: MealType.lunch,
          name: 'Салат Цезарь с курицей',
          calories: 450,
          imageUrl: '',
        ),
        MealItem(
          type: MealType.dinner,
          name: 'Запеченный лосось с овощами',
          calories: 550,
          imageUrl: '',
        ),
        MealItem(
          type: MealType.snack,
          name: 'Фруктовый смузи',
          calories: 200,
          imageUrl: '',
        ),
      ],
    );
  }
}
