#!/usr/bin/env node

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const GENERATED_PRESETS_PATH = path.join(__dirname, 'generated_presets.json');

async function main() {
  console.log('=== Загрузка пресетов в Firebase ===\n');

  if (!admin.apps.length) {
    try {
      admin.initializeApp({
        projectId: 'photosession-ai-cbfc3',
      });
      console.log('✅ Firebase Admin SDK инициализирован\n');
    } catch (error) {
      console.error('❌ Ошибка инициализации Firebase:', error.message);
      console.log('\n💡 Убедитесь, что выполнена авторизация:');
      console.log('   gcloud auth application-default login');
      process.exit(1);
    }
  }

  const db = admin.firestore();
  const presetsCollection = db.collection('presets');

  if (!fs.existsSync(GENERATED_PRESETS_PATH)) {
    console.error('❌ Файл generated_presets.json не найден');
    console.log('💡 Сначала запустите: dart tool/generate_presets_simple.dart');
    process.exit(1);
  }

  const presetsData = JSON.parse(fs.readFileSync(GENERATED_PRESETS_PATH, 'utf8'));
  console.log(`📋 Загружено ${presetsData.length} пресетов\n`);

  let successCount = 0;
  let failCount = 0;

  for (let i = 0; i < presetsData.length; i++) {
    const preset = presetsData[i];
    const title = preset.title;
    
    console.log(`[${i + 1}/${presetsData.length}] 📸 ${title}`);
    
    try {
      const timestamp = Date.now();
      const titleSlug = title.toLowerCase().replace(/[^a-z0-9]+/g, '_');
      const docId = `preset_${timestamp}_${titleSlug}`;

      const docData = {
        title: preset.title,
        prompt: preset.prompt,
        previewImageUrl: preset.previewImageUrl,
        tags: preset.tags || [],
        createdAt: admin.firestore.Timestamp.fromDate(new Date(preset.createdAt)),
      };

      await presetsCollection.doc(docId).set(docData);
      
      console.log('  ✅ Загружено в Firestore\n');
      successCount++;
    } catch (error) {
      console.error('  ❌ Ошибка:', error.message, '\n');
      failCount++;
    }
  }

  console.log('═══════════════════════════════════════');
  console.log('📊 ИТОГИ');
  console.log('═══════════════════════════════════════');
  console.log(`✅ Успешно: ${successCount}`);
  console.log(`❌ Ошибки: ${failCount}`);
  
  if (successCount > 0) {
    console.log('\n🎉 Пресеты доступны в приложении!');
  }

  process.exit(0);
}

main().catch(error => {
  console.error('❌ Критическая ошибка:', error);
  process.exit(1);
});
