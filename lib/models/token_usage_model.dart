import 'package:json_annotation/json_annotation.dart';

part 'token_usage_model.g.dart';

/// Модель для отслеживания использования токенов пользователем
@JsonSerializable()
class TokenUsageModel {
  /// Общее количество доступных токенов (включая купленные)
  final int totalTokens;

  /// Количество использованных токенов
  final int usedTokens;

  /// Токены, включенные в подписку
  final int subscriptionTokens;

  /// Купленные дополнительные токены
  final int purchasedTokens;

  /// Дата последнего сброса токенов подписки (обычно раз в месяц)
  final DateTime lastResetDate;

  /// Дата последнего использования токенов
  final DateTime? lastUsedDate;

  /// Является ли пользователь триальным
  final bool isTrialUser;

  /// Количество дней, оставшихся в триале
  final int? trialDaysRemaining;

  /// Дата начала триального периода
  final DateTime? trialStartDate;

  /// Дата окончания триального периода
  final DateTime? trialEndDate;

  const TokenUsageModel({
    required this.totalTokens,
    required this.usedTokens,
    required this.subscriptionTokens,
    required this.purchasedTokens,
    required this.lastResetDate,
    this.lastUsedDate,
    this.isTrialUser = false,
    this.trialDaysRemaining,
    this.trialStartDate,
    this.trialEndDate,
  });

  /// Создает модель по умолчанию для нового пользователя
  factory TokenUsageModel.defaultModel() {
    return TokenUsageModel(
      totalTokens:
          210000, // 210k токенов по умолчанию для подписки (7k * 30 дней)
      usedTokens: 0,
      subscriptionTokens: 210000,
      purchasedTokens: 0,
      lastResetDate: DateTime.now(),
    );
  }

  /// Создает модель для пользователя без подписки
  factory TokenUsageModel.freeUser() {
    return TokenUsageModel(
      // Бесплатные пользователи: общий лимит 49k токенов на весь период
      totalTokens: 49000,
      usedTokens: 0,
      subscriptionTokens: 0,
      purchasedTokens: 0,
      lastResetDate: DateTime.now(),
    );
  }

  /// Создает модель для триального пользователя
  factory TokenUsageModel.trialUser() {
    final now = DateTime.now();
    return TokenUsageModel(
      totalTokens: 98000, // 98k токенов за весь триал
      usedTokens: 0,
      subscriptionTokens: 98000,
      purchasedTokens: 0,
      lastResetDate: now,
      isTrialUser: true,
      trialDaysRemaining: 7,
      trialStartDate: now,
      trialEndDate: now.add(const Duration(days: 7)),
    );
  }

  /// Оставшиеся токены
  int get remainingTokens => totalTokens - usedTokens;

  /// Оставшиеся платные (купленные) токены — часть от remainingTokens,
  /// но не больше общей суммы купленных токенов
  int get remainingPurchasedTokens {
    final remaining = remainingTokens;
    if (remaining <= 0) return 0;
    return remaining > purchasedTokens ? purchasedTokens : remaining;
  }

  /// Проверяет, есть ли достаточно токенов для запроса
  bool hasEnoughTokens(int requiredTokens) {
    return remainingTokens >= requiredTokens;
  }

  /// Проверяет, истек ли триальный период
  bool get isTrialExpired {
    if (!isTrialUser || trialEndDate == null) return false;
    return DateTime.now().isAfter(trialEndDate!);
  }

  /// Получает процент использованных токенов
  double get usagePercentage {
    if (totalTokens == 0) return 0.0;
    return (usedTokens / totalTokens).clamp(0.0, 1.0);
  }

  /// Получает процент оставшегося времени триала
  double get trialTimePercentage {
    if (!isTrialUser || trialStartDate == null || trialEndDate == null) {
      return 0.0;
    }

    final now = DateTime.now();
    final totalDuration = trialEndDate!.difference(trialStartDate!);
    final elapsed = now.difference(trialStartDate!);

    if (elapsed.inMilliseconds <= 0) return 1.0;
    if (elapsed >= totalDuration) return 0.0;

    return 1.0 - (elapsed.inMilliseconds / totalDuration.inMilliseconds);
  }

