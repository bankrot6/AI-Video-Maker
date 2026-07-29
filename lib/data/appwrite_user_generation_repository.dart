import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/user_generation.dart';
import '../services/appwrite_auth_service.dart';
import 'user_generation_repository.dart';

UserGeneration _docToGeneration(Document doc) {
  final m = Map<String, dynamic>.from(doc.data);
  m['id'] = doc.$id;
  return UserGeneration.fromJson(m);
}

class AppwriteUserGenerationRepository implements UserGenerationRepository {
  AppwriteUserGenerationRepository({
    String? endpoint,
    String? projectId,
    String? databaseId,
    String? collectionId,
  })  : _endpoint = (endpoint ?? dotenv.env['APPWRITE_ENDPOINT'])?.trim(),
        _projectId = (projectId ?? dotenv.env['APPWRITE_PROJECT_ID'])?.trim(),
        _databaseId = databaseId ?? dotenv.env['APPWRITE_DATABASE_ID'] ?? '',
        _collectionId =
            collectionId ?? dotenv.env['APPWRITE_GENERATIONS_COLLECTION_ID'] ?? 'user_generations' {
    final ep = _endpoint ?? '';
    final pid = _projectId ?? '';
    if (ep.isNotEmpty && pid.isNotEmpty) {
      debugPrint('AppwriteUserGenerationRepo: SDK инициализирован');
    }
  }

  final String? _endpoint;
  final String? _projectId;
  final String _databaseId;
  final String _collectionId;

  AppwriteAuthService get _auth => AppwriteAuthService.instance;

  Databases? get _sessionDb {
    final client = _auth.sessionClient;
    if (client == null) return null;
    return Databases(client);
  }

  Client? get _realtimeClient => _auth.sessionClient;

  bool get _isConfigured {
    final ep = _endpoint ?? '';
    final pid = _projectId ?? '';
    return ep.isNotEmpty && pid.isNotEmpty && _databaseId.isNotEmpty && _collectionId.isNotEmpty;
  }

  Future<List<Document>> _queryByUserId({
    required String presetId,
    required String userId,
    int limit = 50,
  }) async {
    final db = _sessionDb;
    if (db == null) return [];
    try {
      final result = await db.listDocuments(
        databaseId: _databaseId,
        collectionId: _collectionId,
        queries: [
          Query.equal('presetId', presetId),
          Query.equal('appwriteUserId', userId),
          Query.orderDesc(r'$createdAt'),
          Query.limit(limit),
        ],
      );
      return result.documents;
    } catch (e) {
      debugPrint('AppwriteUserGenerationRepo: queryByUserId $e');
      return [];
    }
  }

  /// Запрашивает старые документы (без appwriteUserId) по deviceId.
  /// Работает только если коллекция имеет read("any") и docs доступны публично.
  Future<List<Document>> _queryLegacyByDeviceId({
    required String presetId,
    required String deviceId,
    int limit = 50,
  }) async {
    final db = _sessionDb;
    if (db == null) return [];
    try {
      try {
        final result = await db.listDocuments(
          databaseId: _databaseId,
          collectionId: _collectionId,
          queries: [
            Query.equal('presetId', presetId),
            Query.equal('deviceId', deviceId),
            Query.orderDesc(r'$createdAt'),
            Query.limit(limit),
          ],
        );
        return result.documents.where((doc) {
          final uid = doc.data['appwriteUserId'] as String? ?? '';
          return uid.isEmpty;
        }).toList();
      } catch (e2) {
        final msg = e2.toString();
        if (msg.contains('deviceId') || msg.contains('Attribute not found')) {
          final result = await db.listDocuments(
            databaseId: _databaseId,
            collectionId: _collectionId,
            queries: [
              Query.equal('presetId', presetId),
              Query.orderDesc(r'$createdAt'),
              Query.limit(limit),
            ],
          );
          return result.documents.where((doc) {
            final docDeviceId = doc.data['deviceId'] as String? ?? '';
            final uid = doc.data['appwriteUserId'] as String? ?? '';
            return docDeviceId == deviceId && uid.isEmpty;
          }).toList();
        }
        rethrow;
      }
    } catch (e) {
      debugPrint('AppwriteUserGenerationRepo: queryLegacyByDeviceId $e');
      return [];
    }
  }

