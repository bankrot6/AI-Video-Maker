import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'huggingface_inference_client.dart';
import 'video_generation_service.dart';

class HuggingFaceVideoGenerationService implements VideoGenerationService {
  final HuggingFaceInferenceClient _client;
  final String? _apiToken;
  final String _model;
  final String? _baseUrlOverride;
  final bool _waitForModel;

  HuggingFaceVideoGenerationService({
    String? apiToken,
    String? model,
    String? baseUrl,
    Duration? timeout,
    Duration? pollInterval,
    Duration? pollTimeout,
    bool? waitForModel,
  })  : _apiToken = apiToken ?? dotenv.env['HUGGINGFACE_API_TOKEN'],
        _waitForModel = waitForModel ?? _resolveWaitForModel(),
        _client = HuggingFaceInferenceClient(
          apiToken: apiToken ?? dotenv.env['HUGGINGFACE_API_TOKEN'],
          timeout: timeout ?? const Duration(seconds: 90),
          pollInterval: pollInterval ?? const Duration(seconds: 3),
          pollTimeout: pollTimeout ?? const Duration(minutes: 4),
          waitForModel: waitForModel ?? _resolveWaitForModel(),
        ),
        _model = model ??
            dotenv.env['HUGGINGFACE_VIDEO_MODEL'] ??
            'cerspense/zeroscope_v2_576w',
        _baseUrlOverride = baseUrl ?? dotenv.env['HUGGINGFACE_VIDEO_URL'];

  @override
  Future<bool> isAvailable() async {
    final baseUrl = _resolveBaseUrl();
    final hasUrl = baseUrl != null && baseUrl.isNotEmpty;
    final hasToken = _client.hasToken;
    final available = hasUrl && hasToken;
    debugPrint(
        '🤗 HF VIDEO: доступность token=$hasToken baseUrl=$hasUrl model=$_model');
    return available;
  }

