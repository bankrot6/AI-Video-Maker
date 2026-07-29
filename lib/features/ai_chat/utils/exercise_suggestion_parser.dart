import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/ai_agent_action.dart';
import '../../../models/workout_plan_model.dart';

/// Парсер для извлечения предложений упражнений из ответов AI
class ExerciseSuggestionParser {
  /// Извлекает предложения упражнений из текста ответа AI
  /// Поддерживает два формата JSON:
  /// 1. Новый формат (как на главном экране): {"exercises": [...]}
  /// 2. Старый формат (с markdown): {"exerciseSuggestions": [...]}
  static List<ExerciseSuggestion> parseExerciseSuggestions(String aiResponse) {
    final suggestions = <ExerciseSuggestion>[];

    try {
      // МЕТОД 1: Умный поиск JSON с балансировкой скобок (как на главном экране)
      // Ищем ключевое слово "exercises" и извлекаем JSON от последней открывающей скобки
      final int keyPos = aiResponse.lastIndexOf('exercises');
      if (keyPos != -1) {
        int searchFrom = aiResponse.lastIndexOf('{', keyPos);
        if (searchFrom != -1) {
          final json = _extractBalancedJson(aiResponse, searchFrom);
          if (json != null && json.contains('exercises')) {
            try {
              final jsonData = Map<String, dynamic>.from(
                jsonDecode(json) as Map,
              );

              if (jsonData.containsKey('exercises')) {
                final exercisesJson = jsonData['exercises'] as List;
                int index = 0;
                for (var exercise in exercisesJson) {
                  try {
                    final exerciseMap = exercise as Map<String, dynamic>;
                    suggestions.add(
                      ExerciseSuggestion(
                        id: 'ex_${index++}_${exerciseMap['name'].hashCode}',
                        exercise: ExerciseItem.fromJson(exerciseMap),
                        reasoning: 'Предложено AI тренером',
                      ),
                    );
                  } catch (e) {
                    debugPrint('⚠️ Ошибка парсинга упражнения: $e');
                  }
                }
                debugPrint('✅ Найдено ${suggestions.length} упражнений (новый формат, метод балансировки)');
                return suggestions;
              }
            } catch (e) {
              debugPrint('⚠️ Ошибка парсинга JSON с балансировкой: $e');
            }
          }
        }
      }

      // Fallback: пробуем старый формат с markdown и exerciseSuggestions
      final jsonMatch = RegExp(
        r'```json\s*(\{.*?"exerciseSuggestions".*?\})\s*```',
        dotAll: true,
      ).firstMatch(aiResponse);

      if (jsonMatch != null) {
        final jsonString = jsonMatch.group(1);
        if (jsonString != null) {
          final jsonData = Map<String, dynamic>.from(
            jsonDecode(jsonString) as Map,
          );

          if (jsonData.containsKey('exerciseSuggestions')) {
            final suggestionsJson = jsonData['exerciseSuggestions'] as List;
            for (var suggestion in suggestionsJson) {
              try {
                suggestions.add(
                  ExerciseSuggestion.fromJson(
                    suggestion as Map<String, dynamic>,
                  ),
                );
              } catch (e) {
                debugPrint('⚠️ Ошибка парсинга предложения упражнения: $e');
              }
            }
            debugPrint('✅ Найдено ${suggestions.length} упражнений (старый формат)');
            return suggestions;
          }
        }
      }

      debugPrint('✅ JSON с упражнениями не найден');
      return suggestions;
    } catch (e) {
      debugPrint('❌ Ошибка парсинга предложений упражнений: $e');
      return [];
    }
  }

  /// Создает действие добавления упражнения из предложения
  static AddExerciseAction createAddExerciseAction(
    ExerciseSuggestion suggestion,
  ) {
    return AddExerciseAction(
      id: suggestion.id,
      description: suggestion.reasoning,
      exercise: suggestion.exercise,
      targetDayIndex: suggestion.targetDayIndex,
      targetDayTitle: suggestion.targetDayTitle,
    );
  }

