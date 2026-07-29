import '../models/user_model.dart';

class NutritionCalculator {
  /// Расчет базового метаболизма по формуле Харриса-Бенедикта для соответствия с MealPlanScreen
  static double calculateBMR(
      Gender gender, double weightKg, double heightCm, int age) {
    if (gender == Gender.male) {
      // Формула для мужчин: 88.362 + (13.397 × вес в кг) + (4.799 × рост в см) - (5.677 × возраст в годах)
      return 88.362 + (13.397 * weightKg) + (4.799 * heightCm) - (5.677 * age);
    } else {
      // Формула для женщин: 447.593 + (9.247 × вес в кг) + (3.098 × рост в см) - (4.330 × возраст в годах)
      return 447.593 + (9.247 * weightKg) + (3.098 * heightCm) - (4.330 * age);
    }
  }

  /// Расчет дневной потребности в калориях с учетом активности
  static int calculateTDEE(double bmr, ActivityLevel activityLevel) {
    double multiplier;

    switch (activityLevel) {
      case ActivityLevel.sedentary:
        multiplier = 1.2; // Малоподвижный образ жизни
        break;
      case ActivityLevel.lightlyActive:
        multiplier = 1.375; // Легкая активность
        break;
      case ActivityLevel.moderatelyActive:
        multiplier = 1.55; // Умеренная активность
        break;
      case ActivityLevel.veryActive:
        multiplier = 1.725; // Высокая активность
        break;
      case ActivityLevel.extraActive:
        multiplier = 1.9; // Очень высокая активность
        break;
    }

    return (bmr * multiplier).round();
  }

  /// Расчет целевых калорий с учетом цели (похудение, поддержание, набор)
  static int calculateTargetCalories(int tdee, Goal goal) {
    switch (goal) {
      case Goal.loseWeight:
        return (tdee * 0.85).round(); // дефицит 15%
      case Goal.maintain:
        return tdee;
      case Goal.gainMuscle:
        return (tdee * 1.15)
            .round(); // профицит 15% для соответствия с MealPlanScreen
    }
  }

  /// Расчет макронутриентов (БЖУ) на основе целевых калорий и цели
  static NutritionGoals calculateMacronutrients(int targetCalories, Goal goal) {
    int proteinGrams;
    int fatGrams;
    int carbsGrams;

    switch (goal) {
      case Goal.loseWeight:
        // Больше белка для сохранения мышц, меньше углеводов
        proteinGrams =
            (targetCalories * 0.3 / 4).round(); // 30% от калорий из белка
        fatGrams =
            (targetCalories * 0.35 / 9).round(); // 35% от калорий из жира
        carbsGrams =
            (targetCalories * 0.35 / 4).round(); // 35% от калорий из углеводов
        break;
      case Goal.maintain:
        // Сбалансированные макронутриенты
        proteinGrams =
            (targetCalories * 0.25 / 4).round(); // 25% от калорий из белка
        fatGrams = (targetCalories * 0.3 / 9).round(); // 30% от калорий из жира
        carbsGrams =
            (targetCalories * 0.45 / 4).round(); // 45% от калорий из углеводов
        break;
      case Goal.gainMuscle:
        // Больше углеводов для энергии, высокий белок для синтеза мышц
        proteinGrams =
            (targetCalories * 0.25 / 4).round(); // 25% от калорий из белка
        fatGrams =
            (targetCalories * 0.25 / 9).round(); // 25% от калорий из жира
        carbsGrams =
            (targetCalories * 0.5 / 4).round(); // 50% от калорий из углеводов
        break;
    }

    // Рекомендованная вода: 30 мл на кг веса по умолчанию недоступна здесь,
    // поэтому зададим дефолт 2000 мл, а фактический расчет выполним при создании профиля
    return NutritionGoals(
      dailyCalories: targetCalories,
      dailyProtein: proteinGrams,
      dailyFat: fatGrams,
      dailyCarbs: carbsGrams,
      dailyWaterMl: 2000,
    );
  }

  /// Расчет полной модели питания для пользователя
  static NutritionGoals calculateNutritionGoals(
    Gender gender,
    double weightKg,
    double heightCm,
    int age,
    ActivityLevel activityLevel,
    Goal goal,
  ) {
    final bmr = calculateBMR(gender, weightKg, heightCm, age);
    final tdee = calculateTDEE(bmr, activityLevel);
    final targetCalories = calculateTargetCalories(tdee, goal);

    return calculateMacronutrients(targetCalories, goal);
  }
}
