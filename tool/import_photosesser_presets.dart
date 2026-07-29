// Импорт пресетов на основе идей из @photosesser Telegram канала
// Генерирует промпты (DeepSeek) → превью (Nano Banana) → сохраняет в Firebase
// Запуск: dart run tool/import_photosesser_presets.dart

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
[Lighting: golden hour/harsh flash/soft window light/studio softbox/Rembrandt lighting/backlight. Camera: 35mm/50mm/85mm lens, f/1.4-f/2.8 aperture for portraits. Add: "professional photography, high resolution, sharp focus, raw photo, natural skin texture, 3:4 aspect ratio, photorealistic"]

CRITICAL RULES:
- Output ONLY the 6-section structured prompt in English
- Use professional photography terminology (aperture, bokeh, depth of field, Rembrandt lighting, etc.)
- Be EXTREMELY detailed and concrete in every section
- NO generic phrases - every detail must be specific and visual
- Include realistic technical specs (lens, lighting, film stock if vintage)
- Keep prompt concise yet detailed (aim for 250-400 words total)
Output the complete structured prompt. No quotes, no "Here is...", just content.''';

void main() async {
  print('=== Импорт пресетов Photosesser ===\n');
  
  final env = _loadEnv();
  final deepSeekKey = env['DEEPSEEK_API_KEY']?.trim();
  final piapiKey = env['PIAPI_API_KEY']?.trim();
  final firebaseProjectId = env['FIREBASE_PROJECT_ID']?.trim();

  if (deepSeekKey == null || deepSeekKey.isEmpty) {
    print('❌ Ошибка: задай DEEPSEEK_API_KEY в .env');
    exit(1);
  }
  if (piapiKey == null || piapiKey.isEmpty) {
    print('❌ Ошибка: задай PIAPI_API_KEY в .env');
    exit(1);
  }
  if (firebaseProjectId == null || firebaseProjectId.isEmpty) {
    print('❌ Ошибка: задай FIREBASE_PROJECT_ID в .env');
    exit(1);
  }

  final ideasFile = File('tool/photosesser_ideas.json');
  if (!ideasFile.existsSync()) {
    print('❌ Файл tool/photosesser_ideas.json не найден');
    exit(1);
  }

  final ideas = jsonDecode(await ideasFile.readAsString()) as List;
  print('📋 Загружено ${ideas.length} идей\n');

  final results = <Map<String, dynamic>>[];
  var successCount = 0;
  var failCount = 0;

  for (var i = 0; i < ideas.length; i++) {
    final idea = ideas[i] as Map<String, dynamic>;
    final title = idea['title'] as String;
    final theme = idea['theme'] as String;
    final tags = (idea['tags'] as List).cast<String>();

    print('[${ i + 1}/${ideas.length}] 🎨 $title');
    print('  Тема: $theme');

    print('  ├─ Генерация промпта (DeepSeek)...');
    final prompt = await _generatePrompt(deepSeekKey, theme);
    if (prompt == null || prompt.isEmpty) {
      print('  └─ ❌ Не удалось сгенерировать промпт\n');
      failCount++;
      continue;
    }
    print('  ├─ ✅ Промпт готов (${prompt.length} символов)');

    print('  ├─ Генерация превью (Nano Banana)...');
    final imageUrl = await _generateImage(piapiKey, prompt);
    if (imageUrl == null || imageUrl.isEmpty) {
      print('  └─ ❌ Не удалось сгенерировать превью\n');
      failCount++;
      continue;
    }
    print('  ├─ ✅ Превью создано');

    results.add({
      'title': title,
      'prompt': prompt,
      'previewImageUrl': imageUrl,
      'tags': tags,
      'createdAt': DateTime.now().toIso8601String(),
    });

    print('  └─ ✅ Готов к импорту\n');
    successCount++;

    await Future.delayed(const Duration(seconds: 2));
  }

  print('=== Результаты ===');
  print('✅ Успешно: $successCount');
  print('❌ Ошибки: $failCount');

  if (results.isNotEmpty) {
    final outputFile = File('tool/generated_presets.json');
    await outputFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(results),
    );
    print('\n📦 Данные сохранены в: ${outputFile.path}');
    print('\n💡 Теперь импортируйте в Firebase:');
    print('   dart run tool/upload_to_firebase.dart');
  }
}

Future<String?> _generatePrompt(String apiKey, String theme) async {
  final userContent = 'Generate one photo session prompt based on this theme: $theme';
  final content = '$_deepSeekSystemPrompt\n\n$userContent';

  final client = HttpClient();
  try {
    final req = await client.postUrl(
      Uri.parse('https://api.deepseek.com/v1/chat/completions'),
    );
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Authorization', 'Bearer $apiKey');
    req.write(jsonEncode({
      'model': 'deepseek-chat',
      'messages': [
        {'role': 'user', 'content': content},
      ],
      'max_tokens': 2000,
      'temperature': 0.8,
    }));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();

    if (res.statusCode != 200) {
      print('    DeepSeek HTTP ${res.statusCode}: ${body.substring(0, 200)}');
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
    if (text.startsWith('"') && text.endsWith('"') && text.length > 1) {
      text = text.substring(1, text.length - 1).trim();
    }
    if (text.toLowerCase().startsWith('prompt:')) {
      text = text.substring(7).trim();
    }
    return text.isEmpty ? null : text;
  } catch (e) {
    print('    DeepSeek error: $e');
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
        'output_format': 'jpeg',
        'aspect_ratio': '3:4',
        'resolution': '2K',
        'safety_level': 'high',
      },
    }));
    var res = await createRes.close();
    var body = await res.transform(utf8.decoder).join();
    var json = jsonDecode(body) as Map<String, dynamic>?;
    if (json == null || res.statusCode < 200 || res.statusCode >= 300) {
      print('    Nano Banana create: ${res.statusCode}');
      return null;
    }
    var data = json['data'];
    if (data is! Map<String, dynamic>) return null;
    final taskId = data['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) return null;

    final deadline = DateTime.now().add(const Duration(minutes: 5));
    var attempts = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 4));
      attempts++;
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
        print('    Task failed');
        return null;
      }
      if (status == 'completed') {
        final output = data['output'];
        if (output is Map<String, dynamic>) {
          final url = output['image_url'] as String?;
          if (url != null && url.isNotEmpty) return url;
          final urls = output['image_urls'];
          if (urls is List && urls.isNotEmpty && urls.first is String) {
            return urls.first as String;
          }
        }
        return null;
      }
    }
    print('    Timeout после $attempts попыток');
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
