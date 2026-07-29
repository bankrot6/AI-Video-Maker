import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_generation.dart';
import '../services/firebase_anonymous_auth_service.dart';
import 'user_generation_repository.dart';

class FirebaseUserGenerationRepository implements UserGenerationRepository {
  FirebaseUserGenerationRepository({
    FirebaseFirestore? firestore,
    String? collectionPath,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _collectionPath = collectionPath ?? 'user_generations';

  final FirebaseFirestore _firestore;
  final String _collectionPath;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(_collectionPath);

  @override
  Future<List<UserGeneration>> getGenerationsByPreset(
    String presetId, {
    required String deviceId,
  }) async {
    try {
      debugPrint('FirebaseUserGenerationRepo: загрузка для preset=$presetId deviceId=${deviceId.substring(0, 8)}...');

      final uid = FirebaseAnonymousAuthService.instance.uid;

      final byDevice = await _collection
          .where('deviceId', isEqualTo: deviceId)
          .get();

      QuerySnapshot<Map<String, dynamic>>? byUid;
      if (uid != null && uid.isNotEmpty) {
        byUid = await _collection.where('firebaseUid', isEqualTo: uid).get();
      }

      final merged = <String, Map<String, dynamic>>{};
      for (final doc in byDevice.docs) {
        merged[doc.id] = {...doc.data(), 'id': doc.id};
      }
      if (byUid != null) {
        for (final doc in byUid.docs) {
          merged[doc.id] = {...doc.data(), 'id': doc.id};
        }
      }

      debugPrint(
        'FirebaseUserGenerationRepo: слито документов по deviceId+uid: ${merged.length}',
      );

      final generations = merged.values
          .map(UserGeneration.fromJson)
          .where((gen) => gen.presetId == presetId)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      debugPrint('FirebaseUserGenerationRepo: для preset=$presetId найдено ${generations.length} генераций');
      return generations;
    } catch (e, st) {
      debugPrint('FirebaseUserGenerationRepo: ошибка $e');
      debugPrint('FirebaseUserGenerationRepo: стек $st');
      return [];
    }
  }

  @override
  Stream<Set<String>> watchUsedPresetIds(String deviceId) {
    if (deviceId.isEmpty) return Stream.value(<String>{});
    return _collection
        .where('deviceId', isEqualTo: deviceId)
        .snapshots()
        .map((snapshot) {
          final ids = snapshot.docs
              .map((doc) => doc.data()['presetId'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
          debugPrint('watchUsedPresetIds: найдено ${ids.length} использованных пресетов для устройства');
          return ids;
        })
        .handleError((Object e) {
          debugPrint('watchUsedPresetIds: ошибка stream: $e');
          return <String>{};
        });
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
    assert(
      pairedResultImageUrl == null ||
          pairedResultImageUrl.startsWith('http://') ||
          pairedResultImageUrl.startsWith('https://'),
    );
    assert(
      pairedReferenceImageUrl == null ||
          pairedReferenceImageUrl.startsWith('http://') ||
          pairedReferenceImageUrl.startsWith('https://'),
    );
    try {
      await FirebaseAnonymousAuthService.instance.ensureSignedIn();

      final docId = (clientAssignedDocumentId != null &&
              clientAssignedDocumentId.isNotEmpty)
          ? clientAssignedDocumentId
          : 'gen_${DateTime.now().millisecondsSinceEpoch}';
      debugPrint('FirebaseUserGenerationRepo: создание $docId для preset=$presetId, auth uid=${FirebaseAnonymousAuthService.instance.uid}');

      final uid = FirebaseAnonymousAuthService.instance.uid;
      final data = <String, dynamic>{
        'presetId': presetId,
        'userImageUrl': userImageUrl,
        'resultImageUrl': resultImageUrl,
        'deviceId': deviceId,
        'createdAt': DateTime.now().toIso8601String(),
        if (uid != null && uid.isNotEmpty) 'firebaseUid': uid,
        'accountKeyDeviceId': deviceId,
      };
      if (referenceImageUrl != null && referenceImageUrl.isNotEmpty) {
        data['referenceImageUrl'] = referenceImageUrl;
      }

      await _collection.doc(docId).set(data);

      debugPrint('FirebaseUserGenerationRepo: создано успешно, ID=$docId');
      
      data['id'] = docId;
      return UserGeneration.fromJson(data);
    } catch (e, st) {
      debugPrint('FirebaseUserGenerationRepo: ОШИБКА создания генерации: $e');
      debugPrint('FirebaseUserGenerationRepo: стек $st');
      return null;
    }
  }

  @override
  Future<bool> deleteGeneration(
    String generationId, {
    required String deviceId,
    required String presetId,
  }) async {
    if (generationId.isEmpty || deviceId.isEmpty || presetId.isEmpty) {
      return false;
    }
    try {
      await FirebaseAnonymousAuthService.instance.ensureSignedIn();
      final snap = await _collection.doc(generationId).get();
      if (!snap.exists) return true;
      final data = snap.data();
      if (data == null) return true;
      if (data['presetId'] != presetId || data['deviceId'] != deviceId) {
        debugPrint('FirebaseUserGenerationRepo: deleteGeneration — нет доступа');
        return false;
      }
      await _collection.doc(generationId).delete();
      debugPrint('FirebaseUserGenerationRepo: удалено $generationId');
      return true;
    } catch (e, st) {
      debugPrint('FirebaseUserGenerationRepo: deleteGeneration $e');
      debugPrint('$st');
      return false;
    }
  }
}
