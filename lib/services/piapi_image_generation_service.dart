import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'ai_image_generation_service.dart';
import 'proxied_image_service.dart';

class PiApiImageGenerationService implements AiImageGenerationService {
  final String? _apiKey;
  final String _taskUrl;
  final String _model;
  final String _taskType;
  final int _width;
  final int _height;
  final int _seed;
  final double _flowShift;
  final int _batchSize;
  final String? _negativePrompt;
  final String? _serviceMode;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _pollTimeout;
  final int _maxRequestRetries;
  PiApiImageGenerationService({
    String? apiKey,
    String? taskUrl,
    String? model,
    String? taskType,
    int? width,
    int? height,
    int? seed,
    double? flowShift,
    int? batchSize,
    String? negativePrompt,
    String? serviceMode,
    Duration? timeout,
    Duration? pollInterval,
    Duration? pollTimeout,
  })  : _apiKey = apiKey ?? dotenv.env['PIAPI_API_KEY'],
        _taskUrl = taskUrl ??
            dotenv.env['PIAPI_TASK_URL'] ??
            dotenv.env['PIAPI_BASE_URL'] ??
            'https://api.piapi.ai/api/v1/task',
        _model = 'Qubico/z-image',
        _taskType = taskType ?? 'txt2img',
        _width = width ?? _parseIntEnv('PIAPI_IMAGE_WIDTH', fallback: 1024),
        _height = height ?? _parseIntEnv('PIAPI_IMAGE_HEIGHT', fallback: 1024),
        _seed = seed ?? _parseIntEnv('PIAPI_IMAGE_SEED', fallback: -1),
        _flowShift =
            flowShift ?? _parseDoubleEnv('PIAPI_FLOW_SHIFT', fallback: 3),
        _batchSize = batchSize ?? _parseIntEnv('PIAPI_BATCH_SIZE', fallback: 1),
        _negativePrompt =
            negativePrompt ?? dotenv.env['PIAPI_NEGATIVE_PROMPT']?.trim(),
        _serviceMode = serviceMode ??
            _normalizeServiceMode(dotenv.env['PIAPI_SERVICE_MODE']),
        _timeout = timeout ?? const Duration(seconds: 25),
        _pollInterval = pollInterval ?? const Duration(milliseconds: 1400),
        _pollTimeout = pollTimeout ?? const Duration(seconds: 95),
        _maxRequestRetries =
            _parseIntEnv('PIAPI_REQUEST_RETRIES', fallback: 2).clamp(0, 5);

  @override
  Future<bool> isAvailable() async {
    final hasKey = (_apiKey ?? '').trim().isNotEmpty;
    final hasUrl = _taskUrl.trim().isNotEmpty;
    debugPrint('🟣 PIAPI: доступность apiKey=$hasKey taskUrl=$hasUrl');
    return hasKey && hasUrl;
  }

