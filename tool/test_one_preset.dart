// Тест генерации одного пресета
// Запуск: dart tool/test_one_preset.dart

import 'dart:convert';
import 'dart:io';

const theme = 'child playing in a rustic garden setting with fresh vegetables and natural props';

const systemPrompt = '''
You are an expert prompt engineer for AI-powered professional photo sessions. Generate a HIGHLY DETAILED image generation prompt in English with a structured format.

MANDATORY STRUCTURE (6 sections):

SCENE DESCRIPTION:
[2-4 sentences describing setting, environment, atmosphere, key objects, background.]

CHARACTER:
[2-3 sentences: specific clothing items, accessories, pose, gaze direction. ALWAYS include: "Facial features, skin texture, age, and hair color must be preserved exactly as in the reference photo without any alterations."]

OBJECTS AND DETAILS:
[1-2 sentences listing concrete props, materials, textures.]

ATMOSPHERE AND MOOD:
[1-2 sentences: emotional tone]

COLOR PALETTE:
[1 sentence with specific color names and tones]

TECHNICAL PARAMETERS:
[Lighting, Camera specs. Add: "professional photography, high resolution, sharp focus, raw photo, natural skin texture, 3:4 aspect ratio, photorealistic"]

Output ONLY the structured prompt. No quotes, no preamble.''';

void main() async {
  print('🧪 Тест генерации одного пресета\n');
  print('Тема: $theme\n');
  
  final env = _loadEnv();
  final key = env['DEEPSEEK_API_KEY']?.trim();
  
  if (key == null || key.isEmpty) {
    print('❌ DEEPSEEK_API_KEY не найден');
    exit(1);
  }
  
  print('🤖 Запрос к DeepSeek...');
  
  final client = HttpClient();
  try {
    final req = await client.postUrl(
      Uri.parse('https://api.deepseek.com/v1/chat/completions'),
    );
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('Authorization', 'Bearer $key');
    
    req.write(jsonEncode({
      'model': 'deepseek-chat',
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': 'Generate one prompt for: $theme'},
      ],
      'max_tokens': 2000,
      'temperature': 0.8,
    }));
    
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    
    print('📡 HTTP ${res.statusCode}\n');
    
    if (res.statusCode == 200) {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      final message = choices?[0]['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;
      
      if (content != null) {
        print('✅ РЕЗУЛЬТАТ:\n');
        print('═══════════════════════════════════════');
        print(content);
        print('═══════════════════════════════════════\n');
        print('📏 Длина: ${content.length} символов');
      } else {
        print('❌ Пустой ответ');
      }
    } else {
      print('❌ Ошибка: $body');
    }
  } catch (e) {
    print('❌ Exception: $e');
  } finally {
    client.close(force: true);
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
    out[key] = value;
  }
  return out;
}
