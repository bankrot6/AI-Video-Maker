import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'ai_image_generation_service.dart';

class NanoBananaImageGenerationService implements AiImageGenerationService {
  final String? _apiKey;
  final String? _accessToken;
  final String? _projectId;
  final String _location;
  final String _model;
  final String? _baseUrlOverride;
  final Duration _timeout;
  final bool _preferStream;

  NanoBananaImageGenerationService({
    String? apiKey,
    String? accessToken,
    String? projectId,
    String? location,
    String? baseUrl,
    String? model,
    Duration? timeout,
    bool? preferStream,
  })  : _apiKey = apiKey ?? dotenv.env['NANO_BANANA_API_KEY'],
        _accessToken = accessToken ?? dotenv.env['NANO_BANANA_ACCESS_TOKEN'],
        _projectId = projectId ??
            dotenv.env['NANO_BANANA_PROJECT_ID'] ??
            dotenv.env['GOOGLE_CLOUD_PROJECT'] ??
            dotenv.env['PROJECT_ID'],
        _location = location ?? dotenv.env['NANO_BANANA_LOCATION'] ?? 'global',
        _model = model ??
            dotenv.env['NANO_BANANA_MODEL'] ??
            'gemini-2.5-flash-image',
        _baseUrlOverride = baseUrl ?? dotenv.env['NANO_BANANA_BASE_URL'],
        _timeout = timeout ?? const Duration(seconds: 45),
        _preferStream = preferStream ??
            (dotenv.env['NANO_BANANA_STREAM']?.toLowerCase() == 'true');

  @override
  Future<bool> isAvailable() async {
    final baseUrl = _resolveBaseUrl();
    final hasUrl = baseUrl != null && baseUrl.isNotEmpty;
    final hasToken = (_accessToken ?? '').isNotEmpty;
    final hasKey = (_apiKey ?? '').isNotEmpty;
    final requiresToken = baseUrl != null && _requiresAccessToken(baseUrl);
    final available =
        hasUrl && (requiresToken ? hasToken : (hasToken || hasKey));
    debugPrint(
        '🍌 NANO_BANANA: доступность token=$hasToken apiKey=$hasKey baseUrl=$hasUrl requiresToken=$requiresToken');
    return available;
  }

  @override
  Future<AiImageGenerationResult> generateImageFromPrompt(
    String prompt, {
    int batchSize = 1,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      debugPrint('🍌 NANO_BANANA: пустой промпт');
      return const AiImageGenerationResult(
          errorMessage: 'Пустой промпт. Напишите, что нужно сгенерировать.');
    }
    if (!await isAvailable()) {
      debugPrint('🍌 NANO_BANANA: сервис не настроен');
      return const AiImageGenerationResult(
        errorMessage: 'Сервис не настроен. Проверьте ключи и URL в .env файле.',
      );
    }

    try {
      final baseUrl = _resolveBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        debugPrint('🍌 NANO_BANANA: baseUrl не задан');
        return const AiImageGenerationResult(
          errorMessage: 'Не задан URL для модели (NANO_BANANA_BASE_URL).',
        );
      }
      final token = _accessToken;
      final apiKey = _apiKey;
      final hasToken = token != null && token.isNotEmpty;
      final hasKey = apiKey != null && apiKey.isNotEmpty;
      if (_requiresAccessToken(baseUrl) && !hasToken) {
        debugPrint('🍌 NANO_BANANA: нужен access token для Vertex AI');
        return const AiImageGenerationResult(
          errorMessage:
              'Для этого endpoint нужен access token. Используйте project URL или OAuth.',
        );
      }
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      var requestUrl = baseUrl;
      if (hasToken) {
        headers['Authorization'] = 'Bearer $token';
      } else if (hasKey) {
        requestUrl = _applyApiKeyToUrl(requestUrl, apiKey);
      }

      final supportsImage = _supportsImageOutput();
      final payload = _isVertexUrl(baseUrl)
          ? _buildVertexPayload(trimmed, supportsImage: supportsImage)
          : _buildGenericPayload(trimmed);

      final response = await http
          .post(
            Uri.parse(requestUrl),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
            '🍌 NANO_BANANA: HTTP ${response.statusCode} ${response.body}');
        final error = _extractErrorMessage(response.body) ??
            'Ошибка запроса: HTTP ${response.statusCode}';
        return AiImageGenerationResult(errorMessage: error);
      }

