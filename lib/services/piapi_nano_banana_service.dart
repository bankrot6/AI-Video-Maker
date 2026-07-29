import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'photosession_generation_router.dart';
import 'piapi_upload_service.dart';

enum PiApiNanaBananaTaskType {
  pro('nano-banana-pro'),
  v2('nano-banana-2');

  const PiApiNanaBananaTaskType(this.value);
  final String value;
}

class PiApiNanaBananaService implements PhotosessionGenerationService {
  PiApiNanaBananaService({
    String? apiKey,
    String? taskUrl,
    Duration? timeout,
    Duration? pollInterval,
    Duration? pollTimeout,
    PiApiNanaBananaTaskType taskType = PiApiNanaBananaTaskType.pro,
  })  : _apiKey = apiKey ?? dotenv.env['PIAPI_API_KEY'],
        _taskUrl = _normalize(
          taskUrl ??
              dotenv.env['PIAPI_TASK_URL'] ??
              dotenv.env['PIAPI_BASE_URL'] ??
              'https://api.piapi.ai/api/v1/task',
        ),
        _timeout = timeout ?? const Duration(seconds: 30),
        _pollInterval = pollInterval ?? const Duration(seconds: 3),
        _pollTimeout = pollTimeout ?? const Duration(minutes: 5),
        _taskType = taskType;

  static String _normalize(String url) {
    final t = url.trim();
    return t.endsWith('/') ? t.substring(0, t.length - 1) : t;
  }

  final String? _apiKey;
  final String _taskUrl;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _pollTimeout;
  final PiApiNanaBananaTaskType _taskType;

  static const _singleImageIdentityLock =
      'IDENTITY PRESERVATION — HIGHEST PRIORITY, NON-NEGOTIABLE:\n'
      'The provided image shows a REAL, SPECIFIC person. '
      'This is NOT a visual style reference — this IS the identity reference. '
      'Reproduce this exact person with 100% photorealistic fidelity.\n'
      'Preserve ALL of the following without ANY deviation:\n'
      '— GENDER: use EXACTLY the gender visible in the image. '
      'If the image shows a MAN — generate a MAN. '
      'If the image shows a WOMAN — generate a WOMAN. '
      'IGNORE any gender words in the scene description below.\n'
      '— FACE: exact face shape, bone structure, jaw line, cheekbones, '
      'eye shape/color/spacing, nose bridge and tip shape, '
      'lip shape and fullness, eyebrow arch/color/thickness, '
      'hairline, forehead width, chin contour, any visible skin marks\n'
      '— HAIR: exact color, length, texture, volume and style\n'
      '— SKIN: exact skin tone and texture across face AND all visible body — '
      'do NOT lighten, do NOT over-smooth, do NOT alter\n'
      '— BODY: exact body type and build — do NOT slim down, do NOT idealize, '
      'do NOT make more athletic or muscular; preserve shoulder width, '
      'torso proportions, waist-to-hip ratio, arm/leg proportions\n'
      '— AGE: preserve exact apparent age — do NOT make younger or older\n'
      'This is NOT a person who looks similar — this IS the EXACT same person. '
      'The face must be unmistakably and consistently the same person from the image.\n\n';

  static const _multiImageRoleLock =
      'MULTI-IMAGE ROLE LOCK — HIGHEST PRIORITY, NON-NEGOTIABLE:\n'
      'image1 is the style/reference image.\n'
      'image2 is the identity image of the REAL, SPECIFIC person who must appear in the result.\n'
      'Never copy identity from image1.\n'
      'Always preserve identity from image2 with maximum fidelity.\n'
      'Preserve ALL of the following from image2 without ANY deviation:\n'
      '— GENDER: use EXACTLY the gender visible in image2. '
      'If image2 shows a MAN — generate a MAN. '
      'If image2 shows a WOMAN — generate a WOMAN. '
      'IGNORE any gender words in the style description below.\n'
      '— FACE: exact face shape, bone structure, jaw line, cheekbones, '
      'eye shape/color/spacing, nose bridge and tip shape, '
      'lip shape and fullness, eyebrow arch/color/thickness, '
      'hairline, forehead width, chin contour, any visible skin marks\n'
      '— HAIR: exact color, length, texture, volume and style as in image2 unless image1 requires '
      'minor styling adjustments that still keep the same person recognizable\n'
      '— SKIN: exact skin tone and texture across face AND all visible body — '
      'do NOT lighten, do NOT over-smooth, do NOT alter\n'
      '— BODY: exact body type and build — do NOT slim down, do NOT idealize, '
      'do NOT make more athletic or muscular; preserve shoulder width, '
      'torso proportions, waist-to-hip ratio, arm/leg proportions\n'
      '— AGE: preserve exact apparent age — do NOT make younger or older\n'
      'This is NOT a person who looks similar — this IS the EXACT same person from image2. '
      'The face must be unmistakably and consistently the same person from image2.\n\n';

