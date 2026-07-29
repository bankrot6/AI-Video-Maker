import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/exercise_info.dart';
import 'nutrition_analysis/deepseek/deepseek_client.dart';

/// Сервис для анализа упражнений с использованием DeepSeek AI
class ExerciseAnalysisService {
  final DeepSeekClient _client;

  ExerciseAnalysisService({DeepSeekClient? client})
      : _client = client ?? DeepSeekClient.fromEnvironment();

  /// Анализирует упражнение и возвращает детальную информацию о нем
  Future<ExerciseInfo> analyzeExercise(
    String exerciseName, {
    BuildContext? context,
  }) async {
    debugPrint('🏋️ EXERCISE_ANALYZER: ===== НАЧАЛО АНАЛИЗА УПРАЖНЕНИЯ =====');
    debugPrint('🏋️ EXERCISE_ANALYZER: Упражнение: "$exerciseName"');

    try {
      // Определяем язык интерфейса
      final language = _determineLanguage(context);

      // Создаем промпт для анализа упражнения
      final prompt = _buildExerciseAnalysisPrompt(exerciseName, language);

      debugPrint(
          '🏋️ EXERCISE_ANALYZER: ===== ОТПРАВКА ЗАПРОСА К DEEPSEEK =====');
      debugPrint(
          '🏋️ EXERCISE_ANALYZER: Размер промпта: ${prompt.length} символов');

      // Отправляем запрос к DeepSeek
      final response = await _client.generateText(prompt);

      debugPrint(
          '🏋️ EXERCISE_ANALYZER: ===== ПОЛУЧЕН ОТВЕТ ОТ DEEPSEEK =====');
      debugPrint(
          '🏋️ EXERCISE_ANALYZER: Размер ответа: ${response.length} символов');

      // Парсим ответ
      final exerciseInfo =
          _parseExerciseResponse(response, exerciseName, context);

      debugPrint('🏋️ EXERCISE_ANALYZER: ===== АНАЛИЗ ЗАВЕРШЕН =====');
      debugPrint('🏋️ EXERCISE_ANALYZER: Результат: ${exerciseInfo.name}');

      return exerciseInfo;
    } catch (e) {
      debugPrint('❌ EXERCISE_ANALYZER: Ошибка при анализе: $e');
      return ExerciseInfo.empty().copyWith(
        name: exerciseName,
        error: e.toString(),
      );
    }
  }

  /// Потоковый анализ упражнения с постепенным возвратом частичных результатов
  Stream<ExerciseInfo> analyzeExerciseStream(
    String exerciseName, {
    BuildContext? context,
  }) async* {
    debugPrint(
        '🏋️ EXERCISE_ANALYZER_STREAM: ===== НАЧАЛО ПОТОКОВОГО АНАЛИЗА =====');
    debugPrint('🏋️ EXERCISE_ANALYZER_STREAM: Упражнение: "$exerciseName"');

    try {
      // Определяем язык интерфейса
      final language = _determineLanguage(context);

      // Создаем промпт для анализа упражнения
      final prompt = _buildExerciseAnalysisPrompt(exerciseName, language);

      debugPrint(
          '🏋️ EXERCISE_ANALYZER_STREAM: ===== ОТПРАВКА ЗАПРОСА К DEEPSEEK =====');

      // Накопительный буфер для ответа
      String accumulatedResponse = '';

      // Получаем поток ответов от DeepSeek
      await for (final chunk in _client.generateTextStream(prompt)) {
        accumulatedResponse += chunk;

        // Парсим частичный ответ и отдаем его
        final partialInfo = _parseExerciseResponse(
          accumulatedResponse,
          exerciseName,
          context,
          isPartial: true,
        );

        yield partialInfo;
      }

      debugPrint('🏋️ EXERCISE_ANALYZER_STREAM: ===== АНАЛИЗ ЗАВЕРШЕН =====');
    } catch (e) {
      debugPrint('❌ EXERCISE_ANALYZER_STREAM: Ошибка при анализе: $e');
      yield ExerciseInfo.empty().copyWith(
        name: exerciseName,
        error: e.toString(),
      );
    }
  }

