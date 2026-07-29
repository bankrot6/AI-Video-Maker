import 'package:shared_preferences/shared_preferences.dart';
import '../data/subscription_repository.dart';
import '../models/subscription_model.dart';

class CityLimitService {
  static const String _periodKeyStorage = 'city_usage_period_key';
  static const String _totalUsageKey = 'city_usage_total';
  static const String _dailyUsagePrefix = 'city_usage_day_';

  static const int _paidDailyLimit = 5;
  static const int _trialDailyLimit = 3;
  static const int _trialTotalLimit = 21;

  final SubscriptionRepository _subscriptionRepository;
  final SharedPreferences _prefs;

  CityLimitService(this._subscriptionRepository, this._prefs);

  Future<CityLimitCheckResult> checkAndRecordCityCreation() async {
    final subscription = await _subscriptionRepository.getCurrentSubscription();
    final limits = _resolveLimits(subscription);
    if (limits == null) {
      return CityLimitCheckResult.allowed();
    }

    final now = DateTime.now();
    _syncPeriodKey(subscription);

    final dailyKey = '$_dailyUsagePrefix${_dateKey(now)}';
    final usedToday = _prefs.getInt(dailyKey) ?? 0;
    final usedTotal = _prefs.getInt(_totalUsageKey) ?? 0;

    if (limits.dailyLimit != null && usedToday >= limits.dailyLimit!) {
      return CityLimitCheckResult.denied(
        reason: limits.isTrial
            ? CityLimitReason.trialDailyLimit
            : CityLimitReason.dailyLimit,
        dailyLimit: limits.dailyLimit,
        totalLimit: limits.totalLimit,
        remainingDaily: 0,
        remainingTotal: limits.totalLimit != null
            ? (limits.totalLimit! - usedTotal).clamp(0, limits.totalLimit!)
            : null,
      );
    }

    if (limits.totalLimit != null && usedTotal >= limits.totalLimit!) {
      return CityLimitCheckResult.denied(
        reason: limits.isTrial
            ? CityLimitReason.trialTotalLimit
            : CityLimitReason.totalLimit,
        dailyLimit: limits.dailyLimit,
        totalLimit: limits.totalLimit,
        remainingDaily: limits.dailyLimit != null
            ? (limits.dailyLimit! - usedToday).clamp(0, limits.dailyLimit!)
            : null,
        remainingTotal: 0,
      );
    }

    await _prefs.setInt(dailyKey, usedToday + 1);
    if (limits.totalLimit != null) {
      await _prefs.setInt(_totalUsageKey, usedTotal + 1);
    }

    return CityLimitCheckResult.allowed(
      dailyLimit: limits.dailyLimit,
      totalLimit: limits.totalLimit,
      remainingDaily: limits.dailyLimit != null
          ? (limits.dailyLimit! - usedToday - 1)
              .clamp(0, limits.dailyLimit!)
          : null,
      remainingTotal: limits.totalLimit != null
          ? (limits.totalLimit! - usedTotal - 1)
              .clamp(0, limits.totalLimit!)
          : null,
    );
  }

  CityLimitDefinition? _resolveLimits(SubscriptionModel subscription) {
    if (subscription.type == SubscriptionType.free) {
      return null;
    }

    if (subscription.type == SubscriptionType.trial && subscription.isActive) {
      return const CityLimitDefinition(
        dailyLimit: _trialDailyLimit,
        totalLimit: _trialTotalLimit,
        isTrial: true,
      );
    }

    if (!subscription.isPaidUser) {
      return null;
    }

    final totalLimit = _totalLimitForPaid(subscription);
    return CityLimitDefinition(
      dailyLimit: _paidDailyLimit,
      totalLimit: totalLimit,
      isTrial: false,
    );
  }

  int? _totalLimitForPaid(SubscriptionModel subscription) {
    switch (subscription.type) {
      case SubscriptionType.weekly:
        return 14;
      case SubscriptionType.monthly:
        return 60;
      case SubscriptionType.yearly:
        return 730;
      case SubscriptionType.lifetime:
        return null;
      case SubscriptionType.free:
      case SubscriptionType.trial:
        return null;
    }
  }

  void _syncPeriodKey(SubscriptionModel subscription) {
    final currentKey = _prefs.getString(_periodKeyStorage);
    final nextKey =
        '${subscription.type.name}_${subscription.startDate.millisecondsSinceEpoch}';
    if (currentKey == nextKey) return;
    _prefs.setString(_periodKeyStorage, nextKey);
    _prefs.setInt(_totalUsageKey, 0);
  }

  String _dateKey(DateTime date) => '${date.year}_${date.month}_${date.day}';
}

class CityLimitDefinition {
  final int? dailyLimit;
  final int? totalLimit;
  final bool isTrial;

  const CityLimitDefinition({
    required this.dailyLimit,
    required this.totalLimit,
    required this.isTrial,
  });
}

enum CityLimitReason {
  dailyLimit,
  totalLimit,
  trialDailyLimit,
  trialTotalLimit,
}

class CityLimitCheckResult {
  final bool allowed;
  final CityLimitReason? reason;
  final int? dailyLimit;
  final int? totalLimit;
  final int? remainingDaily;
  final int? remainingTotal;

  const CityLimitCheckResult._({
    required this.allowed,
    this.reason,
    this.dailyLimit,
    this.totalLimit,
    this.remainingDaily,
    this.remainingTotal,
  });

  factory CityLimitCheckResult.allowed({
    int? dailyLimit,
    int? totalLimit,
    int? remainingDaily,
    int? remainingTotal,
  }) {
    return CityLimitCheckResult._(
      allowed: true,
      dailyLimit: dailyLimit,
      totalLimit: totalLimit,
      remainingDaily: remainingDaily,
      remainingTotal: remainingTotal,
    );
  }

  factory CityLimitCheckResult.denied({
    required CityLimitReason reason,
    int? dailyLimit,
    int? totalLimit,
    int? remainingDaily,
    int? remainingTotal,
  }) {
    return CityLimitCheckResult._(
      allowed: false,
      reason: reason,
      dailyLimit: dailyLimit,
      totalLimit: totalLimit,
      remainingDaily: remainingDaily,
      remainingTotal: remainingTotal,
    );
  }
}

class CityLimitException implements Exception {
  final CityLimitCheckResult result;

  CityLimitException(this.result);
}
