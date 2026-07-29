import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import 'ai_image_captioning_service.dart';

class PiApiImageCaptioningService implements AiImageCaptioningService {
  static const int _maxBytes = 10 * 1024 * 1024;
  static const Set<String> _allowedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
  };

  final String? _apiKey;
  final String _taskUrl;
  final String _uploadUrl;
  final String _model;
  final String _taskType;
  final String _promptStyle;
  final String _captionLength;
  final String? _serviceMode;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _pollTimeout;
  PiApiImageCaptioningService({
    String? apiKey,
    String? taskUrl,
    String? uploadUrl,
    String? model,
    String? taskType,
    String? promptStyle,
    String? captionLength,
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
        _model = model ??
            dotenv.env['PIAPI_JOYCAPTION_MODEL'] ??
            'Qubico/joycaption',
        _taskType = taskType ??
            dotenv.env['PIAPI_JOYCAPTION_TASK_TYPE'] ??
            'joycaption-beta-one',
        _promptStyle = promptStyle ??
            dotenv.env['PIAPI_JOYCAPTION_PROMPT_STYLE'] ??
            'Descriptive',
        _captionLength = captionLength ??
            dotenv.env['PIAPI_JOYCAPTION_CAPTION_LENGTH'] ??
            'any',
        _serviceMode = serviceMode ??
            _normalizeServiceMode(dotenv.env['PIAPI_SERVICE_MODE']),
        _timeout = timeout ?? const Duration(seconds: 45),
        _pollInterval = pollInterval ?? const Duration(seconds: 2),
        _pollTimeout = pollTimeout ?? const Duration(minutes: 2);

  @override
  Future<bool> isAvailable() async {
    final hasKey = (_apiKey ?? '').trim().isNotEmpty;
    final hasTaskUrl = _taskUrl.trim().isNotEmpty;
    final hasUploadUrl = _uploadUrl.trim().isNotEmpty;
    final isProxied = hasTaskUrl && !_taskUrl.contains('api.piapi.ai');
    debugPrint(
        '🟣 PIAPI JOYCAPTION: доступность key=$hasKey taskUrl=$hasTaskUrl uploadUrl=$hasUploadUrl proxied=$isProxied');
    return hasTaskUrl && hasUploadUrl && (isProxied || hasKey);
  }

  @override
  Future<AiImageCaptioningResult> generateCaptionFromImage(
    File imageFile,
  ) async {
    if (!imageFile.existsSync()) {
      return const AiImageCaptioningResult(
        errorMessage: 'Файл изображения не найден.',
      );
    }
    if (!await isAvailable()) {
      return const AiImageCaptioningResult(
        errorMessage: 'Сервис не настроен. Проверьте ключи и URL в .env файле.',
      );
    }
    final extension = path.extension(imageFile.path).toLowerCase();
    if (!_allowedExtensions.contains(extension)) {
      return AiImageCaptioningResult(
        errorMessage: 'Неподдерживаемый формат: $extension',
      );
    }
    final bytes = await imageFile.readAsBytes();
    if (bytes.length > _maxBytes) {
      return const AiImageCaptioningResult(
        errorMessage:
            'Изображение больше 10MB. Сожмите файл и попробуйте снова.',
      );
    }
    try {
      final uploadResult = await _uploadFile(
        fileName: path.basename(imageFile.path),
        bytes: bytes,
      );
      String imageInput;
      if (uploadResult.url != null && uploadResult.url!.isNotEmpty) {
        imageInput = uploadResult.url!;
      } else if (uploadResult.shouldFallbackToBase64) {
        debugPrint('🟣 PIAPI JOYCAPTION: upload недоступен, используем base64');
        imageInput = base64Encode(bytes);
      } else {
        return AiImageCaptioningResult(
          errorMessage:
              uploadResult.errorMessage ?? 'Не удалось загрузить изображение.',
        );
      }
      final createSnapshot = await _createTask(imageInput);
      if (createSnapshot.errorMessage != null) {
        return AiImageCaptioningResult(
          errorMessage: createSnapshot.errorMessage,
        );
      }
      final firstResult = _resolveCaption(createSnapshot);
      if (firstResult != null) return firstResult;

      final taskId = createSnapshot.taskId;
      if (taskId == null || taskId.isEmpty) {
        return const AiImageCaptioningResult(
          errorMessage: 'Не удалось получить идентификатор задачи.',
        );
      }
      final polled = await _pollTask(taskId);
      return _resolveCaption(polled) ??
          const AiImageCaptioningResult(
            errorMessage: 'Модель не вернула описание.',
          );
    } catch (e) {
      debugPrint('🟣 PIAPI JOYCAPTION: ошибка: $e');
      return AiImageCaptioningResult(errorMessage: 'Ошибка: $e');
    }
  }

  Future<_UploadResult> _uploadFile({
    required String fileName,
    required List<int> bytes,
  }) async {
    final payload = {
      'file_name': fileName,
      'file_data': base64Encode(bytes),
    };
    final client = _createHttpClient();
    try {
      final response = await client
          .post(
            Uri.parse(_uploadUrl),
            headers: _buildUploadHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            '🟣 PIAPI JOYCAPTION: upload HTTP ${response.statusCode} ${response.body}');
        final json = _decodeJson(response.body);
        final errorMessage = _extractErrorMessage(json);
        final shouldFallback = _shouldFallbackToBase64(
          statusCode: response.statusCode,
          errorMessage: errorMessage,
        );
        return _UploadResult(
          errorMessage: errorMessage,
          shouldFallbackToBase64: shouldFallback,
        );
      }
      final json = _decodeJson(response.body);
      if (json is Map<String, dynamic>) {
        final data = json['data'];
        if (data is Map<String, dynamic>) {
          final url = data['url'];
          if (url is String && url.isNotEmpty) {
            return _UploadResult(url: url);
          }
        }
      }
      return const _UploadResult();
    } finally {
      client.close();
    }
  }

  Future<_PiApiCaptionSnapshot> _createTask(String imageUrl) async {
    final payload = _buildPayload(imageUrl);
    final client = _createHttpClient();
    try {
      final response = await client
          .post(
            Uri.parse(_taskUrl),
            headers: _buildTaskHeaders(),
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      final json = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = _extractErrorMessage(json) ??
            'Ошибка запроса: HTTP ${response.statusCode}';
        debugPrint('🟣 PIAPI JOYCAPTION: HTTP ${response.statusCode} $error');
        return _PiApiCaptionSnapshot(errorMessage: error);
      }
      return _PiApiCaptionSnapshot.fromJson(json);
    } finally {
      client.close();
    }
  }

  Future<_PiApiCaptionSnapshot> _fetchTask(String taskId) async {
    final url = _buildTaskStatusUrl(taskId);
    final client = _createHttpClient();
    try {
      final response = await client
          .get(Uri.parse(url), headers: _buildTaskHeaders())
          .timeout(_timeout);
      final json = _decodeJson(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = _extractErrorMessage(json) ??
            'Ошибка запроса: HTTP ${response.statusCode}';
        debugPrint('🟣 PIAPI JOYCAPTION: HTTP ${response.statusCode} $error');
        return _PiApiCaptionSnapshot(errorMessage: error);
      }
      return _PiApiCaptionSnapshot.fromJson(json);
    } finally {
      client.close();
    }
  }

  http.Client _createHttpClient() => http.Client();

  Future<_PiApiCaptionSnapshot> _pollTask(String taskId) async {
    final startedAt = DateTime.now();
    while (DateTime.now().difference(startedAt) <= _pollTimeout) {
      final snapshot = await _fetchTask(taskId);
      if (snapshot.errorMessage != null) return snapshot;
      if (snapshot.isCompleted || snapshot.isFailed) return snapshot;
      await Future.delayed(_pollInterval);
    }
    return const _PiApiCaptionSnapshot(
      errorMessage: 'Истекло время ожидания генерации.',
    );
  }

  AiImageCaptioningResult? _resolveCaption(_PiApiCaptionSnapshot snapshot) {
    if (snapshot.errorMessage != null) {
      return AiImageCaptioningResult(errorMessage: snapshot.errorMessage);
    }
    if (snapshot.isFailed) {
      return AiImageCaptioningResult(
        errorMessage: snapshot.errorMessage ?? 'Генерация завершилась ошибкой.',
      );
    }
    if (!snapshot.isCompleted) return null;
    final caption = snapshot.caption?.trim();
    if (caption == null || caption.isEmpty) {
      return const AiImageCaptioningResult(
        errorMessage: 'Модель не вернула описание.',
      );
    }
    return AiImageCaptioningResult(caption: caption);
  }

  Map<String, dynamic> _buildPayload(String imageUrl) {
    final payload = <String, dynamic>{
      'model': _model,
      'task_type': _taskType,
      'input': {
        'workflow_type': _taskType,
        'prompt_style': _promptStyle,
        'caption_length': _captionLength,
        'image': imageUrl,
      },
    };
    final serviceMode = _serviceMode;
    if (serviceMode != null && serviceMode.isNotEmpty) {
      payload['config'] = {
        'service_mode': serviceMode,
      };
    }
    return payload;
  }

  Map<String, String> _buildTaskHeaders() {
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
    }
    return null;
  }

  bool _shouldFallbackToBase64({
    required int statusCode,
    required String? errorMessage,
  }) {
    if (statusCode != 403) return false;
    final message = (errorMessage ?? '').toLowerCase();
    return message.contains('not allowed to upload') ||
        message.contains('upgrade') ||
        message.contains('plan');
  }

  static String? _normalizeServiceMode(String? value) {
    final raw = value?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (raw == 'public' || raw == 'private') return raw;
    return null;
  }
}

