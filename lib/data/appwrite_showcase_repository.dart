import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/photo_session_preset.dart';
import '../models/preset_tag.dart';
import '../services/appwrite_auth_service.dart';
import '../services/preset_cache_service.dart';
import 'showcase_repository.dart';

class AppwriteShowcaseRepository implements ShowcaseRepository {
  AppwriteShowcaseRepository({
    Client? client,
    String? endpoint,
    String? projectId,
    String? databaseId,
    String? collectionId,
    PresetCacheService? cacheService,
  })  : _client = client ?? _createClient(endpoint, projectId),
        _databaseId =
            databaseId ?? dotenv.env['APPWRITE_DATABASE_ID'] ?? '',
        _collectionId =
            collectionId ?? dotenv.env['APPWRITE_PRESETS_COLLECTION_ID'] ?? '',
        _cacheService = cacheService;

  static Client _createClient(String? endpoint, String? projectId) {
    return Client()
        .setEndpoint((endpoint ?? dotenv.env['APPWRITE_ENDPOINT'] ?? '').trim())
        .setProject((projectId ?? dotenv.env['APPWRITE_PROJECT_ID'] ?? '').trim());
  }

  final Client _client;
  final String _databaseId;
  final String _collectionId;
  final PresetCacheService? _cacheService;
  AppwriteAuthService get _auth => AppwriteAuthService.instance;
  Databases? _databases;
  Databases? _sessionDatabases;

  Databases get _db => _databases ??= Databases(_client);
  Databases? get _sessionDb {
    final client = _auth.sessionClient;
    if (client == null) return null;
    return _sessionDatabases ??= Databases(client);
  }

  List<String> _queriesForList(int limit, {int offset = 0}) {
    final q = <String>[Query.orderDesc('createdAt')];
    if (limit > 0) q.add(Query.limit(limit));
    if (offset > 0) q.add(Query.offset(offset));
    return q;
  }

