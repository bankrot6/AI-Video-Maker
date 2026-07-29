import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'video_generation_service.dart';

class PiApiKlingVideoGenerationService implements VideoGenerationService {
  static const int _maxUploadBytes = 10 * 1024 * 1024;

  final String? _apiKey;
  final String _taskUrl;
  final String _uploadUrl;
  final String? _version;
  final String _mode;
  final double _cfgScale;
  final bool _enableAudio;
  final String? _serviceMode;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _pollTimeout;

  PiApiKlingVideoGenerationService({
    String? apiKey,
    String? taskUrl,
    String? uploadUrl,
    String? version,
    String? mode,
    double? cfgScale,
    bool? enableAudio,
    String? serviceMode,
    Duration? timeout,
    Duration? pollInterval,
    Duration? pollTimeout,
  })  : _apiKey = apiKey ?? dotenv.env['PIAPI_API_KEY'],
        _taskUrl = taskUrl ??
            dotenv.env['PIAPI_TASK_URL'] ??
            dotenv.env['PIAPI_BASE_URL'] ??
            'https://api.piapi.ai/api/v1/task',
        _uploadUrl = uploadUrl ??
            dotenv.env['PIAPI_UPLOAD_URL'] ??
            'https://upload.theapi.app/api/ephemeral_resource',
        _version = _normalizeVersion(
          version ?? dotenv.env['PIAPI_KLING_VERSION'],
        ),
        _mode = _normalizeMode(mode ?? dotenv.env['PIAPI_KLING_MODE']) ?? 'std',
        _cfgScale =
            cfgScale ?? _parseDoubleEnv('PIAPI_KLING_CFG_SCALE', fallback: 0.5),
        _enableAudio = enableAudio ??
            _parseBoolEnv('PIAPI_KLING_ENABLE_AUDIO', fallback: false),
        _serviceMode = _normalizeServiceMode(dotenv.env['PIAPI_SERVICE_MODE']),
        _timeout = timeout ?? const Duration(seconds: 45),
        _pollInterval = pollInterval ?? const Duration(seconds: 2),
        _pollTimeout = pollTimeout ?? const Duration(minutes: 3);

  @override
  Future<bool> isAvailable() async {
    final hasKey = (_apiKey ?? '').trim().isNotEmpty;
    final hasUrl = _taskUrl.trim().isNotEmpty;
    debugPrint('🟣 PIAPI KLING: доступность key=$hasKey url=$hasUrl');
    return hasKey && hasUrl;
  }

  @override
  Future<VideoGenerationResult> generateVideo({
    required String prompt,
    File? referenceImage,
    int durationSeconds = 5,
    String aspectRatio = '9:16',
    int sampleCount = 1,
    String? negativePrompt,
    bool enhancePrompt = true,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      return const VideoGenerationResult(
        errorMessage: 'Пустой промпт. Напишите, что нужно сгенерировать.',
      );
    }
    if (!await isAvailable()) {
      return const VideoGenerationResult(
        errorMessage: 'Сервис не настроен. Проверьте ключи в .env файле.',
      );
    }

    try {
      String? imageUrl;
      if (referenceImage != null && referenceImage.existsSync()) {
        imageUrl = await _uploadReferenceImage(referenceImage);
      }
      final createSnapshot = await _createTask(
        prompt: trimmed,
        imageUrl: imageUrl,
        durationSeconds: _normalizeDuration(durationSeconds),
        aspectRatio: aspectRatio,
        negativePrompt: negativePrompt,
      );
      if (createSnapshot.errorMessage != null) {
        return VideoGenerationResult(errorMessage: createSnapshot.errorMessage);
      }
      final firstResult = await _resolveResult(createSnapshot);
      if (firstResult != null) return firstResult;

      final taskId = createSnapshot.taskId;
      if (taskId == null || taskId.isEmpty) {
        return const VideoGenerationResult(
          errorMessage: 'Не удалось получить идентификатор задачи.',
        );
      }
      final polled = await _pollTask(taskId);
      return await _resolveResult(polled) ??
          const VideoGenerationResult(
            errorMessage: 'Модель не вернула видео.',
          );
    } catch (e) {
      debugPrint('🟣 PIAPI KLING: ошибка генерации: $e');
      return VideoGenerationResult(errorMessage: 'Ошибка генерации: $e');
    }
  }

  Future<_PiApiKlingSnapshot> _createTask({
    required String prompt,
    required int durationSeconds,
    required String aspectRatio,
    String? imageUrl,
    String? negativePrompt,
  }) async {
    final payload = _buildPayload(
      prompt: prompt,
      durationSeconds: durationSeconds,
      aspectRatio: aspectRatio,
      imageUrl: imageUrl,
      negativePrompt: negativePrompt,
    );
    final response = await http
        .post(
          Uri.parse(_taskUrl),
          headers: _buildHeaders(),
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    final json = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _extractErrorMessage(json) ??
          'Ошибка запроса: HTTP ${response.statusCode}';
      debugPrint('🟣 PIAPI KLING: HTTP ${response.statusCode} $error');
      return _PiApiKlingSnapshot(errorMessage: error);
    }
    return _PiApiKlingSnapshot.fromJson(json);
  }

