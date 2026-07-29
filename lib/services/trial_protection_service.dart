import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Сервис защиты от злоупотреблений триальным периодом
class TrialProtectionService {
  static final TrialProtectionService _instance =
      TrialProtectionService._internal();
  factory TrialProtectionService() => _instance;
  TrialProtectionService._internal();

  // Ключи для хранения
  static const String _deviceFingerprintKey = 'device_fingerprint';
  static const String _trialUsageKey = 'trial_usage_history';
  static const String _lastTrialStartKey = 'last_trial_start';
  static const String _suspiciousActivityKey = 'suspicious_activity';

  /// Лимиты для триального периода
  static const int TRIAL_DAILY_TOKENS = 7000; // 7k токенов в день
  static const int TRIAL_HOURLY_LIMIT = 1000; // Не более 1000 токенов в час
  static const int TRIAL_REQUEST_LIMIT = 10; // Не более 10 запросов в час
  static const int TRIAL_MAX_TOTAL_TOKENS = 98000; // 98k токенов за весь триал
  static const int MIN_REQUEST_INTERVAL = 30; // Минимум 30 сек между запросами

  /// Проверяет, может ли пользователь использовать триал
  Future<TrialEligibilityResult> checkTrialEligibility() async {
    try {
      // 1. Проверяем device fingerprint
      final deviceFingerprint = await _getDeviceFingerprint();
      final isDeviceKnown = await _isDeviceUsedTrial(deviceFingerprint);

      if (isDeviceKnown) {
        return TrialEligibilityResult(
          isEligible: false,
          reason: 'trial_already_used_device',
          riskLevel: RiskLevel.high,
        );
      }

      // 2. Проверяем подозрительную активность
      final suspiciousActivity = await _checkSuspiciousActivity();
      if (suspiciousActivity.isNotEmpty) {
        return TrialEligibilityResult(
          isEligible: false,
          reason: 'suspicious_activity_detected',
          riskLevel: RiskLevel.high,
          details: suspiciousActivity,
        );
      }

      // 3. Проверяем временные ограничения
      final lastTrialStart = await _getLastTrialStart();
      if (lastTrialStart != null) {
        final daysSinceLastTrial =
            DateTime.now().difference(lastTrialStart).inDays;
        if (daysSinceLastTrial < 30) {
          return TrialEligibilityResult(
            isEligible: false,
            reason: 'trial_cooldown_period',
            riskLevel: RiskLevel.medium,
            daysToWait: 30 - daysSinceLastTrial,
          );
        }
      }

      return TrialEligibilityResult(
        isEligible: true,
        reason: 'trial_available',
        riskLevel: RiskLevel.low,
      );
    } catch (e) {
      debugPrint('🔴 TRIAL_PROTECTION: Ошибка проверки права на триал: $e');
      return TrialEligibilityResult(
        isEligible: false,
        reason: 'trial_check_error',
        riskLevel: RiskLevel.unknown,
      );
    }
  }

  /// Проверяет, можно ли использовать токены в данный момент
  Future<TokenUsageResult> checkTokenUsage({
    required int requestedTokens,
    required bool isTrialUser,
  }) async {
    if (!isTrialUser) {
      return TokenUsageResult(allowed: true, reason: 'paid_subscription');
    }

    try {
      // 1. Проверяем дневной лимит
      final todayUsage = await _getTodayTokenUsage();
      if (todayUsage + requestedTokens > TRIAL_DAILY_TOKENS) {
        return TokenUsageResult(
          allowed: false,
          reason: 'daily_limit_exceeded',
          remainingTokensToday: TRIAL_DAILY_TOKENS - todayUsage,
          limitValue: TRIAL_DAILY_TOKENS,
        );
      }

      // Проверяем общий лимит за весь триал
      final totalTrialUsage = await _getTotalTrialTokenUsage();
      if (totalTrialUsage + requestedTokens > TRIAL_MAX_TOTAL_TOKENS) {
        return TokenUsageResult(
          allowed: false,
          reason: 'trial_total_limit_exceeded',
          limitValue: TRIAL_MAX_TOTAL_TOKENS,
        );
      }

      // Все проверки пройдены
      return TokenUsageResult(
        allowed: true,
        reason: 'usage_allowed',
        remainingTokensToday: TRIAL_DAILY_TOKENS - todayUsage,
        remainingTrialTokens: TRIAL_MAX_TOTAL_TOKENS - totalTrialUsage,
      );
    } catch (e) {
      debugPrint(
          '🔴 TRIAL_PROTECTION: Ошибка проверки использования токенов: $e');
      return TokenUsageResult(
        allowed: false,
        reason: 'usage_check_error',
      );
    }
  }

