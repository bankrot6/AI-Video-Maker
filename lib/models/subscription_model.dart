/// Типы подписок, доступные в приложении
enum SubscriptionType {
  /// Бесплатная версия
  free,

  /// Пробная версия
  trial,

  /// Недельная подписка
  weekly,

  /// Месячная подписка
  monthly,

  /// Годовая подписка
  yearly,

  /// Бессрочная подписка
  lifetime,
}

/// Модель для хранения информации о подписке пользователя
class SubscriptionModel {
  /// Тип текущей подписки пользователя
  final SubscriptionType type;

  /// Дата начала подписки
  final DateTime startDate;

  /// Дата окончания подписки (для временных подписок)
  final DateTime? endDate;

  /// Количество доступных запросов к AI моделям
  final int availableRequests;

  /// Максимальное количество запросов для данного типа подписки
  final int maxRequests;

  /// Активна ли подписка в настоящий момент
  bool get isActive {
    if (type == SubscriptionType.free || type == SubscriptionType.lifetime) {
      return true;
    }

    final now = DateTime.now();
    return endDate != null && endDate!.isAfter(now);
  }

  /// Количество токенов в день для данного типа подписки
  int get dailyTokens {
    switch (type) {
      case SubscriptionType.free:
        return 0; // Бесплатные пользователи не получают токенов
      case SubscriptionType.trial:
        return 1000; // 1k токенов в день для триала
      case SubscriptionType.weekly:
      case SubscriptionType.monthly:
      case SubscriptionType.yearly:
        return 2000; // 2k токенов в день для платных подписок
      case SubscriptionType.lifetime:
        return 3000; // 3k токенов в день для lifetime подписки
    }
  }

  /// Общее количество токенов за весь период подписки
  int get totalTokensForPeriod {
    switch (type) {
      case SubscriptionType.free:
        return 0;
      case SubscriptionType.trial:
        return 1000; // 1k * 1 день
      case SubscriptionType.weekly:
        return 14000; // 2k * 7 дней
      case SubscriptionType.monthly:
        return 60000; // 2k * 30 дней
      case SubscriptionType.yearly:
        return 730000; // 2k * 365 дней
      case SubscriptionType.lifetime:
        return -1; // Безлимитные токены (будем обрабатывать отдельно)
    }
  }

  /// Проверяет, дает ли подписка безлимитные токены
  bool get hasUnlimitedTokens {
    return type == SubscriptionType.lifetime;
  }

  /// Проверяет, является ли пользователь триальным
  bool get isTrialUser {
    return type == SubscriptionType.trial;
  }

  /// Проверяет, имеет ли пользователь платную подписку
  bool get isPaidUser {
    return [
          SubscriptionType.weekly,
          SubscriptionType.monthly,
          SubscriptionType.yearly,
          SubscriptionType.lifetime,
        ].contains(type) &&
        isActive;
  }

  /// Оставшееся количество дней подписки
  int get daysLeft {
    if (type == SubscriptionType.free) {
      return 0;
    }

    if (type == SubscriptionType.lifetime) {
      return 36500; // ~100 лет
    }

    final now = DateTime.now();
    if (endDate == null || endDate!.isBefore(now)) {
      return 0;
    }

    return endDate!.difference(now).inDays;
  }

  /// Процент оставшихся запросов
  double get requestsPercentage {
    if (maxRequests == 0) return 0;
    return availableRequests / maxRequests;
  }

  const SubscriptionModel({
    required this.type,
    required this.startDate,
    this.endDate,
    required this.availableRequests,
    required this.maxRequests,
  });

  /// Создает копию модели с обновленными параметрами
  SubscriptionModel copyWith({
    SubscriptionType? type,
    DateTime? startDate,
    DateTime? endDate,
    int? availableRequests,
    int? maxRequests,
  }) {
    return SubscriptionModel(
      type: type ?? this.type,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      availableRequests: availableRequests ?? this.availableRequests,
      maxRequests: maxRequests ?? this.maxRequests,
    );
  }

  /// Базовая бесплатная подписка
  factory SubscriptionModel.free() {
    print(
        "🏗️ SUBSCRIPTION_MODEL: Создание бесплатной подписки с лимитом 3 распознавания");
    return SubscriptionModel(
      type: SubscriptionType.free,
      startDate: DateTime.now(),
      availableRequests: 3,
      maxRequests: 3,
    );
  }

  /// Пробная подписка на 1 день
  factory SubscriptionModel.trial() {
    final now = DateTime.now();
    print(
        "🏗️ SUBSCRIPTION_MODEL: Создание пробной подписки с лимитом 10 распознаваний на 1 день");
    return SubscriptionModel(
      type: SubscriptionType.trial,
      startDate: now,
      endDate: now.add(const Duration(days: 1)),
      availableRequests: 10,
      maxRequests: 10,
    );
  }

  /// Недельная подписка
  factory SubscriptionModel.weekly() {
    final now = DateTime.now();
    print(
        "🏗️ SUBSCRIPTION_MODEL: Создание недельной подписки с лимитом 10 распознаваний в день");
    return SubscriptionModel(
      type: SubscriptionType.weekly,
      startDate: now,
      endDate: now.add(const Duration(days: 7)),
      availableRequests: 10,
      maxRequests: 10,
    );
  }

  /// Месячная подписка
  factory SubscriptionModel.monthly() {
    final now = DateTime.now();
    print(
        "🏗️ SUBSCRIPTION_MODEL: Создание месячной подписки с лимитом 10 распознаваний в день");
    return SubscriptionModel(
      type: SubscriptionType.monthly,
      startDate: now,
      endDate: now.add(const Duration(days: 30)),
      availableRequests: 10,
      maxRequests: 10,
    );
  }

  /// Годовая подписка
  factory SubscriptionModel.yearly() {
    final now = DateTime.now();
    print(
        "🏗️ SUBSCRIPTION_MODEL: Создание годовой подписки с лимитом 10 распознаваний в день");
    return SubscriptionModel(
      type: SubscriptionType.yearly,
      startDate: now,
      endDate: now.add(const Duration(days: 365)),
      availableRequests: 10,
      maxRequests: 10,
    );
  }

  /// Бессрочная подписка
  factory SubscriptionModel.lifetime() {
    print(
        "🏗️ SUBSCRIPTION_MODEL: Создание пожизненной подписки с лимитом 10 распознаваний в день");
    return SubscriptionModel(
      type: SubscriptionType.lifetime,
      startDate: DateTime.now(),
      availableRequests: 10,
      maxRequests: 10,
    );
  }
}
