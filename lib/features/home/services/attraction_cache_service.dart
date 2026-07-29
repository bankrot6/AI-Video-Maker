import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attraction_info.dart';

class AttractionCacheService {
  static const String _cachePrefix = 'attraction_cache_';
  static const String _imagePrefix = 'attraction_image_';
  static const Duration _cacheDuration = Duration(days: 30);

  Future<void> cacheAttractionInfo(
    String placeId,
    AttractionInfo info, {
    bool isComplete = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(placeId);

      final cacheData = {
        'info': info.toJson(),
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
        'isComplete': isComplete,
      };

      await prefs.setString(key, jsonEncode(cacheData));
      debugPrint(
          '💾 ATTRACTION_CACHE: Сохранено: $placeId (complete: $isComplete)');
    } catch (e) {
      debugPrint('❌ ATTRACTION_CACHE: Ошибка сохранения: $e');
    }
  }

  Future<AttractionInfo?> getCachedAttractionInfo(
    String placeId, {
    bool allowPartial = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(placeId);

      final cachedString = prefs.getString(key);
      if (cachedString == null) {
        debugPrint('💾 ATTRACTION_CACHE: Кэш не найден для: $placeId');
        return null;
      }

      final cacheData = jsonDecode(cachedString) as Map<String, dynamic>;

      if (!cacheData.containsKey('cachedAt')) {
        debugPrint('💾 ATTRACTION_CACHE: Старый формат кэша: $placeId');
        await clearCachedAttractionInfo(placeId);
        return null;
      }

      final cachedAt = DateTime.fromMillisecondsSinceEpoch(
        cacheData['cachedAt'] as int,
      );

      if (DateTime.now().difference(cachedAt) > _cacheDuration) {
        debugPrint('💾 ATTRACTION_CACHE: Кэш устарел: $placeId');
        await clearCachedAttractionInfo(placeId);
        return null;
      }

      final isComplete = cacheData['isComplete'] as bool? ?? false;
      if (!isComplete && !allowPartial) {
        debugPrint(
            '💾 ATTRACTION_CACHE: Неполный кэш (не разрешено): $placeId');
        return null;
      }

      final info = AttractionInfo.fromJson(
        cacheData['info'] as Map<String, dynamic>,
      );

      debugPrint(
          '💾 ATTRACTION_CACHE: Загружено из кэша: $placeId (complete: $isComplete)');
      return info;
    } catch (e) {
      debugPrint('❌ ATTRACTION_CACHE: Ошибка загрузки: $e');
      await clearCachedAttractionInfo(placeId);
      return null;
    }
  }

  Future<bool> isCacheComplete(String placeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(placeId);

      final cachedString = prefs.getString(key);
      if (cachedString == null) return false;

      final cacheData = jsonDecode(cachedString) as Map<String, dynamic>;
      return cacheData['isComplete'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> hasValidCache(String placeId) async {
    final info = await getCachedAttractionInfo(placeId);
    return info != null;
  }

  Future<void> cacheAttractionImage(String placeId, File imageFile) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/attraction_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final extension = imageFile.path.split('.').last;
      final normalizedId = _normalizeId(placeId);
      final newPath = '${imagesDir.path}/$normalizedId.$extension';

      await imageFile.copy(newPath);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_getImageKey(placeId), newPath);

      debugPrint('💾 ATTRACTION_CACHE: Изображение сохранено: $newPath');
    } catch (e) {
      debugPrint('❌ ATTRACTION_CACHE: Ошибка сохранения изображения: $e');
    }
  }

  Future<File?> getCachedImage(String placeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final imagePath = prefs.getString(_getImageKey(placeId));

      if (imagePath == null) return null;

      final file = File(imagePath);
      if (await file.exists()) {
        debugPrint('💾 ATTRACTION_CACHE: Изображение из кэша: $imagePath');
        return file;
      }

      await prefs.remove(_getImageKey(placeId));
      return null;
    } catch (e) {
      debugPrint('❌ ATTRACTION_CACHE: Ошибка загрузки изображения: $e');
      return null;
    }
  }

  Future<void> clearCachedAttractionInfo(String placeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getCacheKey(placeId));
      debugPrint('💾 ATTRACTION_CACHE: Удалено: $placeId');
    } catch (e) {
      debugPrint('❌ ATTRACTION_CACHE: Ошибка удаления: $e');
    }
  }

  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith(_cachePrefix) || key.startsWith(_imagePrefix)) {
          await prefs.remove(key);
        }
      }

      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/attraction_images');
      if (await imagesDir.exists()) {
        await imagesDir.delete(recursive: true);
      }

      debugPrint('💾 ATTRACTION_CACHE: Весь кэш очищен');
    } catch (e) {
      debugPrint('❌ ATTRACTION_CACHE: Ошибка очистки кэша: $e');
    }
  }

  Future<int> getCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      return keys.where((key) => key.startsWith(_cachePrefix)).length;
    } catch (e) {
      return 0;
    }
  }

  Future<List<String>> getCachedPlaceIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      return keys
          .where((key) => key.startsWith(_cachePrefix))
          .map((key) => key.replaceFirst(_cachePrefix, ''))
          .toList();
    } catch (e) {
      return [];
    }
  }

  String _getCacheKey(String placeId) {
    return '$_cachePrefix${_normalizeId(placeId)}';
  }

  String _getImageKey(String placeId) {
    return '$_imagePrefix${_normalizeId(placeId)}';
  }

  String _normalizeId(String placeId) {
    return placeId.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
  }

  Future<void> cacheAttractionImages(
      String placeId, List<File> imageFiles) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/attraction_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final normalizedId = _normalizeId(placeId);
      final List<String> savedPaths = [];

      for (int i = 0; i < imageFiles.length; i++) {
        final imageFile = imageFiles[i];
        final extension = imageFile.path.split('.').last;
        final newPath = '${imagesDir.path}/${normalizedId}_$i.$extension';

        await imageFile.copy(newPath);
        savedPaths.add(newPath);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_getImagesKey(placeId), savedPaths);

      debugPrint(
          '💾 ATTRACTION_CACHE: Сохранено ${savedPaths.length} изображений для $placeId');
    } catch (e) {
      debugPrint('❌ ATTRACTION_CACHE: Ошибка сохранения изображений: $e');
    }
  }

  Future<List<File>> getCachedImages(String placeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final imagePaths = prefs.getStringList(_getImagesKey(placeId));

      if (imagePaths == null || imagePaths.isEmpty) {
        final singleImage = await getCachedImage(placeId);
        if (singleImage != null) return [singleImage];
        return [];
      }

      final List<File> files = [];
      for (final path in imagePaths) {
        final file = File(path);
        if (await file.exists()) {
          files.add(file);
        }
      }

      if (files.isNotEmpty) {
        debugPrint(
            '💾 ATTRACTION_CACHE: Загружено ${files.length} изображений из кэша для $placeId');
      }

      return files;
    } catch (e) {
      debugPrint('❌ ATTRACTION_CACHE: Ошибка загрузки изображений: $e');
      return [];
    }
  }

  String _getImagesKey(String placeId) {
    return '${_imagePrefix}list_${_normalizeId(placeId)}';
  }
}