class _UploadResult {
  final String? url;
  final String? errorMessage;
  final bool shouldFallbackToBase64;

  const _UploadResult({
    this.url,
    this.errorMessage,
    this.shouldFallbackToBase64 = false,
  });
}

class _PiApiCaptionSnapshot {
  final String? taskId;
  final String? status;
  final String? caption;
  final String? errorMessage;

  const _PiApiCaptionSnapshot({
    this.taskId,
    this.status,
    this.caption,
    this.errorMessage,
  });

  bool get isCompleted => (status ?? '').toLowerCase() == 'completed';
  bool get isFailed => (status ?? '').toLowerCase() == 'failed';

  factory _PiApiCaptionSnapshot.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const _PiApiCaptionSnapshot(
        errorMessage: 'Некорректный ответ сервера.',
      );
    }
    final data = json['data'];
    final payload = data is Map<String, dynamic> ? data : json;
    final output = payload['output'];
    final caption = _extractCaption(output) ?? _extractCaption(payload);
    String? errorMessage;
    final error = payload['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        errorMessage = message;
      }
    }
    return _PiApiCaptionSnapshot(
      taskId: payload['task_id'] as String?,
      status: payload['status'] as String?,
      caption: caption,
      errorMessage: errorMessage,
    );
  }

  static String? _extractCaption(dynamic value) {
    if (value == null) return null;
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is List && value.isNotEmpty) {
      for (final item in value) {
        final nested = _extractCaption(item);
        if (nested != null && nested.trim().isNotEmpty) return nested;
      }
    }
    if (value is Map<String, dynamic>) {
      for (final key in [
        'caption',
        'text',
        'result',
        'description',
        'output',
        'prompt',
      ]) {
        final field = value[key];
        final nested = _extractCaption(field);
        if (nested != null && nested.trim().isNotEmpty) return nested;
      }
      final tags = value['tags'];
      if (tags is List && tags.isNotEmpty) {
        final joined = tags.whereType<String>().join(', ');
        if (joined.trim().isNotEmpty) return joined;
      }
      final captions = value['captions'];
      if (captions is List && captions.isNotEmpty) {
        final joined = captions.whereType<String>().join(' ');
        if (joined.trim().isNotEmpty) return joined;
      }
    }
    return null;
  }
}
