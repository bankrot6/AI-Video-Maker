// import 'dart:convert'; // Удален неиспользуемый импорт

/// Набор функций для DeepSeek Function Calling в контексте нутрициологии
/// Новая возможность DeepSeek R1-0528
class NutritionFunctionTools {
  /// Получает список функций для анализа питания
  static List<Map<String, dynamic>> getNutritionAnalysisTools() {
    return [
      _calculateDailyNormsFunction(),
      _analyzeMacroBalanceFunction(),
      _suggestMealTimingFunction(),
      _calculateBMRFunction(),
    ];
  }

  /// Функция для расчета суточных норм питания
  static Map<String, dynamic> _calculateDailyNormsFunction() {
    return {
      'type': 'function',
      'function': {
        'name': 'calculate_daily_nutrition_norms',
        'description':
            'Рассчитывает персональные суточные нормы калорий и БЖУ на основе параметров пользователя',
        'parameters': {
          'type': 'object',
          'properties': {
            'age': {
              'type': 'integer',
              'description': 'Возраст пользователя в годах',
            },
            'gender': {
              'type': 'string',
              'enum': ['male', 'female'],
              'description': 'Пол пользователя',
            },
            'weight': {
              'type': 'number',
              'description': 'Вес пользователя в килограммах',
            },
            'height': {
              'type': 'number',
              'description': 'Рост пользователя в сантиметрах',
            },
            'activity_level': {
              'type': 'string',
              'enum': [
                'sedentary',
                'lightly_active',
                'moderately_active',
                'very_active',
                'extra_active'
              ],
              'description': 'Уровень физической активности',
            },
            'goal': {
              'type': 'string',
              'enum': ['lose_weight', 'maintain', 'gain_muscle'],
              'description': 'Цель пользователя',
            },
          },
          'required': [
            'age',
            'gender',
            'weight',
            'height',
            'activity_level',
            'goal'
          ],
        },
      },
    };
  }

  /// Функция для анализа баланса макронутриентов
  static Map<String, dynamic> _analyzeMacroBalanceFunction() {
    return {
      'type': 'function',
      'function': {
        'name': 'analyze_macro_balance',
        'description':
            'Анализирует баланс белков, жиров и углеводов в питании пользователя',
        'parameters': {
          'type': 'object',
          'properties': {
            'daily_protein': {
              'type': 'number',
              'description': 'Суточное потребление белков в граммах',
            },
            'daily_fat': {
              'type': 'number',
              'description': 'Суточное потребление жиров в граммах',
            },
            'daily_carbs': {
              'type': 'number',
              'description': 'Суточное потребление углеводов в граммах',
            },
            'target_protein': {
              'type': 'number',
              'description': 'Целевое потребление белков в граммах',
            },
            'target_fat': {
              'type': 'number',
              'description': 'Целевое потребление жиров в граммах',
            },
            'target_carbs': {
              'type': 'number',
              'description': 'Целевое потребление углеводов в граммах',
            },
          },
          'required': [
            'daily_protein',
            'daily_fat',
            'daily_carbs',
            'target_protein',
            'target_fat',
            'target_carbs'
          ],
        },
      },
    };
  }

  /// Функция для предложений по времени приема пищи
  static Map<String, dynamic> _suggestMealTimingFunction() {
    return {
      'type': 'function',
      'function': {
        'name': 'suggest_meal_timing',
        'description':
            'Предлагает оптимальное время приемов пищи на основе целей и образа жизни',
        'parameters': {
          'type': 'object',
          'properties': {
            'wake_up_time': {
              'type': 'string',
              'description': 'Время пробуждения в формате HH:mm',
            },
            'sleep_time': {
              'type': 'string',
              'description': 'Время отхода ко сну в формате HH:mm',
            },
            'workout_time': {
              'type': 'string',
              'description': 'Время тренировок в формате HH:mm (если есть)',
            },
            'goal': {
              'type': 'string',
              'enum': ['lose_weight', 'maintain', 'gain_muscle'],
              'description': 'Цель пользователя',
            },
            'meals_per_day': {
              'type': 'integer',
              'minimum': 3,
              'maximum': 6,
              'description': 'Желаемое количество приемов пищи в день',
            },
          },
          'required': ['wake_up_time', 'sleep_time', 'goal', 'meals_per_day'],
        },
      },
    };
  }

