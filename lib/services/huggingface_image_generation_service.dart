import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'huggingface_inference_client.dart';
import 'ai_image_generation_service.dart';

class HuggingFaceImageGenerationService implements AiImageGenerationService {
  final HuggingFaceInferenceClient _client;
  final String? _apiToken;
  final String _model;
  final String? _baseUrlOverride;
  final bool _waitForModel;
  final Duration _timeout;

  HuggingFaceImageGenerationService({
    String? apiToken,
    String? model,
    String? baseUrl,
    Duration? timeout,
    Duration? pollInterval,
    Duration? pollTimeout,
    bool? waitForModel,
  })  : _apiToken = apiToken ?? dotenv.env['HUGGINGFACE_API_TOKEN'],
        _timeout = timeout ?? const Duration(seconds: 60),
        _waitForModel = waitForModel ?? _resolveWaitForModel(),
        _client = HuggingFaceInferenceClient(
          apiToken: apiToken ?? dotenv.env['HUGGINGFACE_API_TOKEN'],
          timeout: timeout ?? const Duration(seconds: 60),
          pollInterval: pollInterval ?? const Duration(seconds: 2),
          pollTimeout: pollTimeout ?? const Duration(minutes: 2),
          waitForModel: waitForModel ?? _resolveWaitForModel(),
        ),
        _model = model ??
            dotenv.env['HUGGINGFACE_IMAGE_MODEL'] ??
            'stabilityai/sdxl-turbo',
        _baseUrlOverride = baseUrl ?? dotenv.env['HUGGINGFACE_IMAGE_URL'];

  @override
  Future<bool> isAvailable() async {
    if (!_hasValidConfig()) {
      debugPrint('🤗 HF IMAGE: некорректный model id: $_model');
      return false;
    }
    final baseUrl = _resolveBaseUrl();
    final hasUrl = baseUrl != null && baseUrl.isNotEmpty;
    final hasToken = _client.hasToken;
    final available = hasUrl && hasToken;
    debugPrint(
        '🤗 HF IMAGE: доступность token=$hasToken baseUrl=$hasUrl model=$_model');
    return available;
  }

