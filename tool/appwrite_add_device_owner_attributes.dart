// Добавляет атрибуты deviceId (user_generations), ownerId и firebaseOwnerUid (presets).
// firebaseOwnerUid — для согласованности с Firestore (владелец кастомного пресета).
// Запуск: dart run tool/appwrite_add_device_owner_attributes.dart
// Требует в .env: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY, APPWRITE_DATABASE_ID,
//              APPWRITE_PRESETS_COLLECTION_ID, APPWRITE_GENERATIONS_COLLECTION_ID

import 'dart:convert';
import 'dart:io';

void main() async {
  final env = _loadEnv();
  final endpoint = env['APPWRITE_ENDPOINT']?.trim();
  final projectId = env['APPWRITE_PROJECT_ID']?.trim();
  final apiKey = env['APPWRITE_API_KEY']?.trim();
  final databaseId = env['APPWRITE_DATABASE_ID']?.trim();
  final presetsId = env['APPWRITE_PRESETS_COLLECTION_ID']?.trim();
  final generationsId = env['APPWRITE_GENERATIONS_COLLECTION_ID']?.trim();

  if (endpoint == null ||
      projectId == null ||
      apiKey == null ||
      databaseId == null ||
      (presetsId ?? '').isEmpty ||
      (generationsId ?? '').isEmpty) {
    print('Задай в .env: APPWRITE_* переменные (см. комментарий в скрипте)');
    exit(1);
  }

  final presetsIdVal = presetsId!;
  final generationsIdVal = generationsId!;

  final base = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final headers = {
    'Content-Type': 'application/json',
    'X-Appwrite-Project': projectId,
    'X-Appwrite-Key': apiKey,
  };

  print('Добавляю атрибут ownerId в коллекцию presets...');
  final okPresets = await _addStringAttr(
    base,
    headers,
    databaseId,
    presetsIdVal,
    'ownerId',
    128,
    required: false,
  );
  print(okPresets ? 'OK ownerId (presets)' : 'Пропуск или ошибка ownerId');

  print('Добавляю атрибут firebaseOwnerUid в коллекцию presets...');
  final okFirebaseUid = await _addStringAttr(
    base,
    headers,
    databaseId,
    presetsIdVal,
    'firebaseOwnerUid',
    128,
    required: false,
  );
  print(okFirebaseUid
      ? 'OK firebaseOwnerUid (presets)'
      : 'Пропуск или ошибка firebaseOwnerUid');

  print('Добавляю атрибут deviceId в коллекцию user_generations...');
  final okGen = await _addStringAttr(
    base,
    headers,
    databaseId,
    generationsIdVal,
    'deviceId',
    128,
    required: false,
  );
  print(okGen ? 'OK deviceId (user_generations)' : 'Пропуск или ошибка deviceId');

  print('');
  print('Готово. Если атрибуты созданы впервые, подожди несколько секунд.');
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