  @override
  Future<VideoGenerationResult> generateVideo({
    required String prompt,
    File? referenceImage,
    int durationSeconds = 6,
    String aspectRatio = '9:16',
    int sampleCount = 1,
    String? negativePrompt,
    bool enhancePrompt = true,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      debugPrint('🤗 HF VIDEO: пустой промпт');
      return const VideoGenerationResult(
        errorMessage: 'Пустой промпт. Напишите, что нужно сгенерировать.',
      );
    }
    if (!await isAvailable()) {
      debugPrint('🤗 HF VIDEO: сервис не настроен');
      return const VideoGenerationResult(
        errorMessage: 'Сервис не настроен. Проверьте токен и URL в .env файле.',
      );
    }

    try {
      final baseUrl = _resolveBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        return const VideoGenerationResult(
          errorMessage: 'Не задан URL для модели (HUGGINGFACE_VIDEO_URL).',
        );
      }
      final payload = await _buildPayload(
        prompt: trimmed,
        referenceImage: referenceImage,
        negativePrompt: negativePrompt,
      );
      final response = await _client.postJson(
        url: baseUrl,
        payload: payload,
        accept: 'video/*',
      );

      if (!response.isOk) {
        final error = _extractErrorMessage(response.json) ??
            'Ошибка запроса: HTTP ${response.statusCode}';
        debugPrint('🤗 HF VIDEO: HTTP ${response.statusCode} $error');
        return VideoGenerationResult(errorMessage: error);
      }

      final videoBytes = _extractBinaryVideo(response);
      if (videoBytes != null && videoBytes.isNotEmpty) {
        final extension =
            _guessVideoExtension(response.headers['content-type']);
        final file =
            await _saveBytes(videoBytes, trimmed, extension: extension);
        return VideoGenerationResult(file: file);
      }

      final base64Video = _extractBase64(response.json);
      if (base64Video != null && base64Video.isNotEmpty) {
        final decoded = _decodeBase64(base64Video);
        if (decoded == null) {
          return const VideoGenerationResult(
            errorMessage: 'Не удалось декодировать видео.',
          );
        }
        final file = await _saveBytes(decoded, trimmed);
        return VideoGenerationResult(file: file);
      }

      final videoUrl = _extractUrl(response.json);
      if (videoUrl != null && videoUrl.isNotEmpty) {
        final downloaded = await _downloadVideo(videoUrl);
        if (downloaded != null) {
          final file = await _saveBytes(downloaded, trimmed);
          return VideoGenerationResult(file: file, remoteUri: videoUrl);
        }
        return VideoGenerationResult(
          remoteUri: videoUrl,
          errorMessage: 'Видео найдено, но скачать не удалось.',
        );
      }

      return const VideoGenerationResult(
        errorMessage: 'Видео не найдено в ответе.',
      );
    } catch (e) {
      debugPrint('🤗 HF VIDEO: ошибка генерации: $e');
      return VideoGenerationResult(errorMessage: 'Ошибка генерации: $e');
    }
  }

  Future<Map<String, dynamic>> _buildPayload({
    required String prompt,
    File? referenceImage,
    String? negativePrompt,
  }) async {
    if (referenceImage != null && referenceImage.existsSync()) {
      final bytes = await referenceImage.readAsBytes();
      final imageBase64 = base64Encode(bytes);
      return {
        'inputs': {
          'prompt': prompt,
          'image': imageBase64,
        },
        if (negativePrompt != null && negativePrompt.trim().isNotEmpty)
          'parameters': {
            'negative_prompt': negativePrompt.trim(),
          },
        'options': _buildOptions(),
      };
    }
    final payload = <String, dynamic>{
      'inputs': prompt,
      'options': _buildOptions(),
    };
    if (negativePrompt != null && negativePrompt.trim().isNotEmpty) {
      payload['parameters'] = {
        'negative_prompt': negativePrompt.trim(),
      };
    }
    return payload;
  }

  Map<String, dynamic> _buildOptions() {
    return {
      'wait_for_model': _waitForModel,
    };
  }

  String? _resolveBaseUrl() {
    final override = _baseUrlOverride;
    if (override != null && override.isNotEmpty) return override;
    if (_model.isEmpty) return null;
    return 'https://router.huggingface.co/hf-inference/models/$_model';
  }

  Uint8List? _extractBinaryVideo(HuggingFaceInferenceResponse response) {
    if (response.isJson) return null;
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.contains('video/')) return response.bodyBytes;
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
        'video_base64',
        'videoBase64',
        'base64',
        'b64_json',
        'generated_video',
        'video',
      ]) {
        final value = data[key];
        if (value is String && value.isNotEmpty) return value;
      }
      final result = data['result'];
      final nested = _extractBase64(result);
      if (nested != null) return nested;
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
      for (final key in ['video_url', 'videoUrl', 'url', 'uri']) {
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

  Future<Uint8List?> _downloadVideo(String url) async {
    try {
      final headers = <String, String>{};
      final token = _apiToken?.trim();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('🤗 HF VIDEO: ошибка скачивания: $e');
      return null;
    }
  }

  Future<File> _saveBytes(Uint8List bytes, String prompt,
      {String extension = 'mp4'}) async {
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
    if (normalized.isEmpty) return 'video';
    return normalized.length > 32 ? normalized.substring(0, 32) : normalized;
  }

  String _guessVideoExtension(String? contentType) {
    final lower = contentType?.toLowerCase() ?? '';
    if (lower.contains('video/mp4')) return 'mp4';
    if (lower.contains('video/webm')) return 'webm';
    return 'mp4';
  }

  static bool _resolveWaitForModel() {
    final raw = dotenv.env['HUGGINGFACE_WAIT_FOR_MODEL']?.trim();
    if (raw == null || raw.isEmpty) return true;
    final lower = raw.toLowerCase();
    if (lower == 'false' || lower == '0' || lower == 'no') return false;
    return true;
  }
}