  /// Функция для расчета базального метаболизма
  static Map<String, dynamic> _calculateBMRFunction() {
    return {
      'type': 'function',
      'function': {
        'name': 'calculate_bmr',
        'description':
            'Рассчитывает базальный метаболизм (BMR) пользователя по формуле Миффлина-Сан-Жеора',
        'parameters': {
          'type': 'object',
          'properties': {
            'weight': {
              'type': 'number',
              'description': 'Вес в килограммах',
            },
            'height': {
              'type': 'number',
              'description': 'Рост в сантиметрах',
            },
            'age': {
              'type': 'integer',
              'description': 'Возраст в годах',
            },
            'gender': {
              'type': 'string',
              'enum': ['male', 'female'],
              'description': 'Пол',
            },
          },
          'required': ['weight', 'height', 'age', 'gender'],
        },
      },
    };
  }

  /// Выполняет функцию по имени и параметрам
  static Map<String, dynamic> executeFunction(
      String functionName, Map<String, dynamic> parameters) {
    switch (functionName) {
      case 'calculate_daily_nutrition_norms':
        return _calculateDailyNutritionNorms(parameters);
      case 'analyze_macro_balance':
        return _analyzeMacroBalance(parameters);
      case 'suggest_meal_timing':
        return _suggestMealTiming(parameters);
      case 'calculate_bmr':
        return _calculateBMR(parameters);
      default:
        return {'error': 'Неизвестная функция: $functionName'};
    }
  }

  /// Реализация расчета суточных норм
  static Map<String, dynamic> _calculateDailyNutritionNorms(
      Map<String, dynamic> params) {
    final age = params['age'] as int;
    final gender = params['gender'] as String;
    final weight = (params['weight'] as num).toDouble();
    final height = (params['height'] as num).toDouble();
    final activityLevel = params['activity_level'] as String;
    final goal = params['goal'] as String;

    // Расчет BMR по формуле Миффлина-Сан-Жеора
    double bmr;
    if (gender == 'male') {
      bmr = 10 * weight + 6.25 * height - 5 * age + 5;
    } else {
      bmr = 10 * weight + 6.25 * height - 5 * age - 161;
    }

    // Коэффициенты активности
    double activityMultiplier;
    switch (activityLevel) {
      case 'sedentary':
        activityMultiplier = 1.2;
        break;
      case 'lightly_active':
        activityMultiplier = 1.375;
        break;
      case 'moderately_active':
        activityMultiplier = 1.55;
        break;
      case 'very_active':
        activityMultiplier = 1.725;
        break;
      case 'extra_active':
        activityMultiplier = 1.9;
        break;
      default:
        activityMultiplier = 1.2;
    }

    double tdee = bmr * activityMultiplier;

    // Корректировка калорий в зависимости от цели
    double targetCalories;
    switch (goal) {
      case 'lose_weight':
        targetCalories = tdee - 500; // Дефицит 500 ккал для похудения
        break;
      case 'gain_muscle':
        targetCalories = tdee + 300; // Профицит 300 ккал для набора массы
        break;
      default:
        targetCalories = tdee; // Поддержание веса
    }

    // Расчет БЖУ
    double proteinPerKg = goal == 'gain_muscle' ? 2.0 : 1.6;
    double targetProtein = weight * proteinPerKg;
    double targetFat = targetCalories * 0.25 / 9; // 25% от калорий
    double targetCarbs =
        (targetCalories - targetProtein * 4 - targetFat * 9) / 4;

    return {
      'bmr': bmr.round(),
      'tdee': tdee.round(),
      'target_calories': targetCalories.round(),
      'target_protein': targetProtein.round(),
      'target_fat': targetFat.round(),
      'target_carbs': targetCarbs.round(),
      'protein_percentage':
          ((targetProtein * 4 / targetCalories) * 100).round(),
      'fat_percentage': ((targetFat * 9 / targetCalories) * 100).round(),
      'carbs_percentage': ((targetCarbs * 4 / targetCalories) * 100).round(),
    };
  }

