import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final env = _loadEnv();
  final endpoint = env['APPWRITE_ENDPOINT']?.trim();
  final projectId = env['APPWRITE_PROJECT_ID']?.trim();
  final apiKey = env['APPWRITE_API_KEY']?.trim();
  final databaseId = env['APPWRITE_DATABASE_ID']?.trim();
  final collectionId = env['APPWRITE_PRESETS_COLLECTION_ID']?.trim();
  final deepseekKey = env['DEEPSEEK_API_KEY']?.trim();

  if (endpoint == null || endpoint.isEmpty ||
      projectId == null || projectId.isEmpty ||
      apiKey == null || apiKey.isEmpty ||
      databaseId == null || databaseId.isEmpty ||
      collectionId == null || collectionId.isEmpty ||
      deepseekKey == null || deepseekKey.isEmpty) {
    print('Ошибка: в .env должны быть все ключи');
    exit(1);
  }

  final baseUrl = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final headers = {
    'Content-Type': 'application/json',
    'X-Appwrite-Project': projectId,
    'X-Appwrite-Key': apiKey,
  };

  print('Загружаю пресеты...');
  final listUrl = Uri.parse('${baseUrl}databases/$databaseId/collections/$collectionId/documents');

  final response = await http.get(listUrl, headers: headers);

  if (response.statusCode != 200) {
    print('Ошибка загрузки: HTTP ${response.statusCode}');
    print(response.body);
    exit(1);
  }

  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final documents = (json['documents'] as List?) ?? [];

  print('Найдено пресетов: ${documents.length}\n');

  for (final doc in documents) {
    if (doc is! Map<String, dynamic>) continue;

    final id = doc['\$id'] as String?;
    final prompt = doc['prompt'] as String? ?? '';
    final title = doc['title'] as String? ?? '';

    if (id == null || prompt.isEmpty) continue;

    final isRussian = _containsCyrillic(prompt);

    print('--- Пресет: ${title.isNotEmpty ? title : id} ---');
    print('ID: $id');
    print('Язык: ${isRussian ? "Русский ✓" : "Английский"}');

      if (!isRussian) {
        print('Переводим промт на русский через DeepSeek...');

        final russianPrompt = await _translateToRussian(prompt, deepseekKey);

        if (russianPrompt != null && russianPrompt.isNotEmpty) {
          print('Перевод промта получен (${russianPrompt.length} символов)');
          
          String? russianTitle;
          if (title.isNotEmpty && !_containsCyrillic(title)) {
            print('Переводим заголовок на русский...');
            russianTitle = await _translateTitleToRussian(title, deepseekKey);
            if (russianTitle != null) {
              print('Перевод заголовка получен: $russianTitle');
            }
          }
          
          print('Обновляем документ в Appwrite...');

          final updateUrl = Uri.parse(
            '${baseUrl}databases/$databaseId/collections/$collectionId/documents/$id'
          );

          final updateData = <String, dynamic>{
            'prompt': russianPrompt,
          };
          
          if (russianTitle != null) {
            updateData['title'] = russianTitle;
          }

          final updateResponse = await http.patch(
            updateUrl,
            headers: headers,
            body: jsonEncode({'data': updateData}),
          );

          if (updateResponse.statusCode >= 200 && updateResponse.statusCode < 300) {
            print('✓ Пресет обновлён\n');
          } else {
            print('✗ Ошибка обновления: HTTP ${updateResponse.statusCode}');
            print(updateResponse.body);
            print('');
          }
        } else {
          print('✗ Не удалось перевести промт\n');
        }

        await Future.delayed(const Duration(milliseconds: 2000));
      } else {
        print('Пропускаем (уже на русском)\n');
      }
  }

  print('Готово!');
}

Future<String?> _translateToRussian(String englishText, String deepseekKey) async {
  try {
    final uri = Uri.parse('https://api.deepseek.com/chat/completions');
    
    final systemPrompt = '''Ты профессиональный переводчик промптов для генерации изображений.
Переведи следующий английский промт для генерации изображений на русский язык.
ВАЖНО:
- Сохрани ВСЕ технические детали (освещение, композицию, настройки камеры, цвета, текстуры)
- Сохрани структуру и уровень детализации
- Используй фотографическую и кинематографическую терминологию
- НЕ упрощай и НЕ пересказывай своими словами
- Выведи ТОЛЬКО русский перевод, ничего больше
- НЕ добавляй объяснений или комментариев''';

    final payload = {
      'model': 'deepseek-chat',
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': 'Переведи этот промт на русский:\n\n$englishText'},
      ],
      'temperature': 0.3,
      'max_tokens': 2000,
    };
    
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $deepseekKey',
      },
      body: jsonEncode(payload),
    );
    
    if (response.statusCode != 200) {
      print('DeepSeek API ошибка: HTTP ${response.statusCode}');
      print(response.body);
      return null;
    }
    
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      final first = choices.first as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;
      return content?.trim();
    }
    
    return null;
  } catch (e) {
    print('Ошибка запроса к DeepSeek: $e');
    return null;
  }
}

Future<String?> _translateTitleToRussian(String englishTitle, String deepseekKey) async {
  try {
    final uri = Uri.parse('https://api.deepseek.com/chat/completions');
    
    final systemPrompt = '''Переведи короткий заголовок фотосессии на русский язык.
Сохрани смысл и стиль. Выведи ТОЛЬКО русский заголовок, без кавычек и объяснений.''';

    final payload = {
      'model': 'deepseek-chat',
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': 'Переведи: $englishTitle'},
      ],
      'temperature': 0.3,
      'max_tokens': 100,
    };
    
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $deepseekKey',
      },
      body: jsonEncode(payload),
    );
    
    if (response.statusCode != 200) {
      print('DeepSeek API ошибка для title: HTTP ${response.statusCode}');
      return null;
    }
    
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices != null && choices.isNotEmpty) {
      final first = choices.first as Map<String, dynamic>;
      final message = first['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;
      return content?.trim();
    }
    
    return null;
  } catch (e) {
    print('Ошибка перевода title: $e');
    return null;
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
