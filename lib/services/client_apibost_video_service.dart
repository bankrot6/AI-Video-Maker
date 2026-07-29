import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../config/ai_proxy_config.dart';
import 'apibost_model_catalog.dart';
import 'apibost_model_relay.dart';
import 'generated_media.dart';
import 'photosession_generation_router.dart';

/// Генерация видео через Gemini-контур ApiBost
/// (`/v1beta/models/{model}:generateContent`).
///
/// Формат задаётся директивами в тексте промпта — `[9:16]` для пропорций и
/// `[8s]` для длительности; JSON-поля `aspect_ratio` и `duration` релеем
/// игнорируются. Это та же схема, что у image-моделей ApiBost.
///
/// Модель принимает и входные изображения через `inlineData`: одно фото
/// анимируется, поэтому генерация по фото пользователя работает так же, как
/// text-to-video, только с добавленным кадром-источником.
///
/// Кредиты, как и в остальных клиентских ApiBost-сервисах, резервирует
/// вызывающий код.
class ClientApiBostVideoService
    implements PhotosessionGenerationService, ReferenceImageGenerationService {
  ClientApiBostVideoService({
    required String model,
    int durationSeconds = ApiBostModelCatalog.maxVideoDurationSeconds,
    Duration? timeout,
    Duration? downloadTimeout,
  })  : _model = model,
        _durationSeconds = durationSeconds,
        _timeout = timeout ?? const Duration(minutes: 10),
        _downloadTimeout = downloadTimeout ?? const Duration(minutes: 3);

  static const _tag = '🎬 CLIENT_APIBOST_VIDEO';

  static const Set<String> _moderationMarkers = {
    'content_policy_violation',
    'moderation_blocked',
    'prohibited_content',
    'safety',
  };

  static const Set<String> _blockedFinishReasons = {
    'PROHIBITED_CONTENT',
    'IMAGE_PROHIBITED_CONTENT',
    'BLOCKED_REASON_UNSPECIFIED',
  };

  final String _model;
  final int _durationSeconds;
  final Duration _timeout;
  final Duration _downloadTimeout;

  @override
  Future<bool> isAvailable() async {
    final ok = AiProxyConfig.apiBostBaseUrl() != null;
    debugPrint('$_tag isAvailable=$ok model=$_model');
    return ok;
  }

  @override
  Future<PhotosessionGenerationResult> generateImage({
    required String prompt,
    String resolution = '2K',
    String aspectRatio = '3:4',
  }) async {
    return _guarded('generateImage', () async {
      return _generate(
        prompt: prompt,
        aspectRatio: aspectRatio,
        imageBuffers: const [],
      );
    });
  }

  /// Оживляет фото пользователя: кадр уходит в `inlineData`, а промпт описывает
  /// движение. Референс сцены, если он есть, идёт первым — порядок тот же, что
  /// у image-контура ApiBost.
  @override
  Future<PhotosessionGenerationResult> generateWithFace({
    required String userImageUrl,
    required String scenePrompt,
    String? referenceImageUrl,
    String resolution = '2K',
    String aspectRatio = '3:4',
  }) async {
    return _guarded('generateWithFace', () async {
      final imageBuffers = <List<int>>[];

      final hasReference =
          referenceImageUrl != null && referenceImageUrl.trim().isNotEmpty;
      if (hasReference) {
        final referenceBytes = await _resolveToBytes(referenceImageUrl);
        if (referenceBytes == null) {
          return const PhotosessionGenerationResult(
            errorMessage: 'Не найдено референсное изображение',
          );
        }
        imageBuffers.add(referenceBytes);
      }

      final userBytes = await _resolveToBytes(userImageUrl);
      if (userBytes == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Файл пользователя не найден',
        );
      }
      imageBuffers.add(userBytes);

      return _generate(
        prompt: scenePrompt,
        aspectRatio: aspectRatio,
        imageBuffers: imageBuffers,
      );
    });
  }

  @override
  Future<PhotosessionGenerationResult> generateFromReference({
    required String referenceImageUrl,
    required String prompt,
    String resolution = '2K',
    String aspectRatio = '3:4',
  }) async {
    return _guarded('generateFromReference', () async {
      final referenceBytes = await _resolveToBytes(referenceImageUrl);
      if (referenceBytes == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Не найдено референсное изображение',
        );
      }
      return _generate(
        prompt: prompt,
        aspectRatio: aspectRatio,
        imageBuffers: [referenceBytes],
      );
    });
  }

  Future<PhotosessionGenerationResult> _guarded(
    String operation,
    Future<PhotosessionGenerationResult> Function() body,
  ) async {
    if (!await isAvailable()) {
      return const PhotosessionGenerationResult(
        errorMessage: 'ApiBost relay не настроен',
      );
    }
    try {
      return await body();
    } catch (e, st) {
      debugPrint('$_tag ошибка $operation: $e');
      debugPrint('$_tag стек: $st');
      return PhotosessionGenerationResult(errorMessage: 'Ошибка: $e');
    }
  }

  /// Пропорции и длительность Veo принимает только директивами в промпте.
  String _buildPrompt(String prompt, String aspectRatio) {
    final ratio = ApiBostModelCatalog.videoAspectRatioFor(aspectRatio);
    final duration = _durationSeconds.clamp(
      1,
      ApiBostModelCatalog.maxVideoDurationSeconds,
    );
    final directives = '[$ratio] [${duration}s] ';
    final body = _fitToLimit(
      prompt.trim(),
      ApiBostModelCatalog.maxVideoPromptLength - directives.length,
    );
    return '$directives$body';
  }

  /// Директивы формата обязательны, поэтому под текст остаётся меньше лимита.
  /// Рез идёт по границе блока или предложения, чтобы модель не получила
  /// оборванную на полуслове фразу.
  static String _fitToLimit(String text, int limit) {
    if (limit <= 0) return '';
    if (text.length <= limit) return text;

    final head = text.substring(0, limit);
    for (final separator in const ['\n\n', '\n', '. ', '.', ' ']) {
      final cut = head.lastIndexOf(separator);
      if (cut > limit ~/ 2) {
        final trimmed = head.substring(0, cut).trimRight();
        if (trimmed.isNotEmpty) {
          debugPrint('$_tag промпт обрезан до ${trimmed.length} символов '
              '(исходно ${text.length})');
          return trimmed;
        }
      }
    }
    return head.trimRight();
  }

  Future<PhotosessionGenerationResult> _generate({
    required String prompt,
    required String aspectRatio,
    required List<List<int>> imageBuffers,
  }) async {
    if (prompt.trim().isEmpty) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Пустой промт: опишите сцену для генерации видео',
      );
    }

    final fullPrompt = _buildPrompt(prompt, aspectRatio);
    debugPrint('$_tag POST model=$_model images=${imageBuffers.length} '
        'aspectRatio=${ApiBostModelCatalog.videoAspectRatioFor(aspectRatio)}');

    final Map<String, dynamic> data;
    try {
      data = await _postGenerateContent(fullPrompt, imageBuffers);
    } on ApiBostHttpException catch (e) {
      debugPrint('$_tag ошибка model=$_model HTTP ${e.statusCode}: ${e.message}');
      if (_isModerationError(e.message)) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Контент заблокирован политикой безопасности. '
              'Попробуйте другое описание.',
        );
      }
      return PhotosessionGenerationResult(errorMessage: e.message);
    }

    final videoUrl = _firstVideoUrl(data);
    if (videoUrl == null) {
      final finishReason = _extractFinishReason(data);
      debugPrint('$_tag нет ссылки на видео, finishReason=$finishReason');
      if (finishReason != null &&
          _blockedFinishReasons.contains(finishReason)) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Контент заблокирован политикой безопасности. '
              'Попробуйте другое фото или описание.',
        );
      }
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось получить видео из ответа',
      );
    }

    final bytes = await _resolveToBytes(videoUrl);
    if (bytes == null) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось скачать готовое видео',
      );
    }

    final localPath = await _saveLocally(bytes, prompt);
    if (localPath == null) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось сохранить видео',
      );
    }
    debugPrint('$_tag готово: $localPath (${bytes.length} байт)');
    return PhotosessionGenerationResult(imageUrl: localPath);
  }

  Future<Map<String, dynamic>> _postGenerateContent(
    String prompt,
    List<List<int>> imageBuffers,
  ) async {
    final parts = <Map<String, dynamic>>[
      {'text': prompt},
    ];
    for (final buffer in imageBuffers) {
      parts.add({
        'inlineData': {
          'mimeType': 'image/jpeg',
          'data': base64Encode(buffer),
        },
      });
    }

    final response = await http
        .post(
          Uri.parse('${_baseUrl()}/v1beta/models/$_model:generateContent'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {'role': 'user', 'parts': parts},
            ],
          }),
        )
        .timeout(_timeout);
    return _decode(response.statusCode, response.bodyBytes);
  }

  String _baseUrl() {
    final base = AiProxyConfig.apiBostBaseUrl();
    if (base == null) {
      throw StateError('ApiBost relay URL is not configured');
    }
    return base;
  }

  Map<String, dynamic> _decode(int statusCode, List<int> bodyBytes) {
    final body = utf8.decode(bodyBytes, allowMalformed: true);
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiBostHttpException(
        statusCode,
        _tryParseErrorMessage(body) ?? 'ApiBost HTTP $statusCode',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }

  static final RegExp _videoUrlPattern = RegExp(
    r'https?://[^\s()<>"\]]+\.mp4',
    caseSensitive: false,
  );

  /// Ссылка приходит markdown-строкой внутри текстовой части ответа. Chat-контур
  /// оставлен как запасной вариант: он отдаёт то же самое в `choices`.
  static String? _firstVideoUrl(Map<String, dynamic> data) {
    for (final candidate in _asList(data['candidates'])) {
      if (candidate is! Map) continue;
      final content = candidate['content'];
      if (content is! Map) continue;
      for (final part in _asList(content['parts'])) {
        if (part is! Map) continue;
        final text = part['text'];
        if (text is String) {
          final match = _videoUrlPattern.firstMatch(text);
          if (match != null) return match.group(0);
        }
      }
    }

    for (final choice in _asList(data['choices'])) {
      if (choice is! Map) continue;
      final message = choice['message'];
      if (message is! Map) continue;
      final content = message['content'];
      if (content is String) {
        final match = _videoUrlPattern.firstMatch(content);
        if (match != null) return match.group(0);
      }
    }
    return null;
  }

  static String? _extractFinishReason(Map<String, dynamic> data) {
    for (final candidate in _asList(data['candidates'])) {
      if (candidate is Map && candidate['finishReason'] != null) {
        return candidate['finishReason'].toString();
      }
    }
    return null;
  }

  static List<dynamic> _asList(dynamic value) =>
      value is List ? value : const [];

  static bool _isModerationError(String message) {
    final lower = message.toLowerCase();
    return _moderationMarkers.any(lower.contains);
  }

  Future<List<int>?> _resolveToBytes(String url) async {
    final trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      final file = File(trimmed);
      if (await file.exists()) return file.readAsBytes();
      debugPrint('$_tag локальный файл не найден: $trimmed');
      return null;
    }

    final direct = await _download(trimmed);
    if (direct != null) return direct;

    // Ссылки ApiBost могут быть недоступны из РФ напрямую — повторяем попытку
    // через nginx-прокси, как это делает загрузка изображений.
    final proxyBase = AiProxyConfig.imageProxyBaseUrl();
    if (proxyBase == null) return null;
    debugPrint('$_tag повтор загрузки через прокси');
    return _download('$proxyBase?url=${Uri.encodeComponent(trimmed)}');
  }

  Future<List<int>?> _download(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: const {'User-Agent': 'AIVideoMaker/client-apibost'},
          )
          .timeout(_downloadTimeout);
      if (response.statusCode != 200) {
        debugPrint('$_tag ошибка загрузки: HTTP ${response.statusCode}');
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('$_tag ошибка загрузки: $e');
      return null;
    }
  }

  Future<String?> _saveLocally(List<int> bytes, String nameHint) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'apibost_${_sanitize(nameHint)}_'
          '${DateTime.now().millisecondsSinceEpoch}'
          '${GeneratedMedia.videoExtension}';
      final filePath = path.join(directory.path, fileName);
      await File(filePath).writeAsBytes(bytes, flush: true);
      return filePath;
    } catch (e) {
      debugPrint('$_tag ошибка сохранения: $e');
      return null;
    }
  }

  static String? _tryParseErrorMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        final err = j['error'];
        if (err is Map && err['message'] is String) {
          return err['message'] as String;
        }
        if (err is String) return err;
      }
    } catch (_) {}
    return null;
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
}
