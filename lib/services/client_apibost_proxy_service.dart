import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../config/ai_proxy_config.dart';
import 'apibost_model_relay.dart';
import 'apibost_prompt_builder.dart';
import 'photosession_generation_router.dart';

/// Клиентская генерация через ApiBost напрямую по relay-цепочке Yandex → NL,
/// минуя серверную функцию `apibost-proxy`.
///
/// Кредиты при этом резервируются клиентом через `verify-trial`
/// (см. [CreditService.reserveCredits] / [BackgroundGenerationNotifier]),
/// поэтому сам сервис баланс не трогает — он только генерирует изображение
/// и сохраняет его локально (как и серверный сервис, чтобы дальнейшая логика
/// сохранения в истории/Storage в провайдере оставалась неизменной для
/// старых и новых пользователей).
class ClientApiBostProxyService
    implements PhotosessionGenerationService, ReferenceImageGenerationService {
  ClientApiBostProxyService({
    String model = 'gemini-2.5-flash-image',
    double temperature = 0.7,
    Duration? timeout,
    Duration? downloadTimeout,
  })  : _model = model,
        _temperature = temperature,
        _timeout = timeout ?? const Duration(minutes: 7),
        _downloadTimeout = downloadTimeout ?? const Duration(seconds: 45);

  static const _tag = '🟣 CLIENT_APIBOST';

  /// finishReason, при которых контент заблокирован модерацией. Кредиты в этом
  /// случае НЕ возвращаются (запрос к ApiBost выполнен и оплачен) — это
  /// повторяет анти-абьюз логику серверной функции apibost-proxy.
  static const Set<String> blockedFinishReasons = {
    'PROHIBITED_CONTENT',
    'IMAGE_PROHIBITED_CONTENT',
    'BLOCKED_REASON_UNSPECIFIED',
  };

  final String _model;
  final double _temperature;
  final Duration _timeout;
  final Duration _downloadTimeout;

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

    try {
      // Порядок изображений: референс сцены первым (inlineData[0]), затем фото
      // пользователя — идентично серверной функции apibost-proxy.
      final imageBuffers = <List<int>>[];

      if (referenceImageUrl != null && referenceImageUrl.trim().isNotEmpty) {
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

      final enhancedPrompt = ApiBostPromptBuilder.buildFacePrompt(
        scenePrompt: scenePrompt,
        aspectRatio: aspectRatio,
        temperature: _temperature,
        hasReference: referenceImageUrl != null &&
            referenceImageUrl.trim().isNotEmpty,
      );

      debugPrint('$_tag generateWithFace model=$_model '
          'images=${imageBuffers.length}');

      return _generate(
        prompt: enhancedPrompt,
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

    try {
      final referenceBytes = await _resolveToBytes(referenceImageUrl);
      if (referenceBytes == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Не найдено референсное изображение',
        );
      }

      debugPrint('$_tag generateFromReference model=$_model');

      return _generate(
        prompt: ApiBostPromptBuilder.buildReferencePrompt(
          prompt: prompt,
          aspectRatio: aspectRatio,
          temperature: _temperature,
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
      final enrichedPrompt = ApiBostPromptBuilder.buildImagePrompt(
        prompt: prompt,
        aspectRatio: aspectRatio,
        temperature: _temperature,
      );

      debugPrint('$_tag generateImage model=$_model');

      return _generate(
        prompt: enrichedPrompt,
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

    // Аспект-рейтио дублируется в начале промпта как [3:4] — поведение
    // идентично серверной функции (fullPrompt = `[${aspectRatio}] ${prompt}`).
    final fullPrompt =
        '[${ApiBostPromptBuilder.formatAspectRatio(aspectRatio)}] $prompt';

    final call = await _callApiBost(fullPrompt, imageBuffers);

    final base64Image = _extractBase64FromResponse(call.data);
    if (base64Image == null) {
      final finishReason = _extractFinishReason(call.data);
      debugPrint(
        '$_tag нет изображения, finishReason=$finishReason '
        'фактическая модель=${call.actualModel}',
      );
      if (finishReason != null && blockedFinishReasons.contains(finishReason)) {
        return const PhotosessionGenerationResult(
          errorMessage:
              'Контент заблокирован политикой безопасности. Попробуйте другое фото.',
        );
      }
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось получить изображение из ответа',
      );
    }

    final resultBytes = base64Decode(base64Image);
    final localPath = await _saveLocally(resultBytes, saveNameHint);
    if (localPath == null) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось сохранить изображение',
      );
    }
    debugPrint(
      '$_tag фактическая модель=${call.actualModel} '
      '(запрошена=${call.requestedModel})',
    );
    debugPrint('$_tag готово: $localPath');
    return PhotosessionGenerationResult(imageUrl: localPath);
  }

  Future<ApiBostGenerateResult> _callApiBost(
    String prompt,
    List<List<int>> imageBuffers,
  ) async {
    try {
      return await _postGenerateContent(
        requestedModel: _model,
        prompt: prompt,
        imageBuffers: imageBuffers,
      );
    } on ApiBostHttpException catch (e) {
      if (!ApiBostModelRelay.shouldFallbackTo25(
        model: _model,
        httpStatus: e.statusCode,
        errorMessage: e.message,
      )) {
        rethrow;
      }
      debugPrint(
        '$_tag relay 3.1→2.5: HTTP ${e.statusCode} ${e.message}',
      );
      return _postGenerateContent(
        requestedModel: _model,
        prompt: prompt,
        imageBuffers: imageBuffers,
        forceModel: ApiBostModelRelay.flash25Model,
      );
    }
  }

  Future<ApiBostGenerateResult> _postGenerateContent({
    required String requestedModel,
    required String prompt,
    required List<List<int>> imageBuffers,
    String? forceModel,
  }) async {
    final model = forceModel ?? requestedModel;
    final base = AiProxyConfig.apiBostBaseUrl();
    if (base == null) {
      throw StateError('ApiBost relay URL is not configured');
    }
    final url = '$base/v1beta/models/$model:generateContent';
    debugPrint('$_tag POST model=$model');

    // Текст ПЕРЕД изображениями — как в серверной функции и документации
    // ApiBost. При обратном порядке модель возвращает входное фото без правок.
    final parts = <Map<String, dynamic>>[
      {'text': prompt},
    ];
    for (final buf in imageBuffers) {
      parts.add({
        'inlineData': {
          'mimeType': 'image/jpeg',
          'data': base64Encode(buf),
        },
      });
    }

    final payload = {
      'contents': [
        {'role': 'user', 'parts': parts},
      ],
      'generationConfig': {
        'responseModalities':
            ApiBostPromptBuilder.responseModalitiesFor(model),
      },
    };

    // Authorization (Bearer API_BOST_API_KEY) инжектит nginx на NL-сервере в
    // локейшене /apibost/, поэтому клиент ключ ApiBost не передаёт.
    final response = await http
        .post(
          Uri.parse(url),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = _tryParseErrorMessage(response.body) ??
          'ApiBost HTTP ${response.statusCode}';
      debugPrint(
        '$_tag ошибка model=$model HTTP ${response.statusCode}: $message',
      );
      throw ApiBostHttpException(response.statusCode, message);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final data = decoded is Map<String, dynamic>
        ? decoded
        : decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
    final actualModel = ApiBostModelRelay.resolveActualModel(
      requestedModel: model,
      responseHeaders: response.headers,
    );
    if (actualModel != model) {
      debugPrint(
        '$_tag relay сообщил фактическую модель=$actualModel (POST model=$model)',
      );
    }
    return ApiBostGenerateResult(
      data: data,
      actualModel: actualModel,
      requestedModel: requestedModel,
    );
  }

  Future<List<int>?> _resolveToBytes(String url) async {
    final trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      final file = File(trimmed);
      if (await file.exists()) return file.readAsBytes();
      debugPrint('$_tag локальный файл не найден: $trimmed');
      return null;
    }
    try {
      final response = await http
          .get(
            Uri.parse(trimmed),
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
      final sanitized = _sanitize(nameHint);
      final fileName =
          'apibost_${sanitized}_${DateTime.now().millisecondsSinceEpoch}.jpg';
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

  static String? _extractBase64FromResponse(dynamic data) {
    if (data is! Map) return null;
    final candidates = data['candidates'];
    if (candidates is! List) return null;
    for (final candidate in candidates) {
      if (candidate is! Map) continue;
      final content = candidate['content'];
      if (content is! Map) continue;
      final parts = content['parts'];
      if (parts is! List) continue;
      for (final part in parts) {
        if (part is! Map) continue;
        final inline = part['inlineData'] ?? part['inline_data'];
        if (inline is Map) {
          final value = inline['data'];
          if (value is String && value.isNotEmpty) return value;
        }
      }
    }
    return null;
  }

  static String? _extractFinishReason(dynamic data) {
    if (data is! Map) return null;
    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final first = candidates.first;
      if (first is Map) return first['finishReason']?.toString();
    }
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
