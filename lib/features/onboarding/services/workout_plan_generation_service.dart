import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/user_model.dart';
import '../../../models/workout_plan_model.dart';
import '../../../services/localization/app_localization_service.dart';
import '../../../services/region_service.dart';
import '../../../services/nutrition_analysis/deepseek/deepseek_client.dart';

/// Сервис генерации однодневной программы тренировки через LLM (DeepSeek)
class WorkoutPlanGenerationService {
  WorkoutPlanGenerationService({DeepSeekClient? client})
      : _client = client ?? DeepSeekClient.fromEnvironment(fastMode: true);

  final DeepSeekClient _client;

  /// Стримит текст ответа. В конце пытаемся извлечь строго один JSON и распарсить в [WorkoutPlanModel].
  Stream<String> streamWorkoutText({
    required UserModel user,
    required BuildContext context,
    int? dayIndexInWeek,
    int? weekdayNumber,
    DateTime? weekStartDate,
  }) async* {
    final container = ProviderScope.containerOf(context);
    final localizationService = container.read(appLocalizationServiceProvider);
    // Язык интерфейса пользователя (человеческое имя, а не код локали)
    final AppLanguage current = localizationService.getCurrentLanguage();
    final String interfaceLanguage = _mapLanguageToName(current);
    String userCountry = 'US';
    try {
      userCountry = await RegionService().getRegionCode();
    } catch (_) {}

    final String prompt = _buildWorkoutPrompt(
      user: user,
      interfaceLanguage: interfaceLanguage,
      country: userCountry,
      dayIndexInWeek: dayIndexInWeek,
      weekdayNumber: weekdayNumber,
      weekStartDate: weekStartDate,
    );

    debugPrint('🏋️ WORKOUT: Prompt length: ${prompt.length}');
    yield* _client.generateTextStream(prompt);
  }

  WorkoutPlanModel? tryParseWorkoutFromText(String text) {
    final int keyPos = text.lastIndexOf('exercises');
    int searchFrom = 0;
    if (keyPos != -1) {
      searchFrom = text.lastIndexOf('{', keyPos);
      if (searchFrom == -1) searchFrom = 0;
    }

    for (int i = searchFrom; i < text.length; i++) {
      if (text[i] == '{') {
        final json = _extractBalancedJson(text, i);
        if (json != null && json.contains('exercises')) {
          try {
            final Map<String, dynamic> map =
                jsonDecode(json) as Map<String, dynamic>;
            if (!_isValidWorkoutMap(map)) continue;
            return WorkoutPlanModel.fromJson(map);
          } catch (_) {}
        }
      }
    }
    return null;
  }

  /// Нормализует язык текстовых полей JSON под язык интерфейса.
  /// Переводятся только поля dayTitle и exercises[].name. Числа и структура не меняются.
  Future<WorkoutPlanModel> normalizeWorkoutLanguage({
    required BuildContext context,
    required WorkoutPlanModel plan,
  }) async {
    try {
      final container = ProviderScope.containerOf(context);
      final localizationService =
          container.read(appLocalizationServiceProvider);
      final AppLanguage current = localizationService.getCurrentLanguage();
      final String interfaceLanguage = _mapLanguageToName(current);

      // Формируем строгую инструкцию на перевод только текстовых полей
      final String sourceJson = jsonEncode(plan.toJson());
      final buffer = StringBuffer();
      buffer.writeln('You are a precise JSON transformer.');
      buffer.writeln(
          'STRICT LANGUAGE RULE: Output ONLY in language: $interfaceLanguage.');
      buffer.writeln('Input is a JSON for a one-day workout plan.');
      buffer.writeln(
          'Translate ONLY string fields: "dayTitle" and each "exercises[i].name" to $interfaceLanguage.');
      buffer.writeln(
          'Keep all numbers (sets, reps, weightKg) and structure EXACTLY the same.');
      buffer.writeln('Return STRICT JSON ONLY, no markdown, no comments.');
      buffer.writeln('\nINPUT JSON:');
      buffer.writeln(sourceJson);

      final String translated = await _client.generateText(buffer.toString());

      // Пытаемся распарсить обратно
      final Map<String, dynamic> map =
          jsonDecode(translated) as Map<String, dynamic>;
      return WorkoutPlanModel.fromJson(map);
    } catch (_) {
      // Если что-то пошло не так — возвращаем исходный план
      return plan;
    }
  }

  String? _extractBalancedJson(String source, int openingIndex) {
    int depth = 0;
    for (int i = openingIndex; i < source.length; i++) {
      final ch = source[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return source.substring(openingIndex, i + 1);
      }
    }
    return null;
  }

