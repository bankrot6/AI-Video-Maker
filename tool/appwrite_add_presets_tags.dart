// Добавляет атрибут tags (массив строк) в коллекцию presets через Appwrite API.
// Запуск из корня: dart run tool/appwrite_add_presets_tags.dart
// В .env: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY,
//         APPWRITE_DATABASE_ID, APPWRITE_PRESETS_COLLECTION_ID

import 'dart:convert';
import 'dart:io';

void main() async {
  final env = _loadEnv();
  final endpoint = env['APPWRITE_ENDPOINT']?.trim();
  final projectId = env['APPWRITE_PROJECT_ID']?.trim();
  final apiKey = env['APPWRITE_API_KEY']?.trim();
  final databaseId = env['APPWRITE_DATABASE_ID']?.trim();
  final collectionId = env['APPWRITE_PRESETS_COLLECTION_ID']?.trim();

  if (endpoint == null ||
      projectId == null ||
      apiKey == null ||
      databaseId == null ||
      collectionId == null) {
    print(
      'Ошибка: в .env задай APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, '
      'APPWRITE_API_KEY, APPWRITE_DATABASE_ID, APPWRITE_PRESETS_COLLECTION_ID',
    );
    exit(1);
  }

  final baseUrl = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final path =
      'databases/$databaseId/collections/$collectionId/attributes/string';

  final client = HttpClient();
  try {
    final uri = Uri.parse('$baseUrl$path');
    final req = await client.postUrl(uri);
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('X-Appwrite-Project', projectId);
    req.headers.set('X-Appwrite-Key', apiKey);
    req.write(jsonEncode({
      'key': 'tags',
      'size': 64,
      'required': false,
      'array': true,
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();

    if (res.statusCode >= 200 && res.statusCode < 300) {
      print('Атрибут tags создан в коллекции $collectionId.');
      print('Подожди 5–10 сек, пока Appwrite применит схему.');
      return;
    }
    final err = body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic>? : null;
    final msg = err?['message']?.toString() ?? body;
    if (res.statusCode == 409 || msg.toLowerCase().contains('already')) {
      print('Атрибут tags уже есть в коллекции.');
      return;
    }
    print('Ошибка ${res.statusCode}: $msg');
    exit(1);
  } catch (e, st) {
    client.close();
    print('Ошибка: $e');
    print(st);
    exit(1);
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
