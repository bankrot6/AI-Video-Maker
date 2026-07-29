import 'dart:convert';
import 'dart:io';

void main() async {
  print('Настройка Appwrite для фотосессий...\n');

  final env = _loadEnv();
  final endpoint = env['APPWRITE_ENDPOINT']?.trim();
  final projectId = env['APPWRITE_PROJECT_ID']?.trim();
  final apiKey = env['APPWRITE_API_KEY']?.trim();
  final databaseId = env['APPWRITE_DATABASE_ID']?.trim();

  if (endpoint == null || projectId == null || apiKey == null || databaseId == null) {
    print('Ошибка: задай в .env APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY, APPWRITE_DATABASE_ID');
    exit(1);
  }

  print('1/2 Создание Storage Bucket для фото пользователей...');
  final bucketId = await _createBucket(endpoint, projectId, apiKey, 'user-photos');
  if (bucketId != null) {
    print('✅ Bucket создан: $bucketId');
  } else {
    print('⚠️ Не удалось создать bucket (возможно уже существует)');
  }

  print('\n2/2 Создание коллекции для результатов генераций...');
  final collectionId = await _createCollection(endpoint, projectId, apiKey, databaseId);
  if (collectionId != null) {
    print('✅ Collection создана: $collectionId');
  } else {
    print('⚠️ Не удалось создать collection (возможно уже существует)');
  }

  print('\n✅ Настройка завершена!');
  print('\nДобавь в .env:');
  print('APPWRITE_STORAGE_BUCKET_ID=user-photos');
  print('APPWRITE_GENERATIONS_COLLECTION_ID=user_generations');
}

Future<String?> _createBucket(String endpoint, String projectId, String apiKey, String bucketId) async {
  try {
    final baseUrl = endpoint.endsWith('/') ? endpoint : '$endpoint/';
    final uri = Uri.parse('${baseUrl}storage/buckets');
    
    final client = HttpClient();
    final request = await client.postUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('X-Appwrite-Project', projectId);
    request.headers.set('X-Appwrite-Key', apiKey);
    
    request.write(jsonEncode({
      'bucketId': bucketId,
      'name': 'User Photos',
      'permissions': [
        'read("any")',
        'create("any")',
      ],
      'fileSecurity': true,
      'enabled': true,
      'maximumFileSize': 8388608,
      'allowedFileExtensions': ['jpg', 'jpeg', 'png', 'webp'],
      'compression': 'gzip',
      'encryption': true,
      'antivirus': false,
    }));
    
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return bucketId;
    }
    print('Bucket создание: ${response.statusCode} $body');
    return null;
  } catch (e) {
    print('Bucket: $e');
    return null;
  }
}

Future<String?> _createCollection(String endpoint, String projectId, String apiKey, String databaseId) async {
  try {
    final baseUrl = endpoint.endsWith('/') ? endpoint : '$endpoint/';
    final collectionId = 'user_generations';
    
    final client = HttpClient();
    var request = await client.postUrl(Uri.parse('${baseUrl}databases/$databaseId/collections'));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('X-Appwrite-Project', projectId);
    request.headers.set('X-Appwrite-Key', apiKey);
    
    request.write(jsonEncode({
      'collectionId': collectionId,
      'name': 'User Generations',
      'permissions': [
        'read("any")',
        'create("any")',
      ],
      'documentSecurity': false,
    }));
    
    var response = await request.close();
    var body = await response.transform(utf8.decoder).join();
    
    if (response.statusCode < 200 || response.statusCode >= 300) {
      print('Collection: ${response.statusCode} $body');
      client.close();
      return null;
    }

    print('Collection создана, добавляем атрибуты...');

    final attributes = [
      {'key': 'presetId', 'type': 'string', 'size': 100, 'required': true},
      {'key': 'userImageUrl', 'type': 'string', 'size': 500, 'required': true},
      {'key': 'resultImageUrl', 'type': 'string', 'size': 500, 'required': true},
      {'key': 'createdAt', 'type': 'string', 'size': 50, 'required': true},
    ];

    for (final attr in attributes) {
      await Future.delayed(const Duration(milliseconds: 500));
      request = await client.postUrl(Uri.parse('${baseUrl}databases/$databaseId/collections/$collectionId/attributes/string'));
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-Appwrite-Project', projectId);
      request.headers.set('X-Appwrite-Key', apiKey);
      request.write(jsonEncode(attr));
      response = await request.close();
      body = await response.transform(utf8.decoder).join();
      print('Атрибут ${attr['key']}: ${response.statusCode}');
    }

    await Future.delayed(const Duration(milliseconds: 500));
    request = await client.postUrl(Uri.parse('${baseUrl}databases/$databaseId/collections/$collectionId/indexes'));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('X-Appwrite-Project', projectId);
    request.headers.set('X-Appwrite-Key', apiKey);
    request.write(jsonEncode({
      'key': 'presetId_idx',
      'type': 'key',
      'attributes': ['presetId'],
      'orders': ['ASC'],
    }));
    response = await request.close();
    body = await response.transform(utf8.decoder).join();
    print('Индекс presetId: ${response.statusCode}');

    client.close();
    return collectionId;
  } catch (e) {
    print('Collection: $e');
    return null;
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
