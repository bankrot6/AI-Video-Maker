import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/photo_session_preset.dart';

class PresetCacheService {
  static const String _boxName = 'presets_cache';
  static const String _timestampKey = 'last_update';
  static const Duration _cacheDuration = Duration(hours: 1);

  Box<dynamic>? _box;

  Future<void> init() async {
    try {
      await Hive.initFlutter();
      _box = await Hive.openBox(_boxName);
      debugPrint('PresetCache: инициализирован');
    } catch (e) {
      debugPrint('PresetCache: ошибка инициализации $e');
    }
  }

  Future<void> savePresets(List<PhotoSessionPreset> presets) async {
    try {
      if (_box == null) await init();
      if (_box == null) return;

      final jsonList = presets.map((p) => p.toJson()).toList();
      await _box!.put('presets', jsonList);
      await _box!.put(_timestampKey, DateTime.now().millisecondsSinceEpoch);
      debugPrint('PresetCache: сохранено ${presets.length} пресетов');
    } catch (e) {
      debugPrint('PresetCache: ошибка сохранения $e');
    }
  }

  /// Возвращает кэшированные пресеты или null если кэш пуст.
  /// Никогда не сбрасывает устаревший кэш — используй [isStale] чтобы решить
  /// нужно ли фоновое обновление.
  Future<List<PhotoSessionPreset>?> getPresets() async {
    try {
      if (_box == null) await init();
      if (_box == null) return null;

      final jsonList = _box!.get('presets') as List<dynamic>?;
      if (jsonList == null || jsonList.isEmpty) {
        debugPrint('PresetCache: кэш пуст');
        return null;
      }

      final timestamp = _box!.get(_timestampKey) as int?;
      final age = timestamp == null
          ? null
          : DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(timestamp),
            );

      final presets = jsonList
          .map((json) =>
              PhotoSessionPreset.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();

      final ageStr = age == null ? 'неизвестно' : '${age.inMinutes} мин';
      final staleStr = (age != null && age > _cacheDuration) ? ' [устарел]' : '';
      debugPrint(
          'PresetCache: загружено ${presets.length} пресетов (возраст $ageStr)$staleStr');
      return presets;
    } catch (e) {
      debugPrint('PresetCache: ошибка чтения $e');
      return null;
    }
  }

  /// true — кэш есть, но устарел → нужно фоновое обновление.
  /// false — кэш свежий или пуст (пуст проверяй через [getPresets]).
  Future<bool> isStale() async {
    try {
      if (_box == null) await init();
      if (_box == null) return false;
      final timestamp = _box!.get(_timestampKey) as int?;
      if (timestamp == null) return false;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
      return age > _cacheDuration;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    try {
      if (_box == null) await init();
      await _box?.clear();
      debugPrint('PresetCache: кэш очищен');
    } catch (e) {
      debugPrint('PresetCache: ошибка очистки $e');
    }
  }
}
