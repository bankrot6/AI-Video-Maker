import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/photosession_backend.dart';
import '../models/preset_earnings.dart';
import 'credit_service.dart';
import 'device_id_service.dart';

class PresetRewardService {
  static final PresetRewardService _instance = PresetRewardService._internal();
  factory PresetRewardService() => _instance;
  PresetRewardService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<int> syncEarnedCredits() async {
    if (useAppwriteBackend()) {
      debugPrint('💰 REWARD: с Appwrite начисление по Firestore отключено');
      return 0;
    }
    try {
      final deviceId = await DeviceIdService.instance.getDeviceId();

      final presetsSnapshot = await _firestore
          .collection('presets')
          .where('ownerId', isEqualTo: deviceId)
          .where('isPublic', isEqualTo: true)
          .get();

      if (presetsSnapshot.docs.isEmpty) {
        debugPrint('💰 REWARD: Нет публичных пресетов для синхронизации');
        return 0;
      }

      int totalNewCredits = 0;

      for (final presetDoc in presetsSnapshot.docs) {
        final presetData = presetDoc.data();
        final presetId = presetDoc.id;
        final currentLikes = presetData['likesCount'] as int? ?? 0;

        if (currentLikes < PresetEarnings.minLikesForReward) {
          continue;
        }

        final earningsDoc = await _firestore
            .collection('preset_earnings')
            .doc(presetId)
            .get();

        PresetEarnings earnings;
        if (earningsDoc.exists) {
          earnings = PresetEarnings.fromJson(
            earningsDoc.data() as Map<String, dynamic>,
          );
        } else {
          earnings = PresetEarnings.initial(
            presetId: presetId,
            ownerId: deviceId,
          );
        }

        final newCredits = earnings.calculateNewCredits(currentLikes);

        if (newCredits > 0) {
          final updatedEarnings = earnings.copyWith(
            totalLikes: currentLikes,
            creditsEarned: earnings.creditsEarned + newCredits,
            lastProcessedLikes: currentLikes,
            lastProcessedAt: DateTime.now(),
          );

          await _firestore
              .collection('preset_earnings')
              .doc(presetId)
              .set(updatedEarnings.toJson());

          totalNewCredits += newCredits;

          debugPrint('💰 REWARD: Пресет $presetId заработал $newCredits кредитов '
              '($currentLikes лайков)');
        }
      }

      if (totalNewCredits > 0) {
        await CreditService().addEarnedCredits(totalNewCredits);
        debugPrint('🎉 REWARD: Всего начислено $totalNewCredits кредитов');
      } else {
        debugPrint('💰 REWARD: Нет новых кредитов для начисления');
      }

      return totalNewCredits;
    } catch (e, st) {
      debugPrint('🔴 REWARD: Ошибка синхронизации вознаграждений: $e');
      debugPrint('$st');
      return 0;
    }
  }

  /// Сумма [likesCount] по всем публичным пресетам владельца (актуальные данные в `presets`).
  Future<int> sumLiveLikesOnOwnerPublicPresets() async {
    if (useAppwriteBackend()) {
      return 0;
    }
    try {
      final deviceId = await DeviceIdService.instance.getDeviceId();
      final snapshot = await _firestore
          .collection('presets')
          .where('ownerId', isEqualTo: deviceId)
          .where('isPublic', isEqualTo: true)
          .get();

      var sum = 0;
      for (final doc in snapshot.docs) {
        sum += doc.data()['likesCount'] as int? ?? 0;
      }
      return sum;
    } catch (e) {
      debugPrint('🔴 REWARD: sumLiveLikesOnOwnerPublicPresets: $e');
      return 0;
    }
  }

  Future<Map<String, int>> getEarningsStats() async {
    if (useAppwriteBackend()) {
      return {
        'totalCreditsEarned': 0,
        'totalLikes': 0,
        'activePresets': 0,
      };
    }
    try {
      final deviceId = await DeviceIdService.instance.getDeviceId();

      final earningsSnapshot = await _firestore
          .collection('preset_earnings')
          .where('ownerId', isEqualTo: deviceId)
          .get();

      int totalCreditsEarned = 0;
      int totalLikes = 0;
      int activePresets = 0;

      for (final doc in earningsSnapshot.docs) {
        final data = doc.data();
        final earned = data['creditsEarned'] as int? ?? 0;
        totalCreditsEarned += earned;
        totalLikes += data['totalLikes'] as int? ?? 0;
        if (earned > 0) {
          activePresets++;
        }
      }

      debugPrint('📊 REWARD STATS: заработано=$totalCreditsEarned, '
          'лайков=$totalLikes, активных=$activePresets');

      return {
        'totalCreditsEarned': totalCreditsEarned,
        'totalLikes': totalLikes,
        'activePresets': activePresets,
      };
    } catch (e) {
      debugPrint('🔴 REWARD: Ошибка получения статистики: $e');
      return {
        'totalCreditsEarned': 0,
        'totalLikes': 0,
        'activePresets': 0,
      };
    }
  }

  Future<List<PresetEarnings>> getMyEarnings() async {
    if (useAppwriteBackend()) {
      return [];
    }
    try {
      final deviceId = await DeviceIdService.instance.getDeviceId();

      final earningsSnapshot = await _firestore
          .collection('preset_earnings')
          .where('ownerId', isEqualTo: deviceId)
          .orderBy('creditsEarned', descending: true)
          .get();

      return earningsSnapshot.docs
          .map((doc) => PresetEarnings.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('🔴 REWARD: Ошибка получения списка заработков: $e');
      return [];
    }
  }

  Future<PresetEarnings?> getEarningsForPreset(String presetId) async {
    if (useAppwriteBackend()) {
      return null;
    }
    try {
      final earningsDoc =
          await _firestore.collection('preset_earnings').doc(presetId).get();

      if (!earningsDoc.exists) return null;

      return PresetEarnings.fromJson(
        earningsDoc.data() as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('🔴 REWARD: Ошибка получения заработка для пресета: $e');
      return null;
    }
  }
}
