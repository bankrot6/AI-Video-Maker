import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/token_usage_model.dart';
import '../models/subscription_model.dart';
import 'subscription/subscription_storage_service.dart';

import '../services/trial_protection_service.dart';

/// Сервис для управления токенами пользователя
class TokenUsageService {
  // Синглтон
  static final TokenUsageService _instance = TokenUsageService._internal();
  factory TokenUsageService() => _instance;
  TokenUsageService._internal();

  // Ключи для SharedPreferences
  static const String _tokenUsageKey = 'token_usage_data';
  static const String _lastResetCheckKey = 'last_reset_check';
  static const String _userTypeKey = 'user_subscription_type';

  // Лимиты токенов
  // Free: только дневной лимит и общий суммарный лимит
  static const int FREE_DAILY_TOKENS = 7000; // 7k/день для free
  static const int FREE_TOTAL_TOKENS = 49000; // общий лимит для free

  // Paid/Trial: без дневного лимита, только общий лимит по периоду
  static const int WEEKLY_TOTAL_TOKENS = 49000;
  static const int MONTHLY_TOTAL_TOKENS = 210000;
  static const int YEARLY_TOTAL_TOKENS = 2555000;
  static const int YEARLY_TRIAL_TOTAL_TOKENS = 98000; // 7 дней trial окна

  // Сервис защиты триала
  final TrialProtectionService _trialProtection = TrialProtectionService();

