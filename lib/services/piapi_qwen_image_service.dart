import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'photosession_generation_router.dart';
import 'piapi_upload_service.dart';

class PiApiQwenImageService implements PhotosessionGenerationService {
  PiApiQwenImageService({
    String? apiKey,
    String? taskUrl,
    Duration? timeout,
    Duration? pollInterval,
    Duration? pollTimeout,
  })  : _apiKey = apiKey ?? dotenv.env['PIAPI_API_KEY'],
        _taskUrl = _normalize(
          taskUrl ??
              dotenv.env['PIAPI_TASK_URL'] ??
              dotenv.env['PIAPI_BASE_URL'] ??
              'https://api.piapi.ai/api/v1/task',
        ),
        _timeout = timeout ?? const Duration(seconds: 30),
        _pollInterval = pollInterval ?? const Duration(seconds: 3),
        _pollTimeout = pollTimeout ?? const Duration(minutes: 5);

  static String _normalize(String url) {
    final t = url.trim();
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  final String? _apiKey;
  final String _taskUrl;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _pollTimeout;

  static const _model = 'Qubico/qwen-image';

  @override
  Future<bool> isAvailable() async {
    final hasKey = (_apiKey ?? '').trim().isNotEmpty;
    final hasUrl = _taskUrl.trim().isNotEmpty;
    final isProxied = hasUrl && !_taskUrl.contains('api.piapi.ai');
    debugPrint('🔵 PIAPI_QWEN: доступность apiKey=$hasKey taskUrl=$hasUrl proxied=$isProxied');
    return hasUrl && (isProxied || hasKey);
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
        errorMessage: 'PiAPI не настроен. Проверьте PIAPI_API_KEY в .env.',
      );
    }

