import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

import 'appwrite_auth_service.dart';
import 'photosession_remote_storage.dart';

class AppwriteStorageService implements PhotosessionRemoteStorage {
  AppwriteStorageService({
    String? endpoint,
    String? projectId,
    String? bucketId,
  })  : _endpoint = (endpoint ?? dotenv.env['APPWRITE_ENDPOINT'])?.trim(),
        _projectId = (projectId ?? dotenv.env['APPWRITE_PROJECT_ID'])?.trim(),
        _bucketId = (bucketId ?? dotenv.env['APPWRITE_STORAGE_BUCKET_ID'])?.trim() ?? 'user-photos';

  final String? _endpoint;
  final String? _projectId;
  final String _bucketId;

  String _viewUrlForFileId(String fileIdValue) {
    final base = _endpoint?.replaceAll(RegExp(r'/v1/?$'), '') ?? '';
    return '$base/v1/storage/buckets/$_bucketId/files/$fileIdValue/view?project=$_projectId';
  }

  Client _buildClient() {
    final sessionClient = AppwriteAuthService.instance.sessionClient;
    if (sessionClient != null) return sessionClient;
    return Client()
        .setEndpoint(_endpoint ?? '')
        .setProject(_projectId ?? '');
  }

  Storage _buildStorage() => Storage(_buildClient());

  bool _isVersionMismatchParseError(Object e) =>
      e.toString().contains('is not a subtype of type');

  /// Подтверждает, что файл реально присутствует в бакете.
  ///
  /// На сервере 1.8.x SDK 23.x не может распарсить модель файла и бросает
  /// TypeError даже для существующего файла — это трактуем как наличие файла.
  /// Отсутствие файла сервер отдаёт как AppwriteException(404).
  Future<bool> _confirmFileExists(Storage storage, String fileId) async {
    try {
      await storage.getFile(bucketId: _bucketId, fileId: fileId);
      return true;
    } on AppwriteException catch (e) {
      if (e.code == 404) return false;
      debugPrint('AppwriteStorage: confirm getFile error ${e.code} ${e.message}');
      return false;
    } catch (e) {
      if (_isVersionMismatchParseError(e)) return true;
      debugPrint('AppwriteStorage: confirm getFile $e');
      return false;
    }
  }

  Future<String?> _uploadBytes({
    required List<int> bytes,
    required String fileName,
    required String fileId,
  }) async {
    await AppwriteAuthService.instance.ensureSession();
    final storage = _buildStorage();
    try {
      final result = await storage.createFile(
        bucketId: _bucketId,
        fileId: fileId,
        file: InputFile.fromBytes(bytes: bytes, filename: fileName),
        permissions: [Permission.read(Role.any())],
      );
      debugPrint('AppwriteStorage: загружено fileId=${result.$id}');
      return _viewUrlForFileId(result.$id);
    } on AppwriteException catch (e) {
      debugPrint('AppwriteStorage: upload Appwrite error ${e.code} ${e.message}');
      return null;
    } catch (e) {
      // Appwrite SDK 23.x / server 1.8.x: модель файла содержит поля (например
      // encryption: bool), которые сервер 1.8 возвращает null — SDK бросает
      // TypeError даже когда сам запрос прошёл. Раньше здесь URL возвращался
      // оптимистично, но при сбое стораджа файл мог не сохраниться — клиент
      // отдавал «мёртвую» ссылку, и серверная функция падала на скачивании 404.
      // Поэтому подтверждаем фактическое наличие файла перед возвратом URL.
      if (!_isVersionMismatchParseError(e)) {
        debugPrint('AppwriteStorage: upload $e');
        return null;
      }
      final exists = await _confirmFileExists(storage, fileId);
      if (!exists) {
        debugPrint('AppwriteStorage: загрузка не подтверждена, файл отсутствует '
            'fileId=$fileId');
        return null;
      }
      debugPrint('AppwriteStorage: загрузка подтверждена через getFile '
          'fileId=$fileId');
      return _viewUrlForFileId(fileId);
    }
  }

