import 'package:equatable/equatable.dart';

enum Gender { male, female, other }

enum ActivityLevel {
  sedentary, // малоподвижный образ жизни
  lightlyActive, // легкая активность 1-3 раза в неделю
  moderatelyActive, // умеренная активность 3-5 раз в неделю
  veryActive, // активные тренировки 6-7 раз в неделю
  extraActive // экстремальная физическая нагрузка
}

enum Goal { loseWeight, maintain, gainMuscle }

/// Место, где пользователь в основном тренируется
enum WorkoutPlace { gym, home }

/// Дополнительный фокус дня/программы (опционально)
enum BodyFocus { none, arms, chest, back, legs, core, burn, glutes, cardio }

/// Уровень спортивной подготовки
enum ExperienceLevel { beginner, intermediate, athlete }

/// Параметры тренировки в зависимости от уровня подготовки
extension ExperienceLevelWorkoutParams on ExperienceLevel {
  /// Количество упражнений в тренировке
  /// - beginner (новичок): 4 упражнения
  /// - intermediate (любитель): 6 упражнений
  /// - athlete (спортсмен): 8 упражнений
  int get exercisesPerWorkout {
    switch (this) {
      case ExperienceLevel.beginner:
        return 4;
      case ExperienceLevel.intermediate:
        return 6;
      case ExperienceLevel.athlete:
        return 8;
    }
  }

  /// Минимальное количество подходов
  int get minSets {
    switch (this) {
      case ExperienceLevel.beginner:
        return 2;
      case ExperienceLevel.intermediate:
        return 3;
      case ExperienceLevel.athlete:
        return 4;
    }
  }

  /// Максимальное количество подходов
  int get maxSets {
    switch (this) {
      case ExperienceLevel.beginner:
        return 3;
      case ExperienceLevel.intermediate:
        return 4;
      case ExperienceLevel.athlete:
        return 5;
    }
  }

  /// Интенсивность весовой нагрузки (описание для промпта)
  String get weightIntensityDescription {
    switch (this) {
      case ExperienceLevel.beginner:
        return 'light weights (30-50% of estimated max) or bodyweight only, focus on technique';
      case ExperienceLevel.intermediate:
        return 'moderate weights (50-70% of estimated max), balanced volume';
      case ExperienceLevel.athlete:
        return 'challenging weights (70-85% of estimated max), higher intensity';
    }
  }
}

/// Получить количество упражнений по уровню опыта (с fallback на intermediate)
int getExerciseCountForLevel(ExperienceLevel? level) {
  return (level ?? ExperienceLevel.intermediate).exercisesPerWorkout;
}

class UserModel extends Equatable {
  final String id;
  final String name;
  final int age;
  final Gender gender;
  final double height; // в см
  final double weight; // в кг
  final ActivityLevel activityLevel;
  final Goal goal;
  final NutritionGoals nutritionGoals;
  // Новые поля для тренировочного профиля
  final WorkoutPlace? workoutPlace;
  final BodyFocus? extraFocus;

  /// Уровень спортивной подготовки пользователя (опционально)
  final ExperienceLevel? experienceLevel;

  /// Запланированное количество тренировок в неделю (опционально)
  final int? workoutsPerWeek;

  /// План распределения фокусов по дням недели (опционально)
  /// Список содержит фокус для каждого тренировочного дня
  /// Длина списка должна соответствовать workoutsPerWeek
  /// Например: [BodyFocus.chest, BodyFocus.legs, BodyFocus.back] для 3 дней
  final List<BodyFocus>? weeklyFocuses;

  /// Расписание дней недели для тренировок (опционально)
  /// Список содержит номера дней недели от 1 (понедельник) до 7 (воскресенье)
  /// Например: [1, 3, 5] для ПН, СР, ПТ
  /// Длина списка должна соответствовать workoutsPerWeek
  final List<int>? weekSchedule;

