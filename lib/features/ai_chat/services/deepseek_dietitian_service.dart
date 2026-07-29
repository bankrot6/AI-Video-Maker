import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/nutrition_analysis/deepseek/deepseek_client.dart';
import '../../../utils/text_formatter.dart';
import '../../../services/localization/app_localization_service.dart';

import '../models/chat_message.dart';
import '../utils/interactive_parser.dart';

class DeepSeekDietitianService {
  final DeepSeekClient _client;

  DeepSeekDietitianService({DeepSeekClient? client})
      : _client = client ?? DeepSeekClient.fromEnvironment(fastMode: false);

  Future<ChatMessage> generateGeneralResponse({
    required String userMessage,
    List<ChatMessage>? context,
    BuildContext? buildContext,
  }) async {
    try {
      debugPrint('🧠 AI_FRIEND: ===== ГЕНЕРАЦИЯ ОТВЕТА =====');
      debugPrint('🧠 AI_FRIEND: Запрос пользователя: "$userMessage"');

      final language = _determineLanguage(buildContext);
      final prompt = _buildGeneralResponsePrompt(
        userMessage: userMessage,
        context: context,
        language: language,
      );

      debugPrint('🧠 AI_FRIEND: ===== ОТПРАВКА ЗАПРОСА К DEEPSEEK =====');
      debugPrint('🧠 AI_FRIEND: Размер промпта: ${prompt.length} символов');

      final response = await _client.generateText(prompt);

      debugPrint('🧠 AI_FRIEND: ===== ПОЛУЧЕН ОТВЕТ ОТ DEEPSEEK =====');
      debugPrint('🧠 AI_FRIEND: Размер ответа: ${response.length} символов');

      final parsedResponse = _parseResponseWithQuickReplies(response);

      return ChatMessage.ai(
        content: parsedResponse.content,
        quickReplies: parsedResponse.quickReplies,
        metadata: {
          'timestamp': DateTime.now().toIso8601String(),
          'model': 'deepseek-v4-flash',
          'hasQuickReplies': parsedResponse.quickReplies?.isNotEmpty ?? false,
        },
      );
    } catch (e) {
      debugPrint('❌ AI_FRIEND: Ошибка при генерации ответа: $e');
      return ChatMessage.ai(
        content: buildContext != null
            ? buildContext.tr('ai_dietitian_error_response')
            : 'Извините, произошла ошибка при обработке вашего запроса. Попробуйте еще раз.',
        metadata: {'error': true, 'model': 'deepseek-v4-flash'},
      );
    }
  }

  Stream<String> generateGeneralResponseStream({
    required String userMessage,
    List<ChatMessage>? context,
    BuildContext? buildContext,
  }) async* {
    try {
      debugPrint('🧠 AI_FRIEND: ===== ГЕНЕРАЦИЯ ПОТОКОВОГО ОТВЕТА =====');
      debugPrint('🧠 AI_FRIEND: Запрос пользователя: "$userMessage"');

      final language = _determineLanguage(buildContext);
      final prompt = _buildGeneralResponsePrompt(
        userMessage: userMessage,
        context: context,
        language: language,
      );

      debugPrint('🧠 AI_FRIEND: ===== ОТПРАВКА STREAMING ЗАПРОСА =====');
      debugPrint('🧠 AI_FRIEND: Размер промпта: ${prompt.length} символов');

      yield* _client.generateTextStream(prompt);

      debugPrint('🧠 AI_FRIEND: ===== STREAMING ОТВЕТ ЗАВЕРШЕН =====');
    } catch (e) {
      debugPrint('❌ AI_FRIEND: Ошибка при генерации потокового ответа: $e');
      yield buildContext != null
          ? buildContext.tr('ai_dietitian_error_response')
          : 'Извините, произошла ошибка при обработке вашего запроса. Попробуйте еще раз.';
    }
  }

