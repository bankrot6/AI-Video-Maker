import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'video_generation_service.dart';

class Veo2VideoGenerationService implements VideoGenerationService {
  final String? _apiKey;
  final String? _accessToken;
  final String? _projectId;
  final String _location;
  final String _model;
  final String? _baseUrlOverride;
  final String? _storageUri;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _pollTimeout;

  Veo2VideoGenerationService({
    String? apiKey,
    String? accessToken,
    String? projectId,
    String? location,
    String? model,
    String? baseUrl,
    String? storageUri,
    Duration? timeout,
    Duration? pollInterval,
    Duration? pollTimeout,
  })  : _apiKey = apiKey ?? dotenv.env['VEO2_API_KEY'],
        _accessToken = accessToken ?? dotenv.env['VEO2_ACCESS_TOKEN'],
        _projectId = _sanitizeProjectId(
          projectId ??
              dotenv.env['VEO2_PROJECT_ID'] ??
              dotenv.env['GOOGLE_CLOUD_PROJECT'] ??
              dotenv.env['PROJECT_ID'],
        ),
        _location = location ?? dotenv.env['VEO2_LOCATION'] ?? 'us-central1',
        _model = model ?? dotenv.env['VEO2_MODEL'] ?? 'veo-2.0-generate-001',
        _baseUrlOverride = baseUrl ?? dotenv.env['VEO2_BASE_URL'],
        _storageUri = storageUri ?? dotenv.env['VEO2_STORAGE_URI'],
        _timeout = timeout ?? const Duration(seconds: 45),
        _pollInterval = pollInterval ?? const Duration(seconds: 3),
        _pollTimeout = pollTimeout ?? const Duration(minutes: 3);

  @override
  Future<bool> isAvailable() async {
    final token = _cleanToken(_accessToken);
    final hasToken = token != null && token.isNotEmpty;
    final apiKey = _apiKey;
    final hasKey = apiKey != null && apiKey.isNotEmpty;
    final baseUrl = _resolveBaseUrl();
    final hasUrl = baseUrl != null && baseUrl.isNotEmpty;
    final requiresToken = baseUrl != null && _requiresAccessToken(baseUrl);
    final available = hasUrl && (hasToken || hasKey);
    debugPrint(
        '🎬 VEO2: доступность token=$hasToken apiKey=$hasKey baseUrl=$hasUrl requiresToken=$requiresToken');
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
      debugPrint('🎬 VEO2: пустой промпт');
      return const VideoGenerationResult(
        errorMessage: 'Пустой промпт. Напишите, что нужно сгенерировать.',
      );
    }
    if (!await isAvailable()) {
      debugPrint('🎬 VEO2: сервис не настроен');
      return const VideoGenerationResult(
        errorMessage: 'Сервис не настроен. Проверьте ключи и URL в .env файле.',
      );
    }

    try {
      final token = _cleanToken(_accessToken);
      final apiKey = _apiKey;
      final hasToken = token != null && token.isNotEmpty;
      final hasKey = apiKey != null && apiKey.isNotEmpty;
      final baseUrl = _resolveBaseUrl();
      if (baseUrl == null || baseUrl.isEmpty) {
        debugPrint('🎬 VEO2: baseUrl не задан');
        return const VideoGenerationResult(
          errorMessage: 'Не задан URL для модели (VEO2_BASE_URL).',
        );
      }
      if (_requiresAccessToken(baseUrl) && !hasToken && !hasKey) {
        debugPrint('🎬 VEO2: нужен access token для Vertex AI');
        return const VideoGenerationResult(
          errorMessage:
              'Для этого endpoint нужен access token. Используйте project URL или OAuth.',
        );
      }
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
      };
      final projectId = _projectId;
      if (projectId != null && projectId.isNotEmpty && hasKey) {
        headers['X-Goog-User-Project'] = projectId;
      }
      var requestUrl = baseUrl;
      if (hasToken) {
        headers['Authorization'] = 'Bearer $token';
      } else if (hasKey) {
        requestUrl = _applyApiKeyToUrl(requestUrl, apiKey);
      }

