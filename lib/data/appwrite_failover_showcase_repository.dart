import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/photo_session_preset.dart';
import '../services/appwrite_failover_gate.dart';
import 'showcase_repository.dart';

class AppwriteFailoverShowcaseRepository implements ShowcaseRepository {
  AppwriteFailoverShowcaseRepository({
    required ShowcaseRepository appwrite,
    required ShowcaseRepository firebase,
  })  : _appwrite = appwrite,
        _firebase = firebase;

  final ShowcaseRepository _appwrite;
  final ShowcaseRepository _firebase;

  static AppwriteFailoverGate get _gate => AppwriteFailoverGate.instance;

  Future<T> _read<T>(Future<T> Function() aw, Future<T> Function() fb) async {
    if (_gate.shouldPreferFirebase) {
      return fb();
    }
    try {
      final r = await aw().timeout(AppwriteFailoverGate.readTimeout);
      _gate.noteSuccess();
      return r;
    } catch (e, st) {
      debugPrint('AppwriteFailoverShowcaseRepository read: $e');
      debugPrint('$st');
      if (!_gate.noteFailureIfUnreachable(e)) rethrow;
      return fb();
    }
  }

  Future<void> _writeVoid(
    Future<void> Function() aw,
    Future<void> Function() fb,
  ) async {
    if (_gate.shouldPreferFirebase) {
      await fb();
      return;
    }
    try {
      await aw().timeout(AppwriteFailoverGate.readTimeout);
      _gate.noteSuccess();
    } catch (e, st) {
      debugPrint('AppwriteFailoverShowcaseRepository write: $e');
      debugPrint('$st');
      if (!_gate.noteFailureIfUnreachable(e)) rethrow;
      await fb();
    }
  }

  @override
  Future<List<PhotoSessionPreset>> getPresets({int limit = 0}) {
    return _read(
      () => _appwrite.getPresets(limit: limit),
      () => _firebase.getPresets(limit: limit),
    );
  }

  @override
  Future<List<PhotoSessionPreset>> fetchPresetsForUiBootstrap({int limit = 0}) {
    return _read(
      () => _appwrite.fetchPresetsForUiBootstrap(limit: limit),
      () => _firebase.fetchPresetsForUiBootstrap(limit: limit),
    );
  }

  @override
  Stream<List<PhotoSessionPreset>> streamPresetsBootstrap() async* {
    yield await fetchPresetsForUiBootstrap();
  }

  @override
  Future<PhotoSessionPreset?> getPresetById(String id) async {
    if (_gate.shouldPreferFirebase) {
      return _firebase.getPresetById(id);
    }
    try {
      final r = await _appwrite
          .getPresetById(id)
          .timeout(AppwriteFailoverGate.readTimeout);
      _gate.noteSuccess();
      if (r != null) return r;
    } catch (e, st) {
      debugPrint('AppwriteFailoverShowcaseRepository getPresetById: $e');
      debugPrint('$st');
      if (!_gate.noteFailureIfUnreachable(e)) rethrow;
    }
    return _firebase.getPresetById(id);
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
    if (_gate.shouldPreferFirebase) {
      return _firebase.createPreset(
        prompt: prompt,
        previewImageUrl: previewImageUrl,
        title: title,
        tags: tags,
        imageStyle: imageStyle,
        ownerId: ownerId,
        clientAssignedPresetId: clientAssignedPresetId,
        pairedPreviewImageUrl: pairedPreviewImageUrl,
      );
    }
    try {
      final r = await _appwrite
          .createPreset(
            prompt: prompt,
            previewImageUrl: previewImageUrl,
            title: title,
            tags: tags,
            imageStyle: imageStyle,
            ownerId: ownerId,
            clientAssignedPresetId: clientAssignedPresetId,
            pairedPreviewImageUrl: pairedPreviewImageUrl,
          )
          .timeout(AppwriteFailoverGate.readTimeout);
      _gate.noteSuccess();
      return r;
    } catch (e, st) {
      debugPrint('AppwriteFailoverShowcaseRepository createPreset: $e');
      debugPrint('$st');
      if (!_gate.noteFailureIfUnreachable(e)) rethrow;
      return _firebase.createPreset(
        prompt: prompt,
        previewImageUrl: previewImageUrl,
        title: title,
        tags: tags,
        imageStyle: imageStyle,
        ownerId: ownerId,
        clientAssignedPresetId: clientAssignedPresetId,
        pairedPreviewImageUrl: pairedPreviewImageUrl,
      );
    }
  }

  @override
  Stream<List<PhotoSessionPreset>> watchPresets({int limit = 0}) {
    if (_gate.shouldPreferFirebase) {
      return _firebase.watchPresets(limit: limit);
    }
    StreamSubscription<List<PhotoSessionPreset>>? sub;
    var switchedToFirebase = false;
    late final StreamController<List<PhotoSessionPreset>> controller;
    controller = StreamController<List<PhotoSessionPreset>>(
      onListen: () {
        sub = _appwrite.watchPresets(limit: limit).listen(
          (data) {
            _gate.noteSuccess();
            if (!controller.isClosed) controller.add(data);
          },
          onError: (Object e, StackTrace st) {
            debugPrint('AppwriteFailoverShowcaseRepository watchPresets: $e');
            debugPrint('$st');
            if (!_gate.noteFailureIfUnreachable(e)) {
              if (!controller.isClosed) controller.addError(e, st);
              return;
            }
            switchedToFirebase = true;
            sub?.cancel();
            sub = _firebase.watchPresets(limit: limit).listen(
              (data) {
                if (!controller.isClosed) controller.add(data);
              },
              onError: controller.addError,
              onDone: () {
                if (!controller.isClosed) controller.close();
              },
            );
          },
          onDone: () {
            if (switchedToFirebase) return;
            if (!controller.isClosed) controller.close();
          },
        );
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> toggleLike(String presetId, String deviceId) {
    return _writeVoid(
      () => _appwrite.toggleLike(presetId, deviceId),
      () => _firebase.toggleLike(presetId, deviceId),
    );
  }

  @override
  Future<void> updateTags(String presetId, List<String> tags) {
    return _writeVoid(
      () => _appwrite.updateTags(presetId, tags),
      () => _firebase.updateTags(presetId, tags),
    );
  }

  @override
  Future<void> makePublic(String presetId) {
    return _writeVoid(
      () => _appwrite.makePublic(presetId),
      () => _firebase.makePublic(presetId),
    );
  }

  @override
  Future<void> makePrivate(String presetId) {
    return _writeVoid(
      () => _appwrite.makePrivate(presetId),
      () => _firebase.makePrivate(presetId),
    );
  }

  @override
  Future<void> deletePreset(String presetId,
      {required String ownerDeviceId}) async {
    Object? appwriteError;
    try {
      await _appwrite.deletePreset(presetId, ownerDeviceId: ownerDeviceId);
    } catch (e, st) {
      debugPrint('AppwriteFailoverShowcaseRepository deletePreset appwrite: $e');
      debugPrint('$st');
      appwriteError = e;
    }
    try {
      await _firebase.deletePreset(presetId, ownerDeviceId: ownerDeviceId);
    } catch (e, st) {
      debugPrint('AppwriteFailoverShowcaseRepository deletePreset firebase: $e');
      debugPrint('$st');
      if (appwriteError != null) {
        Error.throwWithStackTrace(e, st);
      }
    }
  }
}
