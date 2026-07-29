import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class FaceswapResult {
  const FaceswapResult({this.imageUrl, this.errorMessage});

  final String? imageUrl;
  final String? errorMessage;

  bool get isSuccess => imageUrl != null && imageUrl!.isNotEmpty;
}

class PiApiFaceswapService {
  PiApiFaceswapService({
    String? apiKey,
    String? taskUrl,
    Duration? timeout,
    Duration? pollInterval,
    Duration? pollTimeout,
  })  : _apiKey = apiKey ?? dotenv.env['PIAPI_API_KEY'],
        _taskUrl = _normalizeTaskUrl(
          taskUrl ??
              dotenv.env['PIAPI_TASK_URL'] ??
              dotenv.env['PIAPI_BASE_URL'] ??
              'https://api.piapi.ai/api/v1/task',
        ),
        _timeout = timeout ?? const Duration(seconds: 30),
        _pollInterval = pollInterval ?? const Duration(seconds: 2),
        _pollTimeout = pollTimeout ?? const Duration(minutes: 2);

  static String _normalizeTaskUrl(String url) {
    final t = url.trim();
    if (t.endsWith('/')) return t.substring(0, t.length - 1);
    return t;
  }

  final String? _apiKey;
  final String _taskUrl;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _pollTimeout;

  Future<bool> isAvailable() async {
    final hasKey = (_apiKey ?? '').trim().isNotEmpty;
    final hasUrl = _taskUrl.isNotEmpty;
    final isProxied = hasUrl && !_taskUrl.contains('api.piapi.ai');
    debugPrint('Faceswap: доступность key=$hasKey url=$hasUrl proxied=$isProxied');
    return hasUrl && (isProxied || hasKey);
  }

  Future<FaceswapResult> swapFace({
    required String targetImageUrl,
    required String swapImageUrl,
  }) async {
    if (targetImageUrl.trim().isEmpty || swapImageUrl.trim().isEmpty) {
      return const FaceswapResult(
        errorMessage: 'Нужны URL целевого и подставляемого лица.',
      );
    }
    if (!await isAvailable()) {
      return const FaceswapResult(
        errorMessage: 'Сервис не настроен. Проверьте PIAPI_API_KEY в .env.',
      );
    }

    try {
      final createRes = await _createTask(
        targetImageUrl: targetImageUrl.trim(),
        swapImageUrl: swapImageUrl.trim(),
      );
      if (createRes.errorMessage != null) {
        return FaceswapResult(errorMessage: createRes.errorMessage);
      }
      final taskId = createRes.taskId;
      if (taskId == null || taskId.isEmpty) {
        return const FaceswapResult(
          errorMessage: 'Не получен идентификатор задачи.',
        );
      }
      final polled = await _pollTask(taskId);
      return _resolveResult(polled);
    } catch (e) {
      debugPrint('Faceswap: ошибка $e');
      return FaceswapResult(errorMessage: 'Ошибка смены лица: $e');
    }
  }