  /// Регистрирует начало триального периода
  Future<void> registerTrialStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceFingerprint = await _getDeviceFingerprint();

      // Сохраняем fingerprint устройства
      await prefs.setString(_deviceFingerprintKey, deviceFingerprint);

      // Сохраняем время начала триала
      await prefs.setInt(
          _lastTrialStartKey, DateTime.now().millisecondsSinceEpoch);

      debugPrint('✅ TRIAL_PROTECTION: Триальный период зарегистрирован');
    } catch (e) {
      debugPrint('🔴 TRIAL_PROTECTION: Ошибка регистрации триала: $e');
    }
  }

  /// Записывает использование токенов
  Future<void> recordTokenUsage(int tokens) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      // Обновляем последнее время запроса
      await prefs.setInt('last_request_time', now.millisecondsSinceEpoch);

      // Записываем использование токенов за день
      final dailyUsageKey = 'token_usage_${_getDateKey(now)}';
      final currentDailyUsage = prefs.getInt(dailyUsageKey) ?? 0;
      await prefs.setInt(dailyUsageKey, currentDailyUsage + tokens);

      // Записываем использование токенов за час
      final hourlyUsageKey = 'token_usage_${_getHourKey(now)}';
      final currentHourlyUsage = prefs.getInt(hourlyUsageKey) ?? 0;
      await prefs.setInt(hourlyUsageKey, currentHourlyUsage + tokens);

      // Записываем количество запросов
      final requestKey = 'request_count_${_getHourKey(now)}';
      final currentRequests = prefs.getInt(requestKey) ?? 0;
      await prefs.setInt(requestKey, currentRequests + 1);

      debugPrint('📊 TRIAL_PROTECTION: Записано использование $tokens токенов');
    } catch (e) {
      debugPrint(
          '🔴 TRIAL_PROTECTION: Ошибка записи использования токенов: $e');
    }
  }

  /// Получает статистику использования триала
  Future<TrialUsageStats> getTrialUsageStats() async {
    try {
      final todayUsage = await _getTodayTokenUsage();
      final totalUsage = await _getTotalTrialTokenUsage();
      final hourlyUsage = await _getHourlyTokenUsage();
      final hourlyRequests = await _getHourlyRequestCount();

      return TrialUsageStats(
        tokensUsedToday: todayUsage,
        tokensRemainingToday: TRIAL_DAILY_TOKENS - todayUsage,
        totalTokensUsed: totalUsage,
        totalTokensRemaining: TRIAL_MAX_TOTAL_TOKENS - totalUsage,
        tokensUsedThisHour: hourlyUsage,
        requestsThisHour: hourlyRequests,
        dailyLimit: TRIAL_DAILY_TOKENS,
        totalLimit: TRIAL_MAX_TOTAL_TOKENS,
        hourlyTokenLimit: TRIAL_HOURLY_LIMIT,
        hourlyRequestLimit: TRIAL_REQUEST_LIMIT,
      );
    } catch (e) {
      debugPrint('🔴 TRIAL_PROTECTION: Ошибка получения статистики: $e');
      return TrialUsageStats.empty();
    }
  }

  /// Генерирует уникальный fingerprint устройства
  Future<String> _getDeviceFingerprint() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String fingerprint = '';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        fingerprint =
            '${androidInfo.model}_${androidInfo.device}_${androidInfo.product}_${androidInfo.id}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        fingerprint =
            '${iosInfo.model}_${iosInfo.systemName}_${iosInfo.systemVersion}_${iosInfo.identifierForVendor}';
      }

      // Хешируем для анонимности
      final bytes = utf8.encode(fingerprint);
      final hash = sha256.convert(bytes);
      return hash.toString();
    } catch (e) {
      debugPrint('🔴 TRIAL_PROTECTION: Ошибка генерации fingerprint: $e');
      return 'unknown_device_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Проверяет, использовалось ли устройство для триала
  Future<bool> _isDeviceUsedTrial(String fingerprint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedFingerprint = prefs.getString(_deviceFingerprintKey);
      return savedFingerprint == fingerprint;
    } catch (e) {
      return false;
    }
  }

  /// Проверяет подозрительную активность
  Future<String> _checkSuspiciousActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Проверяем частоту переустановок (по времени первого запуска)
      final firstLaunchKey = 'first_app_launch';
      final firstLaunch = prefs.getInt(firstLaunchKey);
      final now = DateTime.now().millisecondsSinceEpoch;

      if (firstLaunch == null) {
        await prefs.setInt(firstLaunchKey, now);
      } else {
        final daysSinceFirstLaunch =
            (now - firstLaunch) / (1000 * 60 * 60 * 24);
        if (daysSinceFirstLaunch < 1) {
          // Приложение было установлено менее суток назад
          final installCount = prefs.getInt('install_count') ?? 0;
          await prefs.setInt('install_count', installCount + 1);

          if (installCount > 3) {
            return 'frequent_reinstalls';
          }
        }
      }

      return '';
    } catch (e) {
      return '';
    }
  }

  Future<DateTime?> _getLastTrialStart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastTrialStartKey);
      return timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : null;
    } catch (e) {
      return null;
    }
  }

  Future<int> _getTodayTokenUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = _getDateKey(DateTime.now());
      return prefs.getInt('token_usage_$today') ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getHourlyTokenUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hour = _getHourKey(DateTime.now());
      return prefs.getInt('token_usage_$hour') ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> _getHourlyRequestCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hour = _getHourKey(DateTime.now());
      return prefs.getInt('request_count_$hour') ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<DateTime?> _getLastRequestTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('last_request_time');
      return timestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
          : null;
    } catch (e) {
      return null;
    }
  }

  Future<int> _getTotalTrialTokenUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int total = 0;
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith('token_usage_') && key.contains('_')) {
          // Исключаем часовые записи, считаем только дневные
          final parts = key.split('_');
          if (parts.length == 4) {
            // token_usage_year_month_day
            total += prefs.getInt(key) ?? 0;
          }
        }
      }

      return total;
    } catch (e) {
      return 0;
    }
  }

  String _getDateKey(DateTime date) {
    return '${date.year}_${date.month}_${date.day}';
  }

  String _getHourKey(DateTime date) {
    return '${date.year}_${date.month}_${date.day}_${date.hour}';
  }

  /// Очистка старых данных (вызывать периодически)
  Future<void> cleanOldData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final now = DateTime.now();

      for (final key in keys) {
        if (key.startsWith('token_usage_') ||
            key.startsWith('request_count_')) {
          // Удаляем данные старше 30 дней
          try {
            final parts = key.split('_');
            if (parts.length >= 4) {
              final year = int.parse(parts[2]);
              final month = int.parse(parts[3]);
              final day = int.parse(parts[4]);
              final date = DateTime(year, month, day);

              if (now.difference(date).inDays > 30) {
                await prefs.remove(key);
              }
            }
          } catch (e) {
            // Игнорируем ошибки парсинга
          }
        }
      }
    } catch (e) {
      debugPrint('🔴 TRIAL_PROTECTION: Ошибка очистки старых данных: $e');
    }
  }
}