  @override
  Future<AiImageGenerationResult> generateImageFromPrompt(
    String prompt, {
    int batchSize = 1,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      debugPrint('🤗 HF IMAGE: пустой промпт');
      return const AiImageGenerationResult(
        errorMessage: 'Пустой промпт. Напишите, что нужно сгенерировать.',
      );
    }
    final modelError = _validateModelConfig();
    if (modelError != null) {
      return AiImageGenerationResult(errorMessage: modelError);
    }
    if (!await isAvailable()) {
      debugPrint('🤗 HF IMAGE: сервис не настроен');
      return const AiImageGenerationResult(
        errorMessage: 'Сервис не настроен. Проверьте токен и URL в .env файле.',
      );
    }

    try {
      final baseUrl = _resolveBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        return const AiImageGenerationResult(
          errorMessage: 'Не задан URL для модели (HUGGINGFACE_IMAGE_URL).',
        );
      }
      final payload = _buildTextPayload(trimmed);
      final response = await _client.postJson(
        url: baseUrl,
        payload: payload,
        accept: 'image/*',
      );

      if (!response.isOk) {
        final error = _buildNotFoundHint(
              statusCode: response.statusCode,
              baseUrl: baseUrl,
            ) ??
            _extractErrorMessage(response.json) ??
            _extractPlainError(response.bodyBytes) ??
            'Ошибка запроса: HTTP ${response.statusCode}';
        debugPrint('🤗 HF IMAGE: HTTP ${response.statusCode} $error');
        return AiImageGenerationResult(errorMessage: error);
      }

      final bytes = _extractBinaryImage(response);
      if (bytes != null && bytes.isNotEmpty) {
        final extension =
            _guessImageExtension(response.headers['content-type']);
        final file = await _saveBytes(bytes, trimmed, extension: extension);
        return AiImageGenerationResult(file: file);
      }

      final base64Image = _extractBase64(response.json);
      if (base64Image != null && base64Image.isNotEmpty) {
        final decoded = _decodeBase64(base64Image);
        if (decoded == null) {
          return const AiImageGenerationResult(
            errorMessage: 'Не удалось декодировать изображение.',
          );
        }
        final file = await _saveBytes(decoded, trimmed);
        return AiImageGenerationResult(file: file);
      }

      final imageUrl = _extractUrl(response.json);
      if (imageUrl != null && imageUrl.isNotEmpty) {
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
      }

      return const AiImageGenerationResult(
        errorMessage: 'Модель не вернула изображение.',
      );
    } catch (e) {
      debugPrint('🤗 HF IMAGE: ошибка генерации: $e');
      return AiImageGenerationResult(errorMessage: 'Ошибка генерации: $e');
    }
  }

  @override
  Future<AiImageGenerationResult> generateImageFromPromptWithReference({
    required String prompt,
    required File referenceImage,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      debugPrint('🤗 HF IMAGE: пустой промпт');
      return const AiImageGenerationResult(
        errorMessage: 'Пустой промпт. Напишите, что нужно сгенерировать.',
      );
    }
    if (!referenceImage.existsSync()) {
      return generateImageFromPrompt(trimmed);
    }
    final modelError = _validateModelConfig();
    if (modelError != null) {
      return AiImageGenerationResult(errorMessage: modelError);
    }
    if (!await isAvailable()) {
      debugPrint('🤗 HF IMAGE: сервис не настроен');
      return const AiImageGenerationResult(
        errorMessage: 'Сервис не настроен. Проверьте токен и URL в .env файле.',
      );
    }

    try {
      final baseUrl = _resolveBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        return const AiImageGenerationResult(
          errorMessage: 'Не задан URL для модели (HUGGINGFACE_IMAGE_URL).',
        );
      }
      final response = await _postMultipart(
        url: baseUrl,
        prompt: trimmed,
        referenceImage: referenceImage,
      );

      if (response.statusCode != 200) {
        final error = _buildNotFoundHint(
              statusCode: response.statusCode,
              baseUrl: baseUrl,
            ) ??
            _extractErrorMessageFromResponse(response) ??
            'Ошибка запроса: HTTP ${response.statusCode}';
        debugPrint('🤗 HF IMAGE: HTTP ${response.statusCode} $error');
        return AiImageGenerationResult(errorMessage: error);
      }

      final imageBytes = _extractBinaryImageFromHttp(response);
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final extension =
            _guessImageExtension(response.headers['content-type']);
        final file =
            await _saveBytes(imageBytes, trimmed, extension: extension);
        return AiImageGenerationResult(file: file);
      }

      final json = _decodeJsonBytes(response.bodyBytes);
      final base64Result = _extractBase64(json);
      if (base64Result != null && base64Result.isNotEmpty) {
        final decoded = _decodeBase64(base64Result);
        if (decoded == null) {
          return const AiImageGenerationResult(
            errorMessage: 'Не удалось декодировать изображение.',
          );
        }
        final file = await _saveBytes(decoded, trimmed);
        return AiImageGenerationResult(file: file);
      }

      final imageUrl = _extractUrl(json);
      if (imageUrl != null && imageUrl.isNotEmpty) {
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
      }

      return const AiImageGenerationResult(
        errorMessage: 'Модель не вернула изображение.',
      );
    } catch (e) {
      debugPrint('🤗 HF IMAGE: ошибка генерации: $e');
      return AiImageGenerationResult(errorMessage: 'Ошибка генерации: $e');
    }
  }

  Map<String, dynamic> _buildTextPayload(String prompt) {
    return {
      'inputs': prompt,
      'options': _buildOptions(),
    };
  }

  Map<String, dynamic> _buildOptions() {
    return {
      'wait_for_model': _waitForModel,
    };
  }

  static bool _resolveWaitForModel() {
    final raw = dotenv.env['HUGGINGFACE_WAIT_FOR_MODEL']?.trim();
    if (raw == null || raw.isEmpty) return true;
    final lower = raw.toLowerCase();
    if (lower == 'false' || lower == '0' || lower == 'no') return false;
    return true;
  }

  String? _resolveBaseUrl() {
    final override = _baseUrlOverride;
    if (override != null && override.isNotEmpty) return override;
    if (_model.isEmpty) return null;
    if (!_looksLikeModelId(_model)) return null;
    return 'https://router.huggingface.co/hf-inference/models/$_model';
  }

  Uint8List? _extractBinaryImage(HuggingFaceInferenceResponse response) {
    if (response.isJson) return null;
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('image/')) return response.bodyBytes;
    if (contentType.contains('application/octet-stream')) {
      return response.bodyBytes;
    }
    if (response.bodyBytes.isEmpty) return null;
    if (contentType.isEmpty) return response.bodyBytes;
    return null;
  }

  Uint8List? _extractBinaryImageFromHttp(http.Response response) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('image/')) return response.bodyBytes;
    if (contentType.contains('application/octet-stream')) {
      return response.bodyBytes;
    }
    if (response.bodyBytes.isEmpty) return null;
    if (contentType.isEmpty) return response.bodyBytes;
    return null;
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
      for (final key in [
        'image_base64',
        'imageBase64',
        'base64',
        'b64_json',
        'generated_image',
        'image',
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
      final outputs = data['outputs'];
      if (outputs is List && outputs.isNotEmpty) {
        final nested = _extractBase64(outputs.first);
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
      for (final key in ['image_url', 'imageUrl', 'url', 'uri']) {
        final value = data[key];
        if (value is String && value.isNotEmpty) return value;
      }
      final result = data['result'];
      final nested = _extractUrl(result);
      if (nested != null) return nested;
      final outputs = data['outputs'];
      if (outputs is List && outputs.isNotEmpty) {
        final nested = _extractUrl(outputs.first);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  String? _extractErrorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is String && error.isNotEmpty) return error;
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    }
    if (data is List) {
      for (final item in data) {
        final message = _extractErrorMessage(item);
        if (message != null && message.isNotEmpty) return message;
      }
    }
    return null;
  }

  String? _extractPlainError(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty) return null;
    return text.length > 260 ? '${text.substring(0, 260)}...' : text;
  }

  dynamic _decodeJsonBytes(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final body = utf8.decode(bytes, allowMalformed: true).trim();
    if (body.isEmpty) return null;
    if (!body.startsWith('{') && !body.startsWith('[')) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  String? _extractErrorMessageFromResponse(http.Response response) {
    final json = _decodeJsonBytes(response.bodyBytes);
    return _extractErrorMessage(json) ?? _extractPlainError(response.bodyBytes);
  }

  Future<http.Response> _postMultipart({
    required String url,
    required String prompt,
    required File referenceImage,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse(url));
    final token = _apiToken?.trim();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.headers['Accept'] = 'image/*';
    request.files.add(
      await http.MultipartFile.fromPath('inputs', referenceImage.path),
    );
    request.fields['parameters'] = jsonEncode({'prompt': prompt});
    request.fields['options'] = jsonEncode(_buildOptions());
    final streamed = await request.send().timeout(_timeout);
    return http.Response.fromStream(streamed);
  }

  Future<Uint8List?> _downloadImage(String url) async {
    try {
      final headers = <String, String>{};
      final token = _apiToken?.trim();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('🤗 HF IMAGE: ошибка скачивания: $e');
      return null;
    }
  }

  Future<File> _saveBytes(Uint8List bytes, String prompt,
      {String extension = 'png'}) async {
    final directory = await getApplicationDocumentsDirectory();
    final sanitized = _sanitize(prompt);
    final fileName =
        'hf_${sanitized}_${DateTime.now().millisecondsSinceEpoch}.$extension';
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

  String _guessImageExtension(String? contentType) {
    final lower = contentType?.toLowerCase() ?? '';
    if (lower.contains('image/jpeg')) return 'jpg';
    if (lower.contains('image/webp')) return 'webp';
    if (lower.contains('image/png')) return 'png';
    return 'png';
  }

  String? _buildNotFoundHint({
    required int statusCode,
    required String? baseUrl,
  }) {
    if (statusCode != 404) return null;
    if (baseUrl == null) return null;
    if (!baseUrl.contains('router.huggingface.co')) return null;
    return 'Модель не найдена в Hugging Face Inference API. '
        'Проверьте id модели (owner/model) или создайте Inference Endpoint '
        'и укажите HUGGINGFACE_IMAGE_URL.';
  }

  bool _looksLikeModelId(String value) {
    final trimmed = value.trim();
    return trimmed.contains('/') && !trimmed.endsWith('/');
  }

  bool _hasValidConfig() {
    final override = _baseUrlOverride;
    if (override != null && override.isNotEmpty) return true;
    return _looksLikeModelId(_model);
  }

  String? _validateModelConfig() {
    final override = _baseUrlOverride;
    if (override != null && override.isNotEmpty) return null;
    if (_looksLikeModelId(_model)) return null;
    return 'Неверный id модели. Укажи полный формат owner/model '
        '(например, Qwen/Qwen-Image-Edit-2511) '
        'или задай HUGGINGFACE_IMAGE_URL.';
  }
}