  const UserModel({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.height,
    required this.weight,
    required this.activityLevel,
    required this.goal,
    required this.nutritionGoals,
    this.workoutPlace,
    this.extraFocus,
    this.experienceLevel,
    this.workoutsPerWeek,
    this.weeklyFocuses,
    this.weekSchedule,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        age,
        gender,
        height,
        weight,
        activityLevel,
        goal,
        nutritionGoals,
        workoutPlace,
        extraFocus,
        experienceLevel,
        workoutsPerWeek,
        weeklyFocuses,
        weekSchedule,
      ];

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      age: json['age'] as int,
      gender: Gender.values[json['gender'] as int],
      height: json['height'] as double,
      weight: json['weight'] as double,
      activityLevel: ActivityLevel.values[json['activityLevel'] as int],
      goal: Goal.values[json['goal'] as int],
      nutritionGoals: NutritionGoals.fromJson(
          json['nutritionGoals'] as Map<String, dynamic>),
      workoutPlace: json['workoutPlace'] != null
          ? WorkoutPlace.values[json['workoutPlace'] as int]
          : null,
      extraFocus: json['extraFocus'] != null
          ? BodyFocus.values[json['extraFocus'] as int]
          : null,
      experienceLevel: json['experienceLevel'] != null
          ? ExperienceLevel.values[json['experienceLevel'] as int]
          : null,
      workoutsPerWeek: json['workoutsPerWeek'] as int?,
      weeklyFocuses: json['weeklyFocuses'] != null
          ? (json['weeklyFocuses'] as List<dynamic>)
              .map((e) => BodyFocus.values[e as int])
              .toList()
          : null,
      weekSchedule: json['weekSchedule'] != null
          ? (json['weekSchedule'] as List<dynamic>)
              .map((e) => e as int)
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'gender': gender.index,
      'height': height,
      'weight': weight,
      'activityLevel': activityLevel.index,
      'goal': goal.index,
      'nutritionGoals': nutritionGoals.toJson(),
      if (workoutPlace != null) 'workoutPlace': workoutPlace!.index,
      if (extraFocus != null) 'extraFocus': extraFocus!.index,
      if (experienceLevel != null) 'experienceLevel': experienceLevel!.index,
      if (workoutsPerWeek != null) 'workoutsPerWeek': workoutsPerWeek,
      if (weeklyFocuses != null)
        'weeklyFocuses': weeklyFocuses!.map((e) => e.index).toList(),
      if (weekSchedule != null) 'weekSchedule': weekSchedule,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    int? age,
    Gender? gender,
    double? height,
    double? weight,
    ActivityLevel? activityLevel,
    Goal? goal,
    NutritionGoals? nutritionGoals,
    WorkoutPlace? workoutPlace,
    BodyFocus? extraFocus,
    ExperienceLevel? experienceLevel,
    int? workoutsPerWeek,
    List<BodyFocus>? weeklyFocuses,
    List<int>? weekSchedule,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      activityLevel: activityLevel ?? this.activityLevel,
      goal: goal ?? this.goal,
      nutritionGoals: nutritionGoals ?? this.nutritionGoals,
      workoutPlace: workoutPlace ?? this.workoutPlace,
      extraFocus: extraFocus ?? this.extraFocus,
      experienceLevel: experienceLevel ?? this.experienceLevel,
      workoutsPerWeek: workoutsPerWeek ?? this.workoutsPerWeek,
      weeklyFocuses: weeklyFocuses ?? this.weeklyFocuses,
      weekSchedule: weekSchedule ?? this.weekSchedule,
    );
  }
}

class NutritionGoals extends Equatable {
  final int dailyCalories;
  final int dailyProtein; // в граммах
  final int dailyFat; // в граммах
  final int dailyCarbs; // в граммах
  final int dailyWaterMl; // цель воды в мл

  const NutritionGoals({
    required this.dailyCalories,
    required this.dailyProtein,
    required this.dailyFat,
    required this.dailyCarbs,
    required this.dailyWaterMl,
  });

  @override
  List<Object?> get props => [
        dailyCalories,
        dailyProtein,
        dailyFat,
        dailyCarbs,
      ];

  factory NutritionGoals.fromJson(Map<String, dynamic> json) {
    return NutritionGoals(
      dailyCalories: json['dailyCalories'] as int,
      dailyProtein: json['dailyProtein'] as int,
      dailyFat: json['dailyFat'] as int,
      dailyCarbs: json['dailyCarbs'] as int,
      // Поддержка обратной совместимости: если ключ отсутствует, используем 2000 мл
      dailyWaterMl: (json['dailyWaterMl'] as int?) ?? 2000,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dailyCalories': dailyCalories,
      'dailyProtein': dailyProtein,
      'dailyFat': dailyFat,
      'dailyCarbs': dailyCarbs,
      'dailyWaterMl': dailyWaterMl,
    };
  }
}
