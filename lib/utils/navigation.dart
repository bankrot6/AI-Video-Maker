import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/subscription/purchase_routes.dart';
import '../features/subscription/subscription_providers.dart';

/// Навигационные маршруты приложения
class AppNavigation {
  /// Показать экран Paywall
  static Future<bool?> showPaywall(BuildContext context) async {
    return await Navigator.of(context).push<bool>(paywallRoute<bool>());
  }

  /// Открыть экран Paywall, если у пользователя закончились доступные запросы
  /// или требуется покупка подписки для выполнения определенного действия
  static Future<bool> showPaywallIfNeeded(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final subscriptionService = ref.read(subscriptionServiceProvider);
    return await subscriptionService.showPaywallIfNeeded(context);
  }

  /// Показать предупреждение о количестве оставшихся запросов
  static Future<void> showRemainingRequestsWarning(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final subscription =
        await ref.read(subscriptionRepositoryProvider).getCurrentSubscription();
    final subscriptionService = ref.read(subscriptionServiceProvider);

    // Показываем предупреждение только когда осталось ровно 1 использование
    if (subscription.availableRequests == 1 && context.mounted) {
      await subscriptionService.showRemainingRequestsWarning(context);
    }
  }
}

/// Расширение для более удобного доступа к навигационным методам
extension NavigationExtension on BuildContext {
  /// Показать экран Paywall
  Future<bool?> showPaywall() => AppNavigation.showPaywall(this);

  /// Показать экран Paywall, если необходимо
  Future<bool> showPaywallIfNeeded(WidgetRef ref) =>
      AppNavigation.showPaywallIfNeeded(this, ref);

  /// Показать предупреждение о количестве оставшихся запросов
  Future<void> showRemainingRequestsWarning(WidgetRef ref) =>
      AppNavigation.showRemainingRequestsWarning(this, ref);
}
