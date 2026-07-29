// Загрузка сгенерированных пресетов в Firebase Firestore
// Запуск: dart tool/upload_presets_to_firebase.dart

import 'dart:convert';
import 'dart:io';

void main() async {
  print('=== Загрузка пресетов в Firebase ===\n');

  final env = _loadEnv();
  final firebaseProjectId = env['FIREBASE_PROJECT_ID']?.trim();
  final firebaseApiKey = env['FIREBASE_API_KEY']?.trim();
  
  if (firebaseProjectId == null || firebaseProjectId.isEmpty) {
    print('❌ FIREBASE_PROJECT_ID не найден в .env');
    exit(1);
  }
  
  if (firebaseApiKey == null || firebaseApiKey.isEmpty) {
    print('❌ FIREBASE_API_KEY не найден в .env');
    exit(1);
  }

  final presetsFile = File('tool/generated_presets.json');
  if (!presetsFile.existsSync()) {
    print('❌ Файл tool/generated_presets.json не найден');
    print('💡 Сначала запустите: dart tool/generate_presets_simple.dart');
    exit(1);
  }

  final presets = jsonDecode(await presetsFile.readAsString()) as List;
  print('📋 Загружено ${presets.length} пресетов\n');

  var successCount = 0;
  var failCount = 0;

  for (var i = 0; i < presets.length; i++) {
    final preset = presets[i] as Map<String, dynamic>;
    final title = preset['title'] as String;
    
    print('[${ i + 1}/${presets.length}] 📸 $title');
    
    try {
      final success = await _uploadToFirestore(
        projectId: firebaseProjectId,
        apiKey: firebaseApiKey,
        preset: preset,
      );

      if (success) {
        print('  ✅ Загружено в Firestore\n');
        successCount++;
      } else {
        print('  ❌ Ошибка загрузки\n');
        failCount++;
      }
    } catch (e) {
      print('  ❌ Exception: $e\n');
      failCount++;
    }
  }

  print('═══════════════════════════════════════');
  print('📊 ИТОГИ');
  print('═══════════════════════════════════════');
  print('✅ Успешно: $successCount');
  print('❌ Ошибки: $failCount');
  
  if (successCount > 0) {
    print('\n🎉 Пресеты доступны в приложении!');
  }
}

Future<bool> _uploadToFirestore({
  required String projectId,
  required String apiKey,
  required Map<String, dynamic> preset,
}) async {
  final client = HttpClient();
  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final titleSlug = (preset['title'] as String)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final docId = 'preset_${timestamp}_$titleSlug';
    
    final url = 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/presets?documentId=$docId&key=$apiKey';
    
    final req = await client.postUrl(Uri.parse(url));
    req.headers.set('Content-Type', 'application/json');
    
    final fields = <String, dynamic>{};
    
    fields['prompt'] = {'stringValue': preset['prompt'] as String};
    fields['previewImageUrl'] = {'stringValue': preset['previewImageUrl'] as String};
    fields['title'] = {'stringValue': preset['title'] as String};
    fields['createdAt'] = {'stringValue': preset['createdAt'] as String};
    
    final tags = preset['tags'] as List;
    fields['tags'] = {
      'arrayValue': {
        'values': tags.map((tag) => {'stringValue': tag.toString()}).toList(),
      },
    };
    fields['likesCount'] = {'integerValue': '0'};
    fields['likedBy'] = {'arrayValue': <dynamic>{}};

    req.write(jsonEncode({
      'fields': fields,
    }));

    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return true;
    } else {
      print('  ⚠️  Firestore HTTP ${res.statusCode}');
      if (res.statusCode == 401 || res.statusCode == 403) {
        print('  💡 Нужна аутентификация. Используйте Firebase Admin SDK или gcloud auth');
      }
      return false;
    }
  } catch (e) {
    print('  ⚠️  Exception: $e');
    return false;
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
