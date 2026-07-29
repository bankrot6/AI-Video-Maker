import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/photo_session_preset.dart';
import 'showcase_repository.dart';

class DualBackendShowcaseRepository implements ShowcaseRepository {
  DualBackendShowcaseRepository({
    required ShowcaseRepository primary,
    required ShowcaseRepository secondary,
  })  : _primary = primary,
        _secondary = secondary;

  final ShowcaseRepository _primary;
  final ShowcaseRepository _secondary;

  static const _uuid = Uuid();

  Future<T> _primaryOrFallback<T>(
    Future<T> Function() primaryFn,
    Future<T> Function() secondaryFn,
  ) async {
    try {
      return await primaryFn();
    } catch (e, st) {
      debugPrint('DualBackendShowcaseRepository: primary read failed: $e');
      debugPrint('$st');
      return await secondaryFn();
    }
  }

  @override
  Future<List<PhotoSessionPreset>> getPresets({int limit = 0}) {
    return _primaryOrFallback(
      () => _primary.getPresets(limit: limit),
      () => _secondary.getPresets(limit: limit),
    );
  }

  @override
  Future<List<PhotoSessionPreset>> fetchPresetsForUiBootstrap(
      {int limit = 0}) {
    return _primaryOrFallback(
      () => _primary.fetchPresetsForUiBootstrap(limit: limit),
      () => _secondary.fetchPresetsForUiBootstrap(limit: limit),
    );
  }

  @override
  Stream<List<PhotoSessionPreset>> streamPresetsBootstrap() {
    return _primary.streamPresetsBootstrap();
  }

  @override
  Future<PhotoSessionPreset?> getPresetById(String id) async {
    try {
      final r = await _primary.getPresetById(id);
      if (r != null) return r;
    } catch (e, st) {
      debugPrint('DualBackendShowcaseRepository: getPresetById primary $e');
      debugPrint('$st');
    }
    return _secondary.getPresetById(id);
  }

  @override
  Future<PhotoSessionPreset> createPreset({
    required String prompt,
    required String previewImageUrl,
    String? title,
    List<String>? tags,
    String? imageStyle,
    String? ownerId,
    String? clientAssignedPresetId,
    String? pairedPreviewImageUrl,
  }) async {
    final presetId = clientAssignedPresetId ??
        _uuid.v4().replaceAll('-', '').substring(0, 24);
    final mirrorPreview = pairedPreviewImageUrl ?? previewImageUrl;

    debugPrint(
      'DualBackendShowcaseRepository: createPreset primary start id=$presetId '
      'previewLen=${previewImageUrl.length} mirrorPreviewLen=${mirrorPreview.length}',
    );
    final primaryCreated = await _primary.createPreset(
      prompt: prompt,
      previewImageUrl: previewImageUrl,
      title: title,
      tags: tags,
      imageStyle: imageStyle,
      ownerId: ownerId,
      clientAssignedPresetId: presetId,
      pairedPreviewImageUrl: null,
    );
    debugPrint(
      'DualBackendShowcaseRepository: primary createPreset OK id=${primaryCreated.id}, '
      'запускаем зеркало во secondary (Firebase/Appwrite)',
    );
    unawaited(_mirrorCreatePreset(
      prompt: prompt,
      secondaryPreviewUrl: mirrorPreview,
      title: title,
      tags: tags,
      imageStyle: imageStyle,
      ownerId: ownerId,
      presetId: presetId,
    ));
    return primaryCreated;
  }

  Future<void> _mirrorCreatePreset({
    required String prompt,
    required String secondaryPreviewUrl,
    String? title,
    List<String>? tags,
    String? imageStyle,
    String? ownerId,
    required String presetId,
  }) async {
    try {
      debugPrint(
        'DualBackendShowcaseRepository: mirror createPreset start id=$presetId '
        'secondaryPreviewHttp=${secondaryPreviewUrl.startsWith('http')}',
      );
      await _secondary.createPreset(
        prompt: prompt,
        previewImageUrl: secondaryPreviewUrl,
        title: title,
        tags: tags,
        imageStyle: imageStyle,
        ownerId: ownerId,
        clientAssignedPresetId: presetId,
        pairedPreviewImageUrl: null,
      );
      debugPrint(
        'DualBackendShowcaseRepository: mirror createPreset завершён id=$presetId',
      );
    } catch (e, st) {
      debugPrint('DualBackendShowcaseRepository: mirror createPreset ОШИБКА $e');
      debugPrint('$st');
    }
  }

  @override
  Stream<List<PhotoSessionPreset>> watchPresets({int limit = 0}) {
    return _primary.watchPresets(limit: limit);
  }

  @override
  Future<void> toggleLike(String presetId, String deviceId) async {
    await _primary.toggleLike(presetId, deviceId);
    try {
      await _secondary.toggleLike(presetId, deviceId);
    } catch (e, st) {
      debugPrint('DualBackendShowcaseRepository: mirror toggleLike $e');
      debugPrint('$st');
    }
  }

  @override
  Future<void> updateTags(String presetId, List<String> tags) async {
    await _primary.updateTags(presetId, tags);
    try {
      await _secondary.updateTags(presetId, tags);
    } catch (e, st) {
      debugPrint('DualBackendShowcaseRepository: mirror updateTags $e');
      debugPrint('$st');
    }
  }

  @override
  Future<void> makePublic(String presetId) async {
    await _primary.makePublic(presetId);
    try {
      await _secondary.makePublic(presetId);
    } catch (e, st) {
      debugPrint('DualBackendShowcaseRepository: mirror makePublic $e');
      debugPrint('$st');
    }
  }

  @override
  Future<void> makePrivate(String presetId) async {
    await _primary.makePrivate(presetId);
    try {
      await _secondary.makePrivate(presetId);
    } catch (e, st) {
      debugPrint('DualBackendShowcaseRepository: mirror makePrivate $e');
      debugPrint('$st');
    }
  }

  @override
  Future<void> deletePreset(String presetId,
      {required String ownerDeviceId}) async {
    Object? primaryErr;
    try {
      await _primary.deletePreset(presetId, ownerDeviceId: ownerDeviceId);
    } catch (e, st) {
      debugPrint('DualBackendShowcaseRepository: primary deletePreset $e');
      debugPrint('$st');
      primaryErr = e;
    }
    try {
      await _secondary.deletePreset(presetId, ownerDeviceId: ownerDeviceId);
    } catch (e, st) {
      debugPrint('DualBackendShowcaseRepository: secondary deletePreset $e');
      debugPrint('$st');
      if (primaryErr != null) {
        throw StateError('Не удалось удалить пресет: $primaryErr | $e');
      }
    }
  }
}
