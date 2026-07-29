import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_generation.dart';
import '../services/appwrite_failover_gate.dart';
import 'user_generation_repository.dart';

class AppwriteFailoverUserGenerationRepository
    implements UserGenerationRepository {
  AppwriteFailoverUserGenerationRepository({
    required UserGenerationRepository appwrite,
    required UserGenerationRepository firebase,
  })  : _appwrite = appwrite,
        _firebase = firebase;

  final UserGenerationRepository _appwrite;
  final UserGenerationRepository _firebase;

  static AppwriteFailoverGate get _gate => AppwriteFailoverGate.instance;

  @override
  Future<List<UserGeneration>> getGenerationsByPreset(
    String presetId, {
    required String deviceId,
  }) async {
    if (_gate.shouldPreferFirebase) {
      return _firebase.getGenerationsByPreset(presetId, deviceId: deviceId);
    }
    try {
      final list = await _appwrite
          .getGenerationsByPreset(presetId, deviceId: deviceId)
          .timeout(AppwriteFailoverGate.readTimeout);
      _gate.noteSuccess();
      if (list.isNotEmpty) return list;
    } catch (e, st) {
      debugPrint('AppwriteFailoverUserGen getGenerationsByPreset: $e');
      debugPrint('$st');
      if (!_gate.noteFailureIfUnreachable(e)) rethrow;
      return _firebase.getGenerationsByPreset(presetId, deviceId: deviceId);
    }
    return _firebase.getGenerationsByPreset(presetId, deviceId: deviceId);
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
    if (_gate.shouldPreferFirebase) {
      return _firebase.createGeneration(
        presetId: presetId,
        userImageUrl: userImageUrl,
        resultImageUrl: resultImageUrl,
        deviceId: deviceId,
        referenceImageUrl: referenceImageUrl,
        clientAssignedDocumentId: clientAssignedDocumentId,
        pairedUserImageUrl: pairedUserImageUrl,
        pairedResultImageUrl: pairedResultImageUrl,
        pairedReferenceImageUrl: pairedReferenceImageUrl,
      );
    }
    try {
      final r = await _appwrite
          .createGeneration(
            presetId: presetId,
            userImageUrl: userImageUrl,
            resultImageUrl: resultImageUrl,
            deviceId: deviceId,
            referenceImageUrl: referenceImageUrl,
            clientAssignedDocumentId: clientAssignedDocumentId,
            pairedUserImageUrl: pairedUserImageUrl,
            pairedResultImageUrl: pairedResultImageUrl,
            pairedReferenceImageUrl: pairedReferenceImageUrl,
          )
          .timeout(AppwriteFailoverGate.readTimeout);
      _gate.noteSuccess();
      return r;
    } catch (e, st) {
      debugPrint('AppwriteFailoverUserGen createGeneration: $e');
      debugPrint('$st');
      if (!_gate.noteFailureIfUnreachable(e)) rethrow;
      return _firebase.createGeneration(
        presetId: presetId,
        userImageUrl: userImageUrl,
        resultImageUrl: resultImageUrl,
        deviceId: deviceId,
        referenceImageUrl: referenceImageUrl,
        clientAssignedDocumentId: clientAssignedDocumentId,
        pairedUserImageUrl: pairedUserImageUrl,
        pairedResultImageUrl: pairedResultImageUrl,
        pairedReferenceImageUrl: pairedReferenceImageUrl,
      );
    }
  }

  @override
  Stream<Set<String>> watchUsedPresetIds(String deviceId) {
    if (deviceId.isEmpty) return Stream.value(<String>{});
    if (_gate.shouldPreferFirebase) {
      return _firebase.watchUsedPresetIds(deviceId);
    }
    StreamSubscription<Set<String>>? sub;
    var switchedToFirebase = false;
    late final StreamController<Set<String>> controller;
    controller = StreamController<Set<String>>(
      sync: true,
      onListen: () {
        sub = _appwrite.watchUsedPresetIds(deviceId).listen(
          (data) {
            _gate.noteSuccess();
            if (!controller.isClosed) controller.add(data);
          },
          onError: (Object e, StackTrace st) {
            debugPrint('AppwriteFailoverUserGen watchUsedPresetIds: $e');
            debugPrint('$st');
            if (!_gate.noteFailureIfUnreachable(e)) {
              if (!controller.isClosed) controller.addError(e, st);
              return;
            }
            switchedToFirebase = true;
            sub?.cancel();
            sub = _firebase.watchUsedPresetIds(deviceId).listen(
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
  Future<bool> deleteGeneration(
    String generationId, {
    required String deviceId,
    required String presetId,
  }) async {
    if (_gate.shouldPreferFirebase) {
      return _firebase.deleteGeneration(
        generationId,
        deviceId: deviceId,
        presetId: presetId,
      );
    }
    var ok = false;
    try {
      ok = await _appwrite
          .deleteGeneration(
            generationId,
            deviceId: deviceId,
            presetId: presetId,
          )
          .timeout(AppwriteFailoverGate.readTimeout);
      _gate.noteSuccess();
    } catch (e, st) {
      debugPrint('AppwriteFailoverUserGen deleteGeneration appwrite: $e');
      debugPrint('$st');
      if (!_gate.noteFailureIfUnreachable(e)) rethrow;
      return _firebase.deleteGeneration(
        generationId,
        deviceId: deviceId,
        presetId: presetId,
      );
    }
    unawaited(_firebase.deleteGeneration(
      generationId,
      deviceId: deviceId,
      presetId: presetId,
    ));
    if (ok) return true;
    return _firebase.deleteGeneration(
      generationId,
      deviceId: deviceId,
      presetId: presetId,
    );
  }
}
