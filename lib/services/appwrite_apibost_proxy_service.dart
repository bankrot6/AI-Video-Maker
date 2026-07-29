import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'apibost_prompt_builder.dart';
import 'appwrite_storage_service.dart';
import 'device_id_service.dart';
import 'photosession_generation_router.dart';

class AppwriteApiBostProxyService
    implements PhotosessionGenerationService, ReferenceImageGenerationService {
  AppwriteApiBostProxyService({
    String? endpoint,
    String? projectId,
    String? bucketId,
    String model = 'gemini-2.5-flash-image',
    double temperature = 0.7,
    Duration? timeout,
  })  : _model = model,
        _temperature = temperature,
        _timeout = timeout ?? const Duration(seconds: 300) {
    _endpoint = (endpoint ?? dotenv.env['APPWRITE_ENDPOINT'])?.trim();
    _projectId = (projectId ?? dotenv.env['APPWRITE_PROJECT_ID'])?.trim();
    _bucketId =
        (bucketId ?? dotenv.env['APPWRITE_STORAGE_BUCKET_ID'])?.trim() ??
            'user-photos';
  }

  static const _functionId = 'apibost-proxy';
  static const _tag = '🔵 APIBOST_PROXY';
  static const _asyncPollInterval = Duration(seconds: 5);
  static const _asyncPollTimeout = Duration(minutes: 9);
  static final Random _random = Random.secure();

  late final String? _endpoint;
  late final String? _projectId;
  late final String _bucketId;
  final String _model;
  final double _temperature;
  final Duration _timeout;

  @override
  Future<bool> isAvailable() async {
    final ok = (_endpoint ?? '').isNotEmpty && (_projectId ?? '').isNotEmpty;
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
        errorMessage: 'ApiBost Proxy не настроен',
      );
    }

    try {
      final resolvedUserUrl = await _resolveToHttpUrl(userImageUrl);
      if (resolvedUserUrl == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Не удалось загрузить фото пользователя',
        );
      }

      // referenceImageUrl — уже HTTP-ссылка (из Appwrite Storage или CDN).
      // Если локальный путь — загружаем в Storage, иначе передаём напрямую.
      // Appwrite function использует image_urls (не скачивает как buffer).
      final resolvedRefUrl = referenceImageUrl != null
          ? await _resolveToHttpUrl(referenceImageUrl)
          : null;

      final enhancedPrompt = ApiBostPromptBuilder.buildFacePrompt(
        scenePrompt: scenePrompt,
        aspectRatio: aspectRatio,
        temperature: _temperature,
        hasReference: resolvedRefUrl != null,
      );

      debugPrint(
          '$_tag generateWithFace model=$_model ref=${resolvedRefUrl != null}');

      return await _callProxy(
        action: 'generate_with_face',
        prompt: enhancedPrompt,
        userImageUrl: resolvedUserUrl,
        referenceImageUrl: resolvedRefUrl,
        resolution: resolution,
        aspectRatio: aspectRatio,
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
        errorMessage: 'ApiBost Proxy не настроен',
      );
    }

    try {
      final resolvedUrl = await _resolveToHttpUrl(referenceImageUrl);
      if (resolvedUrl == null) {
        return const PhotosessionGenerationResult(
          errorMessage: 'Не удалось загрузить изображение-референс',
        );
      }

      debugPrint('$_tag generateFromReference model=$_model');

      return await _callProxy(
        action: 'generate_with_face',
        prompt: ApiBostPromptBuilder.buildReferencePrompt(
          prompt: prompt,
          aspectRatio: aspectRatio,
          temperature: _temperature,
        ),
        userImageUrl: resolvedUrl,
        resolution: resolution,
        aspectRatio: aspectRatio,
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
        errorMessage: 'ApiBost Proxy не настроен',
      );
    }

    try {
      final enrichedPrompt = ApiBostPromptBuilder.buildImagePrompt(
        prompt: prompt,
        aspectRatio: aspectRatio,
        temperature: _temperature,
      );

      debugPrint('$_tag generateImage model=$_model');

      return await _callProxy(
        action: 'generate_image',
        prompt: enrichedPrompt,
        userImageUrl: null,
        saveNameHint: prompt,
      );
    } catch (e, st) {
      debugPrint('$_tag ошибка generateImage: $e');
      debugPrint('$_tag стек: $st');
      return PhotosessionGenerationResult(errorMessage: 'Ошибка: $e');
    }
  }

  Future<PhotosessionGenerationResult> _callProxy({
    required String action,
    required String prompt,
    required String? userImageUrl,
    required String saveNameHint,
    String? referenceImageUrl,
    String resolution = '2K',
    String aspectRatio = '3:4',
  }) async {
    // Не отправляем запрос с пустым промтом: серверная функция всё равно вернёт
    // 400 «prompt обязателен», а это лишний execution и нагрузка. saveNameHint —
    // это исходный пользовательский текст сцены (без служебных префиксов).
    if (saveNameHint.trim().isEmpty) {
      debugPrint('$_tag пустой промт — запрос на сервер не отправлен');
      return const PhotosessionGenerationResult(
        errorMessage: 'Пустой промт: опишите сцену для генерации',
      );
    }

    final fingerprint = await DeviceIdService.instance.getDeviceId();
    debugPrint('$_tag fingerprint=${fingerprint.isNotEmpty ? "${fingerprint.substring(0, 8)}... (${fingerprint.length} chars)" : "EMPTY!"}');
    
    final functionBody = <String, dynamic>{
      'action': action,
      'fingerprint': fingerprint,
      'model': _model,
      'prompt': prompt,
      'resolution': resolution,
      'aspectRatio': _formatAspectRatio(aspectRatio),
      if (userImageUrl != null) 'userImageUrl': userImageUrl,
      if (referenceImageUrl != null) 'referenceImageUrl': referenceImageUrl,
    };

    debugPrint('$_tag вызов функции $_functionId action=$action');

    final functions = Functions(_buildClient());
    return _callProxyAsync(
      functions: functions,
      functionBody: functionBody,
      saveNameHint: saveNameHint,
    );
  }

  Future<PhotosessionGenerationResult> _callProxyAsync({
    required Functions functions,
    required Map<String, dynamic> functionBody,
    required String saveNameHint,
  }) async {
    final jobId = _newJobId();
    final jobResultFileId = 'jobr_$jobId';
    final asyncBody = {
      ...functionBody,
      'jobResultFileId': jobResultFileId,
    };

    debugPrint('$_tag async execution job=$jobId model=$_model');
    await functions
        .createExecution(
          functionId: _functionId,
          body: jsonEncode(asyncBody),
          xasync: true,
        )
        .timeout(_timeout);

    // Cleanup временных файлов после завершения генерации.
    // Файлы user_*/ref_*/jobr_* в Appwrite Storage нужны только на время
    // выполнения задачи — после получения результата они становятся мусором.
    final tempFileIdsToCleanup = <String>{jobResultFileId};
    final userImageInBucket =
        _extractFileIdFromUrl(functionBody['userImageUrl'] as String?);
    if (userImageInBucket != null) tempFileIdsToCleanup.add(userImageInBucket);
    final refImageInBucket =
        _extractFileIdFromUrl(functionBody['referenceImageUrl'] as String?);
    if (refImageInBucket != null) tempFileIdsToCleanup.add(refImageInBucket);

    try {
      final deadline = DateTime.now().add(_asyncPollTimeout);
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(_asyncPollInterval);
        final job = await _fetchJobResult(jobResultFileId);
        if (job == null) continue;

        final status = job['status'] as String?;
        if (status == 'failed') {
          final errorMsg = job['error'] as String?;
          return PhotosessionGenerationResult(
            errorMessage: errorMsg ?? 'Генерация завершилась ошибкой.',
          );
        }
        if (status == 'completed') {
          final imageUrl = job['imageUrl'] as String?;
          if (imageUrl == null || imageUrl.isEmpty) {
            return const PhotosessionGenerationResult(
              errorMessage: 'URL изображения отсутствует в ответе функции',
            );
          }
          final localPath =
              await _downloadAndSaveLocally(imageUrl, saveNameHint);
          if (localPath == null) {
            return const PhotosessionGenerationResult(
              errorMessage: 'Не удалось сохранить изображение',
            );
          }
          final actualModel = job['actualModel'] as String?;
          final requestedModel = job['requestedModel'] as String? ?? _model;
          debugPrint(
            '$_tag фактическая модель=${actualModel ?? requestedModel} '
            '(запрошена=$requestedModel)',
          );
          return PhotosessionGenerationResult(imageUrl: localPath);
        }
      }

      return const PhotosessionGenerationResult(
        errorMessage: 'Истекло время ожидания генерации.',
      );
    } finally {
      unawaited(_cleanupTempFiles(tempFileIdsToCleanup));
    }
  }

  String? _extractFileIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (!url.contains('/files/')) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final idx = uri.pathSegments.indexOf('files');
    if (idx < 0 || idx + 1 >= uri.pathSegments.length) return null;
    return uri.pathSegments[idx + 1];
  }

  Future<void> _cleanupTempFiles(Set<String> fileIds) async {
    if (fileIds.isEmpty) return;
    try {
      final storage = AppwriteStorageService(
        endpoint: _endpoint,
        projectId: _projectId,
        bucketId: _bucketId,
      );
      for (final id in fileIds) {
        try {
          await storage.deleteFile(id);
        } catch (_) {
          // не критично — отдельная функция cleanup-orphan-files добьёт мусор
        }
      }
    } catch (e) {
      debugPrint('$_tag cleanup error: $e');
    }
  }

  Future<Map<String, dynamic>?> _fetchJobResult(String fileId) async {
    try {
      final base = (_endpoint ?? '').replaceAll(RegExp(r'/v1/?$'), '');
      final uri = Uri.parse(
        '$base/v1/storage/buckets/$_bucketId/files/$fileId/download'
        '?project=$_projectId',
      );
      final response = await http.get(
        uri,
        headers: {
          'X-Appwrite-Project': _projectId ?? '',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) {
        debugPrint('$_tag job poll HTTP ${response.statusCode}');
        return null;
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('$_tag job poll error: $e');
      return null;
    }
  }

  String _newJobId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rnd = _random.nextInt(1 << 32).toRadixString(36);
    return 'job_${ts}_$rnd';
  }

  Future<String?> _resolveToHttpUrl(String url) async {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;

    final file = File(url);
    if (!await file.exists()) {
      debugPrint('$_tag локальный файл не найден: $url');
      return null;
    }

    debugPrint('$_tag загружаю локальный файл в Appwrite Storage: $url');
    final storage = AppwriteStorageService(
      endpoint: _endpoint,
      projectId: _projectId,
      bucketId: _bucketId,
    );
    return storage.uploadUserPhoto(file);
  }

  Future<String?> _downloadAndSaveLocally(String url, String nameHint) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'X-Appwrite-Project': _projectId ?? '',
        },
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('$_tag ошибка скачивания: HTTP ${response.statusCode}');
        return null;
      }

      final directory = await getApplicationDocumentsDirectory();
      final sanitized = _sanitize(nameHint);
      final fileName =
          'apibost_${sanitized}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = path.join(directory.path, fileName);
      await File(filePath).writeAsBytes(response.bodyBytes, flush: true);
      return filePath;
    } catch (e) {
      debugPrint('$_tag ошибка сохранения: $e');
      return null;
    }
  }

  Client _buildClient() {
    return Client().setEndpoint(_endpoint ?? '').setProject(_projectId ?? '');
  }

  String _formatAspectRatio(String aspectRatio) =>
      ApiBostPromptBuilder.formatAspectRatio(aspectRatio);

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