      final payload = await _buildPayload(
        prompt: trimmed,
        referenceImage: referenceImage,
        durationSeconds: durationSeconds,
        aspectRatio: aspectRatio,
        sampleCount: sampleCount,
        negativePrompt: negativePrompt,
        enhancePrompt: enhancePrompt,
      );

      final response = await http
          .post(
            Uri.parse(requestUrl),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('🎬 VEO2: HTTP ${response.statusCode} ${response.body}');
        final error = _extractErrorMessage(response.body) ??
            'Ошибка запроса: HTTP ${response.statusCode}';
        return VideoGenerationResult(errorMessage: error);
      }

      final data = _decodeResponseBody(response.body);
      if (data == null) {
        debugPrint('🎬 VEO2: не удалось разобрать ответ');
        return const VideoGenerationResult(
          errorMessage: 'Не удалось разобрать ответ модели.',
        );
      }
      final operationName = _extractOperationName(data);
      if (operationName == null || operationName.isEmpty) {
        debugPrint('🎬 VEO2: operation name отсутствует');
        return const VideoGenerationResult(
          errorMessage: 'Не удалось получить id операции.',
        );
      }
      final fetchUrl = _resolveFetchUrl(baseUrl: baseUrl);
      if (fetchUrl == null || fetchUrl.isEmpty) {
        debugPrint('🎬 VEO2: fetch URL не задан');
        return const VideoGenerationResult(
          errorMessage: 'Не задан URL для polling операции.',
        );
      }
      var pollUrl = fetchUrl;
      if (!hasToken && hasKey) {
        pollUrl = _applyApiKeyToUrl(pollUrl, apiKey);
      }