      final data = _decodeResponseBody(response.body);
      if (data == null) {
        debugPrint('🍌 NANO_BANANA: не удалось разобрать ответ');
        return const AiImageGenerationResult(
          errorMessage: 'Не удалось разобрать ответ модели.',
        );
      }
      final base64Image = _extractBase64(data);
      if (base64Image != null && base64Image.isNotEmpty) {
        final bytes = _decodeBase64(base64Image);
        if (bytes == null) {
          debugPrint('🍌 NANO_BANANA: не удалось декодировать base64');
          return const AiImageGenerationResult(
            errorMessage: 'Не удалось декодировать изображение.',
          );
        }
        final file = await _saveBytes(bytes, trimmed);
        return AiImageGenerationResult(file: file);
      }

      final imageUrl = _extractUrl(data);
      if (imageUrl == null || imageUrl.isEmpty) {
        debugPrint('🍌 NANO_BANANA: изображение не найдено в ответе');
        final text = _extractText(data);
        if (text != null && text.isNotEmpty) {
          return AiImageGenerationResult(
            errorMessage: _truncate(
              'Модель вернула только текст: $text',
            ),
          );
        }
        if (!supportsImage) {
          return AiImageGenerationResult(
            errorMessage: 'Модель $_model не поддерживает вывод изображений. '
                'Используйте gemini-2.5-flash-image.',
          );
        }
        return const AiImageGenerationResult(
          errorMessage: 'Модель не вернула изображение.',
        );
      }