  /// Определяет язык интерфейса
  String _determineLanguage(BuildContext? context) {
    if (context == null) return 'ru';

    // Получаем текущую локаль из контекста через AppLocalizationService
    final locale = Localizations.localeOf(context);

    // Возвращаем код языка
    return locale.languageCode;
  }

  /// Создает промпт для анализа упражнения
  String _buildExerciseAnalysisPrompt(String exerciseName, String language) {
    final buffer = StringBuffer();

    // Основная инструкция на английском для модели
    buffer.writeln('''
You are a professional fitness trainer with 15+ years of experience. Analyze the following exercise and provide detailed information.

CRITICAL LANGUAGE REQUIREMENT:
- You MUST respond ONLY in language code: $language
- Do NOT switch language based on exercise name
- ALL sections must be in $language language

Exercise name: $exerciseName

Provide information in the following structured format (no JSON, plain text):

DESCRIPTION:
[Detailed description of how to perform the exercise in 3-5 sentences]

TARGET_MUSCLES:
[Target muscle groups worked by this exercise]

KEY_POINTS:
• [First key point]
• [Second key point]
• [Third key point]

COMMON_MISTAKES:
• [First common mistake]
• [Second common mistake]
• [Third common mistake]

Requirements:
1. Be specific and practical
2. Use simple, clear language
3. Focus on proper technique
4. Highlight safety considerations
5. All text MUST be in $language language
6. Use bullet points (•) for lists
7. Keep descriptions concise but informative
8. Start writing immediately - no preamble

IMPORTANT: Write in the structured format above. Start immediately with DESCRIPTION:
''');

    return buffer.toString();
  }

  /// Парсит ответ от DeepSeek и создает ExerciseInfo
  ExerciseInfo _parseExerciseResponse(
    String response,
    String originalName,
    BuildContext? context, {
    bool isPartial = false,
  }) {
    try {
      // Извлекаем секции из структурированного текста
      final description =
          _extractSection(response, 'DESCRIPTION:', 'TARGET_MUSCLES:');
      final targetMuscles =
          _extractSection(response, 'TARGET_MUSCLES:', 'KEY_POINTS:');
      final keyPoints =
          _extractSection(response, 'KEY_POINTS:', 'COMMON_MISTAKES:');
      final commonMistakes =
          _extractSection(response, 'COMMON_MISTAKES:', null);

      // Если это частичный ответ и ничего не извлечено, возвращаем пустую модель
      if (isPartial &&
          description.isEmpty &&
          targetMuscles.isEmpty &&
          keyPoints.isEmpty &&
          commonMistakes.isEmpty) {
        return ExerciseInfo.empty().copyWith(name: originalName);
      }

      return ExerciseInfo(
        name: originalName,
        description: description,
        keyPoints: keyPoints,
        commonMistakes: commonMistakes,
        targetMuscles: targetMuscles,
      );
    } catch (e) {
      debugPrint('❌ EXERCISE_ANALYZER: Ошибка парсинга: $e');
      if (isPartial) {
        return ExerciseInfo.empty().copyWith(name: originalName);
      }
      return ExerciseInfo.empty().copyWith(
        name: originalName,
        error: e.toString(),
      );
    }
  }

  /// Извлекает секцию текста между двумя маркерами
  String _extractSection(String text, String startMarker, String? endMarker) {
    try {
      final startIndex = text.indexOf(startMarker);
      if (startIndex == -1) return '';

      final contentStart = startIndex + startMarker.length;

      int contentEnd;
      if (endMarker != null) {
        contentEnd = text.indexOf(endMarker, contentStart);
        if (contentEnd == -1) {
          contentEnd = text.length;
        }
      } else {
        contentEnd = text.length;
      }

      final content = text.substring(contentStart, contentEnd).trim();
      return content;
    } catch (e) {
      debugPrint(
          '❌ EXERCISE_ANALYZER: Ошибка извлечения секции $startMarker: $e');
      return '';
    }
  }
}
