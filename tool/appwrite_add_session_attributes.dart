// Добавляет атрибут appwriteUserId в коллекцию user_generations
// и создаёт индекс для эффективных запросов по этому полю.
//
// Запуск: dart run tool/appwrite_add_session_attributes.dart
//
// Требует в .env: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY,
//                 APPWRITE_DATABASE_ID, APPWRITE_GENERATIONS_COLLECTION_ID

import 'dart:convert';
import 'dart:io';

void main() async {
  final env = _loadEnv();
  final endpoint = env['APPWRITE_ENDPOINT']?.trim();
  final projectId = env['APPWRITE_PROJECT_ID']?.trim();
  final apiKey = env['APPWRITE_API_KEY']?.trim();
  final databaseId = env['APPWRITE_DATABASE_ID']?.trim();
  final generationsId = env['APPWRITE_GENERATIONS_COLLECTION_ID']?.trim();

  if (endpoint == null ||
      projectId == null ||
      apiKey == null ||
      databaseId == null ||
      (generationsId ?? '').isEmpty) {
    print(
      'Задай в .env: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY, '
      'APPWRITE_DATABASE_ID, APPWRITE_GENERATIONS_COLLECTION_ID',
    );
    exit(1);
  }

  final base = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final headers = {
    'Content-Type': 'application/json',
    'X-Appwrite-Project': projectId,
    'X-Appwrite-Key': apiKey,
  };

  print('Добавляю атрибут appwriteUserId в user_generations...');
  final attrOk = await _addStringAttr(
    base,
    headers,
    databaseId,
    generationsId!,
    'appwriteUserId',
    128,
    required: false,
  );
  if (attrOk) {
    print('OK appwriteUserId');
  } else {
    print('Пропуск или ошибка appwriteUserId (возможно уже существует)');
  }

  print('Жду 3 сек пока атрибут стабилизируется в Appwrite...');
  await Future.delayed(const Duration(seconds: 3));

  print('Создаю индекс по appwriteUserId...');
  final indexOk = await _createIndex(
    base,
    headers,
    databaseId,
    generationsId,
    'idx_appwrite_user_id',
    'key',
    ['appwriteUserId'],
  );
  if (indexOk) {
    print('OK индекс idx_appwrite_user_id');
  } else {
    print('Пропуск или ошибка индекса (возможно уже существует)');
  }

  print('');
  print('Готово. Новые документы будут содержать appwriteUserId.');
  print('Старые документы мигрируются автоматически при первом запуске приложения.');
}

Future<bool> _addStringAttr(
  String base,
  Map<String, String> headers,
  String databaseId,
  String collectionId,
  String key,
  int size, {
  bool required = false,
}) async {
  final uri = Uri.parse(
    '${base}databases/$databaseId/collections/$collectionId/attributes/string',
  );
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    headers.forEach((k, v) => req.headers.set(k, v));
    req.write(jsonEncode({
      'key': key,
      'size': size,
      'required': required,
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();
    if (res.statusCode >= 200 && res.statusCode < 300) return true;
    if (body.contains('already exists') || body.contains('duplicate')) return true;
    print('  HTTP ${res.statusCode}: $body');
    return false;
  } catch (e) {
    client.close();
    print('  Ошибка: $e');
    return false;
  }
}

Future<bool> _createIndex(
  String base,
  Map<String, String> headers,
  String databaseId,
  String collectionId,
  String key,
  String type,
  List<String> attributes,
) async {
  final uri = Uri.parse(
    '${base}databases/$databaseId/collections/$collectionId/indexes',
  );
  final client = HttpClient();
  try {
    final req = await client.postUrl(uri);
    headers.forEach((k, v) => req.headers.set(k, v));
    req.write(jsonEncode({
      'key': key,
      'type': type,
      'attributes': attributes,
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();
    if (res.statusCode >= 200 && res.statusCode < 300) return true;
    if (body.contains('already exists') || body.contains('duplicate')) return true;
    print('  HTTP ${res.statusCode}: $body');
    return false;
  } catch (e) {
    client.close();
    print('  Ошибка: $e');
    return false;
  }
}

Map<String, String> _loadEnv() {
  final file = File('.env');
  if (!file.existsSync()) return {};
  final out = <String, String>{};
  for (final line in file.readAsStringSync().split('\n')) {
    final s = line.trim();
    if (s.isEmpty || s.startsWith('#')) continue;
    final i = s.indexOf('=');
    if (i <= 0) continue;
    final key = s.substring(0, i).trim();
    var value = s.substring(i + 1).trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    if (value.startsWith("'") && value.endsWith("'")) {
      value = value.substring(1, value.length - 1);
    }
    out[key] = value;
  }
  return out;
}
