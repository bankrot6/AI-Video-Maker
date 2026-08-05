import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'apibost_model_relay.dart';

enum ApiBostVideoTaskStatus { queued, inProgress, completed, failed }

class ApiBostVideoTaskState {
  const ApiBostVideoTaskState({
    required this.status,
    this.progress = 0,
    this.error,
  });

  final ApiBostVideoTaskStatus status;
  final int progress;
  final String? error;

  bool get isTerminal =>
      status == ApiBostVideoTaskStatus.completed ||
      status == ApiBostVideoTaskStatus.failed;

  static ApiBostVideoTaskState fromJson(Map<String, dynamic> json) {
    final raw = (json['status'] as String? ?? '').toLowerCase();
    final status = switch (raw) {
      'completed' || 'succeeded' || 'success' => ApiBostVideoTaskStatus.completed,
      'failed' || 'error' || 'canceled' => ApiBostVideoTaskStatus.failed,
      'in_progress' || 'processing' || 'running' =>
        ApiBostVideoTaskStatus.inProgress,
      _ => ApiBostVideoTaskStatus.queued,
    };
    final progress = json['progress'];
    return ApiBostVideoTaskState(
      status: status,
      progress: progress is num ? progress.toInt() : 0,
      error: _errorMessage(json),
    );
  }

  static String? _errorMessage(Map<String, dynamic> json) {
    final error = json['error'];
    if (error is String && error.isNotEmpty) return error;
    if (error is Map) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    final message = json['message'];
    if (message is String && message.isNotEmpty) return message;
    return null;
  }
}

/// Асинхронный видео-контур ApiBost: `POST /v1/videos` ставит задачу,
/// `GET /v1/videos/{id}` отдаёт статус, `GET /v1/videos/{id}/content` — MP4.
///
/// В отличие от `/v1/chat/completions`, где рендер держит одно соединение
/// несколько минут (мобильные операторы рвут такое молчащее соединение), здесь
/// все запросы короткие. Идентификатор задачи можно сохранить и вернуться за
/// уже оплаченным результатом после перезапуска приложения.
///
/// Пропорции задаются полем `size`: директивы формата в тексте промпта
/// (`[9:16]`), которые понимает chat-контур, этот эндпоинт игнорирует —
/// проверено замером метаданных готовых файлов.
///
/// Только генерация по тексту: переданные кадры (`image_urls`) шлюз молча
/// пропускает и рендерит видео по одному промпту, поэтому генерация по фото
/// пользователя остаётся на chat-контуре с картинками в data-URI.
class ApiBostVideoTaskClient {
  ApiBostVideoTaskClient({
    required String baseUrl,
    Duration? requestTimeout,
  })  : _baseUrl = baseUrl,
        _requestTimeout = requestTimeout ?? const Duration(seconds: 45);

  static const _tag = '🎬 APIBOST_VIDEO_TASK';

  final String _baseUrl;
  final Duration _requestTimeout;

  Future<String> createTask({
    required String model,
    required String prompt,
    required String size,
  }) async {
    final payload = <String, dynamic>{
      'model': model,
      'prompt': prompt,
      'size': size,
    };

    final response = await http
        .post(
          Uri.parse('$_baseUrl/v1/videos'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_requestTimeout);

    final json = _decode(response.statusCode, response.body);
    final id = json['task_id'] ?? json['id'];
    if (id is! String || id.isEmpty) {
      throw ApiBostHttpException(
        response.statusCode,
        'Ответ без идентификатора задачи',
      );
    }
    debugPrint('$_tag задача создана: $id size=$size');
    return id;
  }

  Future<ApiBostVideoTaskState> fetchTask(String taskId) async {
    final response = await http
        .get(Uri.parse('$_baseUrl/v1/videos/$taskId'))
        .timeout(_requestTimeout);
    return ApiBostVideoTaskState.fromJson(
      _decode(response.statusCode, response.body),
    );
  }

  String contentUrl(String taskId) => '$_baseUrl/v1/videos/$taskId/content';

  Map<String, dynamic> _decode(int statusCode, String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw ApiBostHttpException(statusCode, 'Некорректный ответ шлюза');
    }
    final map = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiBostHttpException(
        statusCode,
        ApiBostVideoTaskState._errorMessage(map) ?? 'ApiBost HTTP $statusCode',
      );
    }
    return map;
  }
}
