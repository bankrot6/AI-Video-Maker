import '../models/subscription_model.dart';

enum AiModelTier { economy, standard, advanced, premium, ultra }

abstract final class CreditCost {
  // ApiBost цены (внутренний баланс): Flash 2.5 = $0.020, 3.1 Flash = $0.040,
  // Pro = $0.130, Grok 3 Image = $0.070, GPT Image 1.5 / 2 = $0.160.
  // Реальная себестоимость (÷1.5, бонус ×1.5 при пополнении до $1000):
  //   Nano Banana 2.5 Flash: $0.0133 = 1.33 кр.
  //   Nano Banana 3.1 Flash: $0.0267 = 2.67 кр.
  //   Grok 3 Image:          $0.0467 = 4.67 кр.
  //   Nano Banana Pro:       $0.0867 = 8.67 кр.
  //   GPT Image 1.5 / 2:     $0.1067 = 10.67 кр.
  // Наценка ×3.5. 1 кредит ≈ $0.01
  static const int economyGeneration = 5;  // Nano Banana 2.5 Flash  ($0.0133 × 3.5 ≈ 5)
  static const int standardGeneration = 10; // Nano Banana 3.1 Flash ($0.0267 × 3.5 ≈ 9 → 10)
  static const int advancedGeneration = 15; // Grok 3 Image          ($0.0467 × 3.5 ≈ 16 → 15)
  static const int premiumGeneration = 25; // Nano Banana Pro        ($0.0867 × 3.5 ≈ 30 → 25)
  static const int ultraGeneration = 35; // GPT Image 1.5 / 2        ($0.1067 × 3.5 ≈ 37 → 35)

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
        return 'Nano Banana 2.5 Flash';
      case AiModelTier.standard:
        return 'Nano Banana 3.1 Flash';
      case AiModelTier.advanced:
        return 'Grok 3 Image';
      case AiModelTier.premium:
        return 'Nano Banana Pro';
      case AiModelTier.ultra:
        return 'GPT Image';
    }
  }

  static bool isTierAvailableForTrial(AiModelTier tier) {
    return tier != AiModelTier.premium && tier != AiModelTier.ultra;
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

  // Бесплатный стартовый пул: 10 кредитов (~2 Flash / 1 Standard)
  static const free = CreditPlan(
    totalCredits: 10,
    isFreePlan: true,
    freeGenerations: 2,
  );

  // Trial 1 день → 20 кредитов (~4 Flash / 2 Standard)
  static const trial = CreditPlan(totalCredits: 20);

  // Weekly 99₽ → 40 кредитов (~8 Flash / 4 Standard / 1 Pro)
  static const weekly = CreditPlan(totalCredits: 40);

  // Monthly 299₽ → 140 кредитов (~28 Flash / 14 Standard / 5 Pro)
  static const monthly = CreditPlan(totalCredits: 140);

  // Yearly 999₽ → 500 кредитов (~100 Flash / 50 Standard / 20 Pro)
  static const yearly = CreditPlan(totalCredits: 500);

  int get approximateStandardPhotos =>
      totalCredits ~/ CreditCost.standardGeneration;

  int get approximatePremiumPhotos =>
      totalCredits ~/ CreditCost.premiumGeneration;

  int get approximateEconomyPhotos =>
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

  int get approximateStandardPhotos =>
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
