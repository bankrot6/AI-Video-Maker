// Ограничивает доступ к коллекции user_generations:
//   - убирает read("any") → только аутентифицированные пользователи могут делать запросы
//   - включает documentSecurity: true → Appwrite применяет права на уровне каждого документа
//
// Безопасно для:
//   - Cloud Functions (используют API Key, он обходит permissions)
//   - Admin-скриптов (тоже API Key)
//   - Мобильного клиента (теперь работает через Anonymous Session)
//
// Запуск: dart run tool/appwrite_restrict_generations_collection.dart
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
  final collectionId =
      (env['APPWRITE_GENERATIONS_COLLECTION_ID']?.trim() ?? '').isNotEmpty
          ? env['APPWRITE_GENERATIONS_COLLECTION_ID']!.trim()
          : 'user_generations';

  if (endpoint == null ||
      projectId == null ||
      apiKey == null ||
      (databaseId ?? '').isEmpty) {
    print(
      'Задай в .env: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY, APPWRITE_DATABASE_ID',
    );
    exit(1);
  }

  final base = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final headers = {
    'Content-Type': 'application/json',
    'X-Appwrite-Project': projectId,
    'X-Appwrite-Key': apiKey,
  };

  // Читаем текущее состояние коллекции чтобы не потерять её имя и атрибуты
  print('Читаю текущие настройки коллекции $collectionId...');
  final currentName = await _getCollectionName(
    base,
    headers,
    databaseId!,
    collectionId,
  );
  if (currentName == null) {
    print('Не удалось прочитать коллекцию $collectionId. Проверь .env переменные.');
    exit(1);
  }
  print('Текущее имя коллекции: $currentName');

  print('');
  print('Применяю ограничения:');
  print('  - permissions: ["read(\\"users\\")"]  (только аутентифицированные)');
  print('  - documentSecurity: true            (права на уровне документов активны)');
  print('');

  final ok = await _updateCollectionPermissions(
    base,
    headers,
    databaseId,
    collectionId,
    currentName,
  );

  if (ok) {
    print('✅ Коллекция $collectionId обновлена.');
    print('');
    print('Итог:');
    print('  • Неаутентифицированные запросы → 401 (доступ закрыт)');
    print('  • Anonymous Session → может запрашивать коллекцию,');
    print('    но видит только свои документы (Role.user(uid))');
    print('  • API Key → обходит все ограничения (скрипты, функции — без изменений)');
  } else {
    print('❌ Не удалось обновить коллекцию. Проверь права API Key.');
    exit(1);
  }
}

Future<String?> _getCollectionName(
  String base,
  Map<String, String> headers,
  String databaseId,
  String collectionId,
) async {
  final uri = Uri.parse('${base}databases/$databaseId/collections/$collectionId');
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    headers.forEach((k, v) => req.headers.set(k, v));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();
    if (res.statusCode != 200) {
      print('  GET коллекции HTTP ${res.statusCode}: $body');
      return null;
    }
    final json = jsonDecode(body);
    return json['name'] as String?;
  } catch (e) {
    client.close();
    print('  Ошибка при чтении коллекции: $e');
    return null;
  }
}

Future<bool> _updateCollectionPermissions(
  String base,
  Map<String, String> headers,
  String databaseId,
  String collectionId,
  String collectionName,
) async {
  final uri = Uri.parse('${base}databases/$databaseId/collections/$collectionId');
  final body = jsonEncode({
    'name': collectionName,
    // users() = любой аутентифицированный пользователь (anonymous session включительно)
    'permissions': ['read("users")'],
    // Включаем per-document permissions: пользователь видит только свои документы
    'documentSecurity': true,
  });

  final client = HttpClient();
  try {
    final req = await client.putUrl(uri);
    headers.forEach((k, v) => req.headers.set(k, v));
    req.write(body);
    final res = await req.close();
    final respBody = await res.transform(utf8.decoder).join();
    client.close();
    if (res.statusCode >= 200 && res.statusCode < 300) return true;
    print('  PUT HTTP ${res.statusCode}: $respBody');
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
