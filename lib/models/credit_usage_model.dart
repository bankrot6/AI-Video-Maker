class CreditUsageModel {
  final int totalCredits;
  final int usedCredits;
  final int subscriptionCredits;
  final int purchasedCredits;
  final int earnedCredits;

  final bool isFreeUser;
  final int dailyFreeCreditsUsed;
  final int freePhotosUsed;
  final int freeAudiosUsed;
  final int freeStoriesUsed;
  final DateTime lastDailyResetDate;
  final DateTime? firstUseDate;

  final bool isTrialUser;
  final DateTime? trialStartDate;
  final DateTime? trialEndDate;

  final DateTime lastResetDate;

  const CreditUsageModel({
    required this.totalCredits,
    required this.usedCredits,
    required this.subscriptionCredits,
    required this.purchasedCredits,
    this.earnedCredits = 0,
    this.isFreeUser = false,
    this.dailyFreeCreditsUsed = 0,
    this.freePhotosUsed = 0,
    this.freeAudiosUsed = 0,
    this.freeStoriesUsed = 0,
    required this.lastDailyResetDate,
    this.firstUseDate,
    this.isTrialUser = false,
    this.trialStartDate,
    this.trialEndDate,
    required this.lastResetDate,
  });

  static const int freeCreditsPool = 10;

  /// RuStore-сборка распространяется отдельным APK через RuStore. В ней
  /// серверный `device_registry.currentBalance` является единственным
  /// источником истины по балансу (подписки и пакеты начисляются на сервере),
  /// а локальный totalCredits всегда синхронизируется с ним. Поэтому здесь
  /// нельзя повторно прибавлять purchasedCredits/earnedCredits к остатку —
  /// это накопительные счётчики, уже учтённые в currentBalance.
  static const bool isServerAuthoritativeBalance =
      bool.fromEnvironment('RUSTORE');

  int get dailyFreeLimit => 0;

  int get remainingCredits {
    if (isServerAuthoritativeBalance) {
      return (totalCredits - usedCredits).clamp(0, totalCredits);
    }
    if (isFreeUser) {
      final freeRemaining =
          (freeCreditsPool - usedCredits).clamp(0, freeCreditsPool);
      return freeRemaining + purchasedCredits + earnedCredits;
    }
    return (totalCredits - usedCredits).clamp(0, totalCredits);
  }

  bool hasEnoughCredits(int amount) => remainingCredits >= amount;

  double get usagePercentage {
    if (isFreeUser) {
      if (freeCreditsPool == 0) return 0.0;
      return (usedCredits / freeCreditsPool).clamp(0.0, 1.0);
    }
    if (totalCredits == 0) return 0.0;
    return (usedCredits / totalCredits).clamp(0.0, 1.0);
  }

  bool get isTrialExpired {
    if (!isTrialUser || trialEndDate == null) return false;
    return DateTime.now().isAfter(trialEndDate!);
  }

  int get trialDaysRemaining {
    if (!isTrialUser || trialEndDate == null) return 0;
    final diff = trialEndDate!.difference(DateTime.now()).inDays;
    return diff.clamp(0, 1);
  }

  factory CreditUsageModel.freeUser() {
    final now = DateTime.now();
    return CreditUsageModel(
      totalCredits: freeCreditsPool,
      usedCredits: 0,
      subscriptionCredits: 0,
      purchasedCredits: 0,
      earnedCredits: 0,
      isFreeUser: true,
      dailyFreeCreditsUsed: 0,
      lastDailyResetDate: now,
      firstUseDate: now,
      lastResetDate: now,
    );
  }

  factory CreditUsageModel.trialUser() {
    final now = DateTime.now();
    return CreditUsageModel(
      totalCredits: 20,
      usedCredits: 0,
      subscriptionCredits: 20,
      purchasedCredits: 0,
      earnedCredits: 0,
      lastDailyResetDate: now,
      isTrialUser: true,
      trialStartDate: now,
      trialEndDate: now.add(const Duration(days: 1)),
      lastResetDate: now,
    );
  }

  CreditUsageModel copyWith({
    int? totalCredits,
    int? usedCredits,
    int? subscriptionCredits,
    int? purchasedCredits,
    int? earnedCredits,
    bool? isFreeUser,
    int? dailyFreeCreditsUsed,
    int? freePhotosUsed,
    int? freeAudiosUsed,
    int? freeStoriesUsed,
    DateTime? lastDailyResetDate,
    DateTime? firstUseDate,
    bool? isTrialUser,
    DateTime? trialStartDate,
    DateTime? trialEndDate,
    DateTime? lastResetDate,
  }) {
    return CreditUsageModel(
      totalCredits: totalCredits ?? this.totalCredits,
      usedCredits: usedCredits ?? this.usedCredits,
      subscriptionCredits: subscriptionCredits ?? this.subscriptionCredits,
      purchasedCredits: purchasedCredits ?? this.purchasedCredits,
      earnedCredits: earnedCredits ?? this.earnedCredits,
      isFreeUser: isFreeUser ?? this.isFreeUser,
      dailyFreeCreditsUsed: dailyFreeCreditsUsed ?? this.dailyFreeCreditsUsed,
      freePhotosUsed: freePhotosUsed ?? this.freePhotosUsed,
      freeAudiosUsed: freeAudiosUsed ?? this.freeAudiosUsed,
      freeStoriesUsed: freeStoriesUsed ?? this.freeStoriesUsed,
      lastDailyResetDate: lastDailyResetDate ?? this.lastDailyResetDate,
      firstUseDate: firstUseDate ?? this.firstUseDate,
      isTrialUser: isTrialUser ?? this.isTrialUser,
      trialStartDate: trialStartDate ?? this.trialStartDate,
      trialEndDate: trialEndDate ?? this.trialEndDate,
      lastResetDate: lastResetDate ?? this.lastResetDate,
    );
  }

  CreditUsageModel useCredits(int amount) {
    return copyWith(usedCredits: usedCredits + amount);
  }

  CreditUsageModel useFreeGeneration() {
    return copyWith(freePhotosUsed: freePhotosUsed + 1);
  }

  CreditUsageModel addPurchasedCredits(int amount) {
    return copyWith(
      totalCredits: totalCredits + amount,
      purchasedCredits: purchasedCredits + amount,
    );
  }

  CreditUsageModel addEarnedCredits(int amount) {
    return copyWith(
      totalCredits: totalCredits + amount,
      earnedCredits: earnedCredits + amount,
    );
  }

  CreditUsageModel syncServerPurchaseSnapshot({
    required int purchasedCredits,
    required int currentBalance,
  }) {
    final baseCredits = isFreeUser ? freeCreditsPool : subscriptionCredits;
    final nextTotalCredits = baseCredits + purchasedCredits + earnedCredits;
    final nextUsedCredits =
        (nextTotalCredits - currentBalance).clamp(0, nextTotalCredits);

    return copyWith(
      purchasedCredits: purchasedCredits,
      totalCredits: nextTotalCredits,
      usedCredits: nextUsedCredits,
    );
  }

  CreditUsageModel resetDailyCounters() {
    final now = DateTime.now();
    return copyWith(
      lastDailyResetDate: now,
    );
  }

  CreditUsageModel resetForSubscription(int newCredits) {
    final purchasedUsed =
        (usedCredits - subscriptionCredits).clamp(0, purchasedCredits);
    final remainingPurchased = purchasedCredits - purchasedUsed;

    return copyWith(
      totalCredits: newCredits + remainingPurchased + earnedCredits,
      usedCredits: 0,
      subscriptionCredits: newCredits,
      purchasedCredits: remainingPurchased,
      isFreeUser: false,
      isTrialUser: false,
      lastResetDate: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'totalCredits': totalCredits,
        'usedCredits': usedCredits,
        'subscriptionCredits': subscriptionCredits,
        'purchasedCredits': purchasedCredits,
        'earnedCredits': earnedCredits,
        'isFreeUser': isFreeUser,
        'dailyFreeCreditsUsed': dailyFreeCreditsUsed,
        'freePhotosUsed': freePhotosUsed,
        'freeAudiosUsed': freeAudiosUsed,
        'freeStoriesUsed': freeStoriesUsed,
        'lastDailyResetDate': lastDailyResetDate.millisecondsSinceEpoch,
        'firstUseDate': firstUseDate?.millisecondsSinceEpoch,
        'isTrialUser': isTrialUser,
        'trialStartDate': trialStartDate?.millisecondsSinceEpoch,
        'trialEndDate': trialEndDate?.millisecondsSinceEpoch,
        'lastResetDate': lastResetDate.millisecondsSinceEpoch,
      };

  factory CreditUsageModel.fromJson(Map<String, dynamic> json) {
    return CreditUsageModel(
      totalCredits: json['totalCredits'] as int? ?? 0,
      usedCredits: json['usedCredits'] as int? ?? 0,
      subscriptionCredits: json['subscriptionCredits'] as int? ?? 0,
      purchasedCredits: json['purchasedCredits'] as int? ?? 0,
      earnedCredits: json['earnedCredits'] as int? ?? 0,
      isFreeUser: json['isFreeUser'] as bool? ?? false,
      dailyFreeCreditsUsed: json['dailyFreeCreditsUsed'] as int? ?? 0,
      freePhotosUsed: json['freePhotosUsed'] as int? ?? 0,
      freeAudiosUsed: json['freeAudiosUsed'] as int? ?? 0,
      freeStoriesUsed: json['freeStoriesUsed'] as int? ?? 0,
      lastDailyResetDate: DateTime.fromMillisecondsSinceEpoch(
        json['lastDailyResetDate'] as int? ?? 0,
      ),
      firstUseDate: json['firstUseDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['firstUseDate'] as int)
          : null,
      isTrialUser: json['isTrialUser'] as bool? ?? false,
      trialStartDate: json['trialStartDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['trialStartDate'] as int)
          : null,
      trialEndDate: json['trialEndDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['trialEndDate'] as int)
          : null,
      lastResetDate: DateTime.fromMillisecondsSinceEpoch(
        json['lastResetDate'] as int? ?? 0,
      ),
    );
  }

  @override
  String toString() =>
      'CreditUsageModel(remaining: $remainingCredits/$totalCredits, '
      'free: $isFreeUser, trial: $isTrialUser, '
      'dailyLimit: $dailyFreeLimit)';
}

class CreditUsageResult {
  final bool allowed;
  final String reason;
  final int remainingCredits;

  const CreditUsageResult({
    required this.allowed,
    required this.reason,
    this.remainingCredits = 0,
  });
}
