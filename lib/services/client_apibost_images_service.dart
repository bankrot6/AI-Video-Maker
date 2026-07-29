import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../config/ai_proxy_config.dart';
import 'apibost_model_catalog.dart';
import 'apibost_model_relay.dart';
import 'apibost_prompt_builder.dart';
import 'photosession_generation_router.dart';

/// Генерация через OpenAI-совместимый контур ApiBost (`/v1/images/*`).
///
/// Отвечает за модели, которые не понимают Gemini-формат
/// `:generateContent` — gpt-image-1.5, gpt-image-2, grok-3-image.
/// Кредиты, как и в [ClientApiBostProxyService], резервирует вызывающий код.
class ClientApiBostImagesService
    implements PhotosessionGenerationService, ReferenceImageGenerationService {
  ClientApiBostImagesService({
    required String model,
    double temperature = 0.7,
    Duration? timeout,
    Duration? downloadTimeout,
  })  : _model = model,
        _temperature = temperature,
        _timeout = timeout ?? const Duration(minutes: 7),
        _downloadTimeout = downloadTimeout ?? const Duration(seconds: 45);

  static const _tag = '🟠 CLIENT_APIBOST_IMAGES';

  /// Причины отказа модерации OpenAI-контура. Кредиты в этом случае не
  /// возвращаются — запрос к ApiBost выполнен и оплачен.
  static const Set<String> _moderationMarkers = {
    'content_policy_violation',
    'moderation_blocked',
    'safety',
  };

  final String _model;
  final double _temperature;
  final Duration _timeout;
  final Duration _downloadTimeout;

  bool get _acceptsImageInput => ApiBostModelCatalog.supportsImageInput(_model);

  /// `/v1/images/*` принимает пропорции полем `size`, а chat-контур — нет,
  /// поэтому для него аспект-рейтио остаётся в тексте промпта.
  bool get _includePromptParams =>
      ApiBostModelCatalog.transportFor(_model) ==
      ApiBostTransport.openAiChatCompletions;

  @override
  Future<bool> isAvailable() async {
    final ok = AiProxyConfig.apiBostBaseUrl() != null;
    debugPrint('$_tag isAvailable=$ok model=$_model');
    return ok;
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
        errorMessage: 'ApiBost relay не настроен',
      );
    }
    if (!_acceptsImageInput) {
      return PhotosessionGenerationResult(
        errorMessage: 'Модель $_model не умеет работать с фото. '
            'Выберите другую модель для генерации с вашим лицом.',
      );
    }

    try {
      final hasReference =
          referenceImageUrl != null && referenceImageUrl.trim().isNotEmpty;
      final imageBuffers = <List<int>>[];

      if (hasReference) {
        final refBytes = await _resolveToBytes(referenceImageUrl);
        if (refBytes == null) {
          return const PhotosessionGenerationResult(
            errorMessage: 'Не найдено референсное изображение',
          );
        }
        imageBuffers.add(refBytes);
      }

      final userBytes = await _resolveToBytes(userImageUrl);
      if (userBytes == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Файл пользователя не найден',
        );
      }
      imageBuffers.add(userBytes);

      return _generate(
        prompt: ApiBostPromptBuilder.buildFacePrompt(
          scenePrompt: scenePrompt,
          aspectRatio: aspectRatio,
          temperature: _temperature,
          hasReference: hasReference,
          includeParams: _includePromptParams,
        ),
        aspectRatio: aspectRatio,
        imageBuffers: imageBuffers,
        saveNameHint: scenePrompt,
      );
    } catch (e, st) {
      debugPrint('$_tag ошибка generateWithFace: $e');
      debugPrint('$_tag стек: $st');
      return PhotosessionGenerationResult(errorMessage: 'Ошибка: $e');
    }
  }

  @override
  Future<PhotosessionGenerationResult> generateFromReference({
    required String referenceImageUrl,
    required String prompt,
    String resolution = '2K',
    String aspectRatio = '3:4',
  }) async {
    if (!await isAvailable()) {
      return const PhotosessionGenerationResult(
        errorMessage: 'ApiBost relay не настроен',
      );
    }
    if (!_acceptsImageInput) {
      return PhotosessionGenerationResult(
        errorMessage: 'Модель $_model не умеет работать с референсным фото.',
      );
    }

    try {
      final referenceBytes = await _resolveToBytes(referenceImageUrl);
      if (referenceBytes == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Не найдено референсное изображение',
        );
      }

      return _generate(
        prompt: ApiBostPromptBuilder.buildReferencePrompt(
          prompt: prompt,
          aspectRatio: aspectRatio,
          temperature: _temperature,
          includeParams: _includePromptParams,
        ),
        aspectRatio: aspectRatio,
        imageBuffers: [referenceBytes],
        saveNameHint: prompt,
      );
    } catch (e, st) {
      debugPrint('$_tag ошибка generateFromReference: $e');
      debugPrint('$_tag стек: $st');
      return PhotosessionGenerationResult(errorMessage: 'Ошибка: $e');
    }
  }

  @override
  Future<PhotosessionGenerationResult> generateImage({
    required String prompt,
    String resolution = '2K',
    String aspectRatio = '3:4',
  }) async {
    if (!await isAvailable()) {
      return const PhotosessionGenerationResult(
        errorMessage: 'ApiBost relay не настроен',
      );
    }

    try {
      return _generate(
        prompt: ApiBostPromptBuilder.buildImagePrompt(
          prompt: prompt,
          aspectRatio: aspectRatio,
          temperature: _temperature,
          includeParams: _includePromptParams,
        ),
        aspectRatio: aspectRatio,
        imageBuffers: const [],
        saveNameHint: prompt,
      );
    } catch (e, st) {
      debugPrint('$_tag ошибка generateImage: $e');
      debugPrint('$_tag стек: $st');
      return PhotosessionGenerationResult(errorMessage: 'Ошибка: $e');
    }
  }

  Future<PhotosessionGenerationResult> _generate({
    required String prompt,
    required String aspectRatio,
    required List<List<int>> imageBuffers,
    required String saveNameHint,
  }) async {
    if (saveNameHint.trim().isEmpty) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Пустой промт: опишите сцену для генерации',
      );
    }

    final size = ApiBostModelCatalog.sizeForAspectRatio(aspectRatio);
    final transport = ApiBostModelCatalog.transportFor(_model);
    debugPrint('$_tag POST model=$_model images=${imageBuffers.length} '
        'size=$size transport=${transport.name}');

    final Map<String, dynamic> data;
    try {
      data = switch (transport) {
        ApiBostTransport.openAiChatCompletions =>
          await _postChatCompletions(prompt: prompt),
        _ when imageBuffers.isEmpty =>
          await _postGenerations(prompt: prompt, size: size),
        _ => await _postEdits(
            prompt: prompt,
            size: size,
            imageBuffers: imageBuffers,
          ),
      };
    } on ApiBostHttpException catch (e) {
      debugPrint('$_tag ошибка model=$_model HTTP ${e.statusCode}: ${e.message}');
      if (_isModerationError(e.message)) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Контент заблокирован политикой безопасности. '
              'Попробуйте другое фото или описание.',
        );
      }
      return PhotosessionGenerationResult(errorMessage: e.message);
    }

    final bytes = await _extractImageBytes(data);
    if (bytes == null) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось получить изображение из ответа',
      );
    }

    final localPath = await _saveLocally(bytes, saveNameHint);
    if (localPath == null) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось сохранить изображение',
      );
    }
    debugPrint('$_tag готово: $localPath');
    return PhotosessionGenerationResult(imageUrl: localPath);
  }

  Future<Map<String, dynamic>> _postGenerations({
    required String prompt,
    required String size,
  }) async {
    final response = await http
        .post(
          Uri.parse('${_baseUrl()}/v1/images/generations'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': _model,
            'prompt': prompt,
            'size': size,
            'n': 1,
          }),
        )
        .timeout(_timeout);
    return _decode(response.statusCode, response.bodyBytes);
  }

  Future<Map<String, dynamic>> _postChatCompletions({
    required String prompt,
  }) async {
    final response = await http
        .post(
          Uri.parse('${_baseUrl()}/v1/chat/completions'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': _model,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
            'temperature': _temperature,
          }),
        )
        .timeout(_timeout);
    return _decode(response.statusCode, response.bodyBytes);
  }

  Future<Map<String, dynamic>> _postEdits({
    required String prompt,
    required String size,
    required List<List<int>> imageBuffers,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${_baseUrl()}/v1/images/edits'),
    )
      ..fields['model'] = _model
      ..fields['prompt'] = prompt
      ..fields['size'] = size
      ..fields['n'] = '1';

    for (var i = 0; i < imageBuffers.length; i++) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'image[]',
          imageBuffers[i],
          filename: 'image_$i.jpg',
        ),
      );
    }

    final streamed = await request.send().timeout(_timeout);
    final response = await http.Response.fromStream(streamed);
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

  /// `/v1/images/*` отдаёт результат в `data[]` (обычно ссылкой, реже
  /// `b64_json`), а `/v1/chat/completions` — markdown-ссылкой в тексте ответа.
  Future<List<int>?> _extractImageBytes(Map<String, dynamic> data) async {
    final items = data['data'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final b64 = item['b64_json'];
        if (b64 is String && b64.isNotEmpty) return base64Decode(b64);
        final url = item['url'];
        if (url is String && url.isNotEmpty) {
          final bytes = await _resolveToBytes(url);
          if (bytes != null) return bytes;
        }
      }
    }

    final url = _firstImageUrlInChatResponse(data);
    if (url != null) return _resolveToBytes(url);
    return null;
  }

  static final RegExp _imageUrlPattern = RegExp(
    r'https?://[^\s()<>"\]]+',
    caseSensitive: false,
  );

  static String? _firstImageUrlInChatResponse(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List) return null;
    for (final choice in choices) {
      if (choice is! Map) continue;
      final message = choice['message'];
      if (message is! Map) continue;

      final images = message['images'];
      if (images is List) {
        for (final image in images) {
          if (image is Map) {
            final url = image['image_url'];
            if (url is Map && url['url'] is String) return url['url'] as String;
            if (url is String && url.isNotEmpty) return url;
          }
        }
      }

      final content = message['content'];
      if (content is String) {
        final match = _imageUrlPattern.firstMatch(content);
        if (match != null) return match.group(0);
      }
    }
    return null;
  }

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

    // ApiBost отдаёт результат ссылкой на сторонний CDN, доступность которого
    // из РФ не гарантирована, — повторяем попытку через nginx image-прокси.
    final proxyBase = AiProxyConfig.imageProxyBaseUrl();
    if (proxyBase == null) return null;
    debugPrint('$_tag повтор загрузки через image-прокси');
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
        debugPrint('$_tag ошибка загрузки изображения: HTTP '
            '${response.statusCode}');
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      debugPrint('$_tag ошибка загрузки изображения: $e');
      return null;
    }
  }

  Future<String?> _saveLocally(List<int> bytes, String nameHint) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'apibost_${_sanitize(nameHint)}_'
          '${DateTime.now().millisecondsSinceEpoch}.jpg';
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
    if (normalized.isEmpty) return 'image';
    return normalized.length > 32 ? normalized.substring(0, 32) : normalized;
  }
}
