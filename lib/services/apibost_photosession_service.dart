import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../config/ai_proxy_config.dart';
import 'photosession_generation_router.dart';

class ApiBostPhotosessionService implements PhotosessionGenerationService {
  ApiBostPhotosessionService({
    String? apiKey,
    String model = 'gemini-2.5-flash-image',
    double temperature = 0.7,
    Duration? timeout,
  })  : _apiKey = apiKey,
        _model = model,
        _temperature = temperature,
        _baseUrl = AiProxyConfig.apiBostBaseUrl() ?? 'https://apibost.com',
        _timeout = timeout ?? const Duration(seconds: 90);

  final String? _apiKey;
  final String _model;
  final double _temperature;
  final String _baseUrl;
  final Duration _timeout;
  bool get _useProxy => _baseUrl.startsWith('http://') && _baseUrl.contains('/apibost');

  @override
  Future<bool> isAvailable() async {
    final ok = _useProxy || (_apiKey ?? '').trim().isNotEmpty;
    debugPrint('🔵 API_BOST: доступность=$ok proxy=$_useProxy');
    return ok;
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
        errorMessage: 'ApiBost API не настроен',
      );
    }

    try {
      final userImageBytes = await _downloadImage(userImageUrl);
      if (userImageBytes == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Не удалось загрузить фото пользователя',
        );
      }

      List<int>? referenceImageBytes;
      if (referenceImageUrl != null) {
        referenceImageBytes = await _downloadImage(referenceImageUrl);
        debugPrint(
          '🔵 API_BOST: референс ${referenceImageBytes != null ? "загружен" : "не найден"}',
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

      final apiBostParams = '[${_formatAspectRatio(aspectRatio)}] [temp=$_temperature]';
      final enhancedPrompt = '$apiBostParams\n'
          '$faceBodyLock'
          '$scenePrompt\n\n'
          'FINAL REMINDER: The person in the output MUST be photorealistic and '
          'visually identical to the reference photo — same face, same gender, same body. '
          'OUTPUT FORMAT: VERTICAL PORTRAIT, aspect ratio 3:4 (taller than wide, '
          'like a phone photo). NEVER generate a horizontal or landscape image. '
          'Any text or inscriptions shown in the image MUST be rendered '
          'in Cyrillic (Russian) exactly as specified — do NOT translate to English.';

      debugPrint('🔵 API_BOST: генерация с лицом, модель=$_model');
      debugPrint('🔵 API_BOST: prompt=$enhancedPrompt');

      final base64UserImage = base64Encode(userImageBytes);
      final payload = referenceImageBytes != null
          ? _buildPayloadWithTwoImages(
              enhancedPrompt,
              base64Encode(referenceImageBytes),
              base64UserImage,
            )
          : _buildPayloadWithImage(enhancedPrompt, base64UserImage, 'image/jpeg');

      final response = await http
          .post(
            Uri.parse(_buildUrl()),
            headers: _buildHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        final error =
            _extractErrorMessage(response.body) ?? 'HTTP ${response.statusCode}';
        debugPrint('🔵 API_BOST: ошибка $error');
        return PhotosessionGenerationResult(errorMessage: error);
      }

      String? specificError;
      final imageUrl = await _extractAndSaveImage(
        response.body,
        scenePrompt,
        onError: (e) => specificError = e,
      );

      if (imageUrl == null) {
        return PhotosessionGenerationResult(
          errorMessage: specificError ?? 'Не удалось получить изображение из ответа',
        );
      }

      return PhotosessionGenerationResult(imageUrl: imageUrl);
    } catch (e, st) {
      debugPrint('🔵 API_BOST: ошибка $e');
      debugPrint('🔵 API_BOST: стек $st');
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
        errorMessage: 'ApiBost API не настроен',
      );
    }

    try {
      final apiBostParams = '[${_formatAspectRatio(aspectRatio)}] [temp=$_temperature]';
      final enrichedPrompt = '$apiBostParams $prompt';

      debugPrint('🔵 API_BOST: text-to-image, модель=$_model');
      debugPrint('🔵 API_BOST: prompt=$enrichedPrompt');

      final payload = _buildPayload(enrichedPrompt);
      final response = await http
          .post(
            Uri.parse(_buildUrl()),
            headers: _buildHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        final error =
            _extractErrorMessage(response.body) ?? 'HTTP ${response.statusCode}';
        debugPrint('🔵 API_BOST: ошибка $error');
        return PhotosessionGenerationResult(errorMessage: error);
      }

      String? specificError;
      final imageUrl = await _extractAndSaveImage(
        response.body,
        prompt,
        onError: (e) => specificError = e,
      );

      if (imageUrl == null) {
        return PhotosessionGenerationResult(
          errorMessage: specificError ?? 'Не удалось получить изображение из ответа',
        );
      }

      return PhotosessionGenerationResult(imageUrl: imageUrl);
    } catch (e, st) {
      debugPrint('🔵 API_BOST: ошибка $e');
      debugPrint('🔵 API_BOST: стек $st');
      return PhotosessionGenerationResult(errorMessage: 'Ошибка: $e');
    }
  }

  String _buildUrl() =>
      '$_baseUrl/v1beta/models/$_model:generateContent';

  Map<String, String> _buildHeaders() => {
        'Content-Type': 'application/json',
        if (!_useProxy) 'Authorization': 'Bearer $_apiKey',
      };

  Map<String, dynamic> _buildPayload(String prompt) => {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          }
        ],
      };

  Map<String, dynamic> _buildPayloadWithImage(
    String prompt,
    String base64Image,
    String mimeType,
  ) =>
      {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'inlineData': {'mimeType': mimeType, 'data': base64Image},
              },
              {'text': prompt},
            ],
          }
        ],
      };

  Map<String, dynamic> _buildPayloadWithTwoImages(
    String prompt,
    String base64RefImage,
    String base64UserImage,
  ) =>
      {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'inlineData': {'mimeType': 'image/jpeg', 'data': base64RefImage},
              },
              {
                'inlineData': {'mimeType': 'image/jpeg', 'data': base64UserImage},
              },
              {'text': prompt},
            ],
          }
        ],
      };

  String _formatAspectRatio(String aspectRatio) {
    const supported = {
      '1:1', '3:2', '2:3', '3:4', '4:3', '4:5', '5:4', '9:16', '16:9', '21:9',
    };
    return supported.contains(aspectRatio) ? aspectRatio : '3:4';
  }

  Future<List<int>?> _downloadImage(String url) async {
    try {
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        final file = File(url);
        if (await file.exists()) {
          debugPrint('🔵 API_BOST: читаем локальный файл $url');
          return await file.readAsBytes();
        }
        debugPrint('🔵 API_BOST: локальный файл не найден $url');
        return null;
      }
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode == 200) return response.bodyBytes;
      debugPrint('🔵 API_BOST: ошибка загрузки ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('🔵 API_BOST: ошибка загрузки: $e');
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
        debugPrint('🔵 API_BOST: base64 не найден в ответе');
        if (finishReason != null) {
          debugPrint('🔵 API_BOST: finishReason=$finishReason');
          if (finishReason == 'PROHIBITED_CONTENT' ||
              finishReason == 'IMAGE_PROHIBITED_CONTENT' ||
              finishReason == 'BLOCKED_REASON_UNSPECIFIED') {
            onError?.call(
              'ApiBost заблокировал генерацию: контент нарушает политику безопасности. '
              'Попробуйте другое фото или описание.',
            );
          }
        }
        if (textContent != null) {
          debugPrint(
            '🔵 API_BOST: text=${textContent.length > 300 ? textContent.substring(0, 300) : textContent}',
          );
        }
        return null;
      }

      final imageBytes = base64Decode(base64Image);
      final file = await _saveImageToFile(imageBytes, prompt);
      debugPrint('🔵 API_BOST: изображение сохранено ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('🔵 API_BOST: ошибка извлечения изображения: $e');
      return null;
    }
  }

  String? _extractBase64FromResponse(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final candidates = json['candidates'];
    if (candidates is! List) return null;
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
    return null;
  }

  String? _extractFinishReason(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final candidates = json['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final c = candidates.first;
      if (c is Map<String, dynamic>) return c['finishReason']?.toString();
    }
    return null;
  }

  String? _extractTextFromResponse(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final candidates = json['candidates'];
    if (candidates is! List) return null;
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

  Future<File> _saveImageToFile(List<int> bytes, String prompt) async {
    final directory = await getApplicationDocumentsDirectory();
    final sanitized = _sanitize(prompt);
    final fileName =
        'apibost_${sanitized}_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
}