  /// Реализация анализа баланса макронутриентов
  static Map<String, dynamic> _analyzeMacroBalance(
      Map<String, dynamic> params) {
    final dailyProtein = (params['daily_protein'] as num).toDouble();
    final dailyFat = (params['daily_fat'] as num).toDouble();
    final dailyCarbs = (params['daily_carbs'] as num).toDouble();
    final targetProtein = (params['target_protein'] as num).toDouble();
    final targetFat = (params['target_fat'] as num).toDouble();
    final targetCarbs = (params['target_carbs'] as num).toDouble();

    double proteinDiff = dailyProtein - targetProtein;
    double fatDiff = dailyFat - targetFat;
    double carbsDiff = dailyCarbs - targetCarbs;

    return {
      'protein_status': proteinDiff >= 0 ? 'adequate' : 'deficit',
      'protein_difference': proteinDiff.round(),
      'fat_status': fatDiff >= -5 && fatDiff <= 5
          ? 'optimal'
          : (fatDiff > 5 ? 'excess' : 'deficit'),
      'fat_difference': fatDiff.round(),
      'carbs_status': carbsDiff >= -10 && carbsDiff <= 10
          ? 'optimal'
          : (carbsDiff > 10 ? 'excess' : 'deficit'),
      'carbs_difference': carbsDiff.round(),
      'overall_balance': _getOverallBalance(proteinDiff, fatDiff, carbsDiff),
    };
  }

  /// Реализация предложений по времени приема пищи
  static Map<String, dynamic> _suggestMealTiming(Map<String, dynamic> params) {
    final wakeUpTime = params['wake_up_time'] as String;
    // final sleepTime = params['sleep_time'] as String; // Будет использовано в будущих версиях
    final goal = params['goal'] as String;
    final mealsPerDay = params['meals_per_day'] as int;
    // final workoutTime = params['workout_time'] as String?; // Будет использовано для оптимизации времени приема пищи

    List<String> mealTimes = [];
    List<String> mealTypes = [];

    // Простая логика для демонстрации
    final wakeHour = int.parse(wakeUpTime.split(':')[0]);

    if (mealsPerDay >= 3) {
      mealTimes.addAll([
        '${(wakeHour + 1).toString().padLeft(2, '0')}:00', // Завтрак через час после пробуждения
        '${(wakeHour + 5).toString().padLeft(2, '0')}:00', // Обед
        '${(wakeHour + 11).toString().padLeft(2, '0')}:00', // Ужин
      ]);
      mealTypes.addAll(['Завтрак', 'Обед', 'Ужин']);
    }

    return {
      'suggested_meal_times': mealTimes,
      'meal_types': mealTypes,
      'recommendations': goal == 'lose_weight'
          ? [
              'Последний прием пищи за 3 часа до сна',
              'Больший интервал между приемами пищи'
            ]
          : [
              'Равномерное распределение калорий',
              'Перекусы между основными приемами'
            ],
    };
  }

  /// Реализация расчета BMR
  static Map<String, dynamic> _calculateBMR(Map<String, dynamic> params) {
    final weight = (params['weight'] as num).toDouble();
    final height = (params['height'] as num).toDouble();
    final age = params['age'] as int;
    final gender = params['gender'] as String;

    double bmr;
    if (gender == 'male') {
      bmr = 10 * weight + 6.25 * height - 5 * age + 5;
    } else {
      bmr = 10 * weight + 6.25 * height - 5 * age - 161;
    }

    return {
      'bmr': bmr.round(),
      'formula': 'Mifflin-St Jeor',
      'explanation': gender == 'male'
          ? '10 × вес + 6.25 × рост - 5 × возраст + 5'
          : '10 × вес + 6.25 × рост - 5 × возраст - 161',
    };
  }

  /// Оценивает общий баланс макронутриентов
  static String _getOverallBalance(
      double proteinDiff, double fatDiff, double carbsDiff) {
    int issues = 0;
    if (proteinDiff.abs() > 10) issues++;
    if (fatDiff.abs() > 5) issues++;
    if (carbsDiff.abs() > 10) issues++;

    if (issues == 0) return 'excellent';
    if (issues == 1) return 'good';
    if (issues == 2) return 'needs_improvement';
    return 'poor';
  }
}
