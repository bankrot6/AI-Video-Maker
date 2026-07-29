import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/credit_config.dart';
import '../models/credit_usage_model.dart';
import '../models/subscription_model.dart';
import 'subscription/subscription_storage_service.dart';
import 'device_registry_service.dart';

class CreditReservation {
  const CreditReservation({
    required this.amount,
    required this.countAsFreeGeneration,
  });

  final int amount;
  final bool countAsFreeGeneration;
}

class CreditReservationResult {
  const CreditReservationResult({
    required this.success,
    this.remainingCredits = 0,
    this.reason = 'unknown',
    this.reservation,
  });

  final bool success;
  final int remainingCredits;
  final String reason;
  final CreditReservation? reservation;
}

class CreditService {
  static final CreditService _instance = CreditService._internal();
  factory CreditService() => _instance;
  CreditService._internal();

  static const String _creditUsageKey = 'credit_usage_data';

  /// На RuStore-сборке серверный `device_registry.currentBalance` —
  /// единственный источник истины по балансу. Кредиты подписки и пакетов
  /// начисляются на сервере и подтягиваются через [refreshFromServer], поэтому
  /// локально их выдавать (и тем более повторно прибавлять purchasedCredits)
  /// нельзя — иначе баланс задваивается (см. баг «215 на главной, 180 в пресете»).
  static const bool _serverAuthoritative =
      CreditUsageModel.isServerAuthoritativeBalance;

