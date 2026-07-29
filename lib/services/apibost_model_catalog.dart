/// Транспорт, по которому модель доступна в ApiBost.
enum ApiBostTransport {
  /// `/v1beta/models/{model}:generateContent` — Gemini-совместимые модели.
  geminiGenerateContent,

  /// `/v1/images/generations` и `/v1/images/edits` — OpenAI-совместимые модели.
  openAiImages,

  /// `/v1/chat/completions` — модели, отдающие картинку в ответе чата.
  openAiChatCompletions,
}

/// Единый источник знаний о том, как обращаться к конкретной модели ApiBost.
///
/// Транспорт и возможности модели описаны здесь, а не разбросаны по сервисам,
/// поэтому добавление новой модели не требует правок в самих сервисах.
abstract final class ApiBostModelCatalog {
  static const String gptImage15 = 'gpt-image-1.5';
  static const String gptImage2 = 'gpt-image-2';
  static const String grokImage = 'grok-3-image';

  static const Set<String> _openAiImageModels = {gptImage15, gptImage2};
  static const Set<String> _chatCompletionModels = {grokImage};

  /// Модели, принимающие только текст: редактирование и перенос стиля по фото
  /// для них недоступны.
  static const Set<String> _textOnlyModels = {grokImage};

  static const String squareSize = '1024x1024';
  static const String portraitSize = '1024x1536';
  static const String landscapeSize = '1536x1024';

  static const Set<String> _landscapeRatios = {
    '3:2',
    '4:3',
    '5:4',
    '16:9',
    '21:9',
  };

  static String _normalize(String model) => model.trim().toLowerCase();

  static ApiBostTransport transportFor(String model) {
    final normalized = _normalize(model);
    if (_openAiImageModels.contains(normalized)) {
      return ApiBostTransport.openAiImages;
    }
    if (_chatCompletionModels.contains(normalized)) {
      return ApiBostTransport.openAiChatCompletions;
    }
    return ApiBostTransport.geminiGenerateContent;
  }

  static bool supportsImageInput(String model) {
    return !_textOnlyModels.contains(_normalize(model));
  }

  /// OpenAI-модели задают пропорции параметром `size`, а не текстом промпта.
  static String sizeForAspectRatio(String aspectRatio) {
    final ratio = aspectRatio.trim();
    if (ratio == '1:1') return squareSize;
    if (_landscapeRatios.contains(ratio)) return landscapeSize;
    return portraitSize;
  }
}
