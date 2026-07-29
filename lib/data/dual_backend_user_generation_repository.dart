import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_generation.dart';
import 'user_generation_repository.dart';

class DualBackendUserGenerationRepository implements UserGenerationRepository {
  DualBackendUserGenerationRepository({
    required UserGenerationRepository primary,
    required UserGenerationRepository secondary,
  })  : _primary = primary,
        _secondary = secondary;

  final UserGenerationRepository _primary;
  final UserGenerationRepository _secondary;

  @override
  Future<List<UserGeneration>> getGenerationsByPreset(
    String presetId, {
    required String deviceId,
  }) async {
    try {
      final list =
          await _primary.getGenerationsByPreset(presetId, deviceId: deviceId);
      if (list.isNotEmpty) return list;
    } catch (e, st) {
      debugPrint('DualBackendUserGen: primary getGenerationsByPreset $e');
      debugPrint('$st');
    }
    return _secondary.getGenerationsByPreset(presetId, deviceId: deviceId);
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
    final docId = clientAssignedDocumentId ??
        'gen_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint(
      'DualBackendUserGen: createGeneration primary docId=$docId preset=$presetId '
      'resultHttp=${resultImageUrl.startsWith('http')}',
    );
    final primaryGen = await _primary.createGeneration(
      presetId: presetId,
      userImageUrl: userImageUrl,
      resultImageUrl: resultImageUrl,
      deviceId: deviceId,
      referenceImageUrl: referenceImageUrl,
      clientAssignedDocumentId: docId,
      pairedUserImageUrl: null,
      pairedResultImageUrl: null,
      pairedReferenceImageUrl: null,
    );
    debugPrint(
      'DualBackendUserGen: primary OK id=$docId, зеркало в secondary (Firebase/Appwrite)',
    );
    unawaited(_mirrorCreateGeneration(
      presetId: presetId,
      userImageUrl: pairedUserImageUrl ?? userImageUrl,
      resultImageUrl: pairedResultImageUrl ?? resultImageUrl,
      deviceId: deviceId,
      referenceImageUrl: pairedReferenceImageUrl ?? referenceImageUrl,
      docId: docId,
    ));
    return primaryGen;
  }

  Future<void> _mirrorCreateGeneration({
    required String presetId,
    required String userImageUrl,
    required String resultImageUrl,
    required String deviceId,
    String? referenceImageUrl,
    required String docId,
  }) async {
    try {
      debugPrint(
        'DualBackendUserGen: mirror createGeneration start docId=$docId '
        'resultHttp=${resultImageUrl.startsWith('http')}',
      );
      await _secondary.createGeneration(
        presetId: presetId,
        userImageUrl: userImageUrl,
        resultImageUrl: resultImageUrl,
        deviceId: deviceId,
        referenceImageUrl: referenceImageUrl,
        clientAssignedDocumentId: docId,
        pairedUserImageUrl: null,
        pairedResultImageUrl: null,
        pairedReferenceImageUrl: null,
      );
      debugPrint(
        'DualBackendUserGen: mirror createGeneration завершён docId=$docId',
      );
    } catch (e, st) {
      debugPrint('DualBackendUserGen: mirror createGeneration ОШИБКА $e');
      debugPrint('$st');
    }
  }

  @override
  Stream<Set<String>> watchUsedPresetIds(String deviceId) {
    if (deviceId.isEmpty) return Stream.value(<String>{});

    StreamSubscription<Set<String>>? sub1;
    StreamSubscription<Set<String>>? sub2;
    var a = <String>{};
    var b = <String>{};
    final ctrls = <StreamController<Set<String>>>[];

    void emit() {
      if (ctrls.isEmpty) return;
      final c = ctrls.first;
      if (c.isClosed) return;
      c.add({...a, ...b});
    }

    final controller = StreamController<Set<String>>(
      sync: true,
      onListen: () {
        sub1 = _primary.watchUsedPresetIds(deviceId).listen(
          (v) {
            a = v;
            emit();
          },
          onError: (Object e, StackTrace st) {
            debugPrint('DualBackendUserGen: primary watchUsedPresetIds $e');
            debugPrint('$st');
            a = {};
            emit();
          },
        );
        sub2 = _secondary.watchUsedPresetIds(deviceId).listen(
          (v) {
            b = v;
            emit();
          },
          onError: (Object e, StackTrace st) {
            debugPrint('DualBackendUserGen: secondary watchUsedPresetIds $e');
            debugPrint('$st');
            b = {};
            emit();
          },
        );
      },
      onCancel: () async {
        await sub1?.cancel();
        await sub2?.cancel();
      },
    );
    ctrls.add(controller);

    return controller.stream;
  }

  @override
  Future<bool> deleteGeneration(
    String generationId, {
    required String deviceId,
    required String presetId,
  }) async {
    var ok = false;
    try {
      ok = await _primary.deleteGeneration(
        generationId,
        deviceId: deviceId,
        presetId: presetId,
      );
    } catch (e, st) {
      debugPrint('DualBackendUserGen: primary deleteGeneration $e');
      debugPrint('$st');
    }
    unawaited(_mirrorDeleteGeneration(
      generationId,
      deviceId: deviceId,
      presetId: presetId,
    ));
    if (ok) return true;
    try {
      return await _secondary.deleteGeneration(
        generationId,
        deviceId: deviceId,
        presetId: presetId,
      );
    } catch (e, st) {
      debugPrint('DualBackendUserGen: secondary deleteGeneration $e');
      debugPrint('$st');
      return false;
    }
  }

  Future<void> _mirrorDeleteGeneration(
    String generationId, {
    required String deviceId,
    required String presetId,
  }) async {
    try {
      await _secondary.deleteGeneration(
        generationId,
        deviceId: deviceId,
        presetId: presetId,
      );
    } catch (e, st) {
      debugPrint('DualBackendUserGen: mirror deleteGeneration $e');
      debugPrint('$st');
    }
  }
}
