import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Кадр-обложка для видео.
///
/// В сетках нельзя держать по видеоплееру на плитку: каждый тянет файл целиком
/// при каждом открытии экрана и занимает декодер. Поэтому из видео один раз
/// достаётся первый кадр нативными средствами платформы, кладётся в кэш на
/// диск и дальше показывается как обычная картинка.
class VideoPosterService {
  factory VideoPosterService() => _instance ??= VideoPosterService._();

  VideoPosterService._();

  static VideoPosterService? _instance;

  static const _tag = '🖼 VIDEO_POSTER';

  /// Ширина совпадает с обложками, которые готовит сервер для своих пресетов.
  static const int posterWidth = 400;
  static const int posterQuality = 80;

  final _plugin = FcNativeVideoThumbnail();
  final _memory = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List?>>{};
  final _failed = <String>{};

  static String? _cacheDirPath;

  Uint8List? fromMemory(String source) => _memory[_keyFor(source)];

  /// Постер для [source] — локального файла или ссылки. Повторные вызовы
  /// отдают кэш, одновременные схлопываются в один расчёт.
  Future<Uint8List?> poster(String source) {
    final key = _keyFor(source);
    final cached = _memory[key];
    if (cached != null) return Future.value(cached);
    if (_failed.contains(key)) return Future.value(null);

    final existing = _pending[key];
    if (existing != null) return existing;

    final future = _resolve(source, key);
    _pending[key] = future;
    return future.whenComplete(() => _pending.remove(key));
  }

  Future<Uint8List?> _resolve(String source, String key) async {
    try {
      final cacheFile = await _cacheFile(key);
      if (await cacheFile.exists()) {
        final bytes = await cacheFile.readAsBytes();
        if (bytes.isNotEmpty) {
          _memory[key] = bytes;
          return bytes;
        }
      }

      final local = await _ensureLocalFile(source, key);
      if (local == null) {
        _failed.add(key);
        return null;
      }

      final Uint8List? bytes;
      try {
        bytes = await extractFrame(local.path);
      } finally {
        if (local.isTemporary) await _deleteQuietly(local.path);
      }
      if (bytes == null) {
        _failed.add(key);
        return null;
      }

      await cacheFile.writeAsBytes(bytes, flush: true);
      _memory[key] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('$_tag не удалось получить кадр для $source: $e');
      _failed.add(key);
      return null;
    }
  }

  /// Извлекает кадр из локального видеофайла. Возвращает `null`, если файл
  /// не видео или платформа не смогла его открыть.
  Future<Uint8List?> extractFrame(String filePath) async {
    try {
      return await _plugin.saveThumbnailToBytes(
        srcFile: filePath,
        width: posterWidth,
        height: posterWidth,
        quality: posterQuality,
      );
    } catch (e) {
      debugPrint('$_tag ошибка извлечения кадра из $filePath: $e');
      return null;
    }
  }

  /// Плагин работает только с файлом на диске, поэтому удалённое видео
  /// сначала скачивается во временный файл. Сам файл после извлечения не
  /// нужен — на диске остаётся только кадр.
  Future<_LocalSource?> _ensureLocalFile(String source, String key) async {
    if (!source.startsWith('http://') && !source.startsWith('https://')) {
      if (!await File(source).exists()) return null;
      return _LocalSource(source, isTemporary: false);
    }

    final directory = await _cacheDir();
    final temp = File(path.join(directory.path, '$key.src'));
    try {
      final response = await http
          .get(Uri.parse(source))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        debugPrint('$_tag загрузка видео HTTP ${response.statusCode}');
        return null;
      }
      await temp.writeAsBytes(response.bodyBytes, flush: true);
      return _LocalSource(temp.path, isTemporary: true);
    } catch (e) {
      debugPrint('$_tag не удалось скачать видео $source: $e');
      await _deleteQuietly(temp.path);
      return null;
    }
  }

  Future<void> _deleteQuietly(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<File> _cacheFile(String key) async =>
      File(path.join((await _cacheDir()).path, '$key.jpg'));

  Future<Directory> _cacheDir() async {
    final cached = _cacheDirPath;
    if (cached != null) return Directory(cached);

    final base = await getTemporaryDirectory();
    final directory = Directory(path.join(base.path, 'video_posters'));
    if (!await directory.exists()) await directory.create(recursive: true);
    _cacheDirPath = directory.path;
    return directory;
  }

  static String _keyFor(String source) =>
      md5.convert(utf8.encode(source)).toString();
}

class _LocalSource {
  const _LocalSource(this.path, {required this.isTemporary});

  final String path;
  final bool isTemporary;
}
