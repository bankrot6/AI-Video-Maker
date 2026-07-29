import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppwriteAuthService {
  AppwriteAuthService._();
  static final AppwriteAuthService instance = AppwriteAuthService._();

  Client? _sessionClient;
  String? _userId;

  String? get userId => _userId;

  /// Клиент без API Key — использует сессионные куки Appwrite SDK.
  /// Нужен для запросов, ограниченных правами документов (Permission.read(Role.user(...))).
  Client? get sessionClient => _sessionClient;

  bool get isReady => _userId != null && _sessionClient != null;

  Future<String?> ensureSession() async {
    if (_userId != null) return _userId;

    final endpoint = dotenv.env['APPWRITE_ENDPOINT']?.trim() ?? '';
    final projectId = dotenv.env['APPWRITE_PROJECT_ID']?.trim() ?? '';
    if (endpoint.isEmpty || projectId.isEmpty) return null;

    final client = Client().setEndpoint(endpoint).setProject(projectId);
    final account = Account(client);

    try {
      final user = await account.get();
      _userId = user.$id;
      _sessionClient = client;
      debugPrint('AppwriteAuth: восстановлена сессия uid=$_userId');
      return _userId;
    } catch (_) {
      try {
        final session = await account.createAnonymousSession();
        _userId = session.userId;
        _sessionClient = client;
        debugPrint('AppwriteAuth: создана анонимная сессия uid=$_userId');
        return _userId;
      } catch (e, st) {
        debugPrint('AppwriteAuth: ошибка создания сессии: $e');
        debugPrint('$st');
        return null;
      }
    }
  }

  /// Однократная soft-миграция: находит существующие документы пользователя
  /// по [deviceId] и добавляет в них [appwriteUserId] + персональные permissions.
  ///
  /// Выполняется через [apiKeyClient] (обходит permissions — нужен для записи
  /// в старые документы без прав текущего пользователя).
  Future<void> runMigrationIfNeeded({
    required String deviceId,
    required Client apiKeyClient,
    required String databaseId,
    required String collectionId,
  }) async {
    final uid = _userId;
    if (uid == null || deviceId.isEmpty || databaseId.isEmpty || collectionId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final migKey = 'aw_session_migrated_v1_$uid';
    if (prefs.getBool(migKey) == true) return;

    debugPrint('AppwriteAuth: миграция deviceId=${deviceId.substring(0, 8)}... → uid=$uid');

    try {
      final db = Databases(apiKeyClient);
      var offset = 0;
      var migratedTotal = 0;

      while (true) {
        final result = await db.listDocuments(
          databaseId: databaseId,
          collectionId: collectionId,
          queries: [
            Query.equal('deviceId', deviceId),
            Query.limit(100),
            if (offset > 0) Query.offset(offset),
          ],
        );

        if (result.documents.isEmpty) break;

        for (final doc in result.documents) {
          final existing = doc.data['appwriteUserId'] as String? ?? '';
          if (existing.isNotEmpty) continue;

          try {
            await db.updateDocument(
              databaseId: databaseId,
              collectionId: collectionId,
              documentId: doc.$id,
              data: {'appwriteUserId': uid},
              permissions: [
                Permission.read(Role.user(uid)),
                Permission.update(Role.user(uid)),
                Permission.delete(Role.user(uid)),
              ],
            );
            migratedTotal++;
          } catch (e) {
            debugPrint('AppwriteAuth: не удалось мигрировать ${doc.$id}: $e');
          }
        }

        if (result.documents.length < 100) break;
        offset += 100;
      }

      debugPrint('AppwriteAuth: мигрировано $migratedTotal документов');
      await prefs.setBool(migKey, true);
    } catch (e, st) {
      debugPrint('AppwriteAuth: ошибка миграции: $e');
      debugPrint('$st');
    }
  }
}
