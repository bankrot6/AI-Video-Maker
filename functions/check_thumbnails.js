const admin = require('firebase-admin');

admin.initializeApp({
  projectId: 'photosession-ai-cbfc3',
});

async function checkThumbnails() {
  const db = admin.firestore();
  
  console.log('🔍 Анализ пресетов на наличие миниатюр...\n');
  
  const presetsSnapshot = await db.collection('presets').get();
  
  let total = 0;
  let withThumbnail = 0;
  let withoutThumbnail = 0;
  let missingPresets = [];
  
  presetsSnapshot.forEach(doc => {
    total++;
    const data = doc.data();
    
    if (data.thumbnailUrl) {
      withThumbnail++;
    } else {
      withoutThumbnail++;
      missingPresets.push({
        id: doc.id,
        title: data.title || 'Без названия',
        previewImageUrl: data.previewImageUrl || 'НЕТ',
        isPublic: data.isPublic || false,
      });
    }
  });
  
  console.log('═══════════════════════════════════════════════════');
  console.log(`📊 Всего пресетов: ${total}`);
  console.log(`✅ С миниатюрой (thumbnailUrl): ${withThumbnail} (${(withThumbnail/total*100).toFixed(1)}%)`);
  console.log(`❌ Без миниатюры: ${withoutThumbnail} (${(withoutThumbnail/total*100).toFixed(1)}%)`);
  console.log('═══════════════════════════════════════════════════\n');
  
  if (missingPresets.length > 0) {
    console.log(`📋 Пресеты без миниатюр (первые 20):\n`);
    missingPresets.slice(0, 20).forEach((preset, i) => {
      console.log(`${i+1}. ${preset.id}`);
      console.log(`   Название: ${preset.title}`);
      console.log(`   Публичный: ${preset.isPublic}`);
      console.log(`   Preview: ${preset.previewImageUrl ? '✓' : '✗'}`);
      console.log('');
    });
    
    if (missingPresets.length > 20) {
      console.log(`... и ещё ${missingPresets.length - 20} пресетов\n`);
    }
    
    console.log('💡 Для генерации миниатюр выполните:');
    console.log('   curl -X POST https://us-central1-photosession-ai-cbfc3.cloudfunctions.net/backfillThumbnails');
  }
  
  process.exit(0);
}

checkThumbnails().catch(error => {
  console.error('❌ Ошибка:', error);
  process.exit(1);
});
