import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class PhotosessionGenerationResult {
  const PhotosessionGenerationResult({this.imageUrl, this.errorMessage});

  final String? imageUrl;
  final String? errorMessage;

  bool get isSuccess => imageUrl != null && imageUrl!.isNotEmpty;
}

abstract class PhotosessionGenerationService {
  Future<bool> isAvailable();

  Future<PhotosessionGenerationResult> generateWithFace({
    required String userImageUrl,
    required String scenePrompt,
    String? referenceImageUrl,
    String resolution = '2K',
    String aspectRatio = '3:4',
  });

  Future<PhotosessionGenerationResult> generateImage({
    required String prompt,
    String resolution = '2K',
    String aspectRatio = '3:4',
  });
}

/// Генерация, опирающаяся на изображение пользователя как на референс объекта
/// или стиля — без жёсткой фиксации лица, в отличие от [generateWithFace].
abstract class ReferenceImageGenerationService {
  Future<PhotosessionGenerationResult> generateFromReference({
    required String referenceImageUrl,
    required String prompt,
    String resolution = '2K',
    String aspectRatio = '3:4',
  });
}

class GoogleDirectPhotosessionService implements PhotosessionGenerationService {
  GoogleDirectPhotosessionService({
    String? apiKey,
    String? projectId,
    String? location,
    String? model,
    Duration? timeout,
  })  : _apiKey = apiKey,
        _projectId = projectId,
        _location = location ?? 'global',
        _model = model ?? 'gemini-2.5-flash-image',
        _timeout = timeout ?? const Duration(seconds: 60);

  final String? _apiKey;
  final String? _projectId;
  final String _location;
  final String _model;
  final Duration _timeout;

  @override
  Future<bool> isAvailable() async {
    final hasKey = (_apiKey ?? '').trim().isNotEmpty;
    debugPrint('🟢 GOOGLE_DIRECT: доступность apiKey=$hasKey');
    return hasKey;
  }

