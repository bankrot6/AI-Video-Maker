import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/photo_session_preset.dart';
import '../models/preset_tag.dart';
import '../services/firebase_anonymous_auth_service.dart';
import '../services/preset_cache_service.dart';
import 'showcase_repository.dart';

class FirebaseShowcaseRepository implements ShowcaseRepository {
  FirebaseShowcaseRepository({
    FirebaseFirestore? firestore,
    String? collectionPath,
    PresetCacheService? cacheService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _collectionPath = collectionPath ?? 'presets',
        _cacheService = cacheService;

  final FirebaseFirestore _firestore;
  final String _collectionPath;
  final PresetCacheService? _cacheService;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(_collectionPath);

  Query<Map<String, dynamic>> _presetsQuery(int limit) {
    Query<Map<String, dynamic>> query = _collection.orderBy(
      'createdAt',
      descending: true,
    );
    if (limit > 0) {
      query = query.limit(limit);
    }
    return query;
  }

  List<PhotoSessionPreset> _snapshotToPresets(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final list = <PhotoSessionPreset>[];
    for (final doc in snapshot.docs) {
      final preset = _documentToPreset(doc);
      if (preset != null) {
        list.add(preset);
      } else {
        debugPrint(
          'FirebaseShowcaseRepository: пропущен документ ${doc.id} (пустой prompt или previewImageUrl)',
        );
      }
    }
    // Стабильная сортировка: по дате убыванию, потом по ID возрастанию
    list.sort((a, b) {
      final dateCompare = b.createdAt.compareTo(a.createdAt);
      if (dateCompare != 0) return dateCompare;
      return a.id.compareTo(b.id); // Для стабильности при одинаковых датах
    });
    return list;
  }

  @override
  Future<List<PhotoSessionPreset>> fetchPresetsForUiBootstrap(
      {int limit = 0}) async {
    final query = _presetsQuery(limit);
    try {
      debugPrint(
        'FirebaseShowcaseRepository: bootstrap с сервера '
        '(${limit > 0 ? "до $limit" : "все"})',
      );
      final snap =
          await query.get(const GetOptions(source: Source.server));
      final list = _snapshotToPresets(snap);
      debugPrint(
        'FirebaseShowcaseRepository: bootstrap с сервера, документов ${snap.docs.length}',
      );
      await _maybeSavePresetsToHive(list);
      return list;
    } catch (e) {
      debugPrint(
        'FirebaseShowcaseRepository: bootstrap сервер недоступен ($e), кэш Firestore',
      );
      try {
        final snap =
            await query.get(const GetOptions(source: Source.cache));
        final list = _snapshotToPresets(snap);
        await _maybeSavePresetsToHive(list);
        return list;
      } catch (e2, st) {
        debugPrint('FirebaseShowcaseRepository: ошибка bootstrap: $e2');
        debugPrint('FirebaseShowcaseRepository: $st');
        rethrow;
      }
    }
  }

  Future<void> _maybeSavePresetsToHive(List<PhotoSessionPreset> list) async {
    if (list.isEmpty) return;
    final cacheSave = _cacheService;
    if (cacheSave != null) {
      await cacheSave.savePresets(list);
    }
  }

  @override
  Future<List<PhotoSessionPreset>> getPresets({int limit = 0}) async {
    try {
      final cache = _cacheService;
      if (cache != null) {
        final cached = await cache.getPresets();
        if (cached != null && cached.isNotEmpty) {
          final cachedList = limit > 0 ? cached.take(limit).toList() : cached;
          debugPrint(
            'FirebaseShowcaseRepository: возврат ${cachedList.length} пресетов из кэша',
          );
          return cachedList;
        }
      }

      debugPrint(
        'FirebaseShowcaseRepository: загрузка ${limit > 0 ? 'до $limit' : 'всех'} пресетов из Firestore',
      );
      final querySnapshot = await _presetsQuery(limit).get();

      debugPrint(
        'FirebaseShowcaseRepository: получено ${querySnapshot.docs.length} документов',
      );

      final list = _snapshotToPresets(querySnapshot);

      if (list.isNotEmpty) {
        debugPrint(
          'FirebaseShowcaseRepository: загружено ${list.length} пресетов',
        );
        await _maybeSavePresetsToHive(list);
      }

      return list;
    } catch (e, st) {
      debugPrint('FirebaseShowcaseRepository: ошибка getPresets: $e');
      debugPrint('FirebaseShowcaseRepository: $st');
      return [];
    }
  }

  @override
  Future<PhotoSessionPreset?> getPresetById(String id) async {
    if (id.isEmpty) {
      return null;
    }
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) {
        return null;
      }
      return _documentToPreset(doc);
    } catch (e) {
      debugPrint('FirebaseShowcaseRepository: ошибка getPresetById: $e');
      return null;
    }
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
    assert(
      pairedPreviewImageUrl == null ||
          pairedPreviewImageUrl.startsWith('http://') ||
          pairedPreviewImageUrl.startsWith('https://'),
    );
    try {
      await FirebaseAnonymousAuthService.instance.ensureSignedIn();

      final tagList = tags ?? [];
      final uid = FirebaseAnonymousAuthService.instance.uid;
      final docRef = (clientAssignedPresetId != null &&
              clientAssignedPresetId.isNotEmpty)
          ? _collection.doc(clientAssignedPresetId)
          : _collection.doc();

      final data = {
        'prompt': prompt,
        'previewImageUrl': previewImageUrl,
        if (title != null && title.isNotEmpty) 'title': title,
        if (tagList.isNotEmpty) 'tags': tagList,
        if (imageStyle != null && imageStyle.isNotEmpty) 'imageStyle': imageStyle,
        'createdAt': DateTime.now().toIso8601String(),
        if (ownerId != null && ownerId.isNotEmpty) 'ownerId': ownerId,
        if (uid != null && uid.isNotEmpty) 'firebaseOwnerUid': uid,
        'isPublic': true,
        'likesCount': 0,
        'likedBy': [],
      };

      await docRef.set(data);

      debugPrint(
          'FirebaseShowcaseRepository: пресет создан успешно, ID=${docRef.id}');

      return PhotoSessionPreset(
        id: docRef.id,
        prompt: prompt,
        previewImageUrl: previewImageUrl,
        title: title,
        tags: tagList,
        imageStyle: imageStyle,
        createdAt: DateTime.now(),
        ownerId: ownerId,
      );
    } catch (e, st) {
      debugPrint('FirebaseShowcaseRepository: ошибка createPreset: $e');
      debugPrint('FirebaseShowcaseRepository: $st');
      throw StateError('Не удалось создать пресет: $e');
    }
  }

