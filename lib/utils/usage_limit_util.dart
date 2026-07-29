import 'package:flutter/material.dart';
import '../services/providers.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/localization/app_localization_service.dart';

/// Утилитарный класс для проверки лимитов использования
class UsageLimitUtil {
  /// Выполняет проверку лимитов перед выполнением действия
  static Future<bool> checkUsageLimitBeforeAction(
    BuildContext context,
    WidgetRef ref, {
    bool showRemainingUsagesWarning = true,
    String actionName = '',
    bool suppressFailureSnack = false,
  }) async {
    print("🔍 LIMITS: checkUsageLimitBeforeAction: Начало проверки лимитов");

    final subscription = ref.read(subscriptionServiceProvider);
    final remainingUsages = await subscription.getRemainingRequests();
    final hasPaidSubscription = await subscription.hasPaidSubscription();

    print(
        "📊 LIMITS: Статус подписки перед проверкой: осталось=$remainingUsages, платная=$hasPaidSubscription");

    final hasAvailableRequests = await subscription.hasAvailableRequests();
    print(
        "🔢 LIMITS: Результат проверки hasAvailableRequests: $hasAvailableRequests");

    if (hasAvailableRequests) {
      print("✅ LIMITS: Проверка лимитов пройдена, действие разрешено");
      return true;
    }

    // Показываем Snackbar с сообщением о лимите, с учетом типа подписки пользователя
    if (!suppressFailureSnack && context.mounted) {
      print(
          "⚠️ LIMITS: Показываем сообщение о лимите для действия: $actionName");

      if (hasPaidSubscription) {
        // Для платных пользователей - более вежливое и короткое сообщение без кнопки подписки
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('paid_user_daily_limit'),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        // Для бесплатных пользователей - сообщение с кнопкой подписки
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('free_user_daily_limit'),
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: context.tr('subscription'),
              textColor: Colors.white,
              onPressed: () {
                final subscriptionService =
                    ref.read(subscriptionServiceProvider);
                subscriptionService.showPaywall(context);
              },
            ),
          ),
        );

        // Новое поведение: когда бесплатные распознавания закончились —
        // показываем сообщение и автоматически открываем пэйвол через пару секунд
        // (не мешает действию кнопки Snackbar)
        Future.delayed(const Duration(seconds: 2), () {
          if (!context.mounted) return;
          final subscriptionService = ref.read(subscriptionServiceProvider);
          subscriptionService.showPaywall(context);
        });
      }
    }

    print("❌ LIMITS: Проверка лимитов не пройдена, действие запрещено");
    return false;
  }

  /// Проверяет и регистрирует использование лимита
  static Future<(bool isSuccess, int remainingUsages)> registerUsage(
    BuildContext context,
    WidgetRef ref, {
    bool showRemainingUsagesWarning = true,
  }) async {
    print("📝 LIMITS: Начинаем регистрацию использования");

    final subscription = ref.read(subscriptionServiceProvider);
    final remainingBefore = await subscription.getRemainingRequests();
    final hasPaidSubscription = await subscription.hasPaidSubscription();

    print(
        "📊 LIMITS: Статус до регистрации: осталось=$remainingBefore, платная=$hasPaidSubscription");

    final success = await subscription.useRequest();
    final remainingAfter = await subscription.getRemainingRequests();

    print(
        "✅ LIMITS: Использование зарегистрировано, осталось запросов: $remainingAfter, платная: $hasPaidSubscription");

    // Показываем предупреждение, когда осталось мало запросов
    if (context.mounted) {
      print(
          "🔔 LIMITS: Проверка необходимости показа предупреждения: осталось=$remainingAfter");

      if (showRemainingUsagesWarning &&
          remainingAfter <= 2 &&
          !hasPaidSubscription) {
        print(
            "🔔 LIMITS: Показываем предупреждение о количестве оставшихся запросов ($remainingAfter)");
        await subscription.showRemainingRequestsWarning(context);
      }
    }

    return (success, remainingAfter);
  }

  /// Показывает предупреждение о превышении лимита
  static Future<void> showLimitExceededSnackbar(
    BuildContext context,
  ) async {
    print("🔔 LIMITS: Показываем снэкбар о превышении лимита");

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('free_user_daily_limit'),
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

/// Результат проверки лимитов использования
class UsageLimitResult {
  /// Успешно ли зарегистрировано использование
  final bool isSuccess;

  /// Оставшееся количество использований
  final int remainingUsages;

  /// Превышен ли лимит использований
  final bool limitExceeded;

  /// Есть ли у пользователя платная подписка
  final bool hasPaidSubscription;

  /// Текст ошибки (если есть)
  final String? error;

  UsageLimitResult({
    required this.isSuccess,
    required this.remainingUsages,
    required this.limitExceeded,
    required this.hasPaidSubscription,
    this.error,
  });
}
