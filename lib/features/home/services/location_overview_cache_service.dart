import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/location_overview_info.dart';

class LocationOverviewCacheService {
  static const String _cachePrefix = 'location_overview_cache_';
  static const Duration _cacheDuration = Duration(days: 30);

  Future<void> cacheLocationOverview(
    String locationKey,
    LocationOverviewInfo info, {
    required bool isComplete,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(locationKey);

      final payload = <String, Object?>{
        'info': info.toJson(),
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
        'isComplete': isComplete,
      };

      await prefs.setString(key, jsonEncode(payload));
      debugPrint(
          '💾 LOCATION_OVERVIEW_CACHE: Сохранено: $locationKey (complete: $isComplete)');
    } catch (e) {
      debugPrint('❌ LOCATION_OVERVIEW_CACHE: Ошибка сохранения: $e');
    }
  }

  Future<LocationOverviewInfo?> getCachedLocationOverview(
    String locationKey, {
    bool allowPartial = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getCacheKey(locationKey);

      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final cachedAtMs = decoded['cachedAt'];
      if (cachedAtMs is! int) {
        await clearCachedLocationOverview(locationKey);
        return null;
      }

      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
      if (DateTime.now().difference(cachedAt) > _cacheDuration) {
        await clearCachedLocationOverview(locationKey);
        return null;
      }

      final isComplete = decoded['isComplete'] as bool? ?? false;
      if (!isComplete && !allowPartial) return null;

      final infoMap = decoded['info'];
      if (infoMap is! Map<String, dynamic>) return null;

      return LocationOverviewInfo.fromJson(infoMap);
    } catch (e) {
      debugPrint('❌ LOCATION_OVERVIEW_CACHE: Ошибка загрузки: $e');
      await clearCachedLocationOverview(locationKey);
      return null;
    }
  }

  Future<bool> isCacheComplete(String locationKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_getCacheKey(locationKey));
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      return decoded['isComplete'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearCachedLocationOverview(String locationKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getCacheKey(locationKey));
    } catch (e) {
      debugPrint('❌ LOCATION_OVERVIEW_CACHE: Ошибка удаления: $e');
    }
  }

  static String normalizeKey(String value) {
    return value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
  }

  String _getCacheKey(String locationKey) {
    return '$_cachePrefix${normalizeKey(locationKey)}';
  }
}











