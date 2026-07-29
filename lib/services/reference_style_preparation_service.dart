import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ai_image_captioning_service.dart';
import 'nutrition_analysis/deepseek/deepseek_client.dart';
import 'reference_face_mask_service.dart';

class PreparedReferenceStyle {
  const PreparedReferenceStyle({
    required this.preparedReferenceFile,
    required this.scenePrompt,
    required this.isMasked,
    this.rawCaption,
  });

  final File preparedReferenceFile;
  final String scenePrompt;
  final bool isMasked;
  final String? rawCaption;
}

abstract class ReferenceStylePreparationService {
  Future<PreparedReferenceStyle> prepare({
    required File referenceImage,
  });
}

class AiReferenceStylePreparationService
    implements ReferenceStylePreparationService {
  AiReferenceStylePreparationService({
    required AiImageCaptioningService captioningService,
    required ReferenceFaceMaskService faceMaskService,
    DeepSeekClient? client,
  })  : _captioningService = captioningService,
        _faceMaskService = faceMaskService,
        _client = client ??
            DeepSeekClient.fromEnvironment(
              enableCaching: false,
              fastMode: true,
            );

  final AiImageCaptioningService _captioningService;
  final ReferenceFaceMaskService _faceMaskService;
  final DeepSeekClient _client;

  @override
  Future<PreparedReferenceStyle> prepare({
    required File referenceImage,
  }) async {
    final preparedReferenceFile =
        await _faceMaskService.suppressFaceIdentity(referenceImage);
    final isMasked = preparedReferenceFile.path != referenceImage.path;
    final rawCaption = await _extractCaption(referenceImage);
    final extractedStyle = await _rewriteStyleDescription(
      rawCaption: rawCaption,
    );

    return PreparedReferenceStyle(
      preparedReferenceFile: preparedReferenceFile,
      scenePrompt: _composeGenerationPrompt(extractedStyle),
      isMasked: isMasked,
      rawCaption: rawCaption,
    );
  }

  Future<String?> _extractCaption(File imageFile) async {
    try {
      final available = await _captioningService.isAvailable();
      if (!available) {
        return null;
      }

      final result = await _captioningService.generateCaptionFromImage(imageFile);
      final caption = result.caption?.trim();
      if (caption == null || caption.isEmpty) {
        return null;
      }
      return caption;
    } catch (e) {
      debugPrint('ReferenceStylePreparationService caption: $e');
      return null;
    }
  }

  Future<String> _rewriteStyleDescription({
    required String? rawCaption,
  }) async {
    final caption = rawCaption?.trim();
    if (caption == null || caption.isEmpty) {
      return _fallbackStyleDescription;
    }

    const systemPrompt = '''
You prepare a style-transfer prompt for multimodal portrait generation.

Goal: extract only reusable scene/style information from a reference photo caption.

Keep:
- environment and location
- composition and framing
- camera distance and angle
- pose and body language
- wardrobe and accessories
- lighting direction and quality
- color palette
- props and background details
- mood and photographic finish

Remove completely:
- face shape, eyes, nose, lips, eyebrows
- age, ethnicity, skin tone
- hair color, hairline, hairstyle when it describes identity
- attractiveness or beauty adjectives
- any wording that copies the person from the reference photo

Rewrite the result in English as a compact production prompt with sections:
SCENE:
WARDROBE:
POSE_AND_FRAMING:
LIGHTING_AND_COLOR:
BACKGROUND_AND_PROPS:
MOOD_AND_RENDERING:

Use neutral wording like "subject" or "person".
Do not mention identity traits from the reference.
Output only the rewritten prompt.''';

    final request = '$systemPrompt\n\nReference caption:\n$caption';

    try {
      final response = await _client.generateText(request);
      final cleaned = response.trim();
      if (cleaned.isEmpty) {
        return _fallbackStyleDescription;
      }
      return cleaned;
    } catch (e) {
      debugPrint('ReferenceStylePreparationService rewrite: $e');
      return _fallbackStyleDescription;
    }
  }

  String _composeGenerationPrompt(String styleDescription) {
    return '''
ROLE SPLIT:
- image1 is only a style and scene guide.
- image2 is the only identity source. Preserve the exact person from image2.
- Never copy face shape, eyes, nose, lips, eyebrows, skin tone, age, ethnicity, hairline, or identity traits from image1.
- Use image1 only for composition, wardrobe, pose, lighting, palette, background, props, and overall photographic direction.

STYLE TARGET:
$styleDescription

OUTPUT GOAL:
Create a new photorealistic vertical portrait of the exact person from image2 inside a scene that matches image1 in framing, pose, styling, lighting, color palette, background, and mood. Keep the result natural, coherent, and realistic.
'''.trim();
  }

  static const String _fallbackStyleDescription = '''
SCENE:
Use image1 as a scene guide for the overall environment, composition, camera distance, and framing.
WARDROBE:
Match the clothing styling and accessories from image1 without copying identity-specific traits.
POSE_AND_FRAMING:
Follow the body pose, shot scale, and camera angle from image1.
LIGHTING_AND_COLOR:
Match the lighting direction, light softness, exposure, and color palette from image1.
BACKGROUND_AND_PROPS:
Recreate the same background mood, props, and spatial layout visible in image1.
MOOD_AND_RENDERING:
Photorealistic portrait, natural skin texture, high detail, professional editorial finish.
''';
}
