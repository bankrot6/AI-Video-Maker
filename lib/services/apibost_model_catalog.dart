/// Транспорт, по которому модель доступна в ApiBost.
enum ApiBostTransport {
  /// `/v1beta/models/{model}:generateContent` — Gemini-совместимые модели.
  geminiGenerateContent,

  /// `/v1/images/generations` и `/v1/images/edits` — OpenAI-совместимые модели.
  openAiImages,

  /// `/v1/chat/completions` — модели, отдающие картинку в ответе чата.
  openAiChatCompletions,

  /// `/v1/chat/completions` — Veo-модели, отдающие ссылку на MP4 в ответе чата.
  videoChatCompletions,
}

/// Единый источник знаний о том, как обращаться к конкретной модели ApiBost.
///
/// Транспорт и возможности модели описаны здесь, а не разбросаны по сервисам,
/// поэтому добавление новой модели не требует правок в самих сервисах.
abstract final class ApiBostModelCatalog {
  static const String gptImage15 = 'gpt-image-1.5';
  static const String gptImage2 = 'gpt-image-2';
  static const String grokImage = 'grok-3-image';

  static const String veoLite = 'veo3.1-lite';
  static const String veoFast = 'veo3.1-fast';
  static const String veoPro = 'veo3.1-pro';
  static const String veoFastPreview = 'veo-3.1-fast-generate-preview';
  static const String veoPro4k = 'veo3.1-pro-4k';

  static const Set<String> _openAiImageModels = {gptImage15, gptImage2};
  static const Set<String> _chatCompletionModels = {grokImage};

  /// Veo-модели ApiBost: принимают только текст и возвращают ссылку на MP4.
  static const Set<String> _videoModels = {
    veoLite,
    veoFast,
    veoPro,
    veoFastPreview,
    veoPro4k,
  };

  /// Модели, принимающие только текст: редактирование и перенос стиля по фото
  /// для них недоступны.
  static const Set<String> _textOnlyModels = {grokImage, ..._videoModels};

  static bool isVideoModel(String model) =>
      _videoModels.contains(_normalize(model));

  /// Veo принимает только четыре пропорции, тогда как в приложении форматов
  /// кадра больше (3:4, 4:5, 2:3 и т.д.), поэтому запрошенное значение
  /// приводится к ближайшему поддерживаемому по соотношению ширины к высоте.
  static const Set<String> _videoAspectRatios = {
    '16:9',
    '9:16',
    '1:1',
    '21:9',
  };

  static const String defaultVideoAspectRatio = '16:9';

  /// Максимальная длительность клипа у Veo — 8 секунд.
  static const int maxVideoDurationSeconds = 8;

  /// Релей ApiBost отвечает 422 `string_too_long`, если поле `prompt` длиннее
  /// 2000 символов. Лимит считается по всей строке, включая директивы формата.
  static const int maxVideoPromptLength = 2000;

  static String videoAspectRatioFor(String aspectRatio) {
    final requested = aspectRatio.trim();
    if (_videoAspectRatios.contains(requested)) return requested;

    final ratio = _parseRatio(requested);
    if (ratio == null) return defaultVideoAspectRatio;

    var best = defaultVideoAspectRatio;
    var bestDistance = double.infinity;
    for (final candidate in _videoAspectRatios) {
      final candidateRatio = _parseRatio(candidate);
      if (candidateRatio == null) continue;
      final distance = (candidateRatio - ratio).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }

  static double? _parseRatio(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final width = double.tryParse(parts[0].trim());
    final height = double.tryParse(parts[1].trim());
    if (width == null || height == null || height == 0) return null;
    return width / height;
  }

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
    if (_videoModels.contains(normalized)) {
      return ApiBostTransport.videoChatCompletions;
    }
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
