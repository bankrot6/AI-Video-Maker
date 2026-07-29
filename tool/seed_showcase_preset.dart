// Серверный скрипт: генерирует промпт (DeepSeek) → картинку (Nano Banana) → пресет в витрине (Appwrite).
// Запуск из корня: dart run tool/seed_showcase_preset.dart
// С темой: dart run tool/seed_showcase_preset.dart "пляж на закате"
// По крону (раз в день): 0 9 * * * cd /path/to/Photosession-AI && dart run tool/seed_showcase_preset.dart
// В .env: DEEPSEEK_API_KEY, PIAPI_API_KEY, APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY, APPWRITE_DATABASE_ID, APPWRITE_PRESETS_COLLECTION_ID

import 'dart:convert';
import 'dart:io';

const _deepSeekSystemPrompt = '''
You are an expert prompt engineer for AI-powered professional photo sessions. Generate a HIGHLY DETAILED image generation prompt in English with a structured format used by professional photographers.

MANDATORY STRUCTURE (6 sections):

SCENE DESCRIPTION:
[2-4 sentences describing setting, environment, atmosphere, key objects, background. Be VERY specific: location type, spatial layout, colors, textures, materials, lighting quality.]

CHARACTER:
[2-3 sentences: specific clothing items with colors/patterns/fit, accessories (jewelry/bags/shoes with details), exact pose and body language, gaze direction. ALWAYS include: "Facial features, skin texture, age, and hair color must be preserved exactly as in the reference photo without any alterations."]

OBJECTS AND DETAILS:
[1-2 sentences listing concrete props, materials, textures. Use specific terms: "white ceramic vase with gold trim" not "vase"]

ATMOSPHERE AND MOOD:
[1-2 sentences: emotional tone - romantic, energetic, serene, luxurious, playful, mysterious, confident, nostalgic]

COLOR PALETTE:
[1 sentence with specific color names and tones: "Warm golden hour tones with deep burgundy and cream accents"]

TECHNICAL PARAMETERS:
[Lighting: golden hour/harsh flash/soft window light/studio softbox/Rembrandt lighting/backlight. Camera: 35mm/50mm/85mm lens, f/1.4-f/2.8 aperture for portraits. Add: "professional photography, high resolution, sharp focus, raw photo, natural skin texture, 3:4 aspect ratio"]

CRITICAL RULES:
- Output ONLY the 6-section structured prompt in English
- Use professional photography terminology (aperture, bokeh, depth of field, Rembrandt lighting, etc.)
- Be EXTREMELY detailed and concrete in every section
- NO generic phrases - every detail must be specific and visual
- Include realistic technical specs (lens, lighting, film stock if vintage)
Output the complete structured prompt. No quotes, no "Here is...", just content.''';

void main(List<String> args) async {
  final env = _loadEnv();
  final themeHint = args.isNotEmpty ? args.first.trim() : null;

  final deepSeekKey = env['DEEPSEEK_API_KEY']?.trim();
  final piapiKey = env['PIAPI_API_KEY']?.trim();
  final endpoint = env['APPWRITE_ENDPOINT']?.trim();
  final projectId = env['APPWRITE_PROJECT_ID']?.trim();
  final appwriteKey = env['APPWRITE_API_KEY']?.trim();
  final databaseId = env['APPWRITE_DATABASE_ID']?.trim();
  final collectionId = env['APPWRITE_PRESETS_COLLECTION_ID']?.trim();

  if (deepSeekKey == null || deepSeekKey.isEmpty) {
    print('Ошибка: задай DEEPSEEK_API_KEY в .env');
    exit(1);
  }
  if (piapiKey == null || piapiKey.isEmpty) {
    print('Ошибка: задай PIAPI_API_KEY в .env');
    exit(1);
  }
  if (endpoint == null || endpoint.isEmpty || projectId == null || projectId.isEmpty ||
      appwriteKey == null || appwriteKey.isEmpty || databaseId == null || databaseId.isEmpty ||
      collectionId == null || collectionId.isEmpty) {
    print('Ошибка: задай в .env APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY, APPWRITE_DATABASE_ID, APPWRITE_PRESETS_COLLECTION_ID');
    exit(1);
  }

  print('1/3 Генерация промпта (DeepSeek)...');
  final prompt = await _generatePrompt(deepSeekKey, themeHint);
  if (prompt == null || prompt.isEmpty) {
    print('Не удалось сгенерировать промпт.');
    exit(1);
  }
  print('Промпт: ${prompt.length} символов');

  print('2/3 Генерация изображения (Nano Banana)...');
  final imageUrl = await _generateImage(piapiKey, prompt);
  if (imageUrl == null || imageUrl.isEmpty) {
    print('Не удалось получить изображение.');
    exit(1);
  }
  print('Изображение: $imageUrl');

  print('3/3 Сохранение пресета в Appwrite...');
  final baseUrl = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final docId = await _createPresetDocument(
    baseUrl: baseUrl,
    projectId: projectId,
    apiKey: appwriteKey,
    databaseId: databaseId,
    collectionId: collectionId,
    prompt: prompt,
    previewImageUrl: imageUrl,
  );
  if (docId == null) {
    print('Не удалось создать документ в Appwrite.');
    exit(1);
  }
  print('Пресет создан: $docId');
}