  @override
  Future<List<PhotoSessionPreset>> fetchPresetsForUiBootstrap(
      {int limit = 0}) async {
    if (_databaseId.isEmpty || _collectionId.isEmpty) return [];
    try {
      debugPrint(
        'AppwriteShowcaseRepository: bootstrap с сервера '
        '(${limit > 0 ? "до $limit" : "все"})',
      );
      final list = await _fetchAllPages(limit > 0 ? limit : 500);
      debugPrint(
        'AppwriteShowcaseRepository: bootstrap, документов ${list.length}',
      );
      final cacheSave = _cacheService;
      if (cacheSave != null && list.isNotEmpty && limit == 0) {
        await cacheSave.savePresets(list);
      }
      return list;
    } catch (e, st) {
      debugPrint('AppwriteShowcaseRepository: ошибка bootstrap: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  @override
  Future<List<PhotoSessionPreset>> getPresets({int limit = 0}) async {
    if (_databaseId.isEmpty || _collectionId.isEmpty) {
      debugPrint(
        'AppwriteShowcaseRepository: APPWRITE_DATABASE_ID или коллекция пусты.',
      );
      return [];
    }

    final cache = _cacheService;
    if (cache != null) {
      final cached = await cache.getPresets();
      if (cached != null && cached.isNotEmpty) {
        final cachedList = limit > 0 ? cached.take(limit).toList() : cached;
        debugPrint(
          'AppwriteShowcaseRepository: возврат ${cachedList.length} из кэша',
        );
        return cachedList;
      }
    }

    final list = await _fetchAllPages(limit > 0 ? limit : 500);
    if (list.isNotEmpty) {
      debugPrint('AppwriteShowcaseRepository: загружено ${list.length} пресетов');
      final cacheSave = _cacheService;
      if (cacheSave != null) {
        await cacheSave.savePresets(list);
      }
    }
    return list;
  }

  Future<List<PhotoSessionPreset>> _fetchAllPages(int limit) async {
    const pageSize = 100;
    final all = <PhotoSessionPreset>[];
    var offset = 0;

    while (true) {
      final effectivePage =
          (limit > 0 && limit - all.length < pageSize) ? limit - all.length : pageSize;
      try {
        final result = await _db.listDocuments(
          databaseId: _databaseId,
          collectionId: _collectionId,
          queries: _queriesForList(effectivePage, offset: offset),
        );
        final page = result.documents
            .map(_documentToPreset)
            .whereType<PhotoSessionPreset>()
            .toList();
        all.addAll(page);
        if (page.length < effectivePage) break;
        offset += effectivePage;
        if (limit > 0 && all.length >= limit) break;
      } catch (e, st) {
        debugPrint('AppwriteShowcaseRepository: _fetchAllPages $e');
        debugPrint('$st');
        break;
      }
    }

    all.sort((a, b) {
      final d = b.createdAt.compareTo(a.createdAt);
      if (d != 0) return d;
      return a.id.compareTo(b.id);
    });

    return (limit > 0 && all.length > limit) ? all.take(limit).toList() : all;
  }

  @override
  Stream<List<PhotoSessionPreset>> streamPresetsBootstrap() async* {
    if (_databaseId.isEmpty || _collectionId.isEmpty) return;

    const pageSize = 100;
    final accumulated = <PhotoSessionPreset>[];
    var offset = 0;

    try {
      while (true) {
        final result = await _db.listDocuments(
          databaseId: _databaseId,
          collectionId: _collectionId,
          queries: _queriesForList(pageSize, offset: offset),
        );
        final page = result.documents
            .map(_documentToPreset)
            .whereType<PhotoSessionPreset>()
            .toList();
        if (page.isEmpty) break;

        accumulated.addAll(page);
        accumulated.sort((a, b) {
          final d = b.createdAt.compareTo(a.createdAt);
          if (d != 0) return d;
          return a.id.compareTo(b.id);
        });
        yield List.unmodifiable(accumulated);

        if (page.length < pageSize) break;
        offset += pageSize;
      }
    } catch (e, st) {
      debugPrint('AppwriteShowcaseRepository: streamBootstrap $e');
      debugPrint('$st');
      if (accumulated.isNotEmpty) yield List.unmodifiable(accumulated);
    }
  }

  @override
  Future<PhotoSessionPreset?> getPresetById(String id) async {
    if (_databaseId.isEmpty || _collectionId.isEmpty || id.isEmpty) {
      return null;
    }
    try {
      final doc = await _db.getDocument(
        databaseId: _databaseId,
        collectionId: _collectionId,
        documentId: id,
      );
      return _documentToPreset(doc);
    } catch (_) {
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
    String? thumbnailUrl,
  }) async {
    assert(
      pairedPreviewImageUrl == null ||
          pairedPreviewImageUrl.startsWith('http://') ||
          pairedPreviewImageUrl.startsWith('https://'),
    );
    if (_databaseId.isEmpty || _collectionId.isEmpty) {
      throw StateError('Appwrite database or collection id not configured');
    }
    final tagList = tags ?? [];
    final docId = (clientAssignedPresetId != null && clientAssignedPresetId.isNotEmpty)
        ? clientAssignedPresetId
        : 'unique()';
    await _auth.ensureSession();
    final userId = _auth.userId;
    final sessionDb = _sessionDb;
    final db = sessionDb ?? _db;
    final permissions = userId != null && userId.isNotEmpty
        ? <String>[
            Permission.read(Role.any()),
            Permission.update(Role.user(userId)),
            Permission.delete(Role.user(userId)),
          ]
        : <String>[Permission.read(Role.any())];

    final data = <String, dynamic>{
      'prompt': prompt,
      'previewImageUrl': previewImageUrl,
      if (title != null && title.isNotEmpty) 'title': title,
      if (tagList.isNotEmpty) 'tags': tagList,
      if (imageStyle != null && imageStyle.isNotEmpty) 'imageStyle': imageStyle,
      'createdAt': DateTime.now().toIso8601String(),
      if (ownerId != null && ownerId.isNotEmpty) 'ownerId': ownerId,
      'isPublic': true,
      'likesCount': 0,
      'likedBy': <String>[],
    };
    final thumbnailData = thumbnailUrl != null && thumbnailUrl.isNotEmpty
        ? <String, dynamic>{
            'thumbnailUrl': thumbnailUrl,
            'thumbnailSourceUrl': previewImageUrl,
          }
        : const <String, dynamic>{};

    Future<Document> create(Map<String, dynamic> payload) => db.createDocument(
          databaseId: _databaseId,
          collectionId: _collectionId,
          documentId: docId,
          data: payload,
          permissions: permissions,
        );

    try {
      Document doc;
      try {
        doc = await create({...data, ...thumbnailData});
      } on AppwriteException catch (e) {
        // Коллекции старых окружений могут не знать полей обложки — пресет
        // важнее её, поэтому повтор идёт без них.
        if (thumbnailData.isEmpty || !_isUnknownAttribute(e)) rethrow;
        debugPrint('AppwriteShowcaseRepository: нет полей обложки, '
            'создаём пресет без них: ${e.message}');
        doc = await create(data);
      }
      final preset = _documentToPreset(doc);
      if (preset != null) return preset;
    } catch (e, st) {
      debugPrint('AppwriteShowcaseRepository: createPreset $e');
      debugPrint('$st');
    }
    throw StateError('Не удалось создать пресет');
  }

  static bool _isUnknownAttribute(AppwriteException e) =>
      (e.message ?? '').toLowerCase().contains('unknown attribute');

  @override
  Stream<List<PhotoSessionPreset>> watchPresets({int limit = 0}) async* {
    if (_databaseId.isEmpty || _collectionId.isEmpty) {
      yield <PhotoSessionPreset>[];
      return;
    }
    final effLimit = limit > 0 ? limit : 500;

    Future<List<PhotoSessionPreset>> load() => _fetchAllPages(effLimit);

    yield await load();
    final channel =
        'databases.$_databaseId.collections.$_collectionId.documents';
    final realtime = Realtime(_client);
    final sub = realtime.subscribe([channel]);
    await for (final _ in sub.stream) {
      yield await load();
    }
  }

  @override
  Future<void> toggleLike(String presetId, String deviceId) async {
    final doc = await _db.getDocument(
      databaseId: _databaseId,
      collectionId: _collectionId,
      documentId: presetId,
    );
    final likedBy = _parseLikedBy(doc.data['likedBy']);
    final isLiked = likedBy.contains(deviceId);
    if (isLiked) {
      likedBy.remove(deviceId);
    } else {
      likedBy.add(deviceId);
    }
    await _db.updateDocument(
      databaseId: _databaseId,
      collectionId: _collectionId,
      documentId: presetId,
      data: {
        'likedBy': likedBy,
        'likesCount': likedBy.length,
      },
    );
  }

  @override
  Future<void> updateTags(String presetId, List<String> tags) async {
    await _db.updateDocument(
      databaseId: _databaseId,
      collectionId: _collectionId,
      documentId: presetId,
      data: {'tags': tags},
    );
  }

  @override
  Future<void> makePublic(String presetId) async {
    await _db.updateDocument(
      databaseId: _databaseId,
      collectionId: _collectionId,
      documentId: presetId,
      data: {'isPublic': true},
    );
  }

  @override
  Future<void> makePrivate(String presetId) async {
    await _db.updateDocument(
      databaseId: _databaseId,
      collectionId: _collectionId,
      documentId: presetId,
      data: {'isPublic': false},
    );
  }

  @override
  Future<void> deletePreset(String presetId,
      {required String ownerDeviceId}) async {
    if (_databaseId.isEmpty || _collectionId.isEmpty) {
      throw StateError('Appwrite database or collection id not configured');
    }
    if (presetId.isEmpty || ownerDeviceId.isEmpty) {
      throw StateError('Некорректные параметры удаления');
    }
    final existing = await getPresetById(presetId);
    if (existing == null) {
      await _cacheService?.clear();
      return;
    }
    if (existing.ownerId != ownerDeviceId ||
        !existing.hasTag(PresetTag.idCustom)) {
      throw StateError('Нет прав на удаление пресета');
    }
    await _db.deleteDocument(
      databaseId: _databaseId,
      collectionId: _collectionId,
      documentId: presetId,
    );
    await _cacheService?.clear();
    debugPrint('AppwriteShowcaseRepository: пресет $presetId удалён');
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

  static int _readIntField(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is double) return v.round();
    return fallback;
  }

  PhotoSessionPreset? _documentToPreset(Document doc) {
    final m = Map<String, dynamic>.from(doc.data);
    m[r'$id'] = doc.$id;
    m[r'$createdAt'] = doc.$createdAt;
    return _mapToPreset(m);
  }

  PhotoSessionPreset? _mapToPreset(Map<String, dynamic> doc) {
    try {
      final id = doc[r'$id'] as String? ?? doc['id'] as String? ?? '';
      final data = doc;
      final prompt = data['prompt'] as String? ?? '';
      final previewImageUrl = data['previewImageUrl'] as String? ??
          data['preview_image_url'] as String? ??
          '';
      if (prompt.isEmpty || previewImageUrl.isEmpty) return null;
      final thumbnailUrl = data['thumbnailUrl'] as String?;
      final title = data['title'] as String?;
      final tags = _parseTags(data['tags']);
      final imageStyle = data['imageStyle'] as String?;
      final ownerId = data['ownerId'] as String?;
      final createdAtStr = data['createdAt'] as String? ??
          data['created_at'] as String? ??
          doc[r'$createdAt'] as String?;
      final createdAt = createdAtStr != null
          ? DateTime.tryParse(createdAtStr) ?? DateTime.now()
          : DateTime.now();
      final isPublic = data['isPublic'] as bool? ?? false;
      final likesCount = _readIntField(data['likesCount'], 0);
      final likedBy = _parseLikedBy(data['likedBy']);
      return PhotoSessionPreset(
        id: id,
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
      debugPrint('AppwriteShowcaseRepository: map preset $e');
      return null;
    }
  }
}