  @override
  Future<PhotosessionGenerationResult> generateWithFace({
    required String userImageUrl,
    required String scenePrompt,
    String? referenceImageUrl,
    String resolution = '2K',
    String aspectRatio = '3:4',
  }) async {
    if (!await isAvailable()) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Google API не настроен',
      );
    }

    try {
      final userImageBytes = await _downloadImage(userImageUrl);
      if (userImageBytes == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Не удалось загрузить фото пользователя',
        );
      }

      const faceBodyLock =
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

      final enhancedPrompt = '$faceBodyLock'
          '$scenePrompt\n\n'
          'FINAL REMINDER: The person in the output MUST be photorealistic and '
          'visually identical to the reference photo — same face, same gender, same body. '
          'OUTPUT FORMAT: VERTICAL PORTRAIT, aspect ratio 3:4 (taller than wide, '
          'like a phone photo). NEVER generate a horizontal or landscape image. '
          'Any text or inscriptions shown in the image MUST be rendered '
          'in Cyrillic (Russian) exactly as specified — do NOT translate to English.';

      debugPrint('🟢 GOOGLE_DIRECT: генерация с лицом');
      debugPrint('🟢 GOOGLE_DIRECT: prompt=$enhancedPrompt');

      final base64Image = base64Encode(userImageBytes);
      final payload = _buildPayloadWithImage(
        enhancedPrompt,
        base64Image,
        'image/jpeg',
      );

      final url = _buildUrl();
      final response = await http
          .post(
            Uri.parse(url),
            headers: _buildHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        final error = _extractErrorMessage(response.body) ??
            'HTTP ${response.statusCode}';
        debugPrint('🟢 GOOGLE_DIRECT: ошибка $error');
        return PhotosessionGenerationResult(errorMessage: error);
      }

      String? specificError;
      final imageUrl = await _extractAndSaveImage(
        response.body, 
        scenePrompt,
        onError: (error) => specificError = error,
      );
      
      if (imageUrl == null) {
        return PhotosessionGenerationResult(
          errorMessage: specificError ?? 'Не удалось получить изображение из ответа',
        );
      }

      return PhotosessionGenerationResult(imageUrl: imageUrl);
    } catch (e, st) {
      debugPrint('🟢 GOOGLE_DIRECT: ошибка $e');
      debugPrint('🟢 GOOGLE_DIRECT: стек $st');
      return PhotosessionGenerationResult(errorMessage: 'Ошибка: $e');
    }
  }

  @override
  Future<PhotosessionGenerationResult> generateImage({
    required String prompt,
    String resolution = '2K',
    String aspectRatio = '3:4',
  }) async {
    if (!await isAvailable()) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Google API не настроен',
      );
    }

    try {
      debugPrint('🟢 GOOGLE_DIRECT: генерация text-to-image');
      debugPrint('🟢 GOOGLE_DIRECT: prompt=$prompt');

      final payload = _buildPayload(prompt);
      final url = _buildUrl();
      final response = await http
          .post(
            Uri.parse(url),
            headers: _buildHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        final error = _extractErrorMessage(response.body) ??
            'HTTP ${response.statusCode}';
        debugPrint('🟢 GOOGLE_DIRECT: ошибка $error');
        return PhotosessionGenerationResult(errorMessage: error);
      }

      String? specificError;
      final imageUrl = await _extractAndSaveImage(
        response.body, 
        prompt,
        onError: (error) => specificError = error,
      );
      
      if (imageUrl == null) {
        return PhotosessionGenerationResult(
          errorMessage: specificError ?? 'Не удалось получить изображение из ответа',
        );
      }

      return PhotosessionGenerationResult(imageUrl: imageUrl);
    } catch (e, st) {
      debugPrint('🟢 GOOGLE_DIRECT: ошибка $e');
      debugPrint('🟢 GOOGLE_DIRECT: стек $st');
      return PhotosessionGenerationResult(errorMessage: 'Ошибка: $e');
    }
  }

  String _buildUrl() {
    final apiKey = _apiKey;
    final projectId = _projectId;
    if (projectId != null && projectId.isNotEmpty) {
      return 'https://aiplatform.googleapis.com/v1/projects/'
          '$projectId/locations/$_location/publishers/google/models/'
          '$_model:generateContent?key=$apiKey';
    }
    return 'https://aiplatform.googleapis.com/v1/publishers/google/models/'
        '$_model:generateContent?key=$apiKey';
  }

  Map<String, String> _buildHeaders() {
    return {
      'Content-Type': 'application/json',
    };
  }

  static const _systemInstruction = {
    'parts': [
      {
        'text': 'CRITICAL OUTPUT REQUIREMENTS — ALWAYS APPLY:\n'
            '1. GENDER FROM REFERENCE: When a reference photo is provided, '
            'determine the person\'s gender ONLY from the reference photo. '
            'IGNORE any gender words in the scene description '
            '("young woman", "молодая женщина", "young man", etc.) — '
            'they are generic placeholders. The reference photo is the ground truth.\n'
            '2. IMAGE ORIENTATION: Always generate a VERTICAL PORTRAIT image '
            'with aspect ratio 3:4 (portrait mode, taller than wide, like a phone photo). '
            'NEVER generate a horizontal or landscape image.\n'
            '3. CYRILLIC TEXT: Any text, inscription, greeting, name, date or label '
            'that should appear IN the image MUST be rendered in Cyrillic (Russian) '
            'exactly as specified in the prompt. '
            'Do NOT translate inscriptions to English. '
            'Render them in Cyrillic letters with the requested font, color and position.\n'
            '4. TEXT POSITION: Place inscriptions exactly where specified '
            '(top / center / bottom of frame). Do not move them to the side.',
      }
    ],
  };

  Map<String, dynamic> _buildPayload(String prompt) {
    return {
      'systemInstruction': _systemInstruction,
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        }
      ],
      'generationConfig': {
        'responseModalities': ['IMAGE'],
      },
    };
  }

  Map<String, dynamic> _buildPayloadWithImage(
    String prompt,
    String base64Image,
    String mimeType,
  ) {
    // Image FIRST — Gemini preserves identity better when the reference
    // image appears before the instruction text.
    return {
      'systemInstruction': _systemInstruction,
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'inlineData': {
                'mimeType': mimeType,
                'data': base64Image,
              }
            },
            {'text': prompt},
          ],
        }
      ],
      'generationConfig': {
        'responseModalities': ['IMAGE'],
      },
    };
  }

  Future<List<int>?> _downloadImage(String url) async {
    try {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        final file = File(url);
        if (await file.exists()) {
          debugPrint('🟢 GOOGLE_DIRECT: читаем локальный файл $url');
          return await file.readAsBytes();
        }
        debugPrint('🟢 GOOGLE_DIRECT: локальный файл не найден $url');
        return null;
      }
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      debugPrint('🟢 GOOGLE_DIRECT: ошибка загрузки ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('🟢 GOOGLE_DIRECT: ошибка загрузки: $e');
      return null;
    }
  }

  Future<String?> _extractAndSaveImage(
    String responseBody, 
    String prompt, {
    void Function(String)? onError,
  }) async {
    try {
      final json = jsonDecode(responseBody);
      final base64Image = _extractBase64FromResponse(json);

      if (base64Image == null || base64Image.isEmpty) {
        final finishReason = _extractFinishReason(json);
        final textContent = _extractTextFromResponse(json);
        debugPrint('🟢 GOOGLE_DIRECT: base64 не найден в ответе');
        if (finishReason != null) {
          debugPrint('🟢 GOOGLE_DIRECT: finishReason=$finishReason');
          
          if (finishReason == 'PROHIBITED_CONTENT' || 
              finishReason == 'IMAGE_PROHIBITED_CONTENT' ||
              finishReason == 'BLOCKED_REASON_UNSPECIFIED') {
            onError?.call('Google заблокировал генерацию: контент нарушает политику безопасности. Попробуйте другое фото или описание.');
          }
        }
        if (textContent != null) {
          debugPrint('🟢 GOOGLE_DIRECT: text=${textContent.length > 300 ? textContent.substring(0, 300) : textContent}');
        }
        return null;
      }

      final imageBytes = base64Decode(base64Image);
      final file = await _saveImageToFile(imageBytes, prompt);
      
      debugPrint('🟢 GOOGLE_DIRECT: изображение сохранено ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('🟢 GOOGLE_DIRECT: ошибка извлечения изображения: $e');
      return null;
    }
  }

  String? _extractBase64FromResponse(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final candidates = json['candidates'];
    if (candidates is List) {
      for (final candidate in candidates) {
        if (candidate is! Map<String, dynamic>) continue;
        final content = candidate['content'];
        if (content is! Map<String, dynamic>) continue;
        final parts = content['parts'];
        if (parts is! List) continue;

        for (final part in parts) {
          if (part is! Map<String, dynamic>) continue;
          final inlineData = part['inlineData'] ?? part['inline_data'];
          if (inlineData is Map<String, dynamic>) {
            final data = inlineData['data'];
            if (data is String && data.isNotEmpty) return data;
          }
        }
      }
    }

    return null;
  }

  Future<File> _saveImageToFile(List<int> bytes, String prompt) async {
    final directory = await getApplicationDocumentsDirectory();
    final sanitized = _sanitize(prompt);
    final fileName =
        'google_${sanitized}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final filePath = path.join(directory.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _sanitize(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^а-яёa-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) return 'image';
    return normalized.length > 32 ? normalized.substring(0, 32) : normalized;
  }

  String? _extractFinishReason(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final candidates = json['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final c = candidates.first;
      if (c is Map<String, dynamic>) {
        return c['finishReason']?.toString();
      }
    }
    return null;
  }

  String? _extractTextFromResponse(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final candidates = json['candidates'];
    if (candidates is List) {
      for (final candidate in candidates) {
        if (candidate is! Map<String, dynamic>) continue;
        final content = candidate['content'];
        if (content is! Map<String, dynamic>) continue;
        final parts = content['parts'];
        if (parts is! List) continue;
        for (final part in parts) {
          if (part is! Map<String, dynamic>) continue;
          final text = part['text'];
          if (text is String && text.isNotEmpty) return text;
        }
      }
    }
    return null;
  }

  String? _extractErrorMessage(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final error = json['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) return message;
        }
      }
    } catch (_) {}
    return null;
  }
}
