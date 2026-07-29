/// Единый источник построения промптов для ApiBost-генерации.
///
/// Используется и серверным прокси-сервисом ([AppwriteApiBostProxyService]),
/// и клиентским relay-сервисом ([ClientApiBostProxyService]), чтобы качество
/// генерации не расходилось между двумя путями.
class ApiBostPromptBuilder {
  ApiBostPromptBuilder._();

  static const Set<String> _supportedAspectRatios = {
    '1:1',
    '3:2',
    '2:3',
    '3:4',
    '4:3',
    '4:5',
    '5:4',
    '9:16',
    '16:9',
    '21:9',
  };

  static String formatAspectRatio(String aspectRatio) {
    return _supportedAspectRatios.contains(aspectRatio) ? aspectRatio : '3:4';
  }

  static List<String> responseModalitiesFor(String model) {
    final normalized = model.toLowerCase();
    if (normalized.contains('flash-image') ||
        normalized.contains('pro-image')) {
      return ['TEXT', 'IMAGE'];
    }
    return ['IMAGE'];
  }

  static String _params(String aspectRatio, double temperature) =>
      '[${formatAspectRatio(aspectRatio)}] [temp=$temperature]';

  static const String faceBodyLock =
      'ABSOLUTE IDENTITY PRESERVATION — HIGHEST PRIORITY, NON-NEGOTIABLE:\n'
      'The provided reference photo shows a REAL, SPECIFIC person. '
      'Reproduce this exact person with 100% photorealistic fidelity.\n'
      'Preserve ALL of the following without ANY deviation:\n'
      '— GENDER: use EXACTLY the gender visible in the reference photo. '
      'If the reference shows a MAN — generate a MAN. '
      'If the reference shows a WOMAN — generate a WOMAN. '
      'IGNORE any gender words ("young woman", "молодая женщина", "man", etc.) '
      'in the scene description below — they are template placeholders. '
      'The reference photo overrides all gender text.\n'
      '— FACE: exact face shape, bone structure, jaw line, cheekbones, '
      'eye shape/color/spacing, nose bridge and tip shape, '
      'lip shape and fullness, eyebrow arch/color/thickness, '
      'hairline, forehead width, chin contour, any visible skin marks\n'
      '— HAIR: exact color, length, texture, volume and style as in reference\n'
      '— SKIN: exact skin tone and texture across face AND all visible body — '
      'do NOT lighten, do NOT over-smooth, do NOT alter\n'
      '— BODY: exact body type and build — do NOT slim down, do NOT idealize, '
      'do NOT make more athletic or muscular; preserve shoulder width, '
      'torso proportions, waist-to-hip ratio, arm/leg proportions\n'
      '— AGE: preserve exact apparent age — do NOT make younger or older\n'
      'This is NOT a person who looks similar — this IS the EXACT same person. '
      'The face must be indistinguishable from the reference photo.\n\n';

  static const Map<String, String> _aspectRatioShape = {
    '1:1': 'a SQUARE image',
    '3:2': 'a HORIZONTAL image (wider than tall)',
    '2:3': 'a VERTICAL image (taller than wide)',
    '3:4': 'a VERTICAL image (taller than wide)',
    '4:3': 'a HORIZONTAL image (wider than tall)',
    '4:5': 'a VERTICAL image (taller than wide)',
    '5:4': 'a HORIZONTAL image (wider than tall)',
    '9:16': 'a TALL VERTICAL image (like a phone story)',
    '16:9': 'a WIDE HORIZONTAL image',
    '21:9': 'an ULTRA-WIDE HORIZONTAL image',
  };

  static String _outputFormatRule(String aspectRatio) {
    final ratio = formatAspectRatio(aspectRatio);
    final shape = _aspectRatioShape[ratio] ?? 'an image';
    return 'OUTPUT FORMAT: $shape, aspect ratio exactly $ratio. '
        'Do NOT change the requested proportions.';
  }

  static const String _textRule =
      'Any text or inscription shown in the image MUST be rendered exactly as '
      'specified in the prompt, in its original language and spelling — '
      'do NOT translate it. If the prompt asks for no text, render no text at all.';

  static String _faceFinalReminder(String aspectRatio) =>
      'FINAL REMINDER: The person in the output MUST be photorealistic and '
      'visually identical to the reference photo — same face, same gender, same body. '
      '${_outputFormatRule(aspectRatio)} $_textRule';

  /// Промпт для генерации с лицом пользователя.
  ///
  /// [hasReference] == true — style-transfer (scenePrompt уже содержит ROLE
  /// SPLIT), face-lock не добавляется.
  /// [includeParams] == false — для моделей, задающих пропорции и temperature
  /// отдельными полями запроса (OpenAI `/v1/images`), где префикс `[3:4]`
  /// был бы лишним текстом в промпте.
  static String buildFacePrompt({
    required String scenePrompt,
    required String aspectRatio,
    required double temperature,
    required bool hasReference,
    bool includeParams = true,
  }) {
    final prefix =
        includeParams ? '${_params(aspectRatio, temperature)}\n' : '';
    if (hasReference) {
      return '$prefix$scenePrompt';
    }
    return '$prefix$faceBodyLock$scenePrompt\n\n'
        '${_faceFinalReminder(aspectRatio)}';
  }

  /// Промпт для генерации по изображению-референсу (объект или стиль).
  ///
  /// В отличие от [buildFacePrompt] не навязывает сохранение лица: как именно
  /// использовать референс, описано в самом [prompt].
  static String buildReferencePrompt({
    required String prompt,
    required String aspectRatio,
    required double temperature,
    bool includeParams = true,
  }) {
    final prefix =
        includeParams ? '${_params(aspectRatio, temperature)}\n' : '';
    return '$prefix'
        'The attached image is a reference provided by the user. '
        'Follow the instructions below on how to use it, and always produce a '
        'brand new image — never return the attached image unchanged.\n\n'
        '$prompt\n\n'
        '${_outputFormatRule(aspectRatio)} $_textRule';
  }

  /// Промпт для text-to-image генерации без фото пользователя.
  static String buildImagePrompt({
    required String prompt,
    required String aspectRatio,
    required double temperature,
    bool includeParams = true,
  }) {
    final prefix =
        includeParams ? '${_params(aspectRatio, temperature)}\n' : '';
    return '$prefix$prompt\n\n'
        '${_outputFormatRule(aspectRatio)} $_textRule '
        'Render only what the prompt describes: do not add people, objects, '
        'logos or watermarks that were not requested.';
  }
}