  bool _isValidWorkoutMap(Map<String, dynamic> map) {
    if (!map.containsKey('exercises')) return false;
    final exercises = map['exercises'];
    if (exercises is! List) return false;
    if (exercises.isEmpty) return false;
    int valid = 0;
    for (final e in exercises) {
      if (e is Map<String, dynamic>) {
        final String name = (e['name'] ?? '').toString().trim();
        final int sets = (e['sets'] is num) ? (e['sets'] as num).toInt() : 0;
        final int reps = (e['reps'] is num) ? (e['reps'] as num).toInt() : 0;
        if (name.isNotEmpty && sets > 0 && reps > 0) valid++;
      }
    }
    return valid > 0;
  }

  String _buildWorkoutPrompt({
    required UserModel user,
    required String interfaceLanguage,
    required String country,
    int? dayIndexInWeek,
    int? weekdayNumber,
    DateTime? weekStartDate,
  }) {
    // Получаем параметры тренировки на основе уровня опыта
    final level = user.experienceLevel ?? ExperienceLevel.intermediate;
    final exerciseCount = level.exercisesPerWorkout;
    final minSets = level.minSets;
    final maxSets = level.maxSets;
    final weightIntensity = level.weightIntensityDescription;

    final buffer = StringBuffer();
    buffer.writeln('You are a certified strength and conditioning coach.');
    buffer.writeln(
        'STRICT LANGUAGE RULE: Respond ONLY in language: $interfaceLanguage.');
    buffer.writeln(
        'Never switch language based on SIM, country, or model preferences.');
    buffer.writeln(
        'Use country ($country) ONLY to adapt equipment availability and naming, NOT for output language.');
    buffer.writeln('Goal: produce ONE-DAY training plan for the user.');
    buffer.writeln(
        'Return exercises with: name, sets, reps per set, working weight in kilograms.');
    buffer.writeln('Working weight must be realistic for the user profile.');
    // Сначала отдаём потоковые строки для постепенного UI: заголовок дня и упражнения
    buffer.writeln('Stream output progressively in this exact order:');
    if (dayIndexInWeek != null) {
      buffer.writeln('DAY: <unique day title including "День ${dayIndexInWeek + 1}" or "Day ${dayIndexInWeek + 1}" prefix and workout focus>');
    } else {
      buffer.writeln('DAY: <day title>');
    }
    buffer.writeln(
        'Then EXACTLY $exerciseCount lines: EX: <exercise name>|<sets>|<reps>|<weightKg>');
    buffer.writeln(
        'Do NOT translate the labels "DAY:" and "EX:" — keep them EXACT ASCII uppercase. Only the natural language parts (day title and exercise names) must be in $interfaceLanguage.');
    buffer.writeln(
        'Only after streaming these lines, at the VERY END, output one STRICT JSON block (no markdown/backticks):');
    buffer.writeln('{'
        '"dayTitle": string,'
        '"exercises": ['
        '{"name": string, "sets": number, "reps": number, "weightKg": number}'
        ']'
        '}');

    // Профиль пользователя для персонализации
    buffer.writeln('\nUSER PROFILE:');
    buffer.writeln('gender: ${user.gender.name}');
    buffer.writeln('age: ${user.age}');
    buffer.writeln('height_cm: ${user.height.toStringAsFixed(0)}');
    buffer.writeln('weight_kg: ${user.weight.toStringAsFixed(1)}');
    buffer.writeln('activity: ${user.activityLevel.name}');
    buffer.writeln('goal: ${user.goal.name}');
    if (user.workoutPlace != null) {
      buffer.writeln('workout_place: ${user.workoutPlace!.name}');
    }
    if (user.extraFocus != null) {
      buffer.writeln('focus: ${user.extraFocus!.name}');
    }
    buffer.writeln('experience_level: ${level.name}');
    if (user.workoutsPerWeek != null && user.workoutsPerWeek! > 0) {
      buffer.writeln('workouts_per_week: ${user.workoutsPerWeek}');
    }

    // Информация о плане на неделю (если есть)
    if (user.weeklyFocuses != null && user.weeklyFocuses!.isNotEmpty) {
      buffer.writeln('\nWEEKLY FOCUS PLAN:');
      for (int i = 0; i < user.weeklyFocuses!.length; i++) {
        final focus = user.weeklyFocuses![i];
        final dayNum = i + 1;
        buffer.writeln('day_$dayNum: ${focus.name}');
      }
      buffer.writeln(
          'Use this weekly plan to ensure proper muscle group rotation and avoid overtraining the same muscles on consecutive days.');
    }

    // Контекст недели и дня для вариативности в рамках недели
    if (weekStartDate != null) {
      buffer.writeln('week_start_iso: ${weekStartDate.toIso8601String()}');
    }
    if (dayIndexInWeek != null) {
      buffer.writeln('day_index_in_week: $dayIndexInWeek');
    }
    if (weekdayNumber != null) {
      buffer
          .writeln('weekday_number_iso: $weekdayNumber'); // Monday=1..Sunday=7
    }

    buffer.writeln('\nREQUIREMENTS:');
    buffer.writeln(
        '- Generate EXACTLY $exerciseCount exercises (this is based on user experience level: ${level.name}).');
    buffer.writeln('- Each exercise must have $minSets-$maxSets sets (based on experience level).');
    buffer.writeln('- Each exercise must have integer reps between 6 and 15.');
    buffer.writeln('- Weight intensity: $weightIntensity.');
    buffer.writeln('- weightKg is a number, use 0 if bodyweight.');
    buffer.writeln('- Avoid warm-up and stretching in the list.');
    buffer.writeln(
        '- Distribute fatigue considering workouts_per_week if provided.');
    buffer
        .writeln('- Choose equipment according to workout_place if provided.');
    buffer.writeln(
        '- First stream DAY and EX lines as specified, then final JSON only.');
    
    // КРИТИЧЕСКИ ВАЖНО: инструкции для уникальности тренировок
    buffer.writeln(
        '- CRITICAL: Each day in the week MUST have DIFFERENT main exercises. Never repeat the same primary compound movements across different days.');
    if (dayIndexInWeek != null) {
      buffer.writeln(
          '- This is day ${dayIndexInWeek + 1} of the week. Use day_index_in_week=$dayIndexInWeek to select UNIQUE exercises for this specific day.');
      // Добавляем конкретные инструкции по вариативности в зависимости от дня
      if (dayIndexInWeek == 0) {
        buffer.writeln('- As day 1, focus on primary compound movements like bench press, squats, or deadlifts variations.');
      } else if (dayIndexInWeek == 1) {
        buffer.writeln('- As day 2, use DIFFERENT primary exercises than day 1. Focus on pulling movements, lunges, or overhead work.');
      } else if (dayIndexInWeek == 2) {
        buffer.writeln('- As day 3, use DIFFERENT primary exercises than days 1 and 2. Include unilateral work, machines, or accessory-focused compound movements.');
      } else {
        buffer.writeln('- For day ${dayIndexInWeek + 1}, ensure exercises are different from previous days. Rotate between push/pull/legs patterns.');
      }
    }
    buffer.writeln(
        '- Ensure day-to-day variation across the week (e.g., rotate muscle groups, avoid repeating same main lifts on consecutive days).');
    if (user.weeklyFocuses != null &&
        dayIndexInWeek != null &&
        dayIndexInWeek < user.weeklyFocuses!.length) {
      final currentFocus = user.weeklyFocuses![dayIndexInWeek];
      buffer.writeln(
          '- IMPORTANT: For THIS day (day ${dayIndexInWeek + 1}), focus primarily on: ${currentFocus.name}. Even with the same focus area, use DIFFERENT exercise variations than other days.');
    }

    return buffer.toString();
  }

