import '../models/subscription_model.dart';

enum AiModelTier { economy, standard, advanced, premium, ultra }

abstract final class CreditCost {
  // Цены ApiBost за КЛИП, не за секунду (проверено замером биллинга:
  // veo3.1-lite списал ровно $0.055 за клип 8 с со звуком). Прайс указан во
  // внутреннем балансе, который даётся с бонусом +50% при пополнении, поэтому
  // реальная себестоимость = цена ÷ 1.5:
  //   veo3.1-lite  $0.055 → $0.0367
  //   veo3.1-fast  $0.120 → $0.0800
  //   veo3.1-pro   $0.215 → $0.1433
  //   fast-preview $0.740 → $0.4933
  //   pro-4k       $1.740 → $1.1600
  //
  // Худший сценарий выкупа кредита — годовая подписка (999 ₽ / 500 кр = 2.00 ₽,
  // после комиссии магазина 15% остаётся 1.70 ₽). При курсе 78.7 ₽/$ маржа
  // выходит ≈ 79% на подписках и до 88% на мелком пакете кредитов — то есть на
  // уровне картинок в Repiin (79-81%).
  static const int economyGeneration = 10;   // Veo 3.1 Lite
  static const int standardGeneration = 20;  // Veo 3.1 Fast
  static const int advancedGeneration = 30;  // Veo 3.1 Pro (только с подпиской)
  static const int premiumGeneration = 110;  // Veo 3.1 Fast Preview ($0.740 ≈ 110)
  static const int ultraGeneration = 255;    // Veo 3.1 Pro 4K ($1.740 ≈ 255)

  static int forGeneration(AiModelTier tier) {
    switch (tier) {
      case AiModelTier.economy:
        return economyGeneration;
      case AiModelTier.standard:
        return standardGeneration;
      case AiModelTier.advanced:
        return advancedGeneration;
      case AiModelTier.premium:
        return premiumGeneration;
      case AiModelTier.ultra:
        return ultraGeneration;
    }
  }

  static String tierDisplayName(AiModelTier tier) {
    switch (tier) {
      case AiModelTier.economy:
        return 'Быстрая';
      case AiModelTier.standard:
        return 'Стандартная';
      case AiModelTier.advanced:
        return 'Продвинутая';
      case AiModelTier.premium:
        return 'Премиум';
      case AiModelTier.ultra:
        return 'Максимальная';
    }
  }

  static String tierModelName(AiModelTier tier) {
    switch (tier) {
      case AiModelTier.economy:
        return 'Veo 3.1 Lite';
      case AiModelTier.standard:
        return 'Veo 3.1 Fast';
      case AiModelTier.advanced:
        return 'Veo 3.1 Pro';
      case AiModelTier.premium:
        return 'Veo 3.1 Fast Preview';
      case AiModelTier.ultra:
        return 'Veo 3.1 Pro 4K';
    }
  }

  static bool requiresPaidSubscription(AiModelTier tier) {
    return tier == AiModelTier.advanced ||
        tier == AiModelTier.premium ||
        tier == AiModelTier.ultra;
  }

  static bool isTierAccessible(
    AiModelTier tier, {
    required bool hasPaidSubscription,
  }) {
    if (requiresPaidSubscription(tier)) {
      return hasPaidSubscription;
    }
    return true;
  }

  static bool isTierAvailableForTrial(AiModelTier tier) {
    return !requiresPaidSubscription(tier);
  }

  @Deprecated('Use forGeneration(tier) instead')
  static int get imagePerGeneration => standardGeneration;

  @Deprecated('Use forGeneration(tier) instead')
  static int forVoice(int charCount) => 1;
}

// ────────────────────────────────────────────────
// Цены подписок (РФ): Weekly 99₽, Monthly 299₽, Yearly 999₽
// ────────────────────────────────────────────────

class CreditPlan {
  final int totalCredits;
  final int freeGenerations;
  final bool isFreePlan;

  const CreditPlan({
    required this.totalCredits,
    this.freeGenerations = 0,
    this.isFreePlan = false,
  });

  // Бесплатный стартовый пул: 10 кредитов (1 видео Lite)
  static const free = CreditPlan(
    totalCredits: 10,
    isFreePlan: true,
    freeGenerations: 1,
  );

  // Trial 1 день → 20 кредитов (2 видео Lite)
  static const trial = CreditPlan(totalCredits: 20);

  // Weekly 99₽ → 40 кредитов (4 Lite / 2 Fast / 1 Pro)
  static const weekly = CreditPlan(totalCredits: 40);

  // Monthly 299₽ → 140 кредитов (14 Lite / 7 Fast / 4 Pro)
  static const monthly = CreditPlan(totalCredits: 140);

  // Yearly 999₽ → 500 кредитов (50 Lite / 25 Fast / 16 Pro)
  static const yearly = CreditPlan(totalCredits: 500);

  int get approximateStandardVideos =>
      totalCredits ~/ CreditCost.standardGeneration;

  int get approximatePremiumVideos =>
      totalCredits ~/ CreditCost.advancedGeneration;

  int get approximateEconomyVideos =>
      totalCredits ~/ CreditCost.economyGeneration;

  static CreditPlan forSubscription(SubscriptionType type) {
    switch (type) {
      case SubscriptionType.free:
        return free;
      case SubscriptionType.trial:
        return trial;
      case SubscriptionType.weekly:
        return weekly;
      case SubscriptionType.monthly:
        return monthly;
      case SubscriptionType.yearly:
        return yearly;
      case SubscriptionType.lifetime:
        return yearly;
    }
  }
}

// ────────────────────────────────────────────────
// Разовые пакеты кредитов (наценка ×3)
// ────────────────────────────────────────────────

enum CreditPackageType {
  small('credits_small', 40, 149),
  medium('credits_medium', 150, 449),
  large('credits_large', 400, 999);

  const CreditPackageType(this.id, this.credits, this.priceRub);

  final String id;
  final int credits;
  final int priceRub;

  double get pricePerCredit => priceRub / credits;

  int get approximateStandardVideos =>
      credits ~/ CreditCost.standardGeneration;

  String get savingsLabel {
    switch (this) {
      case CreditPackageType.small:
        return '';
      case CreditPackageType.medium:
        return '-20%';
      case CreditPackageType.large:
        return '-33%';
    }
  }
}
