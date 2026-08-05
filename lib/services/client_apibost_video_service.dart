import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../config/ai_proxy_config.dart';
import 'apibost_model_catalog.dart';
import 'apibost_model_relay.dart';
import 'apibost_video_task_client.dart';
import 'generated_media.dart';
import 'photosession_generation_router.dart';
import 'prompt_length_guard.dart';

/// Генерация видео через ApiBost.
///
/// Генерация по тексту идёт асинхронным `/v1/videos`: задача ставится коротким
/// запросом, дальше опрашивается статус. Раньше единственным путём был
/// `/v1/chat/completions`, где ответа приходилось ждать минуты в одном
/// соединении, и мобильные операторы рвали его — видео рендерилось и
/// списывалось, но до пользователя не доходило.
///
/// Генерация по фото пользователя остаётся на chat-контуре: асинхронный
/// эндпоинт входные кадры молча игнорирует и отдаёт видео по одному промпту.
/// Chat-контур же служит и резервом для текста, а Gemini-контур
/// `:generateContent` — последним резервом: на Veo-моделях он отвечал 524, потому
/// что рендер не успевал за сотню секунд. Потоковый режим использовать нельзя:
/// для Veo ApiBost отдаёт пустой SSE без результата.
///
/// Формат на асинхронном контуре задаётся полем `size`, а на chat-контуре —
/// директивами в тексте промпта (`[9:16]` для пропорций, `[8s]` для
/// длительности): каждый эндпоинт понимает только свой способ, что проверено
/// замером метаданных готовых файлов. Пропорции модель принимает лишь 16:9 и
/// 9:16, на остальные отвечает `400 Invalid aspect ratio`.
///
/// Входные кадры асинхронный контур принимает только публичными ссылками, без
/// base64, поэтому локальные фото сначала выкладываются во временное хранилище.
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
    Duration? pollInterval,
    void Function(String providerTaskId)? onTaskCreated,
  })  : _model = model,
        _durationSeconds = durationSeconds,
        _timeout = timeout ?? const Duration(minutes: 10),
        _downloadTimeout = downloadTimeout ?? const Duration(minutes: 3),
        _pollInterval = pollInterval ?? const Duration(seconds: 4),
        _onTaskCreated = onTaskCreated;

  static const _tag = '🎬 CLIENT_APIBOST_VIDEO';

  /// `rai_policy_violation` — отказ фильтра Responsible AI у Veo: приходит с
  /// кодом 500, хотя запрос технически корректен.
  static const Set<String> _moderationMarkers = {
    'content_policy_violation',
    'moderation_blocked',
    'prohibited_content',
    'rai_policy_violation',
    'rai policy',
    'safety',
  };

  static const String _moderationMessage =
      'Модель отклонила промпт по правилам безопасности. Обычно мешают '
      'реальные люди и знаменитости, насилие, откровенные сцены и бренды — '
      'перепишите эти места и попробуйте снова.';

  static const Set<String> _blockedFinishReasons = {
    'PROHIBITED_CONTENT',
    'IMAGE_PROHIBITED_CONTENT',
    'BLOCKED_REASON_UNSPECIFIED',
  };

  /// Ответы шлюзов (Cloudflare перед ApiBost, nginx, релей) о том, что рендер
  /// не уложился в отведённое им время. К содержимому промпта не относятся.
  static const Set<int> _gatewayTimeoutStatuses = {502, 503, 504, 522, 524};

  static const String _timeoutMessage =
      'Сервис генерации не успел отдать видео и оборвал соединение. '
      'Попробуйте ещё раз через пару минут или упростите описание: '
      'одна сцена, одно действие, без длинных перечислений.';

  static const String _rateLimitMessage =
      'Модель сейчас перегружена запросами. Подождите минуту и повторите.';

  static const String _tooLongMessage =
      'Описание слишком длинное для модели. Сократите его примерно до '
      '${ApiBostModelCatalog.maxVideoPromptTextLength} символов.';

  /// Модель не принимает chat-контур — есть смысл повторить через Gemini-путь.
  static const Set<int> _chatUnsupportedStatuses = {400, 404, 405, 501};

  static const String _downloadFailedMessage =
      'Видео готово, но его не удалось скачать: связь с сервисом оборвалась. '
      'Кредиты вернулись на баланс — повторите попытку.';

  /// Обрыв соединения на мобильной сети — норма, поэтому каждая ссылка
  /// получает несколько попыток, прежде чем оплаченный результат будет потерян.
  static const int _downloadAttempts = 3;

  /// Прокси иногда отвечает 200 с текстом ошибки вместо файла — короткое тело
  /// надёжнее отбраковывать здесь, чем ловить потом на плеере.
  static const int _minVideoBytes = 16 * 1024;

  final String _model;
  final int _durationSeconds;
  final Duration _timeout;
  final Duration _downloadTimeout;
  final Duration _pollInterval;
  final void Function(String providerTaskId)? _onTaskCreated;

  /// Копия сервиса, привязанная к одной генерации.
  ///
  /// Экземпляр из Riverpod-провайдера общий для всех задач одной модели, а
  /// генерации идут параллельно — общий колбэк смешал бы их идентификаторы.
  ClientApiBostVideoService withTaskListener(
    void Function(String providerTaskId) onTaskCreated,
  ) =>
      ClientApiBostVideoService(
        model: _model,
        durationSeconds: _durationSeconds,
        timeout: _timeout,
        downloadTimeout: _downloadTimeout,
        pollInterval: _pollInterval,
        onTaskCreated: onTaskCreated,
      );

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
        imageSources: const [],
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
      final sources = <String>[];
      final hasReference =
          referenceImageUrl != null && referenceImageUrl.trim().isNotEmpty;
      if (hasReference) sources.add(referenceImageUrl.trim());
      sources.add(userImageUrl.trim());

      return _generate(
        prompt: scenePrompt,
        aspectRatio: aspectRatio,
        imageSources: sources,
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
      return _generate(
        prompt: prompt,
        aspectRatio: aspectRatio,
        imageSources: [referenceImageUrl.trim()],
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
    } on TimeoutException catch (e) {
      debugPrint('$_tag таймаут $operation: $e');
      return const PhotosessionGenerationResult(errorMessage: _timeoutMessage);
    } catch (e, st) {
      debugPrint('$_tag ошибка $operation: $e');
      debugPrint('$_tag стек: $st');
      return const PhotosessionGenerationResult(
        errorMessage: 'Не удалось сгенерировать видео. '
            'Попробуйте изменить описание или повторить попытку позже.',
      );
    }
  }

  /// Директивы формата, уже проставленные генератором пресетов. Повторный
  /// префикс съедал бы лимит и дублировал инструкции, поэтому старый снимается.
  static final RegExp _leadingDirectives = RegExp(
    r'^(?:\s*\[\s*(?:\d+\s*:\s*\d+|\d+\s*s)\s*\])+\s*',
    caseSensitive: false,
  );

  String _directives(String ratio) {
    final duration = _durationSeconds.clamp(
      1,
      ApiBostModelCatalog.maxVideoDurationSeconds,
    );
    return '[$ratio] [${duration}s] ';
  }

  /// Текст сцены без служебных директив: их принимает только chat-контур, а
  /// асинхронный задаёт формат полем `size`.
  ///
  /// Лимит считается по самому длинному варианту — с директивами, — чтобы один
  /// и тот же промпт уходил в модель одинаково на обоих контурах.
  String _promptBody(String prompt, String ratio) {
    // Последний рубеж: длину держат генератор промпта и правка под фильтр
    // безопасности, здесь остаётся защита от текста, пришедшего мимо них.
    return PromptLengthGuard.trimToBoundary(
      prompt.trim().replaceFirst(_leadingDirectives, ''),
      ApiBostModelCatalog.maxVideoPromptLength - _directives(ratio).length,
      tag: _tag,
    );
  }

  Future<PhotosessionGenerationResult> _generate({
    required String prompt,
    required String aspectRatio,
    required List<String> imageSources,
  }) async {
    if (prompt.trim().isEmpty) {
      return const PhotosessionGenerationResult(
        errorMessage: 'Пустой промт: опишите сцену для генерации видео',
      );
    }

    final ratio = ApiBostModelCatalog.videoAspectRatioFor(aspectRatio);
    final body = _promptBody(prompt, ratio);
    debugPrint('$_tag генерация model=$_model images=${imageSources.length} '
        'aspectRatio=$ratio');

    final _VideoResponse response;
    try {
      final viaTask = await _generateViaTask(
        body: body,
        ratio: ratio,
        imageSources: imageSources,
        nameHint: prompt,
      );
      if (viaTask != null) return viaTask;

      final buffers = await _resolveBuffers(imageSources);
      if (buffers == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Не найдено изображение для генерации',
        );
      }
      response = await _requestVideo('${_directives(ratio)}$body', buffers);
    } on ApiBostHttpException catch (e) {
      debugPrint('$_tag ошибка model=$_model HTTP ${e.statusCode}: ${e.message}');
      return PhotosessionGenerationResult(errorMessage: _userMessageFor(e));
    } on TimeoutException {
      debugPrint('$_tag таймаут ожидания ответа model=$_model');
      return const PhotosessionGenerationResult(errorMessage: _timeoutMessage);
    } on SocketException catch (e) {
      debugPrint('$_tag сеть недоступна: $e');
      return const PhotosessionGenerationResult(
        errorMessage: 'Нет связи с сервисом генерации. '
            'Проверьте интернет и повторите попытку.',
      );
    }

    final videoUrl = response.videoUrl;
    if (videoUrl == null) {
      debugPrint('$_tag нет ссылки на видео, '
          'finishReason=${response.finishReason}');
      if (response.isBlocked) {
        return const PhotosessionGenerationResult(
          errorMessage: _moderationMessage,
        );
      }
      return const PhotosessionGenerationResult(
        errorMessage: 'Модель не вернула видео по этому описанию. '
            'Попробуйте описать сцену конкретнее: кто в кадре, '
            'что происходит и как движется камера.',
      );
    }

    final localPath = await _downloadVideo(videoUrl, prompt);
    if (localPath == null) {
      return const PhotosessionGenerationResult(
        errorMessage: _downloadFailedMessage,
      );
    }
    debugPrint('$_tag готово: $localPath');
    return PhotosessionGenerationResult(imageUrl: localPath);
  }

  /// Забирает результат задачи, поставленной в прошлом запуске приложения.
  ///
  /// Видео уже оплачено, поэтому попытка его получить всегда предпочтительнее
  /// возврата кредитов. Ссылки у ApiBost живут около двух часов: после этого
  /// задача отвечает ошибкой, и вызывающий код возвращает кредиты.
  Future<PhotosessionGenerationResult> resumeTask(
    String providerTaskId, {
    String nameHint = 'video',
  }) async {
    return _guarded('resumeTask', () async {
      final client = ApiBostVideoTaskClient(baseUrl: _baseUrl());
      final state = await client.fetchTask(providerTaskId);
      if (state.status == ApiBostVideoTaskStatus.failed) {
        return PhotosessionGenerationResult(
          errorMessage: state.error ?? 'Задача завершилась ошибкой',
        );
      }
      if (!state.isTerminal) {
        // Рендер ещё идёт: дожидаемся его, ожидание здесь короче полного цикла.
        final finished = await _awaitTask(client, providerTaskId);
        if (finished.status == ApiBostVideoTaskStatus.failed) {
          return PhotosessionGenerationResult(
            errorMessage: finished.error ?? 'Задача завершилась ошибкой',
          );
        }
      }

      final localPath = await _downloadVideo(
        client.contentUrl(providerTaskId),
        nameHint,
        allowProxyFallback: false,
      );
      if (localPath == null) {
        return const PhotosessionGenerationResult(
          errorMessage: _downloadFailedMessage,
        );
      }
      debugPrint('$_tag догружено (задача $providerTaskId): $localPath');
      return PhotosessionGenerationResult(imageUrl: localPath);
    });
  }

  /// Асинхронный контур: короткий POST ставит задачу, дальше опрос статуса.
  ///
  /// Так рендер не держит одно HTTP-соединение несколько минут — именно на
  /// таком ожидании мобильные операторы рвали соединение, и оплаченное видео
  /// не доходило до пользователя.
  ///
  /// Возвращает `null`, когда контур неприменим: генерация идёт по входному
  /// кадру (эндпоинт молча игнорирует переданные картинки и рендерит видео по
  /// одному тексту) либо шлюз не принял сам запрос. Тогда вызывающий код уходит
  /// на chat-контур с картинками в data-URI.
  Future<PhotosessionGenerationResult?> _generateViaTask({
    required String body,
    required String ratio,
    required List<String> imageSources,
    required String nameHint,
  }) async {
    if (imageSources.isNotEmpty) return null;

    final client = ApiBostVideoTaskClient(baseUrl: _baseUrl());
    final String taskId;
    try {
      taskId = await client.createTask(
        model: _model,
        prompt: body,
        size: ApiBostModelCatalog.videoSizeFor(ratio),
      );
    } on ApiBostHttpException catch (e) {
      if (_isModerationError(e.message)) rethrow;
      if (!_chatUnsupportedStatuses.contains(e.statusCode)) rethrow;
      debugPrint('$_tag асинхронный контур недоступен (HTTP ${e.statusCode}), '
          'уходим на chat-контур');
      return null;
    }
    // Идентификатор нужен до конца рендера: если процесс умрёт, за оплаченным
    // видео можно вернуться при следующем запуске.
    _onTaskCreated?.call(taskId);

    final state = await _awaitTask(client, taskId);
    if (state.status == ApiBostVideoTaskStatus.failed) {
      // Текст ошибки задачи разбирает тот же классификатор, что и ответы
      // шлюза: модерация и лимиты приходят здесь такими же формулировками.
      throw ApiBostHttpException(502, state.error ?? 'Задача завершилась ошибкой');
    }

    final localPath = await _downloadVideo(
      client.contentUrl(taskId),
      nameHint,
      allowProxyFallback: false,
    );
    if (localPath == null) {
      return const PhotosessionGenerationResult(
        errorMessage: _downloadFailedMessage,
      );
    }
    debugPrint('$_tag готово (задача $taskId): $localPath');
    return PhotosessionGenerationResult(imageUrl: localPath);
  }

  /// Опрашивает задачу до терминального состояния. Одиночные сбои опроса не
  /// считаются провалом генерации: видео уже рендерится и оплачено, поэтому
  /// разрыв сети между опросами лишь переносит следующую попытку.
  Future<ApiBostVideoTaskState> _awaitTask(
    ApiBostVideoTaskClient client,
    String taskId,
  ) async {
    final deadline = DateTime.now().add(_timeout);
    var lastProgress = -1;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_pollInterval);
      final ApiBostVideoTaskState state;
      try {
        state = await client.fetchTask(taskId);
      } on ApiBostHttpException catch (e) {
        if (!_gatewayTimeoutStatuses.contains(e.statusCode)) rethrow;
        debugPrint('$_tag опрос задачи $taskId: HTTP ${e.statusCode}, повтор');
        continue;
      } on TimeoutException {
        debugPrint('$_tag опрос задачи $taskId: таймаут, повтор');
        continue;
      } on SocketException catch (e) {
        debugPrint('$_tag опрос задачи $taskId: сеть недоступна ($e), повтор');
        continue;
      }
      if (state.progress != lastProgress) {
        lastProgress = state.progress;
        debugPrint('$_tag задача $taskId: ${state.status.name} '
            '${state.progress}%');
      }
      if (state.isTerminal) return state;
    }
    throw TimeoutException('Задача $taskId не завершилась за $_timeout');
  }

  /// Байты входных кадров для chat-контура. `null` — какой-то кадр недоступен.
  Future<List<List<int>>?> _resolveBuffers(List<String> sources) async {
    final buffers = <List<int>>[];
    for (final source in sources) {
      final bytes = await _resolveToBytes(source);
      if (bytes == null) {
        debugPrint('$_tag не удалось прочитать кадр: $source');
        return null;
      }
      buffers.add(bytes);
    }
    return buffers;
  }

  /// Chat-контур — резервный путь, `:generateContent` подключается только когда
  /// модель его не приняла (иначе повтор стоил бы лишних минут ожидания).
  Future<_VideoResponse> _requestVideo(
    String prompt,
    List<List<int>> imageBuffers,
  ) async {
    try {
      final chat = await _postChatCompletions(prompt, imageBuffers);
      final response = _VideoResponse(
        videoUrl: _firstVideoUrl(chat),
        finishReason: _extractFinishReason(chat),
      );
      if (response.videoUrl != null || response.isBlocked) return response;
      debugPrint('$_tag chat-контур не вернул ссылку, '
          'повтор через generateContent');
    } on ApiBostHttpException catch (e) {
      if (!_chatUnsupportedStatuses.contains(e.statusCode)) rethrow;
      if (_isModerationError(e.message)) rethrow;
      debugPrint('$_tag chat-контур недоступен (HTTP ${e.statusCode}), '
          'повтор через generateContent');
    }

    final data = await _postGenerateContent(prompt, imageBuffers);
    return _VideoResponse(
      videoUrl: _firstVideoUrl(data),
      finishReason: _extractFinishReason(data),
    );
  }

  /// Только без `stream`: в потоковом режиме ApiBost отдаёт для Veo пустой
  /// SSE (одни keepalive-пинги и `[DONE]`), а обычный ответ приходит целиком
  /// примерно за минуту — быстрее, чем срабатывает таймаут Cloudflare.
  Future<Map<String, dynamic>> _postChatCompletions(
    String prompt,
    List<List<int>> imageBuffers,
  ) async {
    final response = await http
        .post(
          Uri.parse('${_baseUrl()}/v1/chat/completions'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': _model,
            'messages': [
              {'role': 'user', 'content': _chatContent(prompt, imageBuffers)},
            ],
          }),
        )
        .timeout(_timeout);
    return _decode(response.statusCode, response.bodyBytes);
  }

  /// Модель принимает и обычную строку, и мультимодальные части; изображения
  /// уходят data-URI, потому что публичного URL у локального файла нет.
  static Object _chatContent(String prompt, List<List<int>> imageBuffers) {
    if (imageBuffers.isEmpty) return prompt;
    return [
      {'type': 'text', 'text': prompt},
      for (final buffer in imageBuffers)
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/jpeg;base64,${base64Encode(buffer)}',
          },
        },
    ];
  }

  /// Сырые ответы шлюзов и биллинга нечитаемы для пользователя, поэтому
  /// наружу уходит текст с понятным следующим шагом.
  String _userMessageFor(ApiBostHttpException e) {
    if (_isModerationError(e.message)) return _moderationMessage;
    if (_gatewayTimeoutStatuses.contains(e.statusCode)) return _timeoutMessage;

    final lower = e.message.toLowerCase();
    if (e.statusCode == 429 || lower.contains('rate limit')) {
      return _rateLimitMessage;
    }
    if (e.statusCode == 422 ||
        lower.contains('string_too_long') ||
        lower.contains('too long')) {
      return _tooLongMessage;
    }
    return 'Не удалось сгенерировать видео (код ${e.statusCode}). '
        'Попробуйте изменить описание или повторить попытку позже.';
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
    for (final choice in _asList(data['choices'])) {
      if (choice is Map && choice['finish_reason'] != null) {
        return choice['finish_reason'].toString();
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

    for (final candidate in _downloadCandidates(trimmed)) {
      final bytes = await _download(candidate);
      if (bytes != null) return bytes;
    }
    return null;
  }

  /// Прокси-релей идёт первым: прямые ссылки ApiBost из РФ не открываются, а
  /// ожидание их таймаута сжигало минуты уже после списания кредитов.
  List<String> _downloadCandidates(String url) {
    final proxyBase = AiProxyConfig.imageProxyBaseUrl();
    if (proxyBase == null) return [url];
    return ['$proxyBase?url=${Uri.encodeComponent(url)}', url];
  }

  /// Готовое видео уже оплачено, поэтому доставка переживает обрывы: каждая
  /// ссылка получает [_downloadAttempts] попыток, а тело пишется потоком в
  /// файл — без промежуточной копии всего ролика в памяти.
  Future<String?> _downloadVideo(
    String url,
    String nameHint, {
    bool allowProxyFallback = true,
  }) async {
    final targetPath = await _videoFilePath(nameHint);
    if (targetPath == null) return null;

    final candidates =
        allowProxyFallback ? _downloadCandidates(url) : <String>[url];
    for (final candidate in candidates) {
      for (var attempt = 1; attempt <= _downloadAttempts; attempt++) {
        if (await _streamToFile(candidate, targetPath)) return targetPath;
        if (attempt < _downloadAttempts) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    // Недокачанный хвост нельзя оставлять: плеер принял бы его за готовое видео.
    final leftover = File(targetPath);
    if (await leftover.exists()) {
      await leftover.delete().catchError((_) => leftover);
    }
    return null;
  }

  Future<bool> _streamToFile(String url, String targetPath) async {
    final client = http.Client();
    final file = File(targetPath);
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = 'AIVideoMaker/client-apibost';
      final response = await client.send(request).timeout(_downloadTimeout);
      if (response.statusCode != 200) {
        debugPrint('$_tag ошибка загрузки: HTTP ${response.statusCode}');
        return false;
      }
      final sink = file.openWrite();
      try {
        await response.stream.pipe(sink).timeout(_downloadTimeout);
      } finally {
        await sink.flush().catchError((_) {});
        await sink.close().catchError((_) {});
      }
      final length = await file.length();
      if (length < _minVideoBytes) {
        debugPrint('$_tag подозрительно короткий ответ: $length байт');
        await file.delete().catchError((_) => file);
        return false;
      }
      debugPrint('$_tag скачано $length байт');
      return true;
    } catch (e) {
      debugPrint('$_tag ошибка загрузки: $e');
      return false;
    } finally {
      client.close();
    }
  }

  Future<String?> _videoFilePath(String nameHint) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return path.join(
        directory.path,
        'apibost_${_sanitize(nameHint)}_'
        '${DateTime.now().millisecondsSinceEpoch}'
        '${GeneratedMedia.videoExtension}',
      );
    } catch (e) {
      debugPrint('$_tag не удалось подготовить файл: $e');
      return null;
    }
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

class _VideoResponse {
  const _VideoResponse({this.videoUrl, this.finishReason});

  final String? videoUrl;
  final String? finishReason;

  bool get isBlocked {
    final reason = finishReason;
    if (reason == null) return false;
    return ClientApiBostVideoService._blockedFinishReasons.contains(reason) ||
        reason.toLowerCase() == 'content_filter';
  }
}
