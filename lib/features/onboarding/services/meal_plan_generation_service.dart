import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import '../../../models/user_model.dart';
import '../../../models/meal_plan_model.dart';
import '../../../services/localization/app_localization_service.dart';
import '../../../services/region_service.dart';
import '../../../services/nutrition_analysis/deepseek/deepseek_client.dart';

/// Сервис генерации персонального плана питания через модель (DeepSeek)
class MealPlanGenerationService {
  MealPlanGenerationService({DeepSeekClient? client})
      : _client = client ?? DeepSeekClient.fromEnvironment(fastMode: true);

  final DeepSeekClient _client;

  /// Стримит текстовые куски ответа модели. В конце постарайтесь извлечь JSON и распарсить в [MealPlanModel].
  Stream<String> streamMealPlanText({
    required UserModel user,
    required BuildContext context,
  }) async* {
    final container = ProviderScope.containerOf(context);
    final localizationService = container.read(appLocalizationServiceProvider);
    final String interfaceLanguage = localizationService.getIntlLocaleString();
    String userCountry = 'US';
    try {
      userCountry = await RegionService().getRegionCode();
    } catch (_) {}

    final String prompt = _buildMealPlanPrompt(
      user: user,
      interfaceLanguage: interfaceLanguage,
      country: userCountry,
    );

    debugPrint('🍽️ MEAL_PLAN: Prompt length: ${prompt.length}');
    yield* _client.generateTextStream(prompt);
  }

  /// Пытается извлечь JSON из произвольного текста и распарсить его в [MealPlanModel].
  MealPlanModel? tryParseMealPlanFromText(String text) {
    // Ищем блок JSON, содержащий ключи totalCalories и meals
    final int keyPos = text.lastIndexOf('totalCalories');
    final bool hasMealsKey = text.contains('"meals"');
    int searchFrom = 0;
    if (keyPos != -1) {
      searchFrom = text.lastIndexOf('{', keyPos);
      if (searchFrom == -1) searchFrom = 0;
    }

    for (int i = searchFrom; i < text.length; i++) {
      if (text[i] == '{') {
        final json = _extractBalancedJson(text, i);
        if (json != null &&
            (json.contains('totalCalories') &&
                (hasMealsKey || json.contains('"meals"')))) {
          try {
            final Map<String, dynamic> map = _decodeJson(json);
            if (!_isValidMealPlanMap(map)) {
              // Ждем финальный корректный JSON от модели
              continue;
            }
            return MealPlanModel.fromJson(map);
          } catch (_) {
            // продолжаем поиск следующего кандидата
          }
        }
      }
    }

    debugPrint('🍽️ MEAL_PLAN: No valid JSON block found yet');
    return null;
  }

  // Отдельный парсер с безопасной обработкой
  Map<String, dynamic> _decodeJson(String source) {
    return jsonDecode(source) as Map<String, dynamic>;
  }

  /// Возвращает JSON-объект как строку, начиная с позиции openingIndex, учитывая баланс скобок
  String? _extractBalancedJson(String source, int openingIndex) {
    int depth = 0;
    for (int i = openingIndex; i < source.length; i++) {
      final ch = source[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          return source.substring(openingIndex, i + 1);
        }
      }
    }
    return null;
  }

  bool _isValidMealPlanMap(Map<String, dynamic> map) {
    if (!map.containsKey('meals')) return false;
    final meals = map['meals'];
    if (meals is! List) return false;
    if (meals.isEmpty) return false;
    // Минимально проверяем структуру: name не пустой, type допустимый
    int valid = 0;
    for (final m in meals) {
      if (m is Map<String, dynamic>) {
        final name = (m['name'] ?? '').toString().trim();
        final type = (m['type'] ?? '').toString().toLowerCase();
        if (name.isNotEmpty &&
            (type.contains('break') ||
                type.contains('lunch') ||
                type.contains('dinn') ||
                type.contains('snack'))) {
          valid++;
        }
      }
    }
    return valid > 0;
  }

  String _buildMealPlanPrompt({
    required UserModel user,
    required String interfaceLanguage,
    required String country,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
        'You are an experienced dietitian with 15+ years of practice.');
    buffer.writeln(
        'STRICT LANGUAGE RULE: Respond ONLY in language: $interfaceLanguage.');
    buffer.writeln(
        'Never switch language based on SIM, country, or model preferences.');
    buffer.writeln(
        'Use country ($country) ONLY to adapt foods/ingredients/brands, NOT for output language.');
    buffer.writeln(
        'All natural language fields, dish names and JSON strings must be in $interfaceLanguage.');
    buffer.writeln(
        'Generate a personalized DAILY meal plan for the user with 4 meals: breakfast, lunch, dinner, snack.');
    buffer.writeln('Keep total daily calories close to the user daily goal.');
    // Сначала отдай 4 строки в машинном формате для потокового отображения блюд:
    // MEAL: <breakfast|lunch|dinner|snack>|<dish name>|<calories>
    // Пример: MEAL: breakfast|Менемен с овощами|420
    // Затем, в самом КОНЦЕ, выдай один блок STRICT JSON по схеме ниже.
    buffer.writeln(
        'First, stream exactly four lines in this machine-readable format (no extra text):');
    buffer.writeln('MEAL: breakfast|<name>|<calories>');
    buffer.writeln('MEAL: lunch|<name>|<calories>');
    buffer.writeln('MEAL: dinner|<name>|<calories>');
    buffer.writeln('MEAL: snack|<name>|<calories>');
    buffer.writeln(
        'After that, at the very END, output STRICT JSON ONLY on a single block, with this schema:');
    buffer.writeln(
        '{\n  "totalCalories": number,\n  "meals": [\n    {"type": "breakfast|lunch|dinner|snack", "name": string, "calories": number, "imageUrl": string}\n  ]\n}');
    buffer.writeln('Avoid markdown, no backticks in the JSON.');

    // Профиль пользователя
    buffer.writeln('\nUSER PROFILE:');
    buffer.writeln('gender: ${user.gender.name}');
    buffer.writeln('age: ${user.age}');
    buffer.writeln('height_cm: ${user.height.toStringAsFixed(0)}');
    buffer.writeln('weight_kg: ${user.weight.toStringAsFixed(1)}');
    buffer.writeln('goal: ${user.goal.name}');
    buffer.writeln('activity: ${user.activityLevel.name}');

    // Цели по питанию
    buffer.writeln('\nNUTRITION GOALS:');
    buffer.writeln('dailyCalories: ${user.nutritionGoals.dailyCalories}');
    buffer.writeln('dailyProtein: ${user.nutritionGoals.dailyProtein}');
    buffer.writeln('dailyFat: ${user.nutritionGoals.dailyFat}');
    buffer.writeln('dailyCarbs: ${user.nutritionGoals.dailyCarbs}');

    // Требования к структуре
    buffer.writeln('\nREQUIREMENTS:');
    buffer.writeln(
        '- Choose locally realistic, popular and healthy dishes for $country (use local names and traditions; avoid generic Western defaults if not typical).');
    buffer.writeln('- Balance macros over the day.');
    buffer.writeln('- Each meal must have name and approx calories.');
    buffer.writeln(
        '- Keep total calories around ${user.nutritionGoals.dailyCalories}.');
    buffer.writeln(
        '- Stream four MEAL lines first (no extra commentary), then output final JSON as the last block.');

    return buffer.toString();
  }
}