  @override
  Stream<List<PhotoSessionPreset>> streamPresetsBootstrap() async* {
    yield await fetchPresetsForUiBootstrap();
  }

  @override
  Stream<List<PhotoSessionPreset>> watchPresets({int limit = 0}) {
    final query = _presetsQuery(limit);
    return query.snapshots(includeMetadataChanges: true).where((snapshot) {
      return !snapshot.metadata.isFromCache;
    }).map(_snapshotToPresets);
  }

  @override
  Future<void> toggleLike(String presetId, String deviceId) async {
    try {
      await FirebaseAnonymousAuthService.instance.ensureSignedIn();

      final docRef = _collection.doc(presetId);
      final doc = await docRef.get();

      if (!doc.exists) {
        debugPrint('FirebaseShowcaseRepository: пресет $presetId не найден');
        return;
      }

      final data = doc.data();
      if (data == null) return;

      final likedByRaw = data['likedBy'];
      final likedBy = <String>[];
      if (likedByRaw is List) {
        for (final e in likedByRaw) {
          if (e is String) likedBy.add(e);
        }
      }

      final isLiked = likedBy.contains(deviceId);
      if (isLiked) {
        likedBy.remove(deviceId);
      } else {
        likedBy.add(deviceId);
      }

      await docRef.update({
        'likedBy': likedBy,
        'likesCount': likedBy.length,
      });

      debugPrint(
          'FirebaseShowcaseRepository: лайк ${isLiked ? "удален" : "добавлен"} для пресета $presetId');
    } catch (e, st) {
      debugPrint('FirebaseShowcaseRepository: ошибка toggleLike: $e');
      debugPrint('FirebaseShowcaseRepository: $st');
      rethrow;
    }
  }

  @override
  Future<void> updateTags(String presetId, List<String> tags) async {
    try {
      await FirebaseAnonymousAuthService.instance.ensureSignedIn();
      await _collection.doc(presetId).update({'tags': tags});
      debugPrint(
          'FirebaseShowcaseRepository: теги пресета $presetId обновлены: ${tags.join(", ")}');
    } catch (e, st) {
      debugPrint('FirebaseShowcaseRepository: ошибка updateTags: $e');
      debugPrint('FirebaseShowcaseRepository: $st');
      rethrow;
    }
  }

