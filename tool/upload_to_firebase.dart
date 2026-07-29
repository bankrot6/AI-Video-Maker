// Загрузка сгенерированных пресетов в Firebase Firestore
// Запуск: dart run tool/upload_to_firebase.dart

import 'dart:convert';
import 'dart:io';

void main() async {
  print('=== Загрузка пресетов в Firebase ===\n');

  final env = _loadEnv();
  final firebaseProjectId = env['FIREBASE_PROJECT_ID']?.trim();
  
  if (firebaseProjectId == null || firebaseProjectId.isEmpty) {
    print('❌ Ошибка: задай FIREBASE_PROJECT_ID в .env');
    exit(1);
  }

  final presetsFile = File('tool/generated_presets.json');
  if (!presetsFile.existsSync()) {
    print('❌ Файл tool/generated_presets.json не найден');
    print('💡 Сначала запустите: dart run tool/import_photosesser_presets.dart');
    exit(1);
  }

  final presets = jsonDecode(await presetsFile.readAsString()) as List;
  print('📋 Загружено ${presets.length} пресетов для импорта\n');

  print('🔧 Инициализация Firebase Admin SDK...');
  
  final serviceAccountPath = env['FIREBASE_SERVICE_ACCOUNT_PATH']?.trim() ?? 
                             'firebase-service-account.json';
  final serviceAccountFile = File(serviceAccountPath);
  
  if (!serviceAccountFile.existsSync()) {
    print('❌ Файл сервисного аккаунта не найден: $serviceAccountPath');
    print('💡 Скачайте его из Firebase Console → Project Settings → Service Accounts');
    print('💡 Или укажите путь в .env: FIREBASE_SERVICE_ACCOUNT_PATH=/path/to/key.json');
    exit(1);
  }

  print('📤 Загрузка пресетов в Firestore...\n');

  var successCount = 0;
  var failCount = 0;

  for (var i = 0; i < presets.length; i++) {
    final preset = presets[i] as Map<String, dynamic>;
    final title = preset['title'] as String;
    
    print('[${ i + 1}/${presets.length}] 📸 $title');
    
    final success = await _uploadToFirestore(
      serviceAccountPath: serviceAccountPath,
      projectId: firebaseProjectId,
      preset: preset,
    );

    if (success) {
      print('  └─ ✅ Загружено\n');
      successCount++;
    } else {
      print('  └─ ❌ Ошибка загрузки\n');
      failCount++;
    }
  }

  print('=== Итоги ===');
  print('✅ Успешно: $successCount');
  print('❌ Ошибки: $failCount');
  
  if (successCount > 0) {
    print('\n🎉 Пресеты доступны в приложении!');
  }
}

Future<bool> _uploadToFirestore({
  required String serviceAccountPath,
  required String projectId,
  required Map<String, dynamic> preset,
}) async {
  final client = HttpClient();
  try {
    final docId = 'preset_${DateTime.now().millisecondsSinceEpoch}_${(preset['title'] as String).replaceAll(' ', '_').toLowerCase()}';
    final url = 'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/presets?documentId=$docId';
    
    final req = await client.postUrl(Uri.parse(url));
    req.headers.set('Content-Type', 'application/json');
    
    final fields = <String, dynamic>{};
    preset.forEach((key, value) {
      if (value is String) {
        fields[key] = {'stringValue': value};
      } else if (value is List) {
        fields[key] = {
          'arrayValue': {
            'values': value.map((v) => {'stringValue': v.toString()}).toList(),
          },
        };
      }
    });

    req.write(jsonEncode({
      'fields': fields,
    }));

    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return true;
    } else {
      print('  Firestore HTTP ${res.statusCode}: ${body.substring(0, 200)}');
      return false;
    }
  } catch (e) {
    print('  Exception: $e');
    client.close();
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
