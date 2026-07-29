import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> testRewardsSystem() async {
  final firestore = FirebaseFirestore.instance;

  print('🧪 Тестирование системы вознаграждений...\n');

  print('1️⃣ Проверка коллекции preset_earnings...');
  try {
    final earningsSnapshot = await firestore
        .collection('preset_earnings')
        .limit(5)
        .get();
    print('   ✅ Коллекция существует, документов: ${earningsSnapshot.docs.length}');

    if (earningsSnapshot.docs.isNotEmpty) {
      for (final doc in earningsSnapshot.docs) {
        final data = doc.data();
        print('   📊 ${doc.id}:');
        print('      - Лайков: ${data['totalLikes']}');
        print('      - Заработано: ${data['creditsEarned']} кредитов');
      }
    }
  } catch (e) {
    print('   ❌ Ошибка: $e');
  }

  print('\n2️⃣ Проверка публичных пресетов с владельцами...');
  try {
    final presetsSnapshot = await firestore
        .collection('presets')
        .where('isPublic', isEqualTo: true)
        .limit(10)
        .get();
    
    final withOwner = presetsSnapshot.docs.where(
      (doc) => doc.data()['ownerId'] != null && doc.data()['ownerId'] != '',
    ).length;
    
    print('   ✅ Публичных пресетов: ${presetsSnapshot.docs.length}');
    print('   ✅ С владельцем: $withOwner');
    
    final withLikes = presetsSnapshot.docs.where(
      (doc) => (doc.data()['likesCount'] ?? 0) >= 3,
    ).length;
    print('   ✅ С 3+ лайками: $withLikes');
  } catch (e) {
    print('   ❌ Ошибка: $e');
  }

  print('\n3️⃣ Проверка потенциального заработка...');
  try {
    final presetsSnapshot = await firestore
        .collection('presets')
        .where('isPublic', isEqualTo: true)
        .get();

    int totalPotentialCredits = 0;
    int eligiblePresets = 0;

    for (final doc in presetsSnapshot.docs) {
      final data = doc.data();
      final ownerId = data['ownerId'];
      final likes = data['likesCount'] ?? 0;

      if (ownerId != null && ownerId != '' && likes >= 3) {
        final earningsDoc = await firestore
            .collection('preset_earnings')
            .doc(doc.id)
            .get();

        final alreadyEarned = earningsDoc.exists
            ? (earningsDoc.data()?['creditsEarned'] ?? 0)
            : 0;

        final potential = (likes - alreadyEarned).clamp(0, 50);
        if (potential > 0) {
          totalPotentialCredits += potential;
          eligiblePresets++;
        }
      }
    }

    print('   ✅ Пресетов с неначисленными кредитами: $eligiblePresets');
    print('   ✅ Потенциальных кредитов для начисления: $totalPotentialCredits');
  } catch (e) {
    print('   ❌ Ошибка: $e');
  }

  print('\n4️⃣ Статистика по заработкам...');
  try {
    final earningsSnapshot = await firestore
        .collection('preset_earnings')
        .get();

    if (earningsSnapshot.docs.isEmpty) {
      print('   ℹ️  Пока нет данных о заработках');
    } else {
      int totalEarned = 0;
      int totalLikes = 0;
      final Map<String, int> ownerStats = {};

      for (final doc in earningsSnapshot.docs) {
        final data = doc.data();
        totalEarned += data['creditsEarned'] as int? ?? 0;
        totalLikes += data['totalLikes'] as int? ?? 0;

        final ownerId = data['ownerId'] as String;
        ownerStats[ownerId] = (ownerStats[ownerId] ?? 0) + (data['creditsEarned'] as int? ?? 0);
      }

      print('   ✅ Всего заработано: $totalEarned кредитов');
      print('   ✅ Всего лайков: $totalLikes');
      print('   ✅ Уникальных создателей: ${ownerStats.length}');
      
      if (ownerStats.isNotEmpty) {
        final topOwner = ownerStats.entries.reduce(
          (a, b) => a.value > b.value ? a : b,
        );
        print('   🏆 Топ создатель: ${topOwner.key.substring(0, 10)}... (${topOwner.value} кредитов)');
      }
    }
  } catch (e) {
    print('   ❌ Ошибка: $e');
  }

  print('\n✅ Тестирование завершено!\n');
}

void main() async {
  print('Для запуска этого теста нужно:');
  print('1. Интегрировать его в существующий Flutter проект');
  print('2. Вызвать testRewardsSystem() после инициализации Firebase');
  print('\nИли использовать Firebase CLI для проверки данных.');
}