  Future<_PiApiKlingSnapshot> _fetchTask(String taskId) async {
    final url = _buildTaskStatusUrl(taskId);
    final response = await http
        .get(Uri.parse(url), headers: _buildHeaders())
        .timeout(_timeout);
    final json = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _extractErrorMessage(json) ??
          'Ошибка запроса: HTTP ${response.statusCode}';
      debugPrint('🟣 PIAPI KLING: HTTP ${response.statusCode} $error');
      return _PiApiKlingSnapshot(errorMessage: error);
    }
    return _PiApiKlingSnapshot.fromJson(json);
  }

  Future<_PiApiKlingSnapshot> _pollTask(String taskId) async {
    final startedAt = DateTime.now();
    while (DateTime.now().difference(startedAt) <= _pollTimeout) {
      final snapshot = await _fetchTask(taskId);
      if (snapshot.errorMessage != null) return snapshot;
      if (snapshot.isCompleted || snapshot.isFailed) return snapshot;
      await Future.delayed(_pollInterval);
    }
    return const _PiApiKlingSnapshot(
      errorMessage: 'Истекло время ожидания генерации.',
    );
  }

  Future<VideoGenerationResult?> _resolveResult(
      _PiApiKlingSnapshot snapshot) async {
    if (snapshot.errorMessage != null) {
      return VideoGenerationResult(errorMessage: snapshot.errorMessage);
    }
    if (snapshot.isFailed) {
      return VideoGenerationResult(
        errorMessage: snapshot.errorMessage ?? 'Генерация завершилась ошибкой.',
      );
    }
    if (!snapshot.isCompleted) return null;
    final videoUrl = snapshot.videoUrl;
    if (videoUrl == null || videoUrl.isEmpty) {
      return const VideoGenerationResult(
        errorMessage: 'Модель не вернула ссылку на видео.',
      );
    }
    final bytes = await _downloadVideo(videoUrl);
    if (bytes != null && bytes.isNotEmpty) {
      final file = await _saveBytes(
        bytes,
        snapshot.promptHint ?? 'kling_story',
        videoUrl,
      );
      return VideoGenerationResult(file: file, remoteUri: videoUrl);
    }
    return VideoGenerationResult(
      remoteUri: videoUrl,
      errorMessage: 'Видео найдено, но скачать не удалось.',
    );
  }

  Future<String?> _uploadReferenceImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxUploadBytes) {
        debugPrint('🟣 PIAPI KLING: изображение больше 10MB');
        return null;
      }
      final payload = {
        'file_name': path.basename(file.path),
        'file_data': base64Encode(bytes),
      };
      final response = await http
          .post(
            Uri.parse(_uploadUrl),
            headers: _buildUploadHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            '🟣 PIAPI KLING: upload HTTP ${response.statusCode} ${response.body}');
        return null;
      }
      final json = _decodeJson(response.body);
      if (json is Map<String, dynamic>) {
        final data = json['data'];
        if (data is Map<String, dynamic>) {
          final url = data['url'];
          if (url is String && url.isNotEmpty) return url;
        }
      }
    } catch (e) {
      debugPrint('🟣 PIAPI KLING: upload error: $e');
    }
    return null;
  }

  Map<String, dynamic> _buildPayload({
    required String prompt,
    required int durationSeconds,
    required String aspectRatio,
    String? imageUrl,
    String? negativePrompt,
  }) {
    final input = <String, dynamic>{
      'prompt': prompt,
      'duration': durationSeconds,
      'aspect_ratio': aspectRatio,
      'cfg_scale': _cfgScale,
      'mode': _resolveMode(),
    };
    final version = _version;
    if (version != null && version.isNotEmpty) {
      input['version'] = version;
    }
    if (negativePrompt != null && negativePrompt.trim().isNotEmpty) {
      input['negative_prompt'] = negativePrompt.trim();
    }
    if (_enableAudio) {
      input['enable_audio'] = true;
    }
    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      input['image_url'] = imageUrl.trim();
    }
    final payload = <String, dynamic>{
      'model': 'kling',
      'task_type': 'video_generation',
      'input': input,
    };
    final serviceMode = _serviceMode;
    if (serviceMode != null && serviceMode.isNotEmpty) {
      payload['config'] = {
        'service_mode': serviceMode,
      };
    }
    return payload;
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final key = _apiKey?.trim();
    if (key != null && key.isNotEmpty) {
      headers['X-API-Key'] = key;
    }
    return headers;
  }

  Map<String, String> _buildUploadHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final key = _apiKey?.trim();
    if (key != null && key.isNotEmpty) {
      headers['x-api-key'] = key;
    }
    return headers;
  }

  String _buildTaskStatusUrl(String taskId) {
    var base = _taskUrl.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base/$taskId';
  }

  dynamic _decodeJson(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  String? _extractErrorMessage(dynamic json) {
    if (json is Map<String, dynamic>) {
      final error = json['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) return message;
      }
      final message = json['message'];
      if (message is String && message.isNotEmpty) return message;
      final data = json['data'];
      if (data is Map<String, dynamic>) {
        final nested = _extractErrorMessage(data);
        if (nested != null && nested.isNotEmpty) return nested;
      }
    }
    return null;
  }

  Future<Uint8List?> _downloadVideo(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode != 200) {
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('🟣 PIAPI KLING: ошибка скачивания: $e');
      return null;
    }
  }

  Future<File> _saveBytes(
    Uint8List bytes,
    String prompt,
    String url,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final sanitized = _sanitize(prompt);
    final extension = _guessVideoExtension(url);
    final fileName =
        'kling_${sanitized}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final filePath = path.join(directory.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _guessVideoExtension(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.webm')) return 'webm';
    return 'mp4';
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

  int _normalizeDuration(int durationSeconds) {
    if (durationSeconds <= 5) return 5;
    return 10;
  }

  String _resolveMode() {
    if (_enableAudio) return 'pro';
    return _mode;
  }

  static String? _normalizeMode(String? value) {
    final raw = value?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (raw == 'std' || raw == 'standard') return 'std';
    if (raw == 'pro') return 'pro';
    return null;
  }

  static String? _normalizeVersion(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static String? _normalizeServiceMode(String? value) {
    final raw = value?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (raw == 'public' || raw == 'private') return raw;
    return null;
  }

  static double _parseDoubleEnv(String key, {required double fallback}) {
    final raw = dotenv.env[key]?.trim();
    if (raw == null || raw.isEmpty) return fallback;
    final parsed = double.tryParse(raw);
    return parsed ?? fallback;
  }

  static bool _parseBoolEnv(String key, {required bool fallback}) {
    final raw = dotenv.env[key]?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return fallback;
    if (raw == 'true' || raw == '1' || raw == 'yes') return true;
    if (raw == 'false' || raw == '0' || raw == 'no') return false;
    return fallback;
  }
}

