import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/user_generation.dart';
import '../services/local_generation_storage.dart';
import 'user_generation_repository.dart';

/// Хранит генерации пользователя локально на устройстве (Hive).
/// Используется для новых пользователей и после завершения миграции.
/// resultImageUrl хранит абсолютный путь к локальному файлу.
class LocalUserGenerationRepository implements UserGenerationRepository {
  static const _boxName = 'local_user_generations';

  static Future<void> ensureOpen() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
  }

  Box<String> get _box => Hive.box<String>(_boxName);

  String _presetKey(String presetId) => 'preset_$presetId';

  List<UserGeneration> _deserializeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => UserGeneration.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('LocalUserGenerationRepo: ошибка десериализации $e');
      return [];
    }
  }

  Future<void> _saveList(String presetId, List<UserGeneration> items) async {
    final raw = jsonEncode(items.map((g) => g.toJson()).toList());
    await _box.put(_presetKey(presetId), raw);
  }

  @override
  Future<List<UserGeneration>> getGenerationsByPreset(
    String presetId, {
    required String deviceId,
  }) async {
    final raw = _box.get(_presetKey(presetId));
    final items = _deserializeList(raw);
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Future<UserGeneration?> createGeneration({
    required String presetId,
    required String userImageUrl,
    required String resultImageUrl,
    required String deviceId,
    String? referenceImageUrl,
    String? clientAssignedDocumentId,
    String? pairedUserImageUrl,
    String? pairedResultImageUrl,
    String? pairedReferenceImageUrl,
  }) async {
    final id = clientAssignedDocumentId ??
        'local_${DateTime.now().millisecondsSinceEpoch}';
    final generation = UserGeneration(
      id: id,
      presetId: presetId,
      userImageUrl: userImageUrl,
      resultImageUrl: resultImageUrl,
      referenceImageUrl: referenceImageUrl,
      createdAt: DateTime.now(),
    );
    final existing = await getGenerationsByPreset(presetId, deviceId: deviceId);
    final updated = [generation, ...existing];
    await _saveList(presetId, updated);
    debugPrint('LocalUserGenerationRepo: сохранено id=$id preset=$presetId');
    return generation;
  }

  @override
  Stream<Set<String>> watchUsedPresetIds(String deviceId) async* {
    yield _collectUsedPresetIds();
    yield* _box.watch().map((_) => _collectUsedPresetIds());
  }

  Set<String> _collectUsedPresetIds() {
    final ids = <String>{};
    for (final key in _box.keys) {
      final k = key as String;
      if (k.startsWith('preset_')) {
        final presetId = k.substring('preset_'.length);
        final raw = _box.get(k);
        if (raw != null && raw.isNotEmpty && raw != '[]') {
          ids.add(presetId);
        }
      }
    }
    return ids;
  }

  @override
  Future<bool> deleteGeneration(
    String generationId, {
    required String deviceId,
    required String presetId,
  }) async {
    final existing = await getGenerationsByPreset(presetId, deviceId: deviceId);
    final toDelete = existing.firstWhere(
      (g) => g.id == generationId,
      orElse: () => UserGeneration(
        id: '',
        presetId: '',
        userImageUrl: '',
        resultImageUrl: '',
      ),
    );

    if (toDelete.id.isEmpty) return false;

    // Удаляем локальный файл если путь локальный
    if (LocalGenerationStorage.isLocalPath(toDelete.resultImageUrl)) {
      await LocalGenerationStorage.instance.deleteImage(toDelete.resultImageUrl);
    }
    if (LocalGenerationStorage.isLocalPath(toDelete.userImageUrl)) {
      await LocalGenerationStorage.instance.deleteImage(toDelete.userImageUrl);
    }

    final updated = existing.where((g) => g.id != generationId).toList();
    await _saveList(presetId, updated);
    debugPrint('LocalUserGenerationRepo: удалено $generationId');
    return true;
  }

  /// Добавляет мигрированную запись (уже с локальным путём) в Hive.
  Future<void> addMigratedGeneration(UserGeneration generation) async {
    final existing = await getGenerationsByPreset(
      generation.presetId,
      deviceId: '',
    );
    if (existing.any((g) => g.id == generation.id)) return;
    final updated = [generation, ...existing];
    await _saveList(generation.presetId, updated);
  }
}