      final bytes = await _downloadImage(imageUrl);
      if (bytes == null) {
        return const AiImageGenerationResult(
          errorMessage: 'Не удалось скачать изображение.',
        );
      }
      final file = await _saveBytes(bytes, trimmed,
          extension: _guessExtension(imageUrl));
      return AiImageGenerationResult(file: file);
    } catch (e) {
      debugPrint('🍌 NANO_BANANA: ошибка генерации: $e');
      return AiImageGenerationResult(
        errorMessage: 'Ошибка генерации: $e',
      );
    }
  }

  @override
  Future<AiImageGenerationResult> generateImageFromPromptWithReference({
    required String prompt,
    required File referenceImage,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      debugPrint('🍌 NANO_BANANA: пустой промпт');
      return const AiImageGenerationResult(
          errorMessage: 'Пустой промпт. Напишите, что нужно сгенерировать.');
    }
    if (!referenceImage.existsSync()) {
      debugPrint('🍌 NANO_BANANA: reference image not found');
      return generateImageFromPrompt(trimmed);
    }
    if (!await isAvailable()) {
      debugPrint('🍌 NANO_BANANA: сервис не настроен');
      return const AiImageGenerationResult(
        errorMessage: 'Сервис не настроен. Проверьте ключи и URL в .env файле.',
      );
    }

    try {
      final baseUrl = _resolveBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        debugPrint('🍌 NANO_BANANA: baseUrl не задан');
        return const AiImageGenerationResult(
          errorMessage: 'Не задан URL для модели (NANO_BANANA_BASE_URL).',
        );
      }
      final token = _accessToken;
      final apiKey = _apiKey;
      final hasToken = token != null && token.isNotEmpty;
      final hasKey = apiKey != null && apiKey.isNotEmpty;
      if (_requiresAccessToken(baseUrl) && !hasToken) {
        debugPrint('🍌 NANO_BANANA: нужен access token для Vertex AI');
        return const AiImageGenerationResult(
          errorMessage:
              'Для этого endpoint нужен access token. Используйте project URL или OAuth.',
        );
      }
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      var requestUrl = baseUrl;
      if (hasToken) {
        headers['Authorization'] = 'Bearer $token';
      } else if (hasKey) {
        requestUrl = _applyApiKeyToUrl(requestUrl, apiKey);
      }

      final supportsImage = _supportsImageOutput();
      final bytes = await referenceImage.readAsBytes();
      final base64Image = base64Encode(bytes);
      final mimeType = _guessMimeType(referenceImage.path);
      final payload = _isVertexUrl(baseUrl)
          ? _buildVertexPayloadWithImage(
              trimmed,
              base64Image,
              mimeType,
              supportsImage: supportsImage,
            )
          : _buildGenericPayloadWithImage(
              trimmed,
              base64Image,
              mimeType,
            );

      final response = await http
          .post(
            Uri.parse(requestUrl),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
            '🍌 NANO_BANANA: HTTP ${response.statusCode} ${response.body}');
        final error = _extractErrorMessage(response.body) ??
            'Ошибка запроса: HTTP ${response.statusCode}';
        return AiImageGenerationResult(errorMessage: error);
      }

      final data = _decodeResponseBody(response.body);
      if (data == null) {
        debugPrint('🍌 NANO_BANANA: не удалось разобрать ответ');
        return const AiImageGenerationResult(
          errorMessage: 'Не удалось разобрать ответ модели.',
        );
      }
      final base64ImageResult = _extractBase64(data);
      if (base64ImageResult != null && base64ImageResult.isNotEmpty) {
        final decoded = _decodeBase64(base64ImageResult);
        if (decoded == null) {
          debugPrint('🍌 NANO_BANANA: не удалось декодировать base64');
          return const AiImageGenerationResult(
            errorMessage: 'Не удалось декодировать изображение.',
          );
        }
        final file = await _saveBytes(decoded, trimmed);
        return AiImageGenerationResult(file: file);
      }

      final imageUrl = _extractUrl(data);
      if (imageUrl == null || imageUrl.isEmpty) {
        debugPrint('🍌 NANO_BANANA: изображение не найдено в ответе');
        final text = _extractText(data);
        if (text != null && text.isNotEmpty) {
          return AiImageGenerationResult(
            errorMessage: _truncate(
              'Модель вернула только текст: $text',
            ),
          );
        }
        if (!supportsImage) {
          return AiImageGenerationResult(
            errorMessage: 'Модель $_model не поддерживает вывод изображений. '
                'Используйте gemini-2.5-flash-image.',
          );
        }
        return const AiImageGenerationResult(
          errorMessage: 'Модель не вернула изображение.',
        );
      }

      final downloaded = await _downloadImage(imageUrl);
      if (downloaded == null) {
        return const AiImageGenerationResult(
          errorMessage: 'Не удалось скачать изображение.',
        );
      }
      final file = await _saveBytes(
        downloaded,
        trimmed,
        extension: _guessExtension(imageUrl),
      );
      return AiImageGenerationResult(file: file);
    } catch (e) {
      debugPrint('🍌 NANO_BANANA: ошибка генерации: $e');
      return AiImageGenerationResult(
        errorMessage: 'Ошибка генерации: $e',
      );
    }
  }

  Future<Uint8List?> _downloadImage(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        debugPrint('🍌 NANO_BANANA: ошибка скачивания ${response.statusCode}');
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('🍌 NANO_BANANA: ошибка скачивания: $e');
      return null;
    }
  }

  Map<String, dynamic> _buildVertexPayload(
    String prompt, {
    required bool supportsImage,
  }) {
    return {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        }
      ],
      'generationConfig': {
        'responseModalities': supportsImage ? ['IMAGE'] : ['TEXT'],
      },
    };
  }

  Map<String, dynamic> _buildVertexPayloadWithImage(
    String prompt,
    String base64Image,
    String mimeType, {
    required bool supportsImage,
  }) {
    return {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
            {
              'inlineData': {
                'mimeType': mimeType,
                'data': base64Image,
              }
            },
          ],
        }
      ],
      'generationConfig': {
        'responseModalities': supportsImage ? ['IMAGE'] : ['TEXT'],
      },
    };
  }

  Map<String, dynamic> _buildGenericPayload(String prompt) {
    return {
      'prompt': prompt,
      if (_model.isNotEmpty) 'model': _model,
      'n': 1,
      'size': '1024x1024',
    };
  }

  Map<String, dynamic> _buildGenericPayloadWithImage(
    String prompt,
    String base64Image,
    String mimeType,
  ) {
    final payload = _buildGenericPayload(prompt);
    payload['image_base64'] = base64Image;
    payload['image_mime_type'] = mimeType;
    return payload;
  }

  Uint8List? _decodeBase64(String raw) {
    final cleaned = _stripDataUrlPrefix(raw).replaceAll(RegExp(r'\s+'), '');
    try {
      return base64Decode(cleaned);
    } catch (_) {
      return null;
    }
  }

  String _stripDataUrlPrefix(String value) {
    final index = value.indexOf('base64,');
    if (value.startsWith('data:') && index != -1) {
      return value.substring(index + 7);
    }
    return value;
  }

  String? _extractBase64(dynamic data) {
    if (data is List) {
      for (final item in data) {
        final nested = _extractBase64(item);
        if (nested != null && nested.isNotEmpty) return nested;
      }
      return null;
    }
    if (data is Map<String, dynamic>) {
      final vertex = _extractVertexInlineData(data);
      if (vertex != null) return vertex;
      for (final key in [
        'image_base64',
        'imageBase64',
        'base64',
        'b64_json',
      ]) {
        final value = data[key];
        if (value is String && value.isNotEmpty) return value;
      }
      final result = data['result'];
      final nested = _extractBase64(result);
      if (nested != null) return nested;
      final images = data['images'];
      if (images is List && images.isNotEmpty) {
        final nested = _extractBase64(images.first);
        if (nested != null) return nested;
      }
      final items = data['data'];
      if (items is List && items.isNotEmpty) {
        final nested = _extractBase64(items.first);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  String? _extractUrl(dynamic data) {
    if (data is List) {
      for (final item in data) {
        final nested = _extractUrl(item);
        if (nested != null && nested.isNotEmpty) return nested;
      }
      return null;
    }
    if (data is Map<String, dynamic>) {
      for (final key in ['image_url', 'imageUrl', 'url']) {
        final value = data[key];
        if (value is String && value.isNotEmpty) return value;
      }
      final result = data['result'];
      final nested = _extractUrl(result);
      if (nested != null) return nested;
      final images = data['images'];
      if (images is List && images.isNotEmpty) {
        final nested = _extractUrl(images.first);
        if (nested != null) return nested;
      }
      final items = data['data'];
      if (items is List && items.isNotEmpty) {
        final nested = _extractUrl(items.first);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  String? _extractVertexInlineData(Map<String, dynamic> data) {
    final candidates = data['candidates'];
    if (candidates is List) {
      for (final candidate in candidates) {
        if (candidate is! Map<String, dynamic>) continue;
        final content = candidate['content'];
        final parts =
            (content is Map<String, dynamic>) ? content['parts'] : null;
        final extracted = _extractInlineDataFromParts(parts);
        if (extracted != null) return extracted;
      }
    }
    final content = data['content'];
    if (content is Map<String, dynamic>) {
      final extracted = _extractInlineDataFromParts(content['parts']);
      if (extracted != null) return extracted;
    }
    return null;
  }

  String? _extractInlineDataFromParts(dynamic parts) {
    if (parts is! List) return null;
    for (final part in parts) {
      if (part is! Map<String, dynamic>) continue;
      final inline = part['inlineData'] ?? part['inline_data'];
      if (inline is Map<String, dynamic>) {
        final data = inline['data'];
        if (data is String && data.isNotEmpty) return data;
      }
      final data = part['data'];
      if (data is String && data.isNotEmpty) return data;
    }
    return null;
  }

  String? _extractText(dynamic data) {
    if (data is List) {
      for (final item in data) {
        final nested = _extractText(item);
        if (nested != null && nested.isNotEmpty) return nested;
      }
      return null;
    }
    if (data is Map<String, dynamic>) {
      final candidates = data['candidates'];
      if (candidates is List) {
        for (final candidate in candidates) {
          if (candidate is! Map<String, dynamic>) continue;
          final content = candidate['content'];
          final parts =
              (content is Map<String, dynamic>) ? content['parts'] : null;
          final text = _extractTextFromParts(parts);
          if (text != null && text.isNotEmpty) return text;
        }
      }
      final content = data['content'];
      if (content is Map<String, dynamic>) {
        final text = _extractTextFromParts(content['parts']);
        if (text != null && text.isNotEmpty) return text;
      }
      final text = data['text'];
      if (text is String && text.isNotEmpty) return text;
    }
    return null;
  }

  String? _extractTextFromParts(dynamic parts) {
    if (parts is! List) return null;
    for (final part in parts) {
      if (part is! Map<String, dynamic>) continue;
      final text = part['text'];
      if (text is String && text.isNotEmpty) return text;
    }
    return null;
  }

  dynamic _decodeResponseBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return _decodeStreamBody(trimmed);
    }
  }

  List<dynamic>? _decodeStreamBody(String body) {
    final lines = body.split('\n');
    final items = <dynamic>[];
    for (var raw in lines) {
      var line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('data:')) {
        line = line.substring(5).trim();
      }
      if (line == '[DONE]') continue;
      try {
        items.add(jsonDecode(line));
      } catch (_) {
        continue;
      }
    }
    if (items.isEmpty) return null;
    return items;
  }

  bool _isVertexUrl(String url) {
    return url.contains('aiplatform.googleapis.com');
  }

  bool _supportsImageOutput() {
    final model = _model.toLowerCase();
    return model.contains('image');
  }

  bool _requiresAccessToken(String url) {
    return _isVertexUrl(url) && url.contains('/projects/');
  }

  String _applyApiKeyToUrl(String url, String apiKey) {
    if (url.contains('key=')) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}key=$apiKey';
  }

  String? _extractErrorMessage(String body) {
    final data = _decodeResponseBody(body);
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    }
    if (data is List) {
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final message = _extractErrorMessage(jsonEncode(item));
          if (message != null && message.isNotEmpty) return message;
        }
      }
    }
    return null;
  }

  String _truncate(String value, {int max = 260}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...';
  }

  String? _resolveBaseUrl() {
    final override = _baseUrlOverride;
    if (override != null && override.isNotEmpty) return override;
    final projectId = _projectId;
    if (projectId != null && projectId.isNotEmpty) {
      return 'https://aiplatform.googleapis.com/v1/projects/'
          '$projectId/locations/$_location/publishers/google/models/'
          '$_model:generateContent';
    }
    final path = _preferStream ? 'streamGenerateContent' : 'generateContent';
    return 'https://aiplatform.googleapis.com/v1/publishers/google/models/'
        '$_model:$path';
  }

  Future<File> _saveBytes(Uint8List bytes, String prompt,
      {String extension = 'png'}) async {
    final directory = await getApplicationDocumentsDirectory();
    final sanitized = _sanitize(prompt);
    final fileName =
        'nano_${sanitized}_${DateTime.now().millisecondsSinceEpoch}.$extension';
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

  String _guessExtension(String url) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'jpg';
    if (lower.endsWith('.webp')) return 'webp';
    return 'png';
  }

  String _guessMimeType(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/png';
  }
}
