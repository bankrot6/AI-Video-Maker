import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class HuggingFaceInferenceResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
  final dynamic json;

  HuggingFaceInferenceResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
    required this.json,
  });

  bool get isOk => statusCode >= 200 && statusCode < 300;

  bool get isJson => json != null;
}

class HuggingFaceInferenceClient {
  final String? _apiToken;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _pollTimeout;
  final bool _waitForModel;

  HuggingFaceInferenceClient({
    String? apiToken,
    Duration timeout = const Duration(seconds: 60),
    Duration pollInterval = const Duration(seconds: 2),
    Duration pollTimeout = const Duration(minutes: 2),
    bool waitForModel = true,
  })  : _apiToken = apiToken,
        _timeout = timeout,
        _pollInterval = pollInterval,
        _pollTimeout = pollTimeout,
        _waitForModel = waitForModel;

  bool get hasToken => (_apiToken ?? '').trim().isNotEmpty;

  Future<HuggingFaceInferenceResponse> postJson({
    required String url,
    required Map<String, dynamic> payload,
    String? accept,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (accept != null && accept.isNotEmpty) {
      headers['Accept'] = accept;
    }
    final token = _apiToken?.trim();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final startedAt = DateTime.now();
    while (true) {
      final response = await http
          .post(
            Uri.parse(url),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(_timeout);

      final decoded = _tryDecodeJson(response.bodyBytes);
      final hfResponse = HuggingFaceInferenceResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        bodyBytes: response.bodyBytes,
        json: decoded,
      );
      if (!_shouldRetry(hfResponse, startedAt)) {
        return hfResponse;
      }
      final delay = _retryDelay(hfResponse);
      await Future.delayed(delay);
    }
  }

  bool _shouldRetry(
      HuggingFaceInferenceResponse response, DateTime startedAt) {
    if (!_waitForModel) return false;
    if (DateTime.now().difference(startedAt) > _pollTimeout) return false;
    if (response.statusCode != 503 && response.statusCode != 202) {
      return false;
    }
    final json = response.json;
    if (json is Map<String, dynamic>) {
      final error = json['error'];
      if (error is String && _looksLikeLoading(error)) return true;
      final estimated = json['estimated_time'];
      if (estimated is num && estimated > 0) return true;
    }
    return response.bodyBytes.isEmpty;
  }

  Duration _retryDelay(HuggingFaceInferenceResponse response) {
    final json = response.json;
    if (json is Map<String, dynamic>) {
      final estimated = json['estimated_time'];
      if (estimated is num && estimated > 0) {
        final seconds = estimated.ceil();
        return Duration(seconds: seconds.clamp(1, 20));
      }
    }
    return _pollInterval;
  }

  bool _looksLikeLoading(String value) {
    final lower = value.toLowerCase();
    return lower.contains('loading') ||
        lower.contains('currently loading') ||
        lower.contains('queued');
  }

  dynamic _tryDecodeJson(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    final body = utf8.decode(bytes, allowMalformed: true).trim();
    if (body.isEmpty) return null;
    if (!body.startsWith('{') && !body.startsWith('[')) {
      return null;
    }
    try {
      return jsonDecode(body);
    } catch (e) {
      debugPrint('🤗 HF: не удалось разобрать JSON: $e');
      return null;
    }
  }
}
