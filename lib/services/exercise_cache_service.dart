import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exercise_info.dart';

/// Сервис для кэширования информации об упражнениях
class ExerciseCacheService {
  static const String _cachePrefix = 'exercise_cache_';
  static const Duration _cacheDuration = Duration(days: 30); // Кэш на 30 дней

  /// Сохраняет информацию об упражнении в кэш
  Future<void> cacheExerciseInfo(String exerciseName, ExerciseInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(exerciseName);

      // Загружаем существующий кэш и мержим
      final existing = prefs.getString(key);
      Map<String, dynamic> cacheData = existing != null
          ? (jsonDecode(existing) as Map<String, dynamic>)
          : <String, dynamic>{};

      cacheData['info'] = info.toJson();
      cacheData['cachedAt'] = DateTime.now().millisecondsSinceEpoch;

      await prefs.setString(key, jsonEncode(cacheData));
      debugPrint('💾 EXERCISE_CACHE: Сохранено в кэш: $exerciseName');
    } catch (e) {
      debugPrint('❌ EXERCISE_CACHE: Ошибка сохранения в кэш: $e');
    }
  }

  /// Кэширует локальный путь к изображению упражнения
  Future<void> cacheExerciseImage(String exerciseName, String imagePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(exerciseName);
      final existing = prefs.getString(key);
      Map<String, dynamic> cacheData = existing != null
          ? (jsonDecode(existing) as Map<String, dynamic>)
          : <String, dynamic>{};

      cacheData['imagePath'] = imagePath;
      cacheData['cachedAt'] = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(key, jsonEncode(cacheData));
      debugPrint('💾 EXERCISE_CACHE: Сохранён путь к изображению: $imagePath');
    } catch (e) {
      debugPrint('❌ EXERCISE_CACHE: Ошибка кэширования изображения: $e');
    }
  }

  /// Возвращает локальный путь к изображению, если закэширован
  Future<String?> getCachedImagePath(String exerciseName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(exerciseName);
      final cachedString = prefs.getString(key);
      if (cachedString == null) return null;
      final cacheData = jsonDecode(cachedString) as Map<String, dynamic>;
      return cacheData['imagePath'] as String?;
    } catch (e) {
      debugPrint('❌ EXERCISE_CACHE: Ошибка получения изображения из кэша: $e');
      return null;
    }
  }

  /// Кэширует список VK видео кандидатов (ownerId/id)
  Future<void> cacheExerciseVideos(
    String exerciseName,
    List<Map<String, String>> videos,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(exerciseName);
      final existing = prefs.getString(key);
      Map<String, dynamic> cacheData = existing != null
          ? (jsonDecode(existing) as Map<String, dynamic>)
          : <String, dynamic>{};

      // Храним только первые 4
      final limited = videos.take(4).toList();
      cacheData['videos'] = limited;
      cacheData['cachedAt'] = DateTime.now().millisecondsSinceEpoch;
      await prefs.setString(key, jsonEncode(cacheData));
      debugPrint('💾 EXERCISE_CACHE: Сохранены видео: ${limited.length}');
    } catch (e) {
      debugPrint('❌ EXERCISE_CACHE: Ошибка кэширования видео: $e');
    }
  }

  /// Возвращает закэшированные VK видео кандидаты (список ownerId/id)
  Future<List<Map<String, String>>> getCachedVideos(String exerciseName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(exerciseName);
      final cachedString = prefs.getString(key);
      if (cachedString == null) return const [];
      final cacheData = jsonDecode(cachedString) as Map<String, dynamic>;
      final list = cacheData['videos'] as List<dynamic>?;
      if (list == null) return const [];
      return list
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v.toString())))
          .toList();
    } catch (e) {
      debugPrint('❌ EXERCISE_CACHE: Ошибка получения видео из кэша: $e');
      return const [];
    }
  }

  /// Получает информацию об упражнении из кэша
  Future<ExerciseInfo?> getCachedExerciseInfo(String exerciseName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(exerciseName);

      final cachedString = prefs.getString(key);
      if (cachedString == null) {
        debugPrint('💾 EXERCISE_CACHE: Кэш не найден для: $exerciseName');
        return null;
      }

      final cacheData = jsonDecode(cachedString) as Map<String, dynamic>;

      // Проверяем наличие поля cachedAt
      if (!cacheData.containsKey('cachedAt') || cacheData['cachedAt'] == null) {
        debugPrint(
            '💾 EXERCISE_CACHE: Старый формат кэша, очищаем: $exerciseName');
        await clearCachedExerciseInfo(exerciseName);
        return null;
      }

      final cachedAt = DateTime.fromMillisecondsSinceEpoch(
        cacheData['cachedAt'] as int,
      );

      // Проверяем, не устарел ли кэш
      if (DateTime.now().difference(cachedAt) > _cacheDuration) {
        debugPrint('💾 EXERCISE_CACHE: Кэш устарел для: $exerciseName');
        await clearCachedExerciseInfo(exerciseName);
        return null;
      }

      final info = ExerciseInfo.fromJson(
        cacheData['info'] as Map<String, dynamic>,
      );

      debugPrint('💾 EXERCISE_CACHE: Загружено из кэша: $exerciseName');
      return info;
    } catch (e) {
      debugPrint('❌ EXERCISE_CACHE: Ошибка загрузки из кэша: $e');
      // Очищаем поврежденный кэш
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = _getCacheKey(exerciseName);
        await prefs.remove(key);
        debugPrint('💾 EXERCISE_CACHE: Поврежденный кэш очищен: $exerciseName');
      } catch (_) {}
      return null;
    }
  }

  /// Удаляет информацию об упражнении из кэша
  Future<void> clearCachedExerciseInfo(String exerciseName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(exerciseName);
      await prefs.remove(key);
      debugPrint('💾 EXERCISE_CACHE: Удалено из кэша: $exerciseName');
    } catch (e) {
      debugPrint('❌ EXERCISE_CACHE: Ошибка удаления из кэша: $e');
    }
  }

  /// Очищает весь кэш упражнений
  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith(_cachePrefix)) {
          await prefs.remove(key);
        }
      }

      debugPrint('💾 EXERCISE_CACHE: Весь кэш упражнений очищен');
    } catch (e) {
      debugPrint('❌ EXERCISE_CACHE: Ошибка очистки кэша: $e');
    }
  }

  /// Получает размер кэша (количество закэшированных упражнений)
  Future<int> getCacheSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      return keys.where((key) => key.startsWith(_cachePrefix)).length;
    } catch (e) {
      debugPrint('❌ EXERCISE_CACHE: Ошибка получения размера кэша: $e');
      return 0;
    }
  }

  /// Генерирует ключ для кэша на основе названия упражнения
  String _getCacheKey(String exerciseName) {
    // Нормализуем название: в нижний регистр, убираем лишние пробелы
    final normalized =
        exerciseName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
    return '$_cachePrefix$normalized';
  }
}
