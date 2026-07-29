import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import 'deepseek_dietitian_service.dart';
// import 'test_data_generator.dart'; // Закомментировано, так как не используется
import '../../../services/localization/app_localization_service.dart';

/// Сервис для работы с ИИ‑другом
class AiDietitianService {
  final DeepSeekDietitianService _deepSeekService;

  AiDietitianService({
    DeepSeekDietitianService? deepSeekService,
  }) : _deepSeekService = deepSeekService ?? DeepSeekDietitianService();

  /// Отправляет сообщение ИИ‑другу и получает ответ
  Future<ChatMessage> sendMessage({
    required String message,
    List<ChatMessage>? context,
    Map<String, dynamic>? userProfile,
    BuildContext? buildContext,
  }) async {
    // Вместо возврата ChatMessage.ai с системным сообщением, всегда используем sendMessageStream
    // и собираем результат в строку (для обратной совместимости)
    try {
      String fullResponse = '';
      await for (final chunk in sendMessageStream(
        message: message,
        context: context,
        userProfile: userProfile,
        buildContext: buildContext,
      )) {
        fullResponse += chunk;
      }
      return ChatMessage.ai(
        content: fullResponse,
        metadata: {
          'timestamp': DateTime.now().toIso8601String(),
          'model': 'ai-dietitian',
          'streaming': false,
        },
      );
    } catch (e) {
      debugPrint('❌ AI_FRIEND: Ошибка при отправке сообщения: $e');
      return ChatMessage.ai(
        content: buildContext != null
            ? buildContext.tr('ai_dietitian_error_response')
            : 'Извините, произошла ошибка при обработке вашего запроса. Попробуйте еще раз.',
        metadata: {'error': true, 'model': 'deepseek-v4-flash'},
      );
    }
  }

  /// Создает тестовые данные питания для демонстрации
  /// Закомментировано по требованию пользователя
  /*
  Future<void> _createTestMealData() async {
    if (_mealRepository == null) {
      debugPrint(
          '⚠️ AI_DIETITIAN: MealRepository недоступен для создания тестовых данных');
      return;
    }

    try {
      debugPrint('🧪 AI_DIETITIAN: Создание тестовых данных питания...');

      final testMeals = TestDataGenerator.generateWeeklyMeals();

      for (final meal in testMeals) {
        await _mealRepository.saveMeal(meal);
      }

      debugPrint(
          '✅ AI_DIETITIAN: Создано ${testMeals.length} тестовых приемов пищи');
    } catch (e) {
      debugPrint('❌ AI_DIETITIAN: Ошибка создания тестовых данных: $e');
    }
  }
  */

  /// Отправляет сообщение ИИ‑другу и получает поток ответов для отображения в реальном времени
  Stream<String> sendMessageStream({
    required String message,
    List<ChatMessage>? context,
    Map<String, dynamic>? userProfile,
    BuildContext? buildContext,
  }) async* {
    try {
      debugPrint('🤖 AI_FRIEND: Получен streaming запрос: "$message"');
      // Используем Deepseek для обычного потокового ответа
      yield* _deepSeekService.generateGeneralResponseStream(
        userMessage: message,
        context: context,
        buildContext: buildContext,
      );
    } catch (e) {
      debugPrint('❌ AI_FRIEND: Ошибка при streaming: $e');
      yield buildContext != null
          ? buildContext.tr('ai_dietitian_error_response')
          : 'Извините, произошла ошибка при обработке вашего запроса. Попробуйте еще раз.';
    }
  }

  /// Проверяет доступность сервиса
  Future<bool> isServiceAvailable() async {
    try {
      // В реальном приложении здесь будет проверка API
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      debugPrint('Сервис ИИ недоступен: $e');
      return false;
    }
  }
}