  Future<_TaskSnapshot> _createTask({
    required String targetImageUrl,
    required String swapImageUrl,
  }) async {
    final payload = <String, dynamic>{
      'model': 'Qubico/image-toolkit',
      'task_type': 'face-swap',
      'input': {
        'target_image': targetImageUrl,
        'swap_image': swapImageUrl,
      },
    };
    debugPrint('Faceswap: создание задачи target=$targetImageUrl swap=$swapImageUrl');
    debugPrint('Faceswap: payload=${jsonEncode(payload)}');
    final response = await http
        .post(
          Uri.parse(_taskUrl),
          headers: _headers(),
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    final json = _decodeJson(response.body);
    debugPrint('Faceswap: ответ создания ${response.statusCode}: ${response.body}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg = _extractMessage(json) ?? 'HTTP ${response.statusCode}';
      return _TaskSnapshot(errorMessage: msg);
    }
    return _TaskSnapshot.fromResponse(json);
  }

  Future<_TaskSnapshot> _pollTask(String taskId) async {
    debugPrint('Faceswap: начинаем опрос задачи $taskId');
    final deadline = DateTime.now().add(_pollTimeout);
    var attempts = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempts++;
      final res = await http
          .get(
            Uri.parse('$_taskUrl/$taskId'),
            headers: _headers(),
          )
          .timeout(_timeout);
      final json = _decodeJson(res.body);
      debugPrint('Faceswap: опрос #$attempts, статус ${res.statusCode}');
      if (res.statusCode < 200 || res.statusCode >= 300) {
        await Future.delayed(_pollInterval);
        continue;
      }
      final snapshot = _TaskSnapshot.fromResponse(json);
      debugPrint('Faceswap: статус задачи=${snapshot.status}, url=${snapshot.imageUrl}');
      if (snapshot.errorMessage != null) {
        debugPrint('Faceswap: ошибка в задаче: ${snapshot.errorMessage}');
        return snapshot;
      }
      if (snapshot.isCompleted || snapshot.isFailed) {
        debugPrint('Faceswap: задача завершена (completed=${snapshot.isCompleted}, failed=${snapshot.isFailed})');
        return snapshot;
      }
      await Future.delayed(_pollInterval);
    }
    debugPrint('Faceswap: таймаут после $attempts попыток');
    return const _TaskSnapshot(
      errorMessage: 'Истекло время ожидания смены лица.',
    );
  }

  FaceswapResult _resolveResult(_TaskSnapshot s) {
    if (s.errorMessage != null) {
      return FaceswapResult(errorMessage: s.errorMessage);
    }
    if (s.isFailed) {
      return FaceswapResult(
        errorMessage: s.errorMessage ?? 'Смена лица завершилась с ошибкой.',
      );
    }
    if (!s.isCompleted || (s.imageUrl == null || s.imageUrl!.isEmpty)) {
      return const FaceswapResult(
        errorMessage: 'Нет URL результата в ответе.',
      );
    }
    return FaceswapResult(imageUrl: s.imageUrl);
  }

  Map<String, String> _headers() {
    final h = <String, String>{'Content-Type': 'application/json'};
    final key = _apiKey?.trim();
    if (key != null && key.isNotEmpty) h['X-API-Key'] = key;
    return h;
  }

  static dynamic _decodeJson(String body) {
    final t = body.trim();
    if (t.isEmpty) return null;
    try {
      return jsonDecode(t);
    } catch (_) {
      return null;
    }
  }

  static String? _extractMessage(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final msg = json['message'];
    if (msg is String && msg.isNotEmpty) return msg;
    final data = json['data'];
    if (data is Map<String, dynamic>) {
      final err = data['error'];
      if (err is Map<String, dynamic>) {
        final m = err['message'];
        if (m is String && m.isNotEmpty) return m;
      }
    }
    return null;
  }
}

class _TaskSnapshot {
  const _TaskSnapshot({
    this.taskId,
    this.status,
    this.imageUrl,
    this.errorMessage,
  });

  final String? taskId;
  final String? status;
  final String? imageUrl;
  final String? errorMessage;

  bool get isCompleted => (status ?? '').toLowerCase() == 'completed';
  bool get isFailed => (status ?? '').toLowerCase() == 'failed';

  factory _TaskSnapshot.fromResponse(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const _TaskSnapshot(errorMessage: 'Некорректный ответ API.');
    }
    final data = json['data'];
    final payload = data is Map<String, dynamic> ? data : json;
    String? imageUrl;
    final output = payload['output'];
    if (output is Map<String, dynamic>) {
      final single = output['image_url'];
      if (single is String && single.isNotEmpty) {
        imageUrl = single;
      } else {
        final list = output['image_urls'];
        if (list is List && list.isNotEmpty && list.first is String) {
          imageUrl = list.first as String;
        }
      }
    }
    String? errorMessage;
    final error = payload['error'];
    if (error is Map<String, dynamic>) {
      final m = error['message'];
      if (m is String && m.isNotEmpty) errorMessage = m;
    }
    return _TaskSnapshot(
      taskId: payload['task_id'] as String?,
      status: payload['status'] as String?,
      imageUrl: imageUrl,
      errorMessage: errorMessage,
    );
  }
}