    final uploadedUrl = await _resolveImageUrl(userImageUrl);
    if (uploadedUrl == null) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось подготовить фото пользователя.',
      );
    }

    final sceneShort = scenePrompt.length > 1500
        ? scenePrompt.substring(0, 1500)
        : scenePrompt;

    final prompt =
        'image1 shows a REAL person. Keep this EXACT person: same face, '
        'gender, skin tone, body type, age, hair. '
        'Do NOT change any physical features.\n\n'
        '$sceneShort\n\n'
        'Vertical portrait format (3:4). Photorealistic, high quality.';

    final payload = <String, dynamic>{
      'model': _model,
      'task_type': 'image-edit',
      'input': {
        'image1': uploadedUrl,
        'prompt': prompt,
        'negative_prompt':
            'blurry, low quality, distorted face, ugly, deformed, '
            'wrong gender, different person, cartoon, anime, drawing',
        'steps': 16,
        'seed': -1,
        'flow_shift': 3,
      },
    };

    debugPrint('🔵 PIAPI_QWEN: создаём задачу image-edit...');
    return _runTask(payload);
  }

  Future<String?> _resolveImageUrl(String imageUrl) async {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return imageUrl;
    }
    final file = File(imageUrl);
    if (!file.existsSync()) return null;
    debugPrint('🔵 PIAPI_QWEN: загружаем фото на PiAPI...');
    final uploader = PiApiUploadService();
    final url = await uploader.uploadImage(file);
    if (url != null) debugPrint('🔵 PIAPI_QWEN: фото загружено $url');
    return url;
  }

  @override
  Future<PhotosessionGenerationResult> generateImage({
    required String prompt,
    String resolution = '2K',
    String aspectRatio = '3:4',
  }) async {
    if (!await isAvailable()) {
      return const PhotosessionGenerationResult(
        errorMessage: 'PiAPI не настроен. Проверьте PIAPI_API_KEY в .env.',
      );
    }

    final trimmed = prompt.length > 2000
        ? prompt.substring(0, 2000)
        : prompt;

    final fullPrompt = '$trimmed\n\n'
        'Vertical portrait format (3:4). Photorealistic, high quality 2K.';

    final payload = <String, dynamic>{
      'model': _model,
      'task_type': 'txt2img',
      'input': {
        'prompt': fullPrompt,
        'negative_prompt':
            'blurry, low quality, distorted face, ugly, deformed, '
            'cartoon, anime, drawing',
        'width': 768,
        'height': 1024,
        'steps': 16,
        'seed': -1,
        'flow_shift': 3,
      },
    };

    debugPrint('🔵 PIAPI_QWEN: создаём задачу txt2img...');
    return _runTask(payload);
  }

  Future<PhotosessionGenerationResult> _runTask(
    Map<String, dynamic> payload,
  ) async {
    final createResponse = await _post(_taskUrl, payload);
    if (createResponse == null) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось создать задачу на PiAPI (Qwen).',
      );
    }

    final taskId = _extractTaskId(createResponse);
    if (taskId == null) {
      final msg = _extractErrorMessage(createResponse);
      return PhotosessionGenerationResult(
        errorMessage: msg ?? 'PiAPI Qwen не вернул task_id.',
      );
    }

    debugPrint('🔵 PIAPI_QWEN: taskId=$taskId — ждём результат...');
    return _poll(taskId);
  }

  Future<PhotosessionGenerationResult> _poll(String taskId) async {
    final deadline = DateTime.now().add(_pollTimeout);
    var attempts = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempts++;
      await Future.delayed(_pollInterval);

      final response = await _get('$_taskUrl/$taskId');
      if (response == null) {
        debugPrint('🔵 PIAPI_QWEN: нет ответа при опросе #$attempts');
        continue;
      }

      final status = _extractStatus(response);
      debugPrint('🔵 PIAPI_QWEN: опрос #$attempts status=$status');

      final statusLower = status?.toLowerCase();

      if (statusLower == 'completed') {
        final url = _extractImageUrl(response);
        if (url != null && url.isNotEmpty) {
          debugPrint('🔵 PIAPI_QWEN: готово! url=$url');
          return PhotosessionGenerationResult(imageUrl: url);
        }
        return const PhotosessionGenerationResult(
          errorMessage: 'Задача завершена, но URL изображения не найден.',
        );
      }

      if (statusLower == 'failed') {
        final msg = _extractErrorMessage(response);
        debugPrint('🔵 PIAPI_QWEN: задача провалилась: $msg');
        return PhotosessionGenerationResult(
          errorMessage: msg ?? 'Задача Qwen завершилась с ошибкой.',
        );
      }
    }

    return const PhotosessionGenerationResult(
      errorMessage: 'Превышено время ожидания Qwen (5 минут).',
    );
  }

  Future<dynamic> _post(String url, Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: _headers(),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      debugPrint('🔵 PIAPI_QWEN: POST → ${response.statusCode}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('🔵 PIAPI_QWEN: тело ошибки: ${response.body}');
        return null;
      }
      return _decode(response.body);
    } catch (e) {
      debugPrint('🔵 PIAPI_QWEN: ошибка POST: $e');
      return null;
    }
  }

  Future<dynamic> _get(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: _headers())
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return _decode(response.body);
    } catch (e) {
      debugPrint('🔵 PIAPI_QWEN: ошибка GET: $e');
      return null;
    }
  }

  Map<String, String> _headers() {
    final h = <String, String>{'Content-Type': 'application/json'};
    final key = _apiKey?.trim();
    if (key != null && key.isNotEmpty) h['X-API-Key'] = key;
    return h;
  }

  static dynamic _decode(String body) {
    try {
      return jsonDecode(body.trim());
    } catch (_) {
      return null;
    }
  }

  static String? _extractTaskId(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final data = json['data'];
    if (data is Map<String, dynamic>) {
      final id = data['task_id'];
      if (id is String && id.isNotEmpty) return id;
    }
    return null;
  }

  static String? _extractStatus(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final data = json['data'];
    if (data is Map<String, dynamic>) {
      final s = data['status'];
      if (s is String) return s;
    }
    return null;
  }

  static String? _extractImageUrl(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final data = json['data'];
    if (data is! Map<String, dynamic>) return null;
    final output = data['output'];
    if (output is Map<String, dynamic>) {
      final single = output['image_url'];
      if (single is String && single.isNotEmpty) return single;
      final list = output['image_urls'];
      if (list is List && list.isNotEmpty && list.first is String) {
        return list.first as String;
      }
    }
    return null;
  }

  static String? _extractErrorMessage(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    final data = json['data'];
    final src = (data is Map<String, dynamic>) ? data : json;

    final error = src['error'];
    if (error is Map<String, dynamic>) {
      final msg = error['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }

    final logs = src['logs'];
    if (logs is List && logs.isNotEmpty) {
      final first = logs.first;
      if (first is String && first.isNotEmpty) return first;
    }

    final msg = json['message'];
    if (msg is String && msg.isNotEmpty && msg != 'success') return msg;
    return null;
  }
}