  @override
  Future<AiImageGenerationResult> generateImageFromPrompt(
    String prompt, {
    int batchSize = 1,
  }) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      debugPrint('🟣 PIAPI: пустой промпт');
      return const AiImageGenerationResult(
        errorMessage: 'Пустой промпт. Напишите, что нужно сгенерировать.',
      );
    }
    if (!await isAvailable()) {
      debugPrint('🟣 PIAPI: сервис не настроен');
      return const AiImageGenerationResult(
        errorMessage: 'Сервис не настроен. Проверьте ключ в .env файле.',
      );
    }

    try {
      final requestedBatchSize = batchSize <= 1
          ? (_batchSize < 1 ? 1 : _batchSize)
          : batchSize;
      final createSnapshot = await _createTaskWithRetry(
        trimmed,
        batchSize: requestedBatchSize,
      );
      if (createSnapshot.errorMessage != null) {
        return AiImageGenerationResult(
          errorMessage: createSnapshot.errorMessage,
        );
      }
      final firstResult = await _resolveResult(createSnapshot);
      if (firstResult != null) return firstResult;

      final taskId = createSnapshot.taskId;
      if (taskId == null || taskId.isEmpty) {
        return const AiImageGenerationResult(
          errorMessage: 'Не удалось получить идентификатор задачи.',
        );
      }
      final polled = await _pollTask(taskId);
      return await _resolveResult(polled) ??
          const AiImageGenerationResult(
            errorMessage: 'Модель не вернула изображение.',
          );
    } catch (e) {
      debugPrint('🟣 PIAPI: ошибка генерации: $e');
      return AiImageGenerationResult(errorMessage: 'Ошибка генерации: $e');
    }
  }

  @override
  Future<AiImageGenerationResult> generateImageFromPromptWithReference({
    required String prompt,
    required File referenceImage,
  }) async {
    if (!referenceImage.existsSync()) {
      return generateImageFromPrompt(prompt);
    }
    debugPrint('🟣 PIAPI: референс не поддерживается, используем текст');
    return generateImageFromPrompt(prompt);
  }

  Future<_PiApiTaskSnapshot> _createTask(
    String prompt, {
    required int batchSize,
  }) async {
    final payload = _buildPayload(prompt, batchSize: batchSize);
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
      debugPrint('🟣 PIAPI: HTTP ${response.statusCode} $error');
      return _PiApiTaskSnapshot(errorMessage: error);
    }
    return _PiApiTaskSnapshot.fromJson(json);
  }

  Future<_PiApiTaskSnapshot> _createTaskWithRetry(
    String prompt, {
    required int batchSize,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _maxRequestRetries; attempt += 1) {
      try {
        return await _createTask(
          prompt,
          batchSize: batchSize,
        );
      } catch (e) {
        lastError = e;
        debugPrint('🟣 PIAPI: create task ошибка attempt=${attempt + 1}: $e');
        if (attempt >= _maxRequestRetries) {
          break;
        }
        await Future.delayed(_retryDelay(attempt));
      }
    }
    return _PiApiTaskSnapshot(
      errorMessage: 'Ошибка создания задачи: $lastError',
    );
  }

  Future<_PiApiTaskSnapshot> _fetchTask(String taskId) async {
    final url = _buildTaskStatusUrl(taskId);
    final response = await http
        .get(Uri.parse(url), headers: _buildHeaders())
        .timeout(_timeout);
    final json = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _extractErrorMessage(json) ??
          'Ошибка запроса: HTTP ${response.statusCode}';
      debugPrint('🟣 PIAPI: HTTP ${response.statusCode} $error');
      return _PiApiTaskSnapshot(errorMessage: error);
    }
    return _PiApiTaskSnapshot.fromJson(json);
  }

  Future<_PiApiTaskSnapshot> _pollTask(String taskId) async {
    final startedAt = DateTime.now();
    var transientErrors = 0;
    while (DateTime.now().difference(startedAt) <= _pollTimeout) {
      _PiApiTaskSnapshot snapshot;
      try {
        snapshot = await _fetchTask(taskId);
      } catch (e) {
        transientErrors += 1;
        debugPrint('🟣 PIAPI: poll ошибка task=$taskId err=$e');
        if (transientErrors > _maxRequestRetries + 1) {
          return _PiApiTaskSnapshot(
            errorMessage: 'Ошибка проверки статуса задачи: $e',
          );
        }
        await Future.delayed(_retryDelay(transientErrors - 1));
        continue;
      }
      transientErrors = 0;
      if (snapshot.errorMessage != null) return snapshot;
      if (snapshot.isCompleted || snapshot.isFailed) return snapshot;
      await Future.delayed(_pollInterval);
    }
    return const _PiApiTaskSnapshot(
      errorMessage: 'Истекло время ожидания генерации.',
    );
  }

  Duration _retryDelay(int attempt) {
    final ms = 450 * (attempt + 1);
    return Duration(milliseconds: ms);
  }

  Future<AiImageGenerationResult?> _resolveResult(
    _PiApiTaskSnapshot snapshot,
  ) async {
    if (snapshot.errorMessage != null) {
      return AiImageGenerationResult(errorMessage: snapshot.errorMessage);
    }
    if (snapshot.isFailed) {
      return AiImageGenerationResult(
        errorMessage: snapshot.errorMessage ?? 'Генерация завершилась ошибкой.',
      );
    }
    if (!snapshot.isCompleted) return null;

    final urls = <String>[
      ...snapshot.imageUrls,
      if (snapshot.imageUrl != null && snapshot.imageUrl!.isNotEmpty)
        snapshot.imageUrl!,
    ];
    if (urls.isEmpty) {
      return const AiImageGenerationResult(
        errorMessage: 'Модель не вернула изображение.',
      );
    }
    final uniqueUrls = <String>{...urls}.toList(growable: false);
    final files = await _downloadAndSaveImages(
      imageUrls: uniqueUrls,
      promptHint: snapshot.promptHint ?? 'image',
    );
    if (files.isEmpty) {
      return const AiImageGenerationResult(
        errorMessage: 'Не удалось скачать изображение.',
      );
    }
    return AiImageGenerationResult(
      file: files.first,
      files: files,
    );
  }

  Map<String, dynamic> _buildPayload(
    String prompt, {
    required int batchSize,
  }) {
    final safeBatchSize = batchSize < 1 ? 1 : batchSize;
    final input = <String, dynamic>{
      'prompt': prompt,
      'width': _width,
      'height': _height,
      'seed': _seed,
      'flow_shift': _flowShift,
      'batch_size': safeBatchSize,
    };
    final negative = _negativePrompt;
    if (negative != null && negative.isNotEmpty) {
      input['negative_prompt'] = negative;
    }
    final payload = <String, dynamic>{
      'model': _model,
      'task_type': _taskType,
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

  Future<Uint8List?> _downloadImage(String url) async {
    return ProxiedImageService().downloadImage(url);
  }

  Future<File> _saveBytes(
    Uint8List bytes,
    String prompt,
    String imageUrl,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final sanitized = _sanitize(prompt);
    final extension = _guessExtension(imageUrl);
    final fileName =
        'piapi_${sanitized}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final filePath = path.join(directory.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<List<File>> _downloadAndSaveImages({
    required List<String> imageUrls,
    required String promptHint,
  }) async {
    final files = <File>[];
    for (final url in imageUrls) {
      final bytes = await _downloadImage(url);
      if (bytes == null || bytes.isEmpty) continue;
      final file = await _saveBytes(bytes, promptHint, url);
      files.add(file);
    }
    return files;
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

  static int _parseIntEnv(String key, {required int fallback}) {
    final raw = dotenv.env[key]?.trim();
    if (raw == null || raw.isEmpty) return fallback;
    final parsed = int.tryParse(raw);
    return parsed ?? fallback;
  }

  static double _parseDoubleEnv(String key, {required double fallback}) {
    final raw = dotenv.env[key]?.trim();
    if (raw == null || raw.isEmpty) return fallback;
    final parsed = double.tryParse(raw);
    return parsed ?? fallback;
  }

  static String? _normalizeServiceMode(String? value) {
    final raw = value?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (raw == 'public' || raw == 'private') return raw;
    return null;
  }
}

class _PiApiTaskSnapshot {
  final String? taskId;
  final String? status;
  final String? imageUrl;
  final List<String> imageUrls;
  final String? errorMessage;
  final String? promptHint;

  const _PiApiTaskSnapshot({
    this.taskId,
    this.status,
    this.imageUrl,
    this.imageUrls = const [],
    this.errorMessage,
    this.promptHint,
  });

  bool get isCompleted => (status ?? '').toLowerCase() == 'completed';
  bool get isFailed => (status ?? '').toLowerCase() == 'failed';

  factory _PiApiTaskSnapshot.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const _PiApiTaskSnapshot(
          errorMessage: 'Некорректный ответ сервера.');
    }
    final data = json['data'];
    final payload = data is Map<String, dynamic> ? data : json;
    final output = payload['output'];
    String? imageUrl;
    final imageUrls = <String>[];
    if (output is Map<String, dynamic>) {
      final directUrl = output['image_url'];
      if (directUrl is String && directUrl.isNotEmpty) {
        imageUrl = directUrl;
        imageUrls.add(directUrl);
      } else {
        final urls = output['image_urls'];
        if (urls is List && urls.isNotEmpty) {
          for (final item in urls) {
            if (item is String && item.isNotEmpty) {
              imageUrls.add(item);
            }
          }
          if (imageUrls.isNotEmpty) imageUrl = imageUrls.first;
        }
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
    final input = payload['input'];
    String? promptHint;
    if (input is Map<String, dynamic>) {
      final prompt = input['prompt'];
      if (prompt is String && prompt.isNotEmpty) {
        promptHint = prompt;
      }
    }
    return _PiApiTaskSnapshot(
      taskId: payload['task_id'] as String?,
      status: payload['status'] as String?,
      imageUrl: imageUrl,
      imageUrls: imageUrls,
      errorMessage: errorMessage,
      promptHint: promptHint,
    );
  }
}