  /// Получает текущую статистику использования токенов
  Future<TokenUsageModel> getTokenUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_tokenUsageKey);

      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        final tokenUsage = TokenUsageModel.fromJson(json);

        // Проверяем, нужно ли сбросить токены подписки
        return await _checkAndResetSubscriptionTokens(tokenUsage);
      }

      // Если данных нет, создаем новую модель на основе подписки
      return await _createInitialTokenUsage();
    } catch (e) {
      debugPrint('🔴 TOKEN_SERVICE: Ошибка получения данных токенов: $e');
      return await _createInitialTokenUsage();
    }
  }

  /// Создает начальную модель токенов на основе подписки
  Future<TokenUsageModel> _createInitialTokenUsage() async {
    try {
      final subscription = await _getCurrentSubscriptionDirect();

      if (subscription != null && subscription.isActive) {
        final int subscriptionTokens = subscription.totalTokensForPeriod > 0
            ? subscription.totalTokensForPeriod
            : subscription.dailyTokens * 30;

        // Специальный кейс: годовая подписка с 7-дневным триалом (trial window)
        final now = DateTime.now();
        final bool isYearlyWithTrialWindow = subscription.type ==
                SubscriptionType.yearly &&
            now.isBefore(subscription.startDate.add(const Duration(days: 7)));

        // Триал определяется ТОЛЬКО из данных подписки (покупки),
        // а не автоматически по eligibility. Для Yearly учитываем окно 7 дней от старта.
        if (subscription.isTrialUser || isYearlyWithTrialWindow) {
          // Во время триала (годовая подписка) общий лимит 14k на 7 дней
          final trialEnd = subscription.isTrialUser
              ? subscription.endDate ?? now.add(const Duration(days: 7))
              : subscription.startDate.add(const Duration(days: 7));

          return TokenUsageModel(
            totalTokens: YEARLY_TRIAL_TOTAL_TOKENS,
            usedTokens: 0,
            subscriptionTokens: YEARLY_TRIAL_TOTAL_TOKENS,
            purchasedTokens: 0,
            lastResetDate: now,
            isTrialUser: true,
            trialDaysRemaining: trialEnd.difference(now).inDays.clamp(0, 7),
            trialStartDate: subscription.startDate,
            trialEndDate: trialEnd,
          );
        } else if (subscription.isPaidUser) {
          return TokenUsageModel(
            totalTokens: subscriptionTokens,
            usedTokens: 0,
            subscriptionTokens: subscriptionTokens,
            purchasedTokens: 0,
            lastResetDate: DateTime.now(),
            isTrialUser: false,
          );
        }
      }

      // Без активной подписки — пользователь бесплатный (общий лимит 7k)
      return TokenUsageModel.freeUser();
    } catch (e) {
      debugPrint(
          '🔴 TOKEN_SERVICE: Ошибка создания начальной модели токенов: $e');
      return TokenUsageModel.freeUser();
    }
  }

  /// Проверяет и сбрасывает токены подписки при необходимости
  Future<TokenUsageModel> _checkAndResetSubscriptionTokens(
      TokenUsageModel tokenUsage) async {
    final now = DateTime.now();
    final lastReset = tokenUsage.lastResetDate;

    // Для триальных пользователей: без дневного лимита. По окончании окна
    // переключаемся на общий лимит подписки, сохраняя использованные токены.
    if (tokenUsage.isTrialUser) {
      // Если триал закончился — переключаемся на лимит подписки, сохраняя уже использованные
      if (tokenUsage.trialEndDate != null &&
          now.isAfter(tokenUsage.trialEndDate!)) {
        try {
          final subscription = await _getCurrentSubscriptionDirect();
          if (subscription != null && subscription.isPaidUser) {
            final fullPeriodTokens = await _getSubscriptionTokens();
            final remainingAfterTrial =
                (fullPeriodTokens - tokenUsage.usedTokens)
                    .clamp(0, fullPeriodTokens);

            final upgraded = tokenUsage.copyWith(
              totalTokens: remainingAfterTrial,
              subscriptionTokens: fullPeriodTokens,
              isTrialUser: false,
              lastResetDate: now,
            );
            await _saveTokenUsage(upgraded);
            return upgraded;
          }
        } catch (e) {
          debugPrint('🔴 TOKEN_SERVICE: Ошибка апгрейда после триала: $e');
        }
      }

      return tokenUsage;
    } else {
      // Для платных пользователей приоритетно ориентируемся на период подписки
      // Если началась новая подписка (обновился startDate), сбрасываем токены на весь период
      try {
        final subscription = await _getCurrentSubscriptionDirect();
        if (subscription != null && subscription.isPaidUser) {
          // Если последний сброс был до старта текущего периода подписки — это продление
          if (lastReset.isBefore(subscription.startDate)) {
            debugPrint(
                '💎 TOKEN_SERVICE: Обнаружено продление подписки — сбрасываем токены по периоду');
            final subscriptionTokens = await _getSubscriptionTokens();
            final updatedUsage =
                tokenUsage.resetSubscriptionTokens(subscriptionTokens);
            await _saveTokenUsage(updatedUsage);
            return updatedUsage;
          }
        }
      } catch (e) {
        debugPrint('🔴 TOKEN_SERVICE: Ошибка проверки продления подписки: $e');
      }

      // Удаляем месячный фолбэк: платные лимиты сбрасываются только по периодам подписки
    }

    return tokenUsage;
  }

  /// Получает количество токенов для текущей подписки
  Future<int> _getSubscriptionTokens() async {
    try {
      final subscription = await _getCurrentSubscriptionDirect();

      if (subscription != null && subscription.isActive) {
        switch (subscription.type) {
          case SubscriptionType.weekly:
            return WEEKLY_TOTAL_TOKENS;
          case SubscriptionType.monthly:
            return MONTHLY_TOTAL_TOKENS;
          case SubscriptionType.yearly:
            return YEARLY_TOTAL_TOKENS;
          case SubscriptionType.lifetime:
            return YEARLY_TOTAL_TOKENS;
          default:
            return 0;
        }
      }

      return 0;
    } catch (e) {
      debugPrint('🔴 TOKEN_SERVICE: Ошибка получения токенов подписки: $e');
      return 0;
    }
  }

  // Удалено: _getUserSubscriptionType не используется

  /// Проверяет, может ли пользователь использовать токены с учетом триальных лимитов
  Future<TokenUsageResult> checkTokenUsage(int tokenCount) async {
    try {
      final tokenUsage = await getTokenUsage();

      // Если есть оставшиеся платные токены, игнорируем триальные дневные лимиты
      if (tokenUsage.remainingPurchasedTokens > 0) {
        return tokenUsage.hasEnoughTokens(tokenCount)
            ? TokenUsageResult(
                allowed: true,
                reason: 'usage_allowed',
                remainingTokensToday: tokenUsage.remainingTokens,
              )
            : TokenUsageResult(
                allowed: false,
                reason: 'insufficient_tokens',
                remainingTokensToday: tokenUsage.remainingTokens,
              );
      }

      // Для триальных пользователей используем защиту триала
      if (tokenUsage.isTrialUser) {
        return await _trialProtection.checkTokenUsage(
          requestedTokens: tokenCount,
          isTrialUser: true,
        );
      }

      // Для платных пользователей проверяем только общий лимит
      if (!tokenUsage.hasEnoughTokens(tokenCount)) {
        return TokenUsageResult(
          allowed: false,
          reason: 'insufficient_tokens',
          remainingTokensToday: tokenUsage.remainingTokens,
        );
      }

      return TokenUsageResult(
        allowed: true,
        reason: 'usage_allowed',
        remainingTokensToday: tokenUsage.remainingTokens,
      );
    } catch (e) {
      debugPrint('🔴 TOKEN_SERVICE: Ошибка проверки токенов: $e');
      return TokenUsageResult(
        allowed: false,
        reason: 'usage_check_error',
      );
    }
  }

  /// Использует токены для AI запроса
  Future<bool> useTokens(int tokenCount) async {
    try {
      final tokenUsage = await getTokenUsage();

      // Проверяем лимиты
      final usageResult = await checkTokenUsage(tokenCount);
      if (!usageResult.allowed) {
        debugPrint(
            '❌ TOKEN_SERVICE: Использование токенов отклонено: ${usageResult.reason}');
        return false;
      }

      // Для триальных пользователей записываем в систему защиты триала
      // Исключение: если списываем платные токены (remainingPurchasedTokens>0), дневной лимит не трогаем
      if (tokenUsage.isTrialUser && tokenUsage.remainingPurchasedTokens == 0) {
        await _trialProtection.recordTokenUsage(tokenCount);
      }

      // Обновляем основную статистику
      final updatedUsage = tokenUsage.useTokens(tokenCount);
      await _saveTokenUsage(updatedUsage);

      debugPrint(
          '✅ TOKEN_SERVICE: Использовано $tokenCount токенов, осталось ${updatedUsage.remainingTokens}');
      return true;
    } catch (e) {
      debugPrint('🔴 TOKEN_SERVICE: Ошибка использования токенов: $e');
      return false;
    }
  }

  /// Сохраняет данные об использовании токенов
  Future<void> _saveTokenUsage(TokenUsageModel tokenUsage) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(tokenUsage.toJson());
      await prefs.setString(_tokenUsageKey, jsonString);

      debugPrint(
          '💾 TOKEN_SERVICE: Данные токенов сохранены: ${tokenUsage.toString()}');
    } catch (e) {
      debugPrint('🔴 TOKEN_SERVICE: Ошибка сохранения данных токенов: $e');
    }
  }

  /// Добавляет купленные токены
  Future<void> addPurchasedTokens(int tokenCount) async {
    try {
      final currentUsage = await getTokenUsage();
      final updatedUsage = currentUsage.addPurchasedTokens(tokenCount);
      await _saveTokenUsage(updatedUsage);

      debugPrint('💰 TOKEN_SERVICE: Добавлено $tokenCount купленных токенов');
    } catch (e) {
      debugPrint('🔴 TOKEN_SERVICE: Ошибка добавления купленных токенов: $e');
    }
  }

  /// Проверяет, достаточно ли токенов для запроса
  Future<bool> hasEnoughTokens(int requiredTokens) async {
    try {
      final usageResult = await checkTokenUsage(requiredTokens);
      return usageResult.allowed;
    } catch (e) {
      debugPrint('🔴 TOKEN_SERVICE: Ошибка проверки токенов: $e');
      return false;
    }
  }

  /// Оценивает количество токенов для текста (приблизительно)
  int estimateTokensForText(String text) {
    // Приблизительная оценка: 1 токен ≈ 4 символа для английского текста
    // Для русского текста может быть немного больше
    // Добавляем небольшой буфер для безопасности
    return (text.length / 3.5).ceil() + 50;
  }

  /// Получает список доступных пакетов токенов для покупки
  List<TokenPackageModel> getAvailablePackages() {
    return [
      TokenPackageModel(
        type: TokenPackageType.small,
        title: 'Стартовый пакет',
        description: '100,000 токенов\n~200 подробных запросов',
        tokens: TokenPackageType.small.tokens,
        price: TokenPackageType.small.priceRub.toDouble(),
        currency: 'RUB',
      ),
      TokenPackageModel(
        type: TokenPackageType.medium,
        title: 'Популярный пакет',
        description: '300,000 токенов\n~600 подробных запросов',
        tokens: TokenPackageType.medium.tokens,
        price: TokenPackageType.medium.priceRub.toDouble(),
        currency: 'RUB',
        badge: 'Лучшее предложение',
      ),
      TokenPackageModel(
        type: TokenPackageType.large,
        title: 'Максимальный пакет',
        description: '800,000 токенов\n~1600 подробных запросов',
        tokens: TokenPackageType.large.tokens,
        price: TokenPackageType.large.priceRub.toDouble(),
        currency: 'RUB',
      ),
    ];
  }

  /// Активирует триальный период
  Future<void> activateTrialPeriod() async {
    try {
      await _trialProtection.registerTrialStart();

      // Создаем токены для триала (годовая логика окна)
      final trialUsage = TokenUsageModel(
        totalTokens: YEARLY_TRIAL_TOTAL_TOKENS,
        usedTokens: 0,
        subscriptionTokens: YEARLY_TRIAL_TOTAL_TOKENS,
        purchasedTokens: 0,
        lastResetDate: DateTime.now(),
        isTrialUser: true,
        trialDaysRemaining: 7,
        trialStartDate: DateTime.now(),
        trialEndDate: DateTime.now().add(const Duration(days: 7)),
      );

      await _saveTokenUsage(trialUsage);
      debugPrint('🎉 TOKEN_SERVICE: Триальный период активирован');
    } catch (e) {
      debugPrint('🔴 TOKEN_SERVICE: Ошибка активации триала: $e');
    }
  }

  /// Получает статистику триального использования
  Future<TrialUsageStats> getTrialUsageStats() async {
    return await _trialProtection.getTrialUsageStats();
  }

  /// Сбрасывает все данные токенов (для тестирования)
  Future<void> resetTokenUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenUsageKey);
      await prefs.remove(_lastResetCheckKey);
      await prefs.remove(_userTypeKey);

      debugPrint('🔄 TOKEN_SERVICE: Данные токенов сброшены');
    } catch (e) {
      debugPrint('🔴 TOKEN_SERVICE: Ошибка сброса данных токенов: $e');
    }
  }

  /// Очищает старые данные
  Future<void> cleanOldData() async {
    await _trialProtection.cleanOldData();
  }

  /// Вспомогательный метод для получения подписки без зависимости от репозитория
  Future<SubscriptionModel?> _getCurrentSubscriptionDirect() async {
    try {
      // 1) Пытаемся получить подписку из нового хранилища (используется для RuStore/ЮKassa)
      final storageService = SubscriptionStorageService();
      final storageInfo = await storageService.getSubscription();
      if (storageInfo != null) {
        return SubscriptionModel(
          type: storageInfo.type,
          startDate: storageInfo.startDate,
          endDate: storageInfo.endDate,
          availableRequests: 10, // по умолчанию дневной лимит запросов
          maxRequests: 10,
        );
      }

      // 2) Фолбэк: старый формат из SubscriptionRepository (in_app_purchase)
      final prefs = await SharedPreferences.getInstance();
      final String? subscriptionJson = prefs.getString('user_subscription');
      if (subscriptionJson == null || subscriptionJson.isEmpty) {
        return null;
      }

      final Map<String, dynamic> data =
          jsonDecode(subscriptionJson) as Map<String, dynamic>;

      final SubscriptionType type =
          SubscriptionType.values[(data['type'] as int?) ?? 0];
      final DateTime startDate =
          DateTime.fromMillisecondsSinceEpoch((data['startDate'] as int?) ?? 0);
      final DateTime? endDate = data['endDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['endDate'] as int)
          : null;
      final int availableRequests = (data['availableRequests'] as int?) ?? 0;
      final int maxRequests = (data['maxRequests'] as int?) ?? 0;

      return SubscriptionModel(
        type: type,
        startDate: startDate,
        endDate: endDate,
        availableRequests: availableRequests,
        maxRequests: maxRequests,
      );
    } catch (e) {
      debugPrint('🔴 TOKEN_SERVICE: Ошибка получения подписки: $e');
      return null;
    }
  }
}

/// Типы подписок пользователей
enum UserSubscriptionType {
  free,
  trial,
  paid,
}
