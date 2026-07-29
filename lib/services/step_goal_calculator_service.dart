import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'nutrition_analysis/deepseek/deepseek_client.dart';

class StepGoalCalculatorService {
  final DeepSeekClient _deepSeekClient;

  StepGoalCalculatorService(this._deepSeekClient);

  Future<int> calculatePersonalizedStepGoal({
    required UserModel user,
    String interfaceLanguage = 'ru',
  }) async {
    try {
      final prompt = _buildPrompt(user: user, language: interfaceLanguage);
      debugPrint('👟 STEP_GOAL: Запрос к AI для расчёта цели шагов...');
      
      final response = await _deepSeekClient.generateText(prompt);
      
      final goal = _parseStepGoal(response);
      debugPrint('👟 STEP_GOAL: AI рекомендует $goal шагов в день');
      
      return goal;
    } catch (e) {
      debugPrint('❌ STEP_GOAL: Ошибка расчёта цели шагов: $e');
      return _calculateFallbackGoal(user);
    }
  }

  String _buildPrompt({
    required UserModel user,
    required String language,
  }) {
    final genderStr = user.gender == Gender.male ? 'мужчина' : 'женщина';
    final goalStr = _getGoalString(user.goal);
    final activityStr = _getActivityString(user.activityLevel);
    final experienceStr = _getExperienceString(user.experienceLevel);
    
    return '''Ты профессиональный фитнес-тренер и нутрициолог. 
Рассчитай оптимальное количество шагов в день для пользователя.

ПРОФИЛЬ ПОЛЬЗОВАТЕЛЯ:
- Пол: $genderStr
- Возраст: ${user.age} лет
- Рост: ${user.height.toStringAsFixed(0)} см
- Вес: ${user.weight.toStringAsFixed(1)} кг
- Уровень активности: $activityStr
- Цель: $goalStr
- Спортивный опыт: $experienceStr
- Тренировок в неделю: ${user.workoutsPerWeek ?? 3}

ТРЕБОВАНИЯ К ОТВЕТУ:
1. Учти все параметры пользователя
2. Для похудения рекомендуй больше шагов (10000-15000)
3. Для поддержания формы - умеренно (8000-12000)
4. Для набора массы - меньше, чтобы сохранять энергию (6000-10000)
5. Учитывай возраст: пожилым людям меньше шагов
6. Учитывай уровень подготовки: новичкам начинать с меньшего
7. Учитывай количество тренировок: в дни тренировок меньше шагов нужно

ФОРМАТ ОТВЕТА (строго JSON без markdown):
{"dailyStepGoal": число, "reasoning": "краткое обоснование на $language"}

Пример: {"dailyStepGoal": 10000, "reasoning": "Для похудения при умеренной активности"}
''';
  }

  String _getGoalString(Goal goal) {
    switch (goal) {
      case Goal.loseWeight:
        return 'похудение';
      case Goal.maintain:
        return 'поддержание формы';
      case Goal.gainMuscle:
        return 'набор мышечной массы';
    }
  }

  String _getActivityString(ActivityLevel level) {
    switch (level) {
      case ActivityLevel.sedentary:
        return 'сидячий образ жизни';
      case ActivityLevel.lightlyActive:
        return 'лёгкая активность';
      case ActivityLevel.moderatelyActive:
        return 'умеренная активность';
      case ActivityLevel.veryActive:
        return 'высокая активность';
      case ActivityLevel.extraActive:
        return 'очень высокая активность';
    }
  }

  String _getExperienceString(ExperienceLevel? level) {
    switch (level) {
      case ExperienceLevel.beginner:
        return 'новичок';
      case ExperienceLevel.intermediate:
        return 'средний уровень';
      case ExperienceLevel.athlete:
        return 'продвинутый/атлет';
      case null:
        return 'не указан';
    }
  }

  int _parseStepGoal(String response) {
    try {
      String cleanResponse = response.trim();
      
      final jsonStartIndex = cleanResponse.indexOf('{');
      final jsonEndIndex = cleanResponse.lastIndexOf('}');
      
      if (jsonStartIndex != -1 && jsonEndIndex != -1) {
        cleanResponse = cleanResponse.substring(jsonStartIndex, jsonEndIndex + 1);
      }
      
      final Map<String, dynamic> json = jsonDecode(cleanResponse);
      final goal = json['dailyStepGoal'];
      
      if (goal is int) {
        return goal.clamp(3000, 25000);
      } else if (goal is double) {
        return goal.round().clamp(3000, 25000);
      } else if (goal is String) {
        return int.tryParse(goal)?.clamp(3000, 25000) ?? 10000;
      }
      
      return 10000;
    } catch (e) {
      debugPrint('⚠️ STEP_GOAL: Ошибка парсинга ответа: $e');
      
      final regex = RegExp(r'\b(\d{4,5})\b');
      final match = regex.firstMatch(response);
      if (match != null) {
        final parsed = int.tryParse(match.group(1)!);
        if (parsed != null && parsed >= 3000 && parsed <= 25000) {
          return parsed;
        }
      }
      
      return 10000;
    }
  }

  int _calculateFallbackGoal(UserModel user) {
    int baseGoal = 8000;
    
    switch (user.goal) {
      case Goal.loseWeight:
        baseGoal = 12000;
        break;
      case Goal.maintain:
        baseGoal = 10000;
        break;
      case Goal.gainMuscle:
        baseGoal = 8000;
        break;
    }
    
    switch (user.activityLevel) {
      case ActivityLevel.sedentary:
        baseGoal = (baseGoal * 0.7).round();
        break;
      case ActivityLevel.lightlyActive:
        baseGoal = (baseGoal * 0.85).round();
        break;
      case ActivityLevel.moderatelyActive:
        break;
      case ActivityLevel.veryActive:
        baseGoal = (baseGoal * 1.1).round();
        break;
      case ActivityLevel.extraActive:
        baseGoal = (baseGoal * 1.2).round();
        break;
    }
    
    if (user.age > 60) {
      baseGoal = (baseGoal * 0.8).round();
    } else if (user.age > 50) {
      baseGoal = (baseGoal * 0.9).round();
    } else if (user.age < 25) {
      baseGoal = (baseGoal * 1.1).round();
    }
    
    if (user.experienceLevel == ExperienceLevel.beginner) {
      baseGoal = (baseGoal * 0.8).round();
    } else if (user.experienceLevel == ExperienceLevel.athlete) {
      baseGoal = (baseGoal * 1.1).round();
    }
    
    baseGoal = (baseGoal / 500).round() * 500;
    
    return baseGoal.clamp(5000, 20000);
  }
}