  @override
  Future<List<UserGeneration>> getGenerationsByPreset(
    String presetId, {
    required String deviceId,
  }) async {
    if (!_isConfigured) {
      debugPrint('AppwriteUserGenerationRepo: SDK не инициализирован');
      return [];
    }
    debugPrint('AppwriteUserGenerationRepo: загрузка preset=$presetId');

    final userId = _auth.userId;
    final futures = <Future<List<Document>>>[];

    if (userId != null && userId.isNotEmpty) {
      futures.add(_queryByUserId(presetId: presetId, userId: userId));
    }
    if (deviceId.isNotEmpty) {
      futures.add(_queryLegacyByDeviceId(presetId: presetId, deviceId: deviceId));
    }

    final results = await Future.wait(futures);

    final merged = <String, Document>{};
    for (final list in results) {
      for (final doc in list) {
        merged[doc.$id] = doc;
      }
    }

    final generations = merged.values
        .map(_docToGeneration)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    debugPrint(
      'AppwriteUserGenerationRepo: preset=$presetId → ${generations.length} генераций',
    );
    return generations;
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

    final db = _sessionDb;
    if (db == null) {
      debugPrint('AppwriteUserGenerationRepo: нет сессии, создание невозможно');
      return null;
    }

    try {
      final docId = (clientAssignedDocumentId != null &&
              clientAssignedDocumentId.isNotEmpty)
          ? clientAssignedDocumentId
          : 'gen_${DateTime.now().millisecondsSinceEpoch}';

      final userId = _auth.userId;

      final data = <String, dynamic>{
        'presetId': presetId,
        'userImageUrl': userImageUrl,
        'resultImageUrl': resultImageUrl,
        'deviceId': deviceId,
        'createdAt': DateTime.now().toIso8601String(),
        if (userId != null && userId.isNotEmpty) 'appwriteUserId': userId,
      };
      if (referenceImageUrl != null && referenceImageUrl.isNotEmpty) {
        data['referenceImageUrl'] = referenceImageUrl;
      }

      final permissions = userId != null && userId.isNotEmpty
          ? [
              Permission.read(Role.user(userId)),
              Permission.update(Role.user(userId)),
              Permission.delete(Role.user(userId)),
            ]
          : [Permission.read(Role.any())];

      final document = await db.createDocument(
        databaseId: _databaseId,
        collectionId: _collectionId,
        documentId: docId,
        data: data,
        permissions: permissions,
      );
      debugPrint(
        'AppwriteUserGenerationRepo: создано ID=${document.$id} '
        'uid=${userId ?? "нет"}',
      );
      return _docToGeneration(document);
    } catch (e, st) {
      debugPrint('AppwriteUserGenerationRepo: ошибка создания $e');
      debugPrint('$st');
      return null;
    }
  }

  @override
  Stream<Set<String>> watchUsedPresetIds(String deviceId) async* {
    final client = _realtimeClient;
    if (deviceId.isEmpty || !_isConfigured || client == null) {
      yield <String>{};
      return;
    }

    Future<Set<String>> load() async {
      final userId = _auth.userId;
      final byUser = (userId != null && userId.isNotEmpty)
          ? await _loadPresetIdsByUserId(userId)
          : <String>{};
      final byDevice = await _loadPresetIdsByDeviceId(deviceId);
      return {...byUser, ...byDevice};
    }

    yield await load();

    final channel =
        'databases.$_databaseId.collections.$_collectionId.documents';
    final realtime = Realtime(client);
    final sub = realtime.subscribe([channel]);
    await for (final _ in sub.stream) {
      yield await load();
    }
  }

  Future<Set<String>> _loadPresetIdsByUserId(String userId) async {
    final db = _sessionDb;
    if (db == null) return {};
    try {
      final result = await db.listDocuments(
        databaseId: _databaseId,
        collectionId: _collectionId,
        queries: [
          Query.equal('appwriteUserId', userId),
          Query.limit(500),
        ],
      );
      return result.documents
          .map((d) => d.data['presetId'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> _loadPresetIdsByDeviceId(String deviceId) async {
    final db = _sessionDb;
    if (db == null) return {};
    try {
      final result = await db.listDocuments(
        databaseId: _databaseId,
        collectionId: _collectionId,
        queries: [
          Query.equal('deviceId', deviceId),
          Query.limit(500),
        ],
      );
      return result.documents
          .where((d) => (d.data['appwriteUserId'] as String? ?? '').isEmpty)
          .map((d) => d.data['presetId'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<bool> deleteGeneration(
    String generationId, {
    required String deviceId,
    required String presetId,
  }) async {
    if (!_isConfigured) {
      debugPrint('AppwriteUserGenerationRepo: SDK не инициализирован');
      return false;
    }
    if (generationId.isEmpty || deviceId.isEmpty || presetId.isEmpty) {
      return false;
    }

    final db = _sessionDb;
    if (db == null) return false;

    try {
      final doc = await db.getDocument(
        databaseId: _databaseId,
        collectionId: _collectionId,
        documentId: generationId,
      );
      final pid = doc.data['presetId'] as String? ?? '';
      final did = doc.data['deviceId'] as String? ?? '';
      final docUserId = doc.data['appwriteUserId'] as String? ?? '';
      final currentUserId = _auth.userId ?? '';

      final ownedByDevice = pid == presetId && did == deviceId;
      final ownedBySession = pid == presetId &&
          docUserId.isNotEmpty &&
          currentUserId.isNotEmpty &&
          docUserId == currentUserId;

      if (!ownedByDevice && !ownedBySession) {
        debugPrint('AppwriteUserGenerationRepo: deleteGeneration — нет доступа');
        return false;
      }

      await db.deleteDocument(
        databaseId: _databaseId,
        collectionId: _collectionId,
        documentId: generationId,
      );
      debugPrint('AppwriteUserGenerationRepo: удалено $generationId');
      return true;
    } catch (e, st) {
      debugPrint('AppwriteUserGenerationRepo: deleteGeneration $e');
      debugPrint('$st');
      return false;
    }
  }

  /// Запускает soft-миграцию, если доступен API-ключ клиент.
  /// Без него вызов — no-op, миграция пропускается (не критично).
  Future<void> migrateIfNeeded(String deviceId) async {
    if (_databaseId.isEmpty || _collectionId.isEmpty) return;
    final ep = _endpoint ?? '';
    final pid = _projectId ?? '';
    if (ep.isEmpty || pid.isEmpty) return;

    final apiKey = dotenv.env['APPWRITE_API_KEY']?.trim();
    if (apiKey == null || apiKey.isEmpty) return;

    final client = Client().setEndpoint(ep).setProject(pid);
    client.setDevKey(apiKey);
    await _auth.runMigrationIfNeeded(
      deviceId: deviceId,
      apiKeyClient: client,
      databaseId: _databaseId,
      collectionId: _collectionId,
    );
  }
}
