import 'dart:convert';
import 'dart:io';

const _adminApiKey = 'photosession_admin_key_2026_secure_secret';

void main() async {
  print('=== Загрузка пресетов через Cloud Function ===\n');

  final env = _loadEnv();
  final projectId = env['FIREBASE_PROJECT_ID']?.trim() ?? 'photosession-ai-cbfc3';
  
  final cloudFunctionUrl = 'https://us-central1-$projectId.cloudfunctions.net/createPresetsBatch';
  
  final presetsFile = File('tool/generated_presets.json');
  if (!presetsFile.existsSync()) {
    print('❌ Файл tool/generated_presets.json не найден');
    print('💡 Сначала запустите: dart tool/generate_presets_simple.dart');
    exit(1);
  }

  final presets = jsonDecode(await presetsFile.readAsString()) as List;
  print('📋 Загружено ${presets.length} пресетов');
  print('🌐 Cloud Function: $cloudFunctionUrl\n');

  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(cloudFunctionUrl));
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('X-Admin-API-Key', _adminApiKey);
    
    req.write(jsonEncode({'presets': presets}));
    
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final result = jsonDecode(body) as Map<String, dynamic>;
      print('✅ Успешно загружено: ${result['successful']}/${result['total']}');
      
      if (result['results'] != null) {
        final results = result['results'] as List;
        for (var i = 0; i < results.length; i++) {
          final r = results[i] as Map<String, dynamic>;
          final status = r['success'] == true ? '✅' : '❌';
          print('  [${ i + 1}] $status ${r['title']}');
        }
      }
      
      print('\n🎉 Пресеты доступны в приложении!');
    } else {
      print('❌ HTTP ${res.statusCode}');
      print('📄 Ответ: $body');
      
      if (res.statusCode == 404) {
        print('\n💡 Cloud Function не развернута. Выполните:');
        print('   1. Исправьте Node.js (см. PRESET_MANAGEMENT_STRATEGY.md)');
        print('   2. npm install в папке functions/');
        print('   3. firebase deploy --only functions');
      } else if (res.statusCode == 403) {
        print('\n💡 Проверьте API ключ в functions/index.js');
      }
    }
  } catch (e) {
    print('❌ Ошибка: $e');
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
    if (value.startsWith("'") && value.endsWith("'")) {
      value = value.substring(1, value.length - 1);
    }
    out[key] = value;
  }
  return out;
}