  /// Создает копию с обновленными значениями
  TokenUsageModel copyWith({
    int? totalTokens,
    int? usedTokens,
    int? subscriptionTokens,
    int? purchasedTokens,
    DateTime? lastResetDate,
    DateTime? lastUsedDate,
    bool? isTrialUser,
    int? trialDaysRemaining,
    DateTime? trialStartDate,
    DateTime? trialEndDate,
  }) {
    return TokenUsageModel(
      totalTokens: totalTokens ?? this.totalTokens,
      usedTokens: usedTokens ?? this.usedTokens,
      subscriptionTokens: subscriptionTokens ?? this.subscriptionTokens,
      purchasedTokens: purchasedTokens ?? this.purchasedTokens,
      lastResetDate: lastResetDate ?? this.lastResetDate,
      lastUsedDate: lastUsedDate ?? this.lastUsedDate,
      isTrialUser: isTrialUser ?? this.isTrialUser,
      trialDaysRemaining: trialDaysRemaining ?? this.trialDaysRemaining,
      trialStartDate: trialStartDate ?? this.trialStartDate,
      trialEndDate: trialEndDate ?? this.trialEndDate,
    );
  }

  /// Обновляет использованные токены
  TokenUsageModel useTokens(int tokens) {
    return copyWith(
      usedTokens: usedTokens + tokens,
      lastUsedDate: DateTime.now(),
      trialDaysRemaining: isTrialUser ? _calculateRemainingTrialDays() : null,
    );
  }

  /// Добавляет купленные токены
  TokenUsageModel addPurchasedTokens(int tokens) {
    return copyWith(
      totalTokens: totalTokens + tokens,
      purchasedTokens: purchasedTokens + tokens,
    );
  }

  /// Сбрасывает токены подписки (ежемесячно)
  TokenUsageModel resetSubscriptionTokens(int newSubscriptionTokens) {
    return copyWith(
      subscriptionTokens: newSubscriptionTokens,
      totalTokens: newSubscriptionTokens + purchasedTokens,
      usedTokens: 0,
      lastResetDate: DateTime.now(),
    );
  }

  /// Обновляет триальный период
  TokenUsageModel updateTrialStatus() {
    if (!isTrialUser) return this;

    final remainingDays = _calculateRemainingTrialDays();
    return copyWith(
      trialDaysRemaining: remainingDays,
    );
  }

  /// Вычисляет количество оставшихся дней триала
  int _calculateRemainingTrialDays() {
    if (!isTrialUser || trialEndDate == null) return 0;

    final now = DateTime.now();
    if (now.isAfter(trialEndDate!)) return 0;

    return trialEndDate!.difference(now).inDays;
  }

  /// Конвертация в JSON
  factory TokenUsageModel.fromJson(Map<String, dynamic> json) =>
      _$TokenUsageModelFromJson(json);

  Map<String, dynamic> toJson() => _$TokenUsageModelToJson(this);

  @override
  String toString() {
    return 'TokenUsageModel(total: $totalTokens, used: $usedTokens, remaining: $remainingTokens, trial: $isTrialUser)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TokenUsageModel &&
        other.totalTokens == totalTokens &&
        other.usedTokens == usedTokens &&
        other.subscriptionTokens == subscriptionTokens &&
        other.purchasedTokens == purchasedTokens &&
        other.isTrialUser == isTrialUser;
  }

  @override
  int get hashCode {
    return totalTokens.hashCode ^
        usedTokens.hashCode ^
        subscriptionTokens.hashCode ^
        purchasedTokens.hashCode ^
        isTrialUser.hashCode;
  }
}

/// Типы пакетов токенов для покупки
enum TokenPackageType {
  small('small', 100000, 99), // 100k токенов за 99 рублей
  medium('medium', 300000, 199), // 300k токенов за 199 рублей
  large('large', 800000, 499); // 800k токенов за 499 рублей

  const TokenPackageType(this.id, this.tokens, this.priceRub);

  final String id;
  final int tokens;
  final int priceRub;

  /// Получает цену за 1000 токенов в рублях
  double get pricePerKTokens => priceRub / (tokens / 1000);
}

/// Модель пакета токенов для покупки
@JsonSerializable()
class TokenPackageModel {
  final TokenPackageType type;
  final String title;
  final String description;
  final int tokens;
  final double price;
  final String currency;
  final String? badge; // Например, "Лучшее предложение"

  const TokenPackageModel({
    required this.type,
    required this.title,
    required this.description,
    required this.tokens,
    required this.price,
    required this.currency,
    this.badge,
  });

  factory TokenPackageModel.fromJson(Map<String, dynamic> json) =>
      _$TokenPackageModelFromJson(json);

  Map<String, dynamic> toJson() => _$TokenPackageModelToJson(this);
}