  String _buildGeneralResponsePrompt({
    required String userMessage,
    List<ChatMessage>? context,
    required String language,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('''
You are a warm, supportive AI friend. Your role is to chat, listen, and help with everyday questions or light planning. Be empathetic, respectful, and non-judgmental.

IMPORTANT:
- Keep responses concise unless the user asks for details.
- Ask 1–2 clarifying questions when needed.
- Avoid giving medical, legal, or financial advice. If such topics appear, offer general information and suggest seeking a professional.
- Do not recommend third-party apps/services; if needed, recommend only features of our app.
- Respond ONLY in the user's interface language: $language
- STRICT LANGUAGE RULE: Never change language based on region or model; output must be strictly in $language.
''');

    if (context != null && context.isNotEmpty) {
      buffer.writeln('\nCONVERSATION CONTEXT:');
      final recentMessages = context.length > 6
          ? context.skip(context.length - 6).toList()
          : context;
      for (final message in recentMessages) {
        final sender = message.type == MessageType.user ? 'User' : 'Friend';
        final shortContent = message.content.length > 100
            ? '${message.content.substring(0, 100)}...'
            : message.content;
        buffer.writeln('$sender: $shortContent');
      }
    }

    buffer.writeln('\nUSER MESSAGE: "$userMessage"');

    buffer.writeln('''

When asking a question to the user, you can suggest answer options in two ways:

1) Regular way (with 🔹 symbol) - for simple cases
2) JSON way (preferred) - for better user experience

For the JSON way, add a block at the end of your response:
```json
{
  "quickReplies": [
    {"id": "1", "text": "Yes"},
    {"id": "2", "text": "Not sure"},
    {"id": "3", "text": "Maybe later"}
  ]
}
```

Rules for quickReplies:
- Use when asking a question to the user
- 2-4 options maximum
- Text up to 50 characters each
- Cover main response scenarios
- id should be unique within the response
- If no question to user, don't add quickReplies

CRITICAL: Response language must be: $language
''');

    return buffer.toString();
  }

  ParsedResponse _parseResponseWithQuickReplies(String response) {
    try {
      debugPrint('🔍 AI_FRIEND: Парсинг ответа для извлечения quickReplies');

      final jsonMatch = RegExp(r'```json\s*(\{.*?\})\s*```', dotAll: true)
          .firstMatch(response);

      List<QuickReply>? quickReplies;
      String cleanContent = response;

      if (jsonMatch != null) {
        try {
          final jsonString = jsonMatch.group(1);
          if (jsonString != null) {
            final jsonData =
                Map<String, dynamic>.from(jsonDecode(jsonString) as Map);

            if (jsonData.containsKey('quickReplies')) {
              final repliesJson = jsonData['quickReplies'] as List;
              quickReplies = repliesJson
                  .map((reply) =>
                      QuickReply.fromJson(reply as Map<String, dynamic>))
                  .toList();

              debugPrint(
                  '✅ AI_FRIEND: Найдено ${quickReplies.length} quickReplies из JSON');
            }
          }

          cleanContent = response.replaceAll(jsonMatch.group(0)!, '').trim();
        } catch (e) {
          debugPrint('⚠️ AI_FRIEND: Ошибка парсинга JSON quickReplies: $e');
        }
      }

      if (quickReplies == null || quickReplies.isEmpty) {
        final textOptions = InteractiveParser.extractOptions(cleanContent);
        if (textOptions.isNotEmpty) {
          quickReplies = textOptions
              .map((text) => QuickReply(
                    id: 'text_${text.hashCode}',
                    text: text,
                  ))
              .toList();

          debugPrint(
              '✅ AI_FRIEND: Найдено ${quickReplies.length} quickReplies из текста');
        }
      }

      return ParsedResponse(
        content: _cleanResponse(cleanContent),
        quickReplies: quickReplies,
      );
    } catch (e) {
      debugPrint('❌ AI_FRIEND: Ошибка при парсинге ответа: $e');
      return ParsedResponse(
        content: _cleanResponse(response),
        quickReplies: null,
      );
    }
  }

  String _cleanResponse(String response) {
    String cleaned = response
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .replaceAll(RegExp(r'\s*\{[^{}]*\}\s*'), '')
        .trim();

    if (cleaned.isNotEmpty) {
      return TextFormatter.cleanAndFormatText(cleaned);
    }

    return response.trim();
  }

  String _determineLanguage(BuildContext? context) {
    if (context != null) {
      try {
        final container = ProviderScope.containerOf(context);
        final localizationService =
            container.read(appLocalizationServiceProvider);
        final currentLanguage = localizationService.getCurrentLanguage();
        return _mapLanguageToCode(currentLanguage);
      } catch (e) {
        debugPrint('❌ AI_FRIEND: Ошибка при получении языка: $e');
      }
    }

    return 'English';
  }

  String _mapLanguageToCode(AppLanguage language) {
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
      case AppLanguage.el:
        return 'Greek';
      case AppLanguage.ca:
        return 'Catalan';
      case AppLanguage.fil:
        return 'Filipino';
      case AppLanguage.ms:
        return 'Malay';
      case AppLanguage.id:
        return 'Indonesian';
    }
  }
}

class ParsedResponse {
  final String content;
  final List<QuickReply>? quickReplies;

  const ParsedResponse({
    required this.content,
    this.quickReplies,
  });
}
