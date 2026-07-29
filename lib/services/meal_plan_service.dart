import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../config/ai_proxy_config.dart';
import '../models/user_model.dart';
import '../models/meal_plan_model.dart';
import '../services/localization/app_localization_service.dart';

final mealPlanServiceProvider = Provider<MealPlanService>((ref) {
  return MealPlanService();
});

class MealPlanService {
  Future<MealPlanModel> generateMealPlan(
      UserModel user, BuildContext context) async {
    final defaultMealPlan = _generateDefaultMealPlan(user, context);
    final prompt = _generatePrompt(user, context);

    try {
      final proxyBaseUrl = AiProxyConfig.deepSeekBaseUrl();
      final proxyToken = AiProxyConfig.token;
      final apiKey = dotenv.env['DEEPSEEK_API_KEY'];
      if (proxyBaseUrl == null && apiKey == null) {
        throw Exception(context.tr('api_key_not_found'));
      }

      final url = Uri.parse(
        proxyBaseUrl != null
            ? '$proxyBaseUrl/chat/completions'
            : 'https://api.deepseek.com/chat/completions',
      );

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (proxyBaseUrl != null && proxyToken != null)
            'X-Ai-Proxy-Token': proxyToken
          else
            'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'deepseek-v4-flash',
          'thinking': {'type': 'disabled'},
          'messages': [
            {
              'role': 'system',
              'content': context.tr('meal_plan_system_prompt')
            },
            {'role': 'user', 'content': prompt}
          ],
          'response_format': {'type': 'json_object'},
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final completion = responseData['choices'][0]['message']['content'];

        try {
          // Парсим JSON-ответ от DeepSeek
          final mealPlanData = jsonDecode(completion);
          return MealPlanModel.fromJson(mealPlanData);
        } catch (e) {
          // Если ответ не соответствует ожидаемому формату,
          // возвращаем сгенерированный план по умолчанию
          return defaultMealPlan;
        }
      } else {
        // Обработка ошибок API
        throw Exception('API error: ${response.statusCode}');
      }
    } catch (e) {
      // Возвращаем план по умолчанию в случае любых ошибок
      return defaultMealPlan;
    }
  }

  // Генерирует запрос на основе данных пользователя
  String _generatePrompt(UserModel user, BuildContext context) {
    final gender = user.gender == Gender.male
        ? context.tr('gender_male_lowercase')
        : context.tr('gender_female_lowercase');

    final goal = user.goal == Goal.loseWeight
        ? context.tr('goal_lose_weight_lowercase')
        : (user.goal == Goal.maintain
            ? context.tr('goal_maintain_lowercase')
            : context.tr('goal_gain_muscle_lowercase'));

    String activityLevel;
    switch (user.activityLevel) {
      case ActivityLevel.sedentary:
        activityLevel = context.tr('activity_sedentary_lowercase');
        break;
      case ActivityLevel.lightlyActive:
        activityLevel = context.tr('activity_lightly_lowercase');
        break;
      case ActivityLevel.moderatelyActive:
        activityLevel = context.tr('activity_moderately_lowercase');
        break;
      case ActivityLevel.veryActive:
        activityLevel = context.tr('activity_very_lowercase');
        break;
      case ActivityLevel.extraActive:
        activityLevel = context.tr('activity_extremely_lowercase');
        break;
    }

    return context.trParams('meal_plan_prompt', [
      gender,
      user.age.toString(),
      user.height.toString(),
      user.weight.toString(),
      activityLevel,
      goal,
      user.nutritionGoals.dailyCalories.toString(),
      user.nutritionGoals.dailyProtein.toString(),
      user.nutritionGoals.dailyFat.toString(),
      user.nutritionGoals.dailyCarbs.toString(),
      user.nutritionGoals.dailyCalories.toString(),
      context.tr('meal_name_placeholder')
    ]);
  }

  // Генерирует план по умолчанию, если API не сработал
  MealPlanModel _generateDefaultMealPlan(UserModel user, BuildContext context) {
    final totalCalories = user.nutritionGoals.dailyCalories;

    return MealPlanModel(
      totalCalories: totalCalories,
      meals: [
        MealItem(
          type: MealType.breakfast,
          name: context.tr('meal_plan_breakfast_3'),
          calories: (totalCalories * 0.2).round(),
          imageUrl: '',
        ),
        MealItem(
          type: MealType.lunch,
          name: context.tr('meal_plan_lunch_3'),
          calories: (totalCalories * 0.35).round(),
          imageUrl: '',
        ),
        MealItem(
          type: MealType.dinner,
          name: context.tr('meal_plan_dinner_3'),
          calories: (totalCalories * 0.25).round(),
          imageUrl: '',
        ),
        MealItem(
          type: MealType.snack,
          name: context.tr('meal_plan_snack_3'),
          calories: (totalCalories * 0.2).round(),
          imageUrl: '',
        ),
      ],
    );
  }
}