  @override
  Future<bool> isAvailable() async {
    final hasKey = (_apiKey ?? '').trim().isNotEmpty;
    final hasUrl = _taskUrl.trim().isNotEmpty;
    debugPrint('🍌 PIAPI_NB: доступность apiKey=$hasKey taskUrl=$hasUrl');
    return hasKey && hasUrl;
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

    final isLocal = !userImageUrl.startsWith('http://') &&
        !userImageUrl.startsWith('https://');

    String uploadedUrl;
    if (isLocal) {
      final file = File(userImageUrl);
      if (!file.existsSync()) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Файл пользователя не найден.',
        );
      }
      debugPrint('🍌 PIAPI_NB: загружаем фото на PiAPI...');
      final uploader = PiApiUploadService();
      final url = await uploader.uploadImage(file);
      if (url == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Не удалось загрузить фото на PiAPI.',
        );
      }
      uploadedUrl = url;
      debugPrint('🍌 PIAPI_NB: фото загружено $uploadedUrl');
    } else {
      uploadedUrl = userImageUrl;
    }

    final imageUrls = <String>[];
    if (referenceImageUrl != null && referenceImageUrl.trim().isNotEmpty) {
      final refUrl = referenceImageUrl.trim();
      if (refUrl.startsWith('http://') || refUrl.startsWith('https://')) {
        imageUrls.add(refUrl);
      } else {
        final refFile = File(refUrl);
        if (refFile.existsSync()) {
          final uploader = PiApiUploadService();
          final url = await uploader.uploadImage(refFile);
          if (url != null) imageUrls.add(url);
        }
      }
    }
    imageUrls.add(uploadedUrl);

    final hasReference = imageUrls.length >= 2;
    final identityLock =
        hasReference ? _multiImageRoleLock : _singleImageIdentityLock;
    final finalReminder = hasReference
        ? 'FINAL REMINDER: image1 defines only style, composition, wardrobe, '
            'lighting and mood. image2 defines the person. '
            'The output person MUST be photorealistic and visually identical '
            'to image2 — same face, same gender, same body. '
        : 'FINAL REMINDER: The provided image defines the person. '
            'The output person MUST be photorealistic and visually identical '
            'to the provided image — same face, same gender, same body. ';
    final prompt = '$identityLock'
        '$scenePrompt\n\n'
        '${finalReminder}'
        'OUTPUT FORMAT: VERTICAL PORTRAIT, aspect ratio 3:4 (taller than wide, '
        'like a phone photo). NEVER generate a horizontal or landscape image. '
        'Any text or inscriptions shown in the image MUST be rendered '
        'in Cyrillic (Russian) exactly as specified — do NOT translate to English.';

    return _runTask(
      prompt: prompt,
      imageUrls: imageUrls,
      aspectRatio: aspectRatio,
      resolution: resolution,
    );
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
    return _runTask(
      prompt: prompt,
      imageUrls: const [],
      aspectRatio: aspectRatio,
      resolution: resolution,
    );
  }

  Future<PhotosessionGenerationResult> _runTask({
    required String prompt,
    required List<String> imageUrls,
    required String aspectRatio,
    required String resolution,
  }) async {
    final payload = <String, dynamic>{
      'model': 'gemini',
      'task_type': _taskType.value,
      'input': {
        'prompt': prompt,
        if (imageUrls.isNotEmpty) 'image_urls': imageUrls,
        'aspect_ratio': aspectRatio,
        'resolution': resolution,
        'output_format': 'jpg',
        if (_taskType == PiApiNanaBananaTaskType.pro) 'safety_level': 'high',
      },
    };

    debugPrint('🍌 PIAPI_NB: создаём задачу task_type=${_taskType.value} resolution=$resolution ar=$aspectRatio images=${imageUrls.length}');
    final createResponse = await _post(_taskUrl, payload);
    if (createResponse == null) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось создать задачу на PiAPI.',
      );
    }

    final taskId = _extractTaskId(createResponse);
    if (taskId == null) {
      final msg = _extractErrorMessage(createResponse);
      return PhotosessionGenerationResult(
        errorMessage: msg ?? 'PiAPI не вернул task_id.',
      );
    }

    debugPrint('🍌 PIAPI_NB: taskId=$taskId — ждём результат...');
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
        debugPrint('🍌 PIAPI_NB: нет ответа при опросе #$attempts');
        continue;
      }

      final status = _extractStatus(response);
      debugPrint('🍌 PIAPI_NB: опрос #$attempts status=$status');

      final statusLower = status?.toLowerCase();

      if (statusLower == 'completed') {
        final url = _extractImageUrl(response);
        if (url != null && url.isNotEmpty) {
          debugPrint('🍌 PIAPI_NB: готово! url=$url');
          return PhotosessionGenerationResult(imageUrl: url);
        }
        return const PhotosessionGenerationResult(
          errorMessage: 'Задача завершена, но URL изображения не найден.',
        );
      }

      if (statusLower == 'failed') {
        final msg = _extractErrorMessage(response);
        debugPrint('🍌 PIAPI_NB: задача провалилась: $msg');
        return PhotosessionGenerationResult(
          errorMessage: msg ?? 'Задача PiAPI завершилась с ошибкой.',
        );
      }
    }

    return const PhotosessionGenerationResult(
      errorMessage: 'Превышено время ожидания PiAPI (5 минут).',
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
      debugPrint('🍌 PIAPI_NB: POST → ${response.statusCode}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('🍌 PIAPI_NB: тело ошибки: ${response.body}');
        return null;
      }
      return _decode(response.body);
    } catch (e) {
      debugPrint('🍌 PIAPI_NB: ошибка POST: $e');
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
      debugPrint('🍌 PIAPI_NB: ошибка GET: $e');
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

    final logs = src['logs'];
    if (logs is List) {
      final allLogs = logs.whereType<String>().join(' ').toLowerCase();
      if (allLogs.contains('high demand') ||
          allLogs.contains('unavailable') ||
          allLogs.contains('overloaded')) {
        return 'Модель сейчас перегружена — попробуйте позже или выберите другую модель.';
      }
    }

    final error = src['error'];
    if (error is Map<String, dynamic>) {
      final msg = error['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }

    if (logs is List && logs.isNotEmpty) {
      final first = logs.first;
      if (first is String && first.isNotEmpty) return first;
    }

    final msg = json['message'];
    if (msg is String && msg.isNotEmpty && msg != 'success') return msg;
    return null;
  }
}