Future<String?> _generatePrompt(String apiKey, String? themeHint) async {
  final userContent = themeHint != null && themeHint.isNotEmpty
      ? 'Generate one photo session prompt. Optional theme or idea: $themeHint'
      : 'Generate one new, creative photo session prompt. Choose an interesting setting and style.';
  final content = '$_deepSeekSystemPrompt\n\n$userContent';

  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('https://api.deepseek.com/v1/chat/completions'));
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Authorization', 'Bearer $apiKey');
    req.write(jsonEncode({
      'model': 'deepseek-chat',
      'messages': [
        {'role': 'user', 'content': content},
      ],
      'max_tokens': 2000,
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();

    if (res.statusCode != 200) {
      print('DeepSeek HTTP ${res.statusCode}: $body');
      return null;
    }
    final json = jsonDecode(body) as Map<String, dynamic>?;
    if (json == null) return null;
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map<String, dynamic>) return null;
    final message = first['message'];
    if (message is! Map<String, dynamic>) return null;
    var text = message['content'] as String? ?? '';
    text = text.trim();
    if (text.startsWith('"') && text.endsWith('"') && text.length > 1) text = text.substring(1, text.length - 1).trim();
    if (text.toLowerCase().startsWith('prompt:')) text = text.substring(7).trim();
    return text.isEmpty ? null : text;
  } catch (e) {
    print('DeepSeek: $e');
    client.close();
    return null;
  }
}

Future<String?> _generateImage(String apiKey, String prompt) async {
  const taskUrl = 'https://api.piapi.ai/api/v1/task';
  final client = HttpClient();
  try {
    final createRes = await client.postUrl(Uri.parse(taskUrl));
    createRes.headers.set('Content-Type', 'application/json');
    createRes.headers.set('X-API-Key', apiKey);
    createRes.write(jsonEncode({
      'model': 'gemini',
      'task_type': 'nano-banana-pro',
      'input': {
        'prompt': prompt,
        'output_format': 'png',
        'aspect_ratio': '3:4',
        'resolution': '1K',
        'safety_level': 'high',
      },
    }));
    var res = await createRes.close();
    var body = await res.transform(utf8.decoder).join();
    var json = jsonDecode(body) as Map<String, dynamic>?;
    if (json == null || res.statusCode < 200 || res.statusCode >= 300) {
      print('Nano Banana create: ${res.statusCode} $body');
      return null;
    }
    var data = json['data'];
    if (data is! Map<String, dynamic>) return null;
    final taskId = data['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) return null;

    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      final getReq = await client.getUrl(Uri.parse('$taskUrl/$taskId'));
      getReq.headers.set('X-API-Key', apiKey);
      res = await getReq.close();
      body = await res.transform(utf8.decoder).join();
      json = jsonDecode(body) as Map<String, dynamic>?;
      if (json == null || res.statusCode != 200) continue;
      data = json['data'];
      if (data is! Map<String, dynamic>) continue;
      final status = (data['status'] as String? ?? '').toLowerCase();
      if (status == 'failed') {
        print('Nano Banana task failed: $data');
        return null;
      }
      if (status == 'completed') {
        final output = data['output'];
        if (output is Map<String, dynamic>) {
          final url = output['image_url'] as String?;
          if (url != null && url.isNotEmpty) return url;
          final urls = output['image_urls'];
          if (urls is List && urls.isNotEmpty && urls.first is String) return urls.first as String;
        }
        return null;
      }
    }
    print('Nano Banana: timeout');
    return null;
  } finally {
    client.close();
  }
}

Future<String?> _createPresetDocument({
  required String baseUrl,
  required String projectId,
  required String apiKey,
  required String databaseId,
  required String collectionId,
  required String prompt,
  required String previewImageUrl,
}) async {
  final path = 'databases/$databaseId/collections/$collectionId/documents';
  final uri = Uri.parse('$baseUrl$path');
  final client = HttpClient();
  try {
    final docId = 'preset_${DateTime.now().millisecondsSinceEpoch}';
    final req = await client.postUrl(uri);
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('X-Appwrite-Project', projectId);
    req.headers.set('X-Appwrite-Key', apiKey);
    final title = _shortTitle(prompt);
    req.write(jsonEncode({
      'documentId': docId,
      'data': {
        'prompt': prompt,
        'previewImageUrl': previewImageUrl,
        if (title.isNotEmpty) 'title': title,
        'createdAt': DateTime.now().toIso8601String(),
      },
      'permissions': ['read("any")'],
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();
    if (res.statusCode >= 200 && res.statusCode < 300) return docId;
    print('Appwrite document: ${res.statusCode} $body');
    return null;
  } catch (e) {
    print('Appwrite: $e');
    client.close();
    return null;
  }
}

String _shortTitle(String prompt) {
  const maxLen = 50;
  final t = prompt.trim();
  if (t.length <= maxLen) return t;
  final cut = t.substring(0, maxLen);
  final lastSpace = cut.lastIndexOf(' ');
  if (lastSpace > 20) return '${cut.substring(0, lastSpace)}...';
  return '$cut...';
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
