import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/token_usage_model.dart';
import '../services/token_usage_service.dart';
import '../services/trial_protection_service.dart';

/// Провайдер сервиса управления токенами
final tokenUsageServiceProvider = Provider<TokenUsageService>((ref) {
  return TokenUsageService();
});

/// Провайдер сервиса защиты триала
final trialProtectionServiceProvider = Provider<TrialProtectionService>((ref) {
  return TrialProtectionService();
});

/// Провайдер для получения текущего состояния токенов пользователя
final tokenUsageProvider = FutureProvider<TokenUsageModel>((ref) async {
  final tokenService = ref.read(tokenUsageServiceProvider);
  return await tokenService.getTokenUsage();
});

/// Провайдер для статистики триального использования
final trialUsageStatsProvider = FutureProvider<TrialUsageStats>((ref) async {
  final trialService = ref.read(trialProtectionServiceProvider);
  return await trialService.getTrialUsageStats();
});

/// Провайдер для проверки возможности использования токенов
final canUseTokensProvider =
    FutureProvider.family<TokenUsageResult, int>((ref, tokenCount) async {
  final tokenService = ref.read(tokenUsageServiceProvider);
  return await tokenService.checkTokenUsage(tokenCount);
});

/// Нотификатор для управления состоянием токенов с возможностью изменения
class TokenUsageNotifier extends AsyncNotifier<TokenUsageModel> {
  late TokenUsageService _tokenService;

  @override
  Future<TokenUsageModel> build() async {
    _tokenService = ref.read(tokenUsageServiceProvider);
    return await _tokenService.getTokenUsage();
  }

  /// Использует указанное количество токенов
  Future<bool> useTokens(int tokenCount) async {
    final success = await _tokenService.useTokens(tokenCount);
    if (success) {
      // Обновляем состояние после использования токенов
      ref.invalidateSelf();
    }
    return success;
  }

  /// Добавляет купленные токены
  Future<void> addPurchasedTokens(int tokenCount) async {
    await _tokenService.addPurchasedTokens(tokenCount);
    // Обновляем состояние после добавления токенов
    ref.invalidateSelf();
  }

  /// Активирует триальный период
  Future<void> activateTrialPeriod() async {
    await _tokenService.activateTrialPeriod();
    // Обновляем состояние после активации триала
    ref.invalidateSelf();
  }

  /// Сбрасывает данные о токенах (для тестирования)
  Future<void> resetTokenUsage() async {
    await _tokenService.resetTokenUsage();
    // Обновляем состояние после сброса
    ref.invalidateSelf();
  }

  /// Проверяет, достаточно ли токенов для запроса
  Future<TokenUsageResult> checkTokenUsage(int requiredTokens) async {
    return await _tokenService.checkTokenUsage(requiredTokens);
  }

  /// Получает доступные пакеты токенов для покупки
  List<TokenPackageModel> getAvailablePackages() {
    return _tokenService.getAvailablePackages();
  }

  /// Обновляет состояние из подписки
  Future<void> refreshFromSubscription() async {
    // Инвалидируем текущее состояние, чтобы оно обновилось
    ref.invalidateSelf();
  }
}

/// Провайдер нотификатора токенов
final tokenUsageNotifierProvider =
    AsyncNotifierProvider<TokenUsageNotifier, TokenUsageModel>(() {
  return TokenUsageNotifier();
});

/// Провайдер для проверки права на триальный период
final trialEligibilityProvider =
    FutureProvider<TrialEligibilityResult>((ref) async {
  final trialService = ref.read(trialProtectionServiceProvider);
  return await trialService.checkTrialEligibility();
});

/// Провайдер для интеграции токенов с подпиской
final subscriptionTokensProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    // Простая проверка подписки без сложных зависимостей
    final tokenService = ref.read(tokenUsageServiceProvider);
    final tokenUsage = await tokenService.getTokenUsage();

    return {
      'hasSubscription': tokenUsage.subscriptionTokens > 0,
      'dailyTokens': tokenUsage.isTrialUser
          ? 7000
          : (tokenUsage.subscriptionTokens > 0 ? 7000 : 0),
      'totalTokens': tokenUsage.totalTokens,
      'isTrialUser': tokenUsage.isTrialUser,
      'isPaidUser':
          (!tokenUsage.isTrialUser && tokenUsage.subscriptionTokens > 0),
      'hasUnlimitedTokens': false,
      'subscriptionType': tokenUsage.isTrialUser
          ? 'trial'
          : (tokenUsage.subscriptionTokens > 0 ? 'paid' : 'free'),
    };
  } catch (e) {
    return {
      'hasSubscription': false,
      'error': e.toString(),
    };
  }
});

/// Комбинированный провайдер для токенов с учетом подписки
final combinedTokenStatusProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final tokenUsageAsync = ref.watch(tokenUsageProvider);
    final subscriptionTokensAsync = ref.watch(subscriptionTokensProvider);
    final trialStatsAsync = ref.watch(trialUsageStatsProvider);

    return await tokenUsageAsync.when(
      data: (tokenUsage) async {
        final subscriptionTokens = subscriptionTokensAsync.when(
          data: (data) => data,
          loading: () => {'loading': true},
          error: (error, stack) => {'error': error.toString()},
        );

        final trialStats = trialStatsAsync.when(
          data: (data) => data,
          loading: () => TrialUsageStats.empty(),
          error: (error, stack) => TrialUsageStats.empty(),
        );

        return {
          'tokenUsage': tokenUsage,
          'subscription': subscriptionTokens,
          'trialStats': trialStats,
          'hasEnoughTokens': tokenUsage.remainingTokens > 100,
          'isLowOnTokens': tokenUsage.remainingTokens < 500,
          'shouldShowUpgrade': tokenUsage.remainingTokens < 200 &&
              !(subscriptionTokens['isPaidUser'] ?? false),
        };
      },
      loading: () => {'loading': true},
      error: (error, stack) => {'error': error.toString()},
    );
  } catch (e) {
    return {'error': e.toString()};
  }
});

/// Провайдер для автоматического обновления токенов при изменении подписки
final tokenSubscriptionSyncProvider = Provider<void>((ref) {
  // Слушаем изменения токенов для обновления триальной статистики
  ref.listen(tokenUsageProvider, (previous, next) {
    next.whenData((tokenUsage) {
      if (tokenUsage.isTrialUser) {
        // Обновляем статистику триала
        ref.invalidate(trialUsageStatsProvider);
      }
    });
  });
});
