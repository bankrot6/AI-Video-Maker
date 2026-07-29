// Одноразовый скрипт: создаёт в Appwrite базу, коллекцию presets и атрибуты.
// Запуск из корня проекта: dart run tool/appwrite_bootstrap.dart
// В .env должны быть: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY

import 'dart:convert';
import 'dart:io';

void main() async {
  final env = _loadEnv();
  final endpoint = env['APPWRITE_ENDPOINT']?.trim();
  final projectId = env['APPWRITE_PROJECT_ID']?.trim();
  final apiKey = env['APPWRITE_API_KEY']?.trim();

  if (endpoint == null ||
      endpoint.isEmpty ||
      projectId == null ||
      projectId.isEmpty ||
      apiKey == null ||
      apiKey.isEmpty) {
    print('Ошибка: в .env задай APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID и APPWRITE_API_KEY');
    print('API Key: Appwrite Console → Project → API Keys → Create (права: Databases)');
    exit(1);
  }

  final baseUrl = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final databaseId = env['APPWRITE_DATABASE_ID']?.trim().isNotEmpty == true
      ? env['APPWRITE_DATABASE_ID']!.trim()
      : null;
  const collectionId = 'presets';

  Map<String, String> headers() => {
        'Content-Type': 'application/json',
        'X-Appwrite-Project': projectId,
        'X-Appwrite-Key': apiKey,
      };

  String? _lastErrorBody;

  Future<Map<String, dynamic>?> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      headers().forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode(body));
      final res = await req.close();
      final respBody = await res.transform(utf8.decoder).join();
      _lastErrorBody = respBody;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return respBody.isEmpty ? <String, dynamic>{} : jsonDecode(respBody) as Map<String, dynamic>;
      }
      print('HTTP ${res.statusCode} $path: $respBody');
      return null;
    } finally {
      client.close();
    }
  }

  String resolvedDatabaseId;
  if (databaseId != null && databaseId.isNotEmpty) {
    print('Использую существующую базу: $databaseId');
    resolvedDatabaseId = databaseId;
    if (await _get(baseUrl, 'databases/$resolvedDatabaseId', headers()) == null) {
      print('Ошибка: база с ID $resolvedDatabaseId не найдена. Проверь APPWRITE_DATABASE_ID в .env');
      exit(1);
    }
  } else {
    print('Создаю базу photosession_db...');
    final dbRes = await post('databases', {
      'databaseId': 'photosession_db',
      'name': 'Photosession',
    });
    if (dbRes != null) {
      resolvedDatabaseId = 'photosession_db';
      print('База создана.');
    } else {
      final body = _lastErrorBody ?? '';
      if ((body.contains('maximum') || body.contains('limit')) && body.contains('403')) {
        print('');
        print('Лимит баз на тарифе достигнут. Используй существующую базу:');
        print('1. Зайди в Appwrite Console → проект → Databases (или Tables).');
        print('2. Открой нужную базу и скопируй её ID (из URL или настроек).');
        print('3. Добавь в .env: APPWRITE_DATABASE_ID=<скопированный_id>');
        print('4. Запусти скрипт снова: dart run tool/appwrite_bootstrap.dart');
        exit(1);
      }
      if (await _get(baseUrl, 'databases/photosession_db', headers()) != null) {
        resolvedDatabaseId = 'photosession_db';
        print('База уже есть, продолжаю.');
      } else {
        print('Не удалось создать базу. Проверь API Key (права Databases).');
        exit(1);
      }
    }
  }

  print('Создаю коллекцию $collectionId...');
  final colRes = await post(
    'databases/$resolvedDatabaseId/collections',
    {
      'collectionId': collectionId,
      'name': 'Presets',
      'permissions': ['read("any")'],
    },
  );
  if (colRes == null) {
    if (await _get(baseUrl, 'databases/$resolvedDatabaseId/collections/$collectionId', headers()) != null) {
      print('Коллекция уже есть, продолжаю.');
    } else {
      print('Не удалось создать коллекцию.');
      exit(1);
    }
  } else {
    print('Коллекция создана.');
  }

  await Future<void>.delayed(const Duration(milliseconds: 500));

  final attrs = [
    {'key': 'prompt', 'size': 2000},
    {'key': 'previewImageUrl', 'size': 2048},
    {'key': 'title', 'size': 512},
    {'key': 'createdAt', 'type': 'datetime'},
    {'key': 'tags', 'size': 64, 'array': true},
  ];

  for (final a in attrs) {
    final key = a['key'] as String;
    print('Добавляю атрибут $key...');
    if (a['type'] == 'datetime') {
      await post(
        'databases/$resolvedDatabaseId/collections/$collectionId/attributes/datetime',
        {'key': key, 'required': false},
      );
    } else {
      final body = <String, dynamic>{
        'key': key,
        'size': a['size'] as int,
        'required': key == 'prompt' || key == 'previewImageUrl',
      };
      if (a['array'] == true) {
        body['array'] = true;
      }
      await post(
        'databases/$resolvedDatabaseId/collections/$collectionId/attributes/string',
        body,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  print('');
  print('Готово. В .env должны быть:');
  print('APPWRITE_DATABASE_ID=$resolvedDatabaseId');
  print('APPWRITE_PRESETS_COLLECTION_ID=$collectionId');
  print('');
  print('Если атрибуты создавались впервые, подожди 5–10 сек и запускай приложение.');
}

Future<Map<String, dynamic>?> _get(
  String baseUrl,
  String path,
  Map<String, String> headers,
) async {
  final uri = Uri.parse('$baseUrl$path');
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    headers.forEach((k, v) => req.headers.set(k, v));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 200) return jsonDecode(body) as Map<String, dynamic>;
    return null;
  } finally {
    client.close();
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
    if (value.startsWith('"') && value.endsWith('"')) value = value.substring(1, value.length - 1);
    if (value.startsWith("'") && value.endsWith("'")) value = value.substring(1, value.length - 1);
    out[key] = value;
  }
  return out;
}
