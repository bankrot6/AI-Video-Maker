import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

import 'photosession_remote_storage.dart';

class FirebaseStorageService implements PhotosessionRemoteStorage {
  FirebaseStorageService({
    String? storageBucket,
  }) : _storageBucket = storageBucket;

  final String? _storageBucket;
  FirebaseStorage? _storage;

  FirebaseStorage _getStorage() {
    if (_storage != null) return _storage!;
    if (_storageBucket != null && _storageBucket.isNotEmpty) {
      _storage = FirebaseStorage.instanceFor(bucket: 'gs://$_storageBucket');
    } else {
      _storage = FirebaseStorage.instance;
    }
    return _storage!;
  }

  /// Результатом генерации может быть MP4, а не картинка: с жёстким
  /// `image/jpeg` браузер и плеер получают неверный тип и не открывают файл.
  static const Map<String, String> _contentTypeByExtension = {
    '.mp4': 'video/mp4',
    '.mov': 'video/quicktime',
    '.webm': 'video/webm',
    '.m4v': 'video/x-m4v',
    '.png': 'image/png',
    '.webp': 'image/webp',
  };

  static String _contentTypeFor(String fileName) =>
      _contentTypeByExtension[path.extension(fileName).toLowerCase()] ??
      'image/jpeg';

  @override
  Future<String?> uploadUserPhoto(File file) async {
    try {
      debugPrint('FirebaseStorage: начинаем загрузку ${file.path}');
      if (!file.existsSync()) {
        debugPrint('FirebaseStorage: файл не существует');
        return null;
      }

      var bytes = await file.readAsBytes();
      final sizeMB = bytes.length / (1024 * 1024);
      debugPrint('FirebaseStorage: размер файла ${sizeMB.toStringAsFixed(2)}MB');

      var fileName = path.basename(file.path);
      final ext = path.extension(fileName).toLowerCase();

      if (ext == '.heic' || ext == '.heif' || ext == '.png') {
        debugPrint('FirebaseStorage: конвертируем $ext в JPG...');
        final image = img.decodeImage(bytes);
        if (image == null) {
          debugPrint('FirebaseStorage: не удалось декодировать изображение');
          return null;
        }
        bytes = img.encodeJpg(image, quality: 85);
        fileName = '${path.basenameWithoutExtension(fileName)}.jpg';
        debugPrint('FirebaseStorage: конвертировано в JPG, размер ${(bytes.length / (1024 * 1024)).toStringAsFixed(2)}MB');
      }

      final fileId = 'user_${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode.abs()}';
      final filePath = 'user-photos/$fileId';
      debugPrint('FirebaseStorage: загрузка в path=$filePath');

      final storage = _getStorage();
      final ref = storage.ref().child(filePath);
      
      final metadata = SettableMetadata(
        contentType: _contentTypeFor(fileName),
        customMetadata: {'uploadedAt': DateTime.now().toIso8601String()},
      );

      await ref.putData(bytes, metadata);
      final downloadUrl = await ref.getDownloadURL();
      
      debugPrint('FirebaseStorage: успешно загружено, URL=$downloadUrl');
      return downloadUrl;
    } catch (e, st) {
      debugPrint('FirebaseStorage: ошибка $e');
      debugPrint('FirebaseStorage: стек $st');
      return null;
    }
  }

  Future<String?> uploadFile(File file, String idPrefix) async {
    try {
      if (!file.existsSync()) {
        debugPrint('FirebaseStorage: файл не существует ${file.path}');
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
      final fileId = '${idPrefix}_${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode.abs().toRadixString(36)}'
          '${path.extension(fileName).toLowerCase()}';
      final filePath = 'user-photos/$fileId';
      
      final storage = _getStorage();
      final ref = storage.ref().child(filePath);
      
      final metadata = SettableMetadata(
        contentType: _contentTypeFor(fileName),
        customMetadata: {'uploadedAt': DateTime.now().toIso8601String()},
      );

      await ref.putData(bytes, metadata);
      final downloadUrl = await ref.getDownloadURL();
      
      debugPrint('FirebaseStorage: загружено $idPrefix, URL=...');
      return downloadUrl;
    } catch (e, st) {
      debugPrint('FirebaseStorage: ошибка uploadFile $e');
      debugPrint('FirebaseStorage: $st');
      return null;
    }
  }

  @override
  Future<String?> uploadResultImage(File file) async =>
      uploadFile(file, 'result');

  @override
  Future<String?> uploadPresetPreview(File file) async =>
      uploadFile(file, 'preview');

  @override
  Future<bool> isAvailable() async {
    try {
      final storage = _getStorage();
      await storage.ref().child('test').getDownloadURL().catchError((_) => '');
      return true;
    } catch (e) {
      debugPrint('FirebaseStorage: проверка доступности - ошибка $e');
      return false;
    }
  }
}