  Future<CreditUsageModel> getCreditUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_creditUsageKey);

      CreditUsageModel usage;
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        usage = CreditUsageModel.fromJson(json);
      } else {
        usage = await _createInitialUsage();
      }

      usage = _checkDailyReset(usage);
      usage = await _checkSubscriptionReset(usage);
      return usage;
    } catch (e) {
      debugPrint('🔴 CREDIT_SERVICE: Ошибка получения данных: $e');
      return await _createInitialUsage();
    }
  }

  Future<CreditUsageModel> _createInitialUsage() async {
    final subscription = await _getCurrentSubscription();

    if (subscription != null && subscription.isActive) {
      if (subscription.isTrialUser) {
        return CreditUsageModel.trialUser();
      }
      if (subscription.isPaidUser) {
        final plan = CreditPlan.forSubscription(subscription.type);
        final now = DateTime.now();
        return CreditUsageModel(
          totalCredits: plan.totalCredits,
          usedCredits: 0,
          subscriptionCredits: plan.totalCredits,
          purchasedCredits: 0,
          lastDailyResetDate: now,
          lastResetDate: now,
        );
      }
    }

    return CreditUsageModel.freeUser();
  }

  CreditUsageModel _checkDailyReset(CreditUsageModel usage) {
    if (usage.isFreeUser) return usage;
    return usage;
  }

  Future<CreditUsageModel> _checkSubscriptionReset(
      CreditUsageModel usage) async {
    try {
      final subscription = await _getCurrentSubscription();
      if (subscription == null) return usage;

      if (_serverAuthoritative) {
        return await _checkSubscriptionResetServerAuthoritative(
            usage, subscription);
      }

      if (subscription.isPaidUser && usage.isFreeUser) {
        final plan = CreditPlan.forSubscription(subscription.type);
        final updated = usage.resetForSubscription(plan.totalCredits);
        await _save(updated);
        return updated;
      }

      if (subscription.isPaidUser &&
          usage.lastResetDate.isBefore(subscription.startDate)) {
        final plan = CreditPlan.forSubscription(subscription.type);
        final updated = usage.resetForSubscription(plan.totalCredits);
        await _save(updated);
        return updated;
      }

      if (usage.isTrialUser &&
          usage.trialEndDate != null &&
          DateTime.now().isAfter(usage.trialEndDate!)) {
        if (subscription.isPaidUser && !subscription.isTrialUser) {
          final plan = CreditPlan.forSubscription(subscription.type);
          final remaining = (plan.totalCredits - usage.usedCredits)
              .clamp(0, plan.totalCredits);
          final updated = usage.copyWith(
            totalCredits: remaining + usage.purchasedCredits,
            subscriptionCredits: plan.totalCredits,
            isTrialUser: false,
            lastResetDate: DateTime.now(),
          );
          await _save(updated);
          return updated;
        }
      }

      if (!subscription.isActive &&
          !usage.isFreeUser &&
          !subscription.isPaidUser) {
        final freeUsage = CreditUsageModel.freeUser().copyWith(
          purchasedCredits: usage.purchasedCredits,
          totalCredits: usage.purchasedCredits,
          firstUseDate: usage.firstUseDate,
        );
        await _save(freeUsage);
        return freeUsage;
      }

      // Миграция: isFreeUser=false без подписки — некорректное состояние.
      // Восстанавливаем флаг, сохраняя купленные/заработанные кредиты.
      if (!usage.isFreeUser &&
          !usage.isTrialUser &&
          !subscription.isPaidUser &&
          usage.subscriptionCredits == 0) {
        final freePool = CreditUsageModel.freeCreditsPool;
        final restored = usage.copyWith(
          isFreeUser: true,
          totalCredits: freePool + usage.purchasedCredits + usage.earnedCredits,
          usedCredits: 0,
        );
        await _save(restored);
        debugPrint('🔄 CREDIT_SERVICE: Восстановлен isFreeUser=true '
            '(purchasedCredits=${usage.purchasedCredits})');
        return restored;
      }
    } catch (e) {
      debugPrint('🔴 CREDIT_SERVICE: Ошибка проверки подписки: $e');
    }
    return usage;
  }

  /// Нормализация состояния подписки для серверо-авторитетных сборок (RuStore).
  ///
  /// Здесь НЕ начисляем кредиты локально: баланс (totalCredits/usedCredits)
  /// принадлежит серверу и подтягивается через [refreshFromServer]. Меняем
  /// только флаги (free/trial/paid) и subscriptionCredits, чтобы остальная
  /// логика (выбор провайдера, лимиты) видела корректный тип пользователя.
  Future<CreditUsageModel> _checkSubscriptionResetServerAuthoritative(
    CreditUsageModel usage,
    SubscriptionModel subscription,
  ) async {
    if (subscription.isPaidUser && (usage.isFreeUser || usage.isTrialUser)) {
      final plan = CreditPlan.forSubscription(subscription.type);
      final updated = usage.copyWith(
        isFreeUser: false,
        isTrialUser: false,
        subscriptionCredits: plan.totalCredits,
      );
      await _save(updated);
      return updated;
    }

    if (!subscription.isActive &&
        !subscription.isPaidUser &&
        !usage.isFreeUser) {
      final updated = usage.copyWith(
        isFreeUser: true,
        isTrialUser: false,
        subscriptionCredits: 0,
      );
      await _save(updated);
      return updated;
    }

    return usage;
  }

  Future<CreditUsageResult> checkCredits(int amount) async {
    await refreshFromServer();
    final usage = await getCreditUsage();
    if (!usage.hasEnoughCredits(amount)) {
      return CreditUsageResult(
        allowed: false,
        reason: 'insufficient_credits',
        remainingCredits: usage.remainingCredits,
      );
    }
    return CreditUsageResult(
      allowed: true,
      reason: 'allowed',
      remainingCredits: usage.remainingCredits,
    );
  }

  Future<bool> useCredits(int amount) async {
    try {
      final usage = await getCreditUsage();
      if (!usage.hasEnoughCredits(amount)) {
        debugPrint('❌ CREDIT_SERVICE: Недостаточно кредитов: '
            '${usage.remainingCredits} < $amount');
        return false;
      }
      final updated = usage.useCredits(amount);
      await _save(updated);
      final limitInfo =
          usage.isFreeUser ? ' (дневной лимит: ${usage.dailyFreeLimit})' : '';
      debugPrint('✅ CREDIT_SERVICE: Использовано $amount кредитов, '
          'осталось ${updated.remainingCredits}$limitInfo');
      return true;
    } catch (e) {
      debugPrint('🔴 CREDIT_SERVICE: Ошибка списания кредитов: $e');
      return false;
    }
  }

  Future<bool> useGenerationCredits(AiModelTier tier) async {
    final credits = CreditCost.forGeneration(tier);
    try {
      final usage = await getCreditUsage();

      if ((usage.isFreeUser || usage.isTrialUser) &&
          !CreditCost.isTierAvailableForTrial(tier)) {
        debugPrint('❌ CREDIT_SERVICE: Модель ${tier.name} недоступна для '
            '${usage.isFreeUser ? "бесплатного" : "триал"} пользователя');
        return false;
      }

      if (usage.isFreeUser) {
        if (!usage.hasEnoughCredits(credits)) {
          debugPrint('❌ CREDIT_SERVICE: Недостаточно кредитов для генерации');
          return false;
        }
        final updated = usage.useCredits(credits).useFreeGeneration();
        await _save(updated);
        debugPrint('✅ CREDIT_SERVICE: Бесплатная генерация ${tier.name}, '
            'осталось ${updated.remainingCredits} кредитов');
        return true;
      }

      return useCredits(credits);
    } catch (e) {
      debugPrint('🔴 CREDIT_SERVICE: Ошибка списания генерации: $e');
      return false;
    }
  }

  Future<bool> canGenerate(AiModelTier tier) async {
    await refreshFromServer();
    final usage = await getCreditUsage();
    if ((usage.isFreeUser || usage.isTrialUser) &&
        !CreditCost.isTierAvailableForTrial(tier)) {
      return false;
    }
    final credits = CreditCost.forGeneration(tier);
    return usage.hasEnoughCredits(credits);
  }

  Future<CreditUsageModel> refreshFromServer() async {
    final usage = await getCreditUsage();
    final subType = usage.isTrialUser
        ? 'trial'
        : usage.isFreeUser
            ? 'free'
            : 'paid';
    final server = await DeviceRegistryService().syncCreditsAndFetch(
      freeCreditsUsed: usage.isFreeUser ? usage.usedCredits : 0,
      freeGenerationsUsed: usage.isFreeUser ? usage.freePhotosUsed : 0,
      purchasedCredits: usage.purchasedCredits,
      earnedCredits: usage.earnedCredits,
      currentBalance: usage.remainingCredits,
      subscriptionType: subType,
    );
    if (server == null) return usage;
    final reconciled = _reconcileWithServer(usage, server);
    await _persistUsage(reconciled, syncServer: false);
    return reconciled;
  }

  Future<CreditReservationResult> reserveGenerationCredits(
      AiModelTier tier) async {
    final usage = await refreshFromServer();
    if ((usage.isFreeUser || usage.isTrialUser) &&
        !CreditCost.isTierAvailableForTrial(tier)) {
      return CreditReservationResult(
        success: false,
        remainingCredits: usage.remainingCredits,
        reason: 'tier_locked',
      );
    }

    final amount = CreditCost.forGeneration(tier);
    return reserveCredits(
      amount,
      countAsFreeGeneration: usage.isFreeUser,
    );
  }

  Future<CreditReservationResult> reserveCredits(
    int amount, {
    bool countAsFreeGeneration = false,
  }) async {
    final usage = await refreshFromServer();
    if (!usage.hasEnoughCredits(amount)) {
      return CreditReservationResult(
        success: false,
        remainingCredits: usage.remainingCredits,
        reason: 'insufficient_credits',
      );
    }

    final reserved = await DeviceRegistryService().reserveCredits(
      amount: amount,
      countAsFreeGeneration: countAsFreeGeneration,
    );
    final server = reserved.state;
    if (server == null) {
      debugPrint('🔴 CREDIT_SERVICE: Резерв кредитов не прошёл: '
          '${reserved.reason}');
      return CreditReservationResult(
        success: false,
        remainingCredits: usage.remainingCredits,
        reason: reserved.reason,
      );
    }

    final serverReconciled = _reconcileWithServer(usage, server);
    final reconciled = countAsFreeGeneration
        ? serverReconciled
        : serverReconciled.copyWith(
            usedCredits: usage.usedCredits + amount,
            totalCredits: usage.usedCredits + amount + server.currentBalance,
          );
    await _persistUsage(reconciled, syncServer: false);
    return CreditReservationResult(
      success: true,
      remainingCredits: reconciled.remainingCredits,
      reason: 'reserved',
      reservation: CreditReservation(
        amount: amount,
        countAsFreeGeneration: countAsFreeGeneration,
      ),
    );
  }

  Future<void> rollbackReservation(CreditReservation reservation) async {
    final usage = await getCreditUsage();
    final server = await DeviceRegistryService().rollbackCredits(
      amount: reservation.amount,
      countAsFreeGeneration: reservation.countAsFreeGeneration,
    );

    final rolledBackLocal = usage.copyWith(
      usedCredits:
          (usage.usedCredits - reservation.amount).clamp(0, usage.usedCredits),
      freePhotosUsed: reservation.countAsFreeGeneration
          ? (usage.freePhotosUsed - 1).clamp(0, usage.freePhotosUsed)
          : usage.freePhotosUsed,
    );

    final reconciled = server == null
        ? rolledBackLocal
        : _reconcileWithServer(rolledBackLocal, server);
    await _persistUsage(reconciled, syncServer: false);
  }

  Future<void> addPurchasedCredits(int amount) async {
    try {
      final usage = await getCreditUsage();
      final updated = usage.addPurchasedCredits(amount);
      await _save(updated);
      debugPrint('💰 CREDIT_SERVICE: Добавлено $amount кредитов');
    } catch (e) {
      debugPrint('🔴 CREDIT_SERVICE: Ошибка добавления кредитов: $e');
    }
  }

  Future<void> grantPurchasedCredits(int amount) async {
    await addPurchasedCredits(amount);
    await refreshFromServer();
  }

  Future<void> applyServerPurchaseSnapshot({
    required int purchasedCredits,
    required int currentBalance,
  }) async {
    try {
      final usage = await getCreditUsage();
      final updated = usage.syncServerPurchaseSnapshot(
        purchasedCredits: purchasedCredits,
        currentBalance: currentBalance,
      );
      await _save(updated);
      debugPrint(
        '💰 CREDIT_SERVICE: Применён серверный снапшот purchased=$purchasedCredits '
        'balance=$currentBalance',
      );
    } catch (e) {
      debugPrint(
          '🔴 CREDIT_SERVICE: Ошибка применения серверного снапшота: $e');
    }
  }

  Future<void> addEarnedCredits(int amount) async {
    try {
      final usage = await getCreditUsage();
      final updated = usage.addEarnedCredits(amount);
      await _save(updated);
      debugPrint('💰 CREDIT_SERVICE: Начислено $amount заработанных кредитов '
          '(всего заработано: ${updated.earnedCredits})');
    } catch (e) {
      debugPrint(
          '🔴 CREDIT_SERVICE: Ошибка начисления заработанных кредитов: $e');
    }
  }

  Future<void> activateSubscription(SubscriptionType type) async {
    try {
      final usage = await getCreditUsage();
      final plan = CreditPlan.forSubscription(type);

      if (type == SubscriptionType.trial) {
        final trialCredits = CreditPlan.trial.totalCredits;
        final trialUsage = CreditUsageModel.trialUser().copyWith(
          purchasedCredits: usage.purchasedCredits,
          totalCredits: trialCredits + usage.purchasedCredits,
        );
        await _save(trialUsage);
        debugPrint('🎉 CREDIT_SERVICE: Триальный период активирован');
        return;
      }

      if (_serverAuthoritative) {
        // RuStore: кредиты подписки начислит сервер (verify-rustore-purchase) и
        // подтянет refreshFromServer. Локально оптимистично показываем номинал
        // плана БЕЗ повторного прибавления purchasedCredits/earnedCredits — они
        // уже учтены в серверном currentBalance.
        final updated = usage.copyWith(
          totalCredits: plan.totalCredits,
          usedCredits: 0,
          subscriptionCredits: plan.totalCredits,
          isFreeUser: false,
          isTrialUser: false,
          lastResetDate: DateTime.now(),
        );
        await _save(updated);
        debugPrint('🎉 CREDIT_SERVICE: Подписка ${type.name} активирована '
            '(server-authoritative), номинал: ${plan.totalCredits}');
        return;
      }

      final updated = usage.resetForSubscription(plan.totalCredits);
      await _save(updated);
      debugPrint('🎉 CREDIT_SERVICE: Подписка ${type.name} активирована, '
          'кредиты: ${plan.totalCredits}');
    } catch (e) {
      debugPrint('🔴 CREDIT_SERVICE: Ошибка активации подписки: $e');
    }
  }

  Future<bool> isFreeUser() async {
    final usage = await getCreditUsage();
    return usage.isFreeUser;
  }

  Future<bool> isPaidUser() async {
    final subscription = await _getCurrentSubscription();
    return subscription != null && subscription.isPaidUser;
  }

  Future<bool> hasCreditsForGeneration(AiModelTier tier) async {
    return canGenerate(tier);
  }

  // --- backward-compat for messenger features ---

  @Deprecated('Use canGenerate(AiModelTier.standard)')
  Future<bool> hasCreditsForImage() => canGenerate(AiModelTier.standard);

  @Deprecated('Use canGenerate(AiModelTier.economy)')
  Future<bool> hasCreditsForText() async {
    final usage = await getCreditUsage();
    return usage.hasEnoughCredits(1);
  }

  @Deprecated('Use canGenerate(AiModelTier.economy)')
  Future<bool> hasCreditsForStory() => canGenerate(AiModelTier.economy);

  @Deprecated('Free story logic removed')
  Future<bool> canUseFreeStory() async {
    final usage = await getCreditUsage();
    return usage.isFreeUser &&
        usage.hasEnoughCredits(CreditCost.economyGeneration);
  }

  @Deprecated('Free generation logic unified')
  Future<bool> canUseFreePhoto() => canUseFreeStory();

  @Deprecated('Free generation logic unified')
  Future<bool> canUseFreeAudio() => canUseFreeStory();

  @Deprecated('Free story logic removed')
  Future<bool> useFreeStory() async {
    return useStoryCredits();
  }

  @Deprecated('Free generation logic unified')
  Future<bool> useFreePhoto() => useImageCredits();

  @Deprecated('Free generation logic unified')
  Future<bool> useFreeAudio() => useVoiceCredits('');

  Future<bool> useTextCredits(String inputText, String outputText) async {
    return useCredits(1);
  }

  Future<bool> useImageCredits() async {
    return useCredits(CreditCost.standardGeneration);
  }

  Future<bool> useStoryCredits() async {
    return useCredits(CreditCost.economyGeneration);
  }

  Future<bool> useVoiceCredits(String text) async {
    return useCredits(1);
  }

  Future<void> resetCreditUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_creditUsageKey);
      debugPrint('🔄 CREDIT_SERVICE: Данные кредитов сброшены');
    } catch (e) {
      debugPrint('🔴 CREDIT_SERVICE: Ошибка сброса: $e');
    }
  }

  Future<void> _save(CreditUsageModel usage) async {
    await _persistUsage(usage, syncServer: true);
  }

  Future<void> _persistUsage(
    CreditUsageModel usage, {
    required bool syncServer,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_creditUsageKey, jsonEncode(usage.toJson()));
      if (syncServer) {
        _syncCreditsAsync(usage);
      }
    } catch (e) {
      debugPrint('🔴 CREDIT_SERVICE: Ошибка сохранения: $e');
    }
  }

  CreditUsageModel _reconcileWithServer(
    CreditUsageModel local,
    DeviceRegistryResult server,
  ) {
    final isFree = server.subscriptionType.isNotEmpty
        ? server.subscriptionType == 'free'
        : local.isFreeUser;
    final isTrial = server.subscriptionType.isNotEmpty
        ? server.subscriptionType == 'trial'
        : local.isTrialUser;
    final serverUsedCredits =
        isFree ? server.freeCreditsUsed : local.usedCredits;
    final serverFreePhotos =
        isFree ? server.freeGenerationsUsed : local.freePhotosUsed;
    final totalCredits = serverUsedCredits + server.currentBalance;

    return local.copyWith(
      isFreeUser: isFree,
      isTrialUser: isTrial,
      purchasedCredits: server.purchasedCredits,
      earnedCredits: server.earnedCredits,
      usedCredits: serverUsedCredits,
      freePhotosUsed: serverFreePhotos,
      totalCredits: totalCredits,
    );
  }

  void _syncCreditsAsync(CreditUsageModel usage) {
    final subType = usage.isTrialUser
        ? 'trial'
        : usage.isFreeUser
            ? 'free'
            : 'paid';

    DeviceRegistryService().syncCredits(
      freeCreditsUsed: usage.isFreeUser ? usage.usedCredits : 0,
      freeGenerationsUsed: usage.isFreeUser ? usage.freePhotosUsed : 0,
      purchasedCredits: usage.purchasedCredits,
      earnedCredits: usage.earnedCredits,
      currentBalance: usage.remainingCredits,
      subscriptionType: subType,
    );
  }

  Future<SubscriptionModel?> _getCurrentSubscription() async {
    try {
      final storageService = SubscriptionStorageService();
      final storageInfo = await storageService.getSubscription();
      if (storageInfo != null) {
        return SubscriptionModel(
          type: storageInfo.type,
          startDate: storageInfo.startDate,
          endDate: storageInfo.endDate,
          availableRequests: 10,
          maxRequests: 10,
        );
      }

      final prefs = await SharedPreferences.getInstance();
      final subscriptionJson = prefs.getString('user_subscription');
      if (subscriptionJson == null || subscriptionJson.isEmpty) return null;

      final data = jsonDecode(subscriptionJson) as Map<String, dynamic>;
      final type = SubscriptionType.values[(data['type'] as int?) ?? 0];
      final startDate =
          DateTime.fromMillisecondsSinceEpoch((data['startDate'] as int?) ?? 0);
      final endDate = data['endDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['endDate'] as int)
          : null;

      return SubscriptionModel(
        type: type,
        startDate: startDate,
        endDate: endDate,
        availableRequests: (data['availableRequests'] as int?) ?? 0,
        maxRequests: (data['maxRequests'] as int?) ?? 0,
      );
    } catch (e) {
      debugPrint('🔴 CREDIT_SERVICE: Ошибка чтения подписки: $e');
      return null;
    }
  }
}