      return await _pollOperation(
        operationName: operationName,
        headers: headers,
        fetchUrl: pollUrl,
      );
    } catch (e) {
      debugPrint('🎬 VEO2: ошибка генерации: $e');
      return VideoGenerationResult(
        errorMessage: 'Ошибка генерации: $e',
      );
    }
  }

  Future<VideoGenerationResult> _pollOperation({
    required String operationName,
    required Map<String, String> headers,
    required String fetchUrl,
  }) async {
    final startedAt = DateTime.now();
    while (DateTime.now().difference(startedAt) <= _pollTimeout) {
      final response = await http
          .post(
            Uri.parse(fetchUrl),
            headers: headers,
            body: jsonEncode({'operationName': operationName}),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint(
            '🎬 VEO2: polling HTTP ${response.statusCode} ${response.body}');
        final error = _extractErrorMessage(response.body) ??
            'Ошибка polling: HTTP ${response.statusCode}';
        return VideoGenerationResult(errorMessage: error);
      }
      final data = _decodeResponseBody(response.body);
      if (data is! Map<String, dynamic>) {
        debugPrint('🎬 VEO2: некорректный ответ polling');
        return const VideoGenerationResult(
          errorMessage: 'Некорректный ответ polling.',
        );
      }

      final done = data['done'] == true;
      if (!done) {
        await Future.delayed(_pollInterval);
        continue;
      }

      final error = _extractOperationError(data);
      if (error != null && error.isNotEmpty) {
        return VideoGenerationResult(errorMessage: error);
      }

      final responseBody = data['response'];
      final searchBody = responseBody ?? data;
      final base64Video = _extractVideoBase64FromAny(searchBody);
      if (base64Video != null && base64Video.isNotEmpty) {
        final bytes = _decodeBase64(base64Video);
        if (bytes == null) {
          return const VideoGenerationResult(
            errorMessage: 'Не удалось декодировать видео.',
          );
        }
        final file = await _saveBytes(bytes, 'veo_story');
        return VideoGenerationResult(file: file);
      }

      final gcsUri = _extractGcsUriFromAny(searchBody);
      if (gcsUri != null && gcsUri.isNotEmpty) {
        final downloaded = await _downloadFromGcs(gcsUri);
        if (downloaded != null) {
          final file = await _saveBytes(downloaded, 'veo_story');
          return VideoGenerationResult(file: file, remoteUri: gcsUri);
        }
        return VideoGenerationResult(
          remoteUri: gcsUri,
          errorMessage:
              'Видео сохранено в GCS, но скачать не удалось. Проверьте доступ.',
        );
      }

      final videoUrl = _extractVideoUrlFromAny(searchBody);
      if (videoUrl != null && videoUrl.isNotEmpty) {
        final downloaded = await _downloadFromUrl(videoUrl);
        if (downloaded != null) {
          final file = await _saveBytes(downloaded, 'veo_story');
          return VideoGenerationResult(file: file);
        }
        return VideoGenerationResult(
          errorMessage: 'Видео найдено, но скачать не удалось.',
        );
      }

      return const VideoGenerationResult(
        errorMessage: 'Видео не найдено в ответе.',
      );
    }
    return const VideoGenerationResult(
      errorMessage: 'Генерация видео превысила таймаут.',
    );
  }

  Future<Map<String, dynamic>> _buildPayload({
    required String prompt,
    required int durationSeconds,
    required String aspectRatio,
    required int sampleCount,
    required bool enhancePrompt,
    File? referenceImage,
    String? negativePrompt,
  }) async {
    final instance = <String, dynamic>{
      'prompt': prompt,
    };
    if (referenceImage != null && referenceImage.existsSync()) {
      final bytes = await referenceImage.readAsBytes();
      instance['image'] = {
        'bytesBase64Encoded': base64Encode(bytes),
        'mimeType': _guessMimeType(referenceImage.path),
      };
    }

    final parameters = <String, dynamic>{
      'durationSeconds': durationSeconds,
      'aspectRatio': aspectRatio,
      'sampleCount': sampleCount,
      'enhancePrompt': enhancePrompt,
    };
    if (negativePrompt != null && negativePrompt.trim().isNotEmpty) {
      parameters['negativePrompt'] = negativePrompt.trim();
    }
    final storageUri = _storageUri;
    if (storageUri != null && storageUri.trim().isNotEmpty) {
      parameters['storageUri'] = storageUri.trim();
    }

    return {
      'instances': [instance],
      'parameters': parameters,
    };
  }

  String? _resolveBaseUrl() {
    final override = _baseUrlOverride;
    if (override != null && override.isNotEmpty) return override;
    final projectId = _projectId;
    if (projectId != null && projectId.isNotEmpty) {
      return 'https://$_location-aiplatform.googleapis.com/v1/projects/'
          '$projectId/locations/$_location/publishers/google/models/'
          '$_model:predictLongRunning';
    }
    return 'https://$_location-aiplatform.googleapis.com/v1/publishers/google/'
        'models/$_model:predictLongRunning';
  }

  String? _resolveFetchUrl({
    String? baseUrl,
  }) {
    final resolvedBaseUrl =
        (baseUrl != null && baseUrl.isNotEmpty) ? baseUrl : _resolveBaseUrl();
    if (resolvedBaseUrl == null || resolvedBaseUrl.isEmpty) {
      return null;
    }
    if (resolvedBaseUrl.contains(':predictLongRunning')) {
      return resolvedBaseUrl.replaceFirst(
        ':predictLongRunning',
        ':fetchPredictOperation',
      );
    }
    if (resolvedBaseUrl.contains(':predict')) {
      return resolvedBaseUrl.replaceFirst(':predict', ':fetchPredictOperation');
    }
    return resolvedBaseUrl;
  }

  bool _requiresAccessToken(String url) {
    return url.contains('aiplatform.googleapis.com') &&
        url.contains('/projects/');
  }

  String _applyApiKeyToUrl(String url, String apiKey) {
    if (url.contains('key=')) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}key=$apiKey';
  }

  dynamic _decodeResponseBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
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

  String? _extractOperationName(dynamic data) {
    if (data is Map<String, dynamic>) {
      final name = data['name'];
      if (name is String && name.isNotEmpty) return name;
    }
    return null;
  }

  String? _extractOperationError(Map<String, dynamic> data) {
    final error = data['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return null;
  }

  String? _extractVideoBase64FromAny(dynamic data) {
    return _findFirstStringByKeys(
      data,
      const {
        'bytesBase64Encoded',
        'videoBase64',
        'video_base64',
        'b64_json',
      },
    );
  }

  String? _extractGcsUriFromAny(dynamic data) {
    return _findFirstStringByKeys(
      data,
      const {
        'gcsUri',
        'gcs_uri',
        'gsUri',
        'gs_uri',
      },
    );
  }

  String? _extractVideoUrlFromAny(dynamic data) {
    return _findFirstStringByKeys(
      data,
      const {
        'videoUrl',
        'video_url',
        'url',
        'uri',
      },
      accept: _looksLikeVideoUrl,
    );
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

  Future<Uint8List?> _downloadFromGcs(String gcsUri) async {
    final match = RegExp(r'^gs://([^/]+)/(.+)$').firstMatch(gcsUri);
    if (match == null) return null;
    final bucket = match.group(1);
    final object = match.group(2);
    if (bucket == null || object == null) return null;
    var url =
        'https://storage.googleapis.com/storage/v1/b/$bucket/o/${Uri.encodeComponent(object)}?alt=media';
    try {
      final headers = <String, String>{};
      final token = _cleanToken(_accessToken);
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final apiKey = _apiKey;
      if (apiKey != null && apiKey.isNotEmpty) {
        url = _applyApiKeyToUrl(url, apiKey);
      }
      final response =
          await http.get(Uri.parse(url), headers: headers).timeout(_timeout);
      if (response.statusCode != 200) {
        return null;
      }
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _downloadFromUrl(String url) async {
    try {
      final headers = <String, String>{};
      final token = _cleanToken(_accessToken);
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      var requestUrl = url;
      final apiKey = _apiKey;
      if (apiKey != null && apiKey.isNotEmpty) {
        requestUrl = _applyApiKeyToUrl(requestUrl, apiKey);
      }
      final response = await http
          .get(Uri.parse(requestUrl), headers: headers)
          .timeout(_timeout);
      if (response.statusCode != 200) {
        return null;
      }
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<File> _saveBytes(Uint8List bytes, String seed,
      {String extension = 'mp4'}) async {
    final directory = await getApplicationDocumentsDirectory();
    final sanitized = _sanitize(seed);
    final fileName =
        'veo_${sanitized}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final filePath = path.join(directory.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _sanitize(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) return 'video';
    return normalized.length > 32 ? normalized.substring(0, 32) : normalized;
  }

  String _guessMimeType(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/png';
  }

  static String? _sanitizeProjectId(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.replaceFirst(RegExp(r'^=+'), '');
  }

  String? _cleanToken(String? token) {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (_looksLikeCommand(trimmed)) return null;
    if (trimmed.contains(' ')) return null;
    return trimmed;
  }

  bool _looksLikeCommand(String token) {
    return token.contains('gcloud') || token.contains('print-access-token');
  }

  String? _findFirstStringByKeys(
    dynamic data,
    Set<String> keys, {
    bool Function(String value)? accept,
  }) {
    if (data is Map<String, dynamic>) {
      for (final key in keys) {
        final value = data[key];
        if (value is String && value.isNotEmpty) {
          if (accept == null || accept(value)) return value;
        }
      }
      for (final value in data.values) {
        final found = _findFirstStringByKeys(value, keys, accept: accept);
        if (found != null) return found;
      }
    } else if (data is List) {
      for (final item in data) {
        final found = _findFirstStringByKeys(item, keys, accept: accept);
        if (found != null) return found;
      }
    }
    return null;
  }

  bool _looksLikeVideoUrl(String value) {
    final lower = value.toLowerCase();
    if (lower.startsWith('gs://')) return true;
    if (lower.startsWith('http')) {
      if (lower.contains('.mp4') ||
          lower.contains('video') ||
          lower.contains('storage.googleapis.com')) {
        return true;
      }
    }
    return false;
  }
}
