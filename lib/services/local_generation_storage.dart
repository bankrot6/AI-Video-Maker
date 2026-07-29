import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'generated_media.dart';

/// Управляет хранением изображений генераций на устройстве.
/// Все файлы хранятся в `<documents>/gen_images/`
class LocalGenerationStorage {
  LocalGenerationStorage._();
  static final LocalGenerationStorage instance = LocalGenerationStorage._();

  static const _subdir = 'gen_images';

  static bool isLocalPath(String url) {
    if (url.isEmpty) return false;
    return !url.startsWith('http://') && !url.startsWith('https://');
  }

  Future<Directory> _imagesDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _subdir));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> saveImageBytes(Uint8List bytes, {String? id}) async {
    final dir = await _imagesDir();
    final fileName = '${id ?? DateTime.now().millisecondsSinceEpoch}'
        '${GeneratedMedia.extensionForBytes(bytes)}';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    debugPrint('LocalGenerationStorage: сохранено ${file.path}');
    return file.path;
  }

  Future<String?> saveImageFromUrl(String url, {String? id}) async {
    try {
      final response = await _downloadBytes(url);
      if (response == null) return null;
      return saveImageBytes(response, id: id);
    } catch (e) {
      debugPrint('LocalGenerationStorage: ошибка скачивания $url — $e');
      return null;
    }
  }

  Future<Uint8List?> readImageBytes(String localPath) async {
    try {
      final file = File(localPath);
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('LocalGenerationStorage: ошибка чтения $localPath — $e');
      return null;
    }
  }

  Future<void> deleteImage(String localPath) async {
    try {
      final file = File(localPath);
      if (file.existsSync()) await file.delete();
    } catch (e) {
      debugPrint('LocalGenerationStorage: ошибка удаления $localPath — $e');
    }
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.add('User-Agent', 'AIVideoMaker/1.0');
      final res = await req.close();
      if (res.statusCode != 200) {
        debugPrint('LocalGenerationStorage: HTTP ${res.statusCode} для $url');
        return null;
      }
      final builder = BytesBuilder();
      await for (final chunk in res) {
        builder.add(chunk);
      }
      return builder.toBytes();
    } finally {
      client.close();
    }
  }
}
