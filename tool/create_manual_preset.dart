// Создание пресета с готовым промптом
// dart run tool/create_manual_preset.dart

import 'dart:convert';
import 'dart:io';

const String manualPrompt = '''
SCENE DESCRIPTION:
A modern upscale restaurant interior with a warm, sophisticated atmosphere. The setting features grey-beige concrete walls with black metal accents, amber woven pendant lights hanging above, and fairy string lights glowing softly in the background. Other guests are visible in the distance, creating a lively yet intimate dining environment. The table in the foreground is light brown wood with pronounced natural grain texture.

CHARACTER:
A man is seated at the table, leaning back slightly in his chair in a relaxed, confident posture. He holds a glass of red wine in one hand, gazing directly at the camera with a calm, composed expression. His other hand rests casually on the table. He wears a white cotton polo shirt paired with an expensive gold wristwatch that catches the light. The framing is a medium shot from the waist up, captured at eye level with centered composition. Facial features, skin texture, age, and hair color must be preserved exactly as in the reference photo without any alterations.

OBJECTS AND DETAILS:
Several deep black ceramic plates with artfully plated dishes are arranged on the table in the foreground. A wine glass filled with rich red wine is held in the subject's hand, with reflections and highlights visible on the glass surface and ceramic plates.

ATMOSPHERE AND MOOD:
Sophisticated, relaxed, and confident. The mood is upscale yet approachable, combining elegance with casual comfort. The atmosphere conveys success and refined taste in a contemporary social dining setting.

COLOR PALETTE:
Warm amber lighting with grey-beige neutrals, black accents, light brown wood tones, and pops of gold from the watch and string lights. The red wine provides a rich color contrast against the neutral palette.

TECHNICAL PARAMETERS:
Mixed ambient lighting with warm overhead illumination, medium contrast with soft shadows, highlights on glass and ceramic surfaces. Shot with 50mm lens at f/2.8 aperture for moderate depth of field, keeping the face and wine glass in sharp focus while gently blurring the background. Professional photography, high resolution, sharp focus, photorealistic, natural skin texture, 3:4 aspect ratio, raw photo quality.
''';

void main() async {
  final env = _loadEnv();
  
  final piapiKey = env['PIAPI_API_KEY']?.trim();
  final endpoint = env['APPWRITE_ENDPOINT']?.trim();
  final projectId = env['APPWRITE_PROJECT_ID']?.trim();
  final appwriteKey = env['APPWRITE_API_KEY']?.trim();
  final databaseId = env['APPWRITE_DATABASE_ID']?.trim();
  final collectionId = env['APPWRITE_PRESETS_COLLECTION_ID']?.trim();

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

  print('1/2 Генерация изображения (Nano Banana)...');
  print('Промпт: ${manualPrompt.length} символов');
  final imageUrl = await _generateImage(piapiKey, manualPrompt);
  if (imageUrl == null || imageUrl.isEmpty) {
    print('Не удалось получить изображение.');
    exit(1);
  }
  print('Изображение: $imageUrl');

  print('2/2 Сохранение пресета в Appwrite...');
  final baseUrl = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final docId = await _createPresetDocument(
    baseUrl: baseUrl,
    projectId: projectId,
    apiKey: appwriteKey,
    databaseId: databaseId,
    collectionId: collectionId,
    prompt: manualPrompt,
    previewImageUrl: imageUrl,
    title: 'Restaurant Elegance',
  );
  if (docId == null) {
    print('Не удалось создать документ в Appwrite.');
    exit(1);
  }
  print('Пресет создан: $docId');
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
      print('Nano Banana create: ${res.statusCode} $body');
      return null;
    }
    var data = json['data'];
    if (data is! Map<String, dynamic>) return null;
    final taskId = data['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) return null;
    print('Task ID: $taskId');

    final deadline = DateTime.now().add(const Duration(minutes: 5));
    var attempts = 0;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 3));
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
      print('Попытка #$attempts: статус=$status');
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
    print('Nano Banana: timeout после $attempts попыток');
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
  String? title,
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
    req.write(jsonEncode({
      'documentId': docId,
      'data': {
        'prompt': prompt,
        'previewImageUrl': previewImageUrl,
        if (title != null && title.isNotEmpty) 'title': title,
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
