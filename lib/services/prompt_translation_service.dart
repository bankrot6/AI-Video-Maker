import 'package:flutter/foundation.dart';
import 'nutrition_analysis/deepseek/deepseek_client.dart';

class PromptTranslationService {
  PromptTranslationService({DeepSeekClient? client})
      : _client = client ?? DeepSeekClient.fromEnvironment(fastMode: true);

  final DeepSeekClient _client;
  final Map<String, String> _cache = {};

  static final _cyrillicQuoteRegex = RegExp(
    r'([«""])([^»""]{1,200}?[\u0400-\u04FF][^»""]{0,200})([»""])',
  );

  /// Заменяет кириллические надписи в кавычках на плейсхолдеры,
  /// возвращает модифицированный текст и словарь восстановления.
  (String, Map<String, String>) _extractCyrillicQuotes(String text) {
    final placeholders = <String, String>{};
    var index = 0;
    final result = text.replaceAllMapped(_cyrillicQuoteRegex, (m) {
      final key = '__INSCRIPTION_${index++}__';
      placeholders[key] = '${m[1]}${m[2]}${m[3]}';
      return key;
    });
    return (result, placeholders);
  }

  String _restoreCyrillicQuotes(String text, Map<String, String> placeholders) {
    var result = text;
    placeholders.forEach((key, value) {
      result = result.replaceAll(key, value);
    });
    return result;
  }

  Future<String> translateToEnglish(String russianPrompt) async {
    final trimmed = russianPrompt.trim();
    if (trimmed.isEmpty) return '';

    if (_cache.containsKey(trimmed)) {
      debugPrint('PromptTranslation: используем кэш');
      return _cache[trimmed]!;
    }

    try {
      debugPrint('PromptTranslation: перевод промта (${trimmed.length} символов)');

      final (textForTranslation, placeholders) = _extractCyrillicQuotes(trimmed);
      if (placeholders.isNotEmpty) {
        debugPrint(
          'PromptTranslation: защищено ${placeholders.length} кириллических надписей',
        );
      }

      const systemPrompt =
          'You are a professional translator for AI image generation prompts.\n'
          'Translate the Russian prompt to English.\n'
          'CRITICAL RULES:\n'
          '— Preserve ALL technical details: lighting, composition, camera settings, colors, textures\n'
          '— Keep the same structure and level of detail\n'
          '— Use photography/cinematography terminology\n'
          '— Do NOT simplify or paraphrase\n'
          '— Placeholders like __INSCRIPTION_0__ must be kept EXACTLY as-is — do NOT translate or remove them\n'
          '— Always add at the end of the translated text: "MANDATORY: vertical portrait orientation, '
          'aspect ratio 3:4 (portrait mode, taller than wide). '
          'DO NOT generate a horizontal or landscape image."\n'
          '— Output ONLY the English translation, nothing else\n'
          '— Do NOT add any explanations or comments';

      final userPrompt = 'Translate this prompt to English:\n\n$textForTranslation';
      final fullPrompt = '$systemPrompt\n\n$userPrompt';

      final result = await _client.generateText(fullPrompt);
      var translated = result.trim();

      if (translated.isEmpty) {
        debugPrint('PromptTranslation: получен пустой перевод, используем оригинал');
        return trimmed;
      }

      if (placeholders.isNotEmpty) {
        translated = _restoreCyrillicQuotes(translated, placeholders);
        debugPrint('PromptTranslation: кириллические надписи восстановлены');
      }

      debugPrint('PromptTranslation: перевод готов (${translated.length} символов)');
      _cache[trimmed] = translated;

      return translated;
    } catch (e) {
      debugPrint('PromptTranslation: ошибка перевода $e, используем оригинал');
      return trimmed;
    }
  }

  void clearCache() {
    _cache.clear();
  }
}
