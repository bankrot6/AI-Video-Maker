// Простой скрипт генерации пресетов без зависимостей Flutter
// Запуск: dart tool/generate_presets_simple.dart

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
- Use professional photography terminology
- Be EXTREMELY detailed and concrete in every section
- NO generic phrases - every detail must be specific and visual
- Keep prompt concise yet detailed (aim for 250-400 words total)
Output the complete structured prompt. No quotes, no "Here is...", just content.''';

void main() async {
  print('=== Генерация пресетов Photosesser ===\n');
  
  final env = _loadEnv();
  final deepSeekKey = env['DEEPSEEK_API_KEY']?.trim();
  final piapiKey = env['PIAPI_API_KEY']?.trim();

  if (deepSeekKey == null || deepSeekKey.isEmpty) {
    print('❌ DEEPSEEK_API_KEY не найден в .env');
    exit(1);
  }
  if (piapiKey == null || piapiKey.isEmpty) {
    print('❌ PIAPI_API_KEY не найден в .env');
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

  for (var i = 0; i < ideas.length; i++) {
    final idea = ideas[i] as Map<String, dynamic>;
    final title = idea['title'] as String;
    final theme = idea['theme'] as String;
    final tags = (idea['tags'] as List).cast<String>();

    print('─────────────────────────────────────');
    print('[${ i + 1}/${ideas.length}] 🎨 $title');
    print('─────────────────────────────────────');

    try {
      print('🤖 Генерация промпта через DeepSeek...');
      final prompt = await _generatePrompt(deepSeekKey, theme);
      if (prompt == null || prompt.isEmpty) {
        print('❌ Не удалось сгенерировать промпт\n');
        continue;
      }
      print('✅ Промпт: ${prompt.length} символов');
      print('─── Промпт (первые 150 символов) ───');
      print(prompt.substring(0, prompt.length > 150 ? 150 : prompt.length));
      print('...\n');

      print('🖼️  Генерация превью через Nano Banana...');
      final imageUrl = await _generateImage(piapiKey, prompt);
      if (imageUrl == null || imageUrl.isEmpty) {
        print('❌ Не удалось сгенерировать изображение\n');
        continue;
      }
      print('✅ Изображение: $imageUrl\n');

      results.add({
        'title': title,
        'prompt': prompt,
        'previewImageUrl': imageUrl,
        'tags': tags,
        'createdAt': DateTime.now().toIso8601String(),
      });

      print('💾 Сохранено в очередь\n');
    } catch (e) {
      print('❌ Ошибка: $e\n');
    }
  }

  print('\n═══════════════════════════════════════');
  print('📊 ИТОГИ');
  print('═══════════════════════════════════════');
  print('✅ Успешно сгенерировано: ${results.length}/${ideas.length}');
  print('❌ Ошибки: ${ideas.length - results.length}');

  if (results.isNotEmpty) {
    final outputFile = File('tool/generated_presets.json');
    await outputFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(results),
    );
    print('\n💾 Данные сохранены: ${outputFile.path}');
    print('\n📤 Следующий шаг:');
    print('   dart tool/upload_to_firebase.dart');
  } else {
    print('\n❌ Не удалось сгенерировать ни одного пресета');
  }
}

Future<String?> _generatePrompt(String apiKey, String theme) async {
  final userContent = 'Generate one professional photo session prompt based on this theme: $theme';
  
  final client = HttpClient();
  try {
    final req = await client.postUrl(
      Uri.parse('https://api.deepseek.com/v1/chat/completions'),
    );
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Authorization', 'Bearer $apiKey');
    
    final payload = {
      'model': 'deepseek-chat',
      'messages': [
        {'role': 'system', 'content': _deepSeekSystemPrompt},
        {'role': 'user', 'content': userContent},
      ],
      'max_tokens': 2000,
      'temperature': 0.8,
    };
    
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    
    if (res.statusCode != 200) {
      print('  ⚠️  DeepSeek HTTP ${res.statusCode}');
      return null;
    }
    
    final json = jsonDecode(body) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;
    
    final message = choices[0]['message'] as Map<String, dynamic>?;
    if (message == null) return null;
    
    var text = (message['content'] as String? ?? '').trim();
    
    if (text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1);
    }
    if (text.toLowerCase().startsWith('prompt:')) {
      text = text.substring(7).trim();
    }
    
    return text.isEmpty ? null : text;
  } catch (e) {
    print('  ⚠️  DeepSeek exception: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<String?> _generateImage(String apiKey, String prompt) async {
  const taskUrl = 'https://api.piapi.ai/api/v1/task';
  final client = HttpClient();
  
  try {
    final createReq = await client.postUrl(Uri.parse(taskUrl));
    createReq.headers.set('Content-Type', 'application/json');
    createReq.headers.set('X-API-Key', apiKey);
    
    final payload = {
      'model': 'gemini',
      'task_type': 'nano-banana-pro',
      'input': {
        'prompt': prompt,
        'output_format': 'jpeg',
        'aspect_ratio': '3:4',
        'resolution': '2K',
        'safety_level': 'high',
      },
    };
    
    createReq.write(jsonEncode(payload));
    var res = await createReq.close();
    var body = await res.transform(utf8.decoder).join();
    
    if (res.statusCode < 200 || res.statusCode >= 300) {
      print('  ⚠️  Nano Banana create: ${res.statusCode}');
      return null;
    }
    
    var json = jsonDecode(body) as Map<String, dynamic>;
    var data = json['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    
    final taskId = data['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) return null;

    print('  📋 Task ID: $taskId');
    print('  ⏳ Ожидание результата...');

    final deadline = DateTime.now().add(const Duration(minutes: 5));
    var attempts = 0;
    
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 5));
      attempts++;
      
      final getReq = await client.getUrl(Uri.parse('$taskUrl/$taskId'));
      getReq.headers.set('X-API-Key', apiKey);
      res = await getReq.close();
      body = await res.transform(utf8.decoder).join();
      
      if (res.statusCode != 200) {
        print('  ⚠️  Poll attempt $attempts: HTTP ${res.statusCode}');
        continue;
      }
      
      json = jsonDecode(body) as Map<String, dynamic>;
      data = json['data'] as Map<String, dynamic>?;
      if (data == null) continue;
      
      final status = (data['status'] as String? ?? '').toLowerCase();
      print('  📊 Попытка $attempts: $status');
      
      if (status == 'failed') {
        print('  ❌ Task провалился');
        return null;
      }
      
      if (status == 'completed') {
        final output = data['output'] as Map<String, dynamic>?;
        if (output != null) {
          final url = output['image_url'] as String?;
          if (url != null && url.isNotEmpty) return url;
          
          final urls = output['image_urls'] as List?;
          if (urls != null && urls.isNotEmpty) {
            return urls.first as String;
          }
        }
        return null;
      }
    }
    
    print('  ⏱️  Timeout после $attempts попыток');
    return null;
  } catch (e) {
    print('  ⚠️  Exception: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}

Map<String, String> _loadEnv() {
  final file = File('.env');
  if (!file.existsSync()) {
    print('⚠️  Файл .env не найден');
    return {};
  }
  
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