  @override
  Future<String?> uploadUserPhoto(File file) async {
    try {
      debugPrint('AppwriteStorage: начинаем загрузку ${file.path}');
      if (!file.existsSync()) {
        debugPrint('AppwriteStorage: файл не существует');
        return null;
      }

      var bytes = await file.readAsBytes();
      final sizeMB = bytes.length / (1024 * 1024);
      debugPrint('AppwriteStorage: размер файла ${sizeMB.toStringAsFixed(2)}MB');

      var fileName = path.basename(file.path);
      final ext = path.extension(fileName).toLowerCase();

      if (ext == '.heic' || ext == '.heif' || ext == '.png') {
        debugPrint('AppwriteStorage: конвертируем $ext в JPG...');
        final image = img.decodeImage(bytes);
        if (image == null) {
          debugPrint('AppwriteStorage: не удалось декодировать изображение');
          return null;
        }
        bytes = img.encodeJpg(image, quality: 85);
        fileName = '${path.basenameWithoutExtension(fileName)}.jpg';
        debugPrint(
          'AppwriteStorage: конвертировано в JPG, размер ${(bytes.length / (1024 * 1024)).toStringAsFixed(2)}MB',
        );
      }

      final fileId =
          'user_${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode.abs()}';
      debugPrint('AppwriteStorage: bucket=$_bucketId fileId=$fileId');

      return await _uploadBytes(bytes: bytes, fileName: fileName, fileId: fileId);
    } catch (e, st) {
      debugPrint('AppwriteStorage: ошибка uploadUserPhoto $e');
      debugPrint('$st');
      return null;
    }
  }

  Future<String?> uploadFile(File file, String idPrefix) async {
    try {
      if (!file.existsSync()) {
        debugPrint('AppwriteStorage: файл не существует ${file.path}');
        return null;
      }
      var bytes = await file.readAsBytes();
      var fileName = path.basename(file.path);
      final ext = path.extension(fileName).toLowerCase();
      if (ext == '.heic' || ext == '.heif' || ext == '.png') {
        final image = img.decodeImage(bytes);
        if (image != null) {
          bytes = img.encodeJpg(image, quality: 85);
          fileName = '${path.basenameWithoutExtension(fileName)}.jpg';
        }
      }
      final fileId =
          '${idPrefix}_${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode.abs().toRadixString(36)}';

      final url = await _uploadBytes(bytes: bytes, fileName: fileName, fileId: fileId);
      if (url != null) debugPrint('AppwriteStorage: загружено $idPrefix');
      return url;
    } catch (e, st) {
      debugPrint('AppwriteStorage: ошибка uploadFile $e');
      debugPrint('$st');
      return null;
    }
  }

  @override
  Future<String?> uploadResultImage(File file) async =>
      uploadFile(file, 'result');

  @override
  Future<String?> uploadPresetPreview(File file) async =>
      uploadFile(file, 'preview');

  /// Удаляет файл из Appwrite Storage по URL или fileId.
  /// Использует API key клиент, т.к. старые файлы созданы без user delete permission.
  Future<bool> deleteFile(String fileUrlOrId) async {
    try {
      final fileId = _extractFileId(fileUrlOrId);
      if (fileId == null) {
        debugPrint('AppwriteStorage: не удалось извлечь fileId из $fileUrlOrId');
        return false;
      }

      final apiKey = _resolveApiKey();
      final Client client;
      if (apiKey != null && apiKey.isNotEmpty) {
        client = Client()
            .setEndpoint(_endpoint ?? '')
            .setProject(_projectId ?? '');
        client.setDevKey(apiKey);
      } else {
        final session = AppwriteAuthService.instance.sessionClient;
        if (session == null) return false;
        client = session;
      }

      await Storage(client).deleteFile(bucketId: _bucketId, fileId: fileId);
      debugPrint('AppwriteStorage: удалён fileId=$fileId');
      return true;
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        debugPrint('AppwriteStorage: файл уже не существует, считаем удалённым');
        return true;
      }
      debugPrint('AppwriteStorage: deleteFile Appwrite error ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('AppwriteStorage: deleteFile $e');
      return false;
    }
  }

  String? _extractFileId(String fileUrlOrId) {
    if (!fileUrlOrId.contains('/')) return fileUrlOrId;
    final uri = Uri.tryParse(fileUrlOrId);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    final idx = segments.indexOf('files');
    if (idx < 0 || idx + 1 >= segments.length) return null;
    return segments[idx + 1];
  }

  String? _resolveApiKey() {
    try {
      return dotenv.env['APPWRITE_API_KEY']?.trim();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      if (_endpoint == null ||
          _endpoint.isEmpty ||
          _projectId == null ||
          _projectId.isEmpty) {
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('AppwriteStorage: проверка доступности — $e');
      return false;
    }
  }
}
