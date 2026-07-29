import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../lib/firebase_options.dart';

Future<void> main() async {
  print('🔍 Анализ пресетов на наличие миниатюр...\n');
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  final firestore = FirebaseFirestore.instance;
  
  try {
    final presetsSnapshot = await firestore.collection('presets').get();
    
    int total = 0;
    int withThumbnail = 0;
    int withoutThumbnail = 0;
    List<Map<String, dynamic>> missingPresets = [];
    
    for (final doc in presetsSnapshot.docs) {
      total++;
      final data = doc.data();
      
      if (data.containsKey('thumbnailUrl') && data['thumbnailUrl'] != null && data['thumbnailUrl'].toString().isNotEmpty) {
        withThumbnail++;
      } else {
        withoutThumbnail++;
        missingPresets.add({
          'id': doc.id,
          'title': data['title'] ?? 'Без названия',
          'previewImageUrl': data['previewImageUrl'] ?? 'НЕТ',
          'isPublic': data['isPublic'] ?? false,
        });
      }
    }
    
    print('═══════════════════════════════════════════════════');
    print('📊 Всего пресетов: $total');
    print('✅ С миниатюрой (thumbnailUrl): $withThumbnail (${(withThumbnail/total*100).toStringAsFixed(1)}%)');
    print('❌ Без миниатюры: $withoutThumbnail (${(withoutThumbnail/total*100).toStringAsFixed(1)}%)');
    print('═══════════════════════════════════════════════════\n');
    
    if (missingPresets.isNotEmpty) {
      print('📋 Пресеты без миниатюр (первые 20):\n');
      
      for (int i = 0; i < missingPresets.length && i < 20; i++) {
        final preset = missingPresets[i];
        print('${i+1}. ${preset['id']}');
        print('   Название: ${preset['title']}');
        print('   Публичный: ${preset['isPublic']}');
        print('   Preview: ${preset['previewImageUrl'] != 'НЕТ' ? '✓' : '✗'}');
        print('');
      }
      
      if (missingPresets.length > 20) {
        print('... и ещё ${missingPresets.length - 20} пресетов\n');
      }
      
      print('💡 Для генерации миниатюр выполните:');
      print('   curl -X POST https://us-central1-photosession-ai-cbfc3.cloudfunctions.net/backfillThumbnails');
    } else {
      print('✅ У всех пресетов есть миниатюры!');
    }
    
  } catch (e) {
    print('❌ Ошибка: $e');
    exit(1);
  }
  
  exit(0);
}