class _PiApiKlingSnapshot {
  final String? taskId;
  final String? status;
  final String? videoUrl;
  final String? errorMessage;
  final String? promptHint;

  const _PiApiKlingSnapshot({
    this.taskId,
    this.status,
    this.videoUrl,
    this.errorMessage,
    this.promptHint,
  });

  bool get isCompleted {
    final value = (status ?? '').toLowerCase();
    return value == 'completed' || value == 'success' || value == 'succeeded';
  }

  bool get isFailed {
    final value = (status ?? '').toLowerCase();
    return value == 'failed' || value == 'error';
  }

  factory _PiApiKlingSnapshot.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const _PiApiKlingSnapshot(
        errorMessage: 'Некорректный ответ сервера.',
      );
    }
    final data = json['data'];
    final payload = data is Map<String, dynamic> ? data : json;
    final output = payload['output'];
    final videoUrl = _extractVideoUrl(output) ?? _extractVideoUrl(payload);
    final input = payload['input'];
    String? promptHint;
    if (input is Map<String, dynamic>) {
      final prompt = input['prompt'];
      if (prompt is String && prompt.isNotEmpty) {
        promptHint = prompt;
      }
    }
    String? errorMessage;
    final error = payload['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        errorMessage = message;
      }
    }
    return _PiApiKlingSnapshot(
      taskId: payload['task_id'] as String?,
      status: payload['status'] as String?,
      videoUrl: videoUrl,
      errorMessage: errorMessage,
      promptHint: promptHint,
    );
  }

  static String? _extractVideoUrl(dynamic value) {
    if (value == null) return null;
    if (value is String && value.isNotEmpty) return value;
    if (value is List) {
      for (final item in value) {
        final nested = _extractVideoUrl(item);
        if (nested != null && nested.isNotEmpty) return nested;
      }
      return null;
    }
    if (value is Map<String, dynamic>) {
      for (final key in [
        'video_url',
        'videoUrl',
        'url',
        'uri',
        'resource',
        'resource_without_watermark',
      ]) {
        final field = value[key];
        if (field is String && field.isNotEmpty) return field;
      }
      final works = value['works'];
      if (works is List && works.isNotEmpty) {
        for (final item in works) {
          final nested = _extractVideoUrl(item);
          if (nested != null && nested.isNotEmpty) return nested;
        }
      }
      final video = value['video'];
      final nested = _extractVideoUrl(video);
      if (nested != null && nested.isNotEmpty) return nested;
      for (final entry in value.values) {
        final nestedValue = _extractVideoUrl(entry);
        if (nestedValue != null && nestedValue.isNotEmpty) return nestedValue;
      }
    }
    return null;
  }
}