/// Результат проверки права на триальный период
class TrialEligibilityResult {
  final bool isEligible;
  final String reason;
  final RiskLevel riskLevel;
  final String? details;
  final int? daysToWait;

  TrialEligibilityResult({
    required this.isEligible,
    required this.reason,
    required this.riskLevel,
    this.details,
    this.daysToWait,
  });
}

/// Результат проверки использования токенов
class TokenUsageResult {
  final bool allowed;
  final String reason;
  final int? remainingTokensToday;
  final int? remainingTrialTokens;
  final int? waitTimeMinutes;
  final int? waitTimeSeconds;
  final int? limitValue;

  TokenUsageResult({
    required this.allowed,
    required this.reason,
    this.remainingTokensToday,
    this.remainingTrialTokens,
    this.waitTimeMinutes,
    this.waitTimeSeconds,
    this.limitValue,
  });
}

/// Статистика использования триала
class TrialUsageStats {
  final int tokensUsedToday;
  final int tokensRemainingToday;
  final int totalTokensUsed;
  final int totalTokensRemaining;
  final int tokensUsedThisHour;
  final int requestsThisHour;
  final int dailyLimit;
  final int totalLimit;
  final int hourlyTokenLimit;
  final int hourlyRequestLimit;

  TrialUsageStats({
    required this.tokensUsedToday,
    required this.tokensRemainingToday,
    required this.totalTokensUsed,
    required this.totalTokensRemaining,
    required this.tokensUsedThisHour,
    required this.requestsThisHour,
    required this.dailyLimit,
    required this.totalLimit,
    required this.hourlyTokenLimit,
    required this.hourlyRequestLimit,
  });

  factory TrialUsageStats.empty() {
    return TrialUsageStats(
      tokensUsedToday: 0,
      tokensRemainingToday: 0,
      totalTokensUsed: 0,
      totalTokensRemaining: 0,
      tokensUsedThisHour: 0,
      requestsThisHour: 0,
      dailyLimit: 0,
      totalLimit: 0,
      hourlyTokenLimit: 0,
      hourlyRequestLimit: 0,
    );
  }
}

/// Уровень риска злоупотребления
enum RiskLevel {
  low,
  medium,
  high,
  unknown,
}