  @override
  Future<void> makePublic(String presetId) async {
    try {
      await FirebaseAnonymousAuthService.instance.ensureSignedIn();
      await _collection.doc(presetId).update({'isPublic': true});
      debugPrint(
          'FirebaseShowcaseRepository: пресет $presetId сделан публичным');
    } catch (e, st) {
      debugPrint('FirebaseShowcaseRepository: ошибка makePublic: $e');
      debugPrint('FirebaseShowcaseRepository: $st');
      rethrow;
    }
  }

  @override
  Future<void> makePrivate(String presetId) async {
    try {
      await FirebaseAnonymousAuthService.instance.ensureSignedIn();
      await _collection.doc(presetId).update({'isPublic': false});
      debugPrint(
          'FirebaseShowcaseRepository: пресет $presetId сделан приватным');
    } catch (e, st) {
      debugPrint('FirebaseShowcaseRepository: ошибка makePrivate: $e');
      debugPrint('FirebaseShowcaseRepository: $st');
      rethrow;
    }
  }

  @override
  Future<void> deletePreset(String presetId,
      {required String ownerDeviceId}) async {
    try {
      if (presetId.isEmpty || ownerDeviceId.isEmpty) {
        throw StateError('Некорректные параметры удаления');
      }
      await FirebaseAnonymousAuthService.instance.ensureSignedIn();
      final docRef = _collection.doc(presetId);
      final doc = await docRef.get();
      if (!doc.exists) {
        await _cacheService?.clear();
        return;
      }
      final data = doc.data();
      if (data == null) return;
      final ownerId = data['ownerId'] as String? ?? '';
      if (ownerId != ownerDeviceId) {
        throw StateError('Нет прав на удаление пресета');
      }
      final tags = _parseTags(data['tags']);
      if (!tags.contains(PresetTag.idCustom)) {
        throw StateError('Удалять можно только пользовательские пресеты');
      }
      await docRef.delete();
      await _cacheService?.clear();
      debugPrint('FirebaseShowcaseRepository: пресет $presetId удалён');
    } catch (e, st) {
      debugPrint('FirebaseShowcaseRepository: ошибка deletePreset: $e');
      debugPrint('FirebaseShowcaseRepository: $st');
      rethrow;
    }
  }

  PhotoSessionPreset? _documentToPreset(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final data = doc.data();
      if (data == null) return null;

      final prompt = data['prompt'] as String? ?? '';
      final previewImageUrl = data['previewImageUrl'] as String? ?? '';

      if (prompt.isEmpty || previewImageUrl.isEmpty) return null;

      final thumbnailUrl = data['thumbnailUrl'] as String?;
      final title = data['title'] as String?;
      final tags = _parseTags(data['tags']);
      final imageStyle = data['imageStyle'] as String?;
      final ownerId = data['ownerId'] as String?;
      final createdAtStr = data['createdAt'] as String?;
      final createdAt = createdAtStr != null
          ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
          : DateTime.now();
      final isPublic = data['isPublic'] as bool? ?? false;
      final likesCount = _readIntField(data['likesCount'], 0);
      final likedBy = _parseLikedBy(data['likedBy']);

      return PhotoSessionPreset(
        id: doc.id,
        prompt: prompt,
        previewImageUrl: previewImageUrl,
        thumbnailUrl: thumbnailUrl?.isNotEmpty == true ? thumbnailUrl : null,
        title: title?.isNotEmpty == true ? title : null,
        tags: tags,
        imageStyle: imageStyle?.isNotEmpty == true ? imageStyle : null,
        createdAt: createdAt,
        ownerId: ownerId?.isNotEmpty == true ? ownerId : null,
        isPublic: isPublic,
        likesCount: likesCount,
        likedBy: likedBy,
      );
    } catch (e) {
      debugPrint('FirebaseShowcaseRepository: ошибка парсинга документа: $e');
      return null;
    }
  }

  static List<String> _parseTags(dynamic raw) {
    final list = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String && e.isNotEmpty) list.add(e);
      }
    }
    return list;
  }

  static List<String> _parseLikedBy(dynamic raw) {
    final list = <String>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is String && e.isNotEmpty) list.add(e);
      }
    }
    return list;
  }

  static int _readIntField(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }
}
