import 'dart:convert';
import 'dart:io';

void main() async {
  final env = _loadEnv();
  final endpoint = env['APPWRITE_ENDPOINT']?.trim();
  final projectId = env['APPWRITE_PROJECT_ID']?.trim();
  final apiKey = env['APPWRITE_API_KEY']?.trim();
  final databaseId = env['APPWRITE_DATABASE_ID']?.trim();
  final collectionId = env['APPWRITE_PRESETS_COLLECTION_ID']?.trim();

  if (endpoint == null || endpoint.isEmpty ||
      projectId == null || projectId.isEmpty ||
      apiKey == null || apiKey.isEmpty ||
      databaseId == null || databaseId.isEmpty ||
      collectionId == null || collectionId.isEmpty) {
    print('Ошибка: в .env должны быть APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY, APPWRITE_DATABASE_ID, APPWRITE_PRESETS_COLLECTION_ID');
    exit(1);
  }

  final baseUrl = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final headers = {
    'Content-Type': 'application/json',
    'X-Appwrite-Project': projectId,
    'X-Appwrite-Key': apiKey,
  };

  print('Загружаю пресеты из $collectionId...');
  final listUrl = Uri.parse('${baseUrl}databases/$databaseId/collections/$collectionId/documents');
  final client = HttpClient();
  
  try {
    final req = await client.getUrl(listUrl);
    headers.forEach((k, v) => req.headers.set(k, v));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    
    if (res.statusCode != 200) {
      print('Ошибка загрузки: HTTP ${res.statusCode}');
      print(body);
      exit(1);
    }
    
    final json = jsonDecode(body) as Map<String, dynamic>;
    final documents = (json['documents'] as List?) ?? [];
    
    print('Найдено пресетов: ${documents.length}');
    
    for (final doc in documents) {
      if (doc is! Map<String, dynamic>) continue;
      
      final id = doc['\$id'] as String?;
      final prompt = doc['prompt'] as String? ?? '';
      final title = doc['title'] as String? ?? '';
      
      if (id == null || prompt.isEmpty) continue;
      
      print('\n--- Пресет $id ---');
      print('Заголовок: $title');
      print('Промт (первые 100 символов): ${prompt.substring(0, prompt.length > 100 ? 100 : prompt.length)}...');
      
      final isRussian = _containsCyrillic(prompt);
      print('Язык: ${isRussian ? "Русский" : "Английский"}');
      
      if (!isRussian) {
        print('Требуется перевод на русский');
      }
    }
    
    print('\n\nДля перевода пресетов на русский используйте DeepSeek API вручную или обновите документы через Appwrite Console');
    
  } finally {
    client.close();
  }
}

bool _containsCyrillic(String text) {
  return text.contains(RegExp(r'[а-яА-ЯёЁ]'));
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