  /// Извлекает упражнения из текста, если нет JSON формата
  /// Ищет паттерны типа:
  /// - Название упражнения: 3 подхода по 12 повторений (вес 20 кг)
  /// - Название: 3x12 @ 20kg
  /// - • Название - делайте 3 подхода по 12 повторений
  /// - Название (3 подхода по 30 секунд)
  static List<ExerciseSuggestion> parsePlainTextExercises(String text) {
    final suggestions = <ExerciseSuggestion>[];
    
    // Паттерны для поиска упражнений в тексте
    final patterns = [
      // Паттерн 1: "Название: 3 подхода по 12 повторений, 20 кг"
      RegExp(
        r'(?:^|\n)[\*\-•]?\s*([А-Яа-яёЁA-Za-z][А-Яа-яёЁA-Za-z\s]{2,30}?):\s*(\d+)\s*(?:подход|sets?|х)\s*(?:по|х|x)\s*(\d+)\s*(?:повтор|reps?|секунд|сек)[\s,]*(?:(\d+(?:\.\d+)?)\s*(?:кг|kg))?',
        multiLine: true,
        caseSensitive: false,
      ),
      // Паттерн 2: "Название - 3x12 @ 20kg"
      RegExp(
        r'(?:^|\n)[\*\-•]?\s*([А-Яа-яёЁA-Za-z][А-Яа-яёЁA-Za-z\s]{2,30}?)\s*[-–—]\s*(\d+)\s*[xх×]\s*(\d+)\s*(?:@|вес:?)?\s*(?:(\d+(?:\.\d+)?)\s*(?:кг|kg))?',
        multiLine: true,
        caseSensitive: false,
      ),
      // Паттерн 3: "Название (3 подхода по 12 повторений)" или "Название - делайте 3 подхода"
      RegExp(
        r'(?:^|\n)[\*\-•]?\s*([А-Яа-яёЁA-Za-z][А-Яа-яёЁA-Za-z\s]{2,30}?)\s*(?:\(|[-–—]\s*(?:делай(?:те)?|выполня(?:й|йте)|рекоменду(?:ю|ем))?)\s*(\d+)\s*(?:подход|sets?)\s*(?:по|х|x|of)?\s*(\d+)\s*(?:повтор|reps?|секунд|сек)',
        multiLine: true,
        caseSensitive: false,
      ),
      // Паттерн 4: Простой список "• Название упражнения" (без параметров, добавим стандартные 3x12)
      RegExp(
        r'(?:^|\n)[\*\-•]\s*([А-Яа-яёЁA-Za-z][А-Яа-яёЁA-Za-z\s]{3,40}?)\s*(?:-|—|–)\s*(?:развивает|работает|нагружает|для|strengthens|builds|targets)',
        multiLine: true,
        caseSensitive: false,
      ),
    ];

    int suggestionId = 0;
    final foundExercises = <String>{}; // Для избежания дубликатов
    
    for (var patternIndex = 0; patternIndex < patterns.length; patternIndex++) {
      final pattern = patterns[patternIndex];
      final matches = pattern.allMatches(text);
      
      for (final match in matches) {
        try {
          final name = match.group(1)?.trim();
          
          // Паттерн 4 - только название без параметров
          if (patternIndex == 3) {
            if (name != null && name.isNotEmpty && !foundExercises.contains(name.toLowerCase())) {
              foundExercises.add(name.toLowerCase());
              suggestions.add(
                ExerciseSuggestion(
                  id: 'text_${suggestionId++}_${name.hashCode}',
                  exercise: ExerciseItem(
                    name: name,
                    sets: 3,
                    reps: 12,
                    weightKg: 0,
                  ),
                  reasoning: 'Предложено AI тренером',
                ),
              );
            }
          } else {
            // Остальные паттерны с параметрами
            final sets = int.tryParse(match.group(2) ?? '');
            final reps = int.tryParse(match.group(3) ?? '');
            final weight = double.tryParse(match.group(4) ?? '0') ?? 0;

            if (name != null && 
                name.isNotEmpty && 
                sets != null && 
                reps != null &&
                !foundExercises.contains(name.toLowerCase())) {
              foundExercises.add(name.toLowerCase());
              suggestions.add(
                ExerciseSuggestion(
                  id: 'text_${suggestionId++}_${name.hashCode}',
                  exercise: ExerciseItem(
                    name: name,
                    sets: sets,
                    reps: reps,
                    weightKg: weight,
                  ),
                  reasoning: 'Предложено AI тренером',
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('⚠️ Ошибка парсинга упражнения из текста: $e');
        }
      }
    }

    if (suggestions.isNotEmpty) {
      debugPrint('✅ Извлечено ${suggestions.length} упражнений из текста');
    }
    
    return suggestions;
  }

  /// Комбинированный парсинг: сначала JSON, затем текст
  static List<ExerciseSuggestion> parse(String aiResponse) {
    final jsonSuggestions = parseExerciseSuggestions(aiResponse);
    if (jsonSuggestions.isNotEmpty) {
      return jsonSuggestions;
    }
    
    // Если JSON не найден, пробуем парсить текст
    return parsePlainTextExercises(aiResponse);
  }

  /// Извлекает сбалансированный JSON из текста начиная с указанной позиции
  /// Используется тот же алгоритм, что и на главном экране
  static String? _extractBalancedJson(String source, int openingIndex) {
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
}