  String _mapLanguageToName(AppLanguage language) {
    switch (language) {
      case AppLanguage.ru:
        return 'Russian';
      case AppLanguage.en:
        return 'English';
      case AppLanguage.es:
        return 'Spanish';
      case AppLanguage.esMX:
        return 'Spanish (Mexico)';
      case AppLanguage.fr:
        return 'French';
      case AppLanguage.frCA:
        return 'French (Canada)';
      case AppLanguage.de:
        return 'German';
      case AppLanguage.it:
        return 'Italian';
      case AppLanguage.pt:
        return 'Portuguese';
      case AppLanguage.ptBR:
        return 'Portuguese (Brazil)';
      case AppLanguage.zh:
        return 'Chinese (Simplified)';
      case AppLanguage.zhTW:
        return 'Chinese (Traditional)';
      case AppLanguage.ja:
        return 'Japanese';
      case AppLanguage.ko:
        return 'Korean';
      case AppLanguage.ar:
        return 'Arabic';
      case AppLanguage.he:
        return 'Hebrew';
      case AppLanguage.hi:
        return 'Hindi';
      case AppLanguage.th:
        return 'Thai';
      case AppLanguage.vi:
        return 'Vietnamese';
      case AppLanguage.tr:
        return 'Turkish';
      case AppLanguage.pl:
        return 'Polish';
      case AppLanguage.uk:
        return 'Ukrainian';
      case AppLanguage.cs:
        return 'Czech';
      case AppLanguage.sk:
        return 'Slovak';
      case AppLanguage.hu:
        return 'Hungarian';
      case AppLanguage.ro:
        return 'Romanian';
      case AppLanguage.hr:
        return 'Croatian';
      case AppLanguage.fi:
        return 'Finnish';
      case AppLanguage.sv:
        return 'Swedish';
      case AppLanguage.da:
        return 'Danish';
      case AppLanguage.no:
        return 'Norwegian';
      case AppLanguage.nl:
        return 'Dutch';
      case AppLanguage.ms:
        return 'Malay';
      case AppLanguage.id:
        return 'Indonesian';
      case AppLanguage.ca:
        return 'Catalan';
      case AppLanguage.el:
        return 'Greek';
      case AppLanguage.fil:
        return 'Filipino';
    }
  }
}
