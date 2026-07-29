import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../data/subscription_repository.dart';
import '../models/subscription_model.dart';
import '../features/subscription/purchase_routes.dart';
import '../services/localization/app_localization_service.dart';

/// Сервис для работы с подписками
class SubscriptionService {
  final SubscriptionRepository _repository;

  /// Конструктор, принимающий репозиторий подписок
  SubscriptionService(this._repository);

  /// Получает текущую активную подписку
  Future<SubscriptionModel?> getCurrentSubscription() async {
    return await _repository.getCurrentSubscription();
  }

  /// Проверяет, активна ли подписка
  Future<bool> hasActiveSubscription() async {
    final subscription = await getCurrentSubscription();
    if (subscription == null) return false;
    return subscription.isActive;
  }

  /// Проверяет, активна ли подписка определенного типа
  Future<bool> hasActiveSubscriptionType(SubscriptionType type) async {
    final subscription = await getCurrentSubscription();
    if (subscription == null) return false;
    return subscription.isActive && subscription.type == type;
  }

  /// Активирует подписку
  Future<bool> activateSubscription(SubscriptionModel subscription) async {
    try {
      await _repository.saveSubscription(subscription);
      debugPrint('💰 SUBSCRIPTION: Подписка активирована: $subscription');
      return true;
    } catch (e) {
      debugPrint('❌ SUBSCRIPTION: Ошибка при активации подписки: $e');
      return false;
    }
  }

  /// Деактивирует подписку
  Future<bool> deactivateSubscription() async {
    try {
      final subscription = await getCurrentSubscription();
      if (subscription == null) return true; // Нет подписки для деактивации

      // Создаем копию с установленным признаком деактивации
      final deactivated = subscription.copyWith(
        endDate: DateTime.now(),
      );

      await _repository.saveSubscription(deactivated);
      debugPrint('💰 SUBSCRIPTION: Подписка деактивирована');
      return true;
    } catch (e) {
      debugPrint('❌ SUBSCRIPTION: Ошибка при деактивации подписки: $e');
      return false;
    }
  }

  /// Продлевает подписку
  Future<bool> extendSubscription(
      SubscriptionType type, int durationDays) async {
    try {
      final currentSubscription = await getCurrentSubscription();
      final DateTime now = DateTime.now();
      DateTime startDate;
      DateTime endDate;

      if (currentSubscription != null && currentSubscription.isActive) {
        // Если есть активная подписка, продлеваем ее
        startDate = currentSubscription.endDate!;
        endDate = startDate.add(Duration(days: durationDays));
      } else {
        // Если нет активной подписки, создаем новую
        startDate = now;
        endDate = now.add(Duration(days: durationDays));
      }

      final subscription = SubscriptionModel(
        type: type,
        startDate: startDate,
        endDate: endDate,
        availableRequests:
            currentSubscription?.maxRequests ?? getDefaultMaxRequests(type),
        maxRequests: getDefaultMaxRequests(type),
      );

      await _repository.saveSubscription(subscription);
      debugPrint(
          '💰 SUBSCRIPTION: Подписка продлена до ${endDate.toIso8601String()}');
      return true;
    } catch (e) {
      debugPrint('❌ SUBSCRIPTION: Ошибка при продлении подписки: $e');
      return false;
    }
  }

  /// Конвертирует тип подписки в количество дней
  int getSubscriptionDurationInDays(SubscriptionType type) {
    switch (type) {
      case SubscriptionType.weekly:
        return 7;
      case SubscriptionType.monthly:
        return 30;
      case SubscriptionType.yearly:
        return 365;
      default:
        return 0;
    }
  }

  /// Проверка, имеет ли пользователь активную платную подписку
  Future<bool> hasPaidSubscription() async {
    final subscription = await getCurrentSubscription();
    final isPaid = subscription?.isActive == true &&
        subscription?.type != SubscriptionType.free;
    debugPrint(
        "💰 SUBSCRIPTION: hasPaidSubscription: $isPaid, тип: ${subscription?.type}");
    return isPaid;
  }

  /// Проверка, имеет ли пользователь доступные запросы
  Future<bool> hasAvailableRequests() async {
    final subscription = await getCurrentSubscription();
    final availableRequests = subscription?.availableRequests ?? 0;
    final hasRequests = availableRequests > 0;

    debugPrint(
        "🔢 SUBSCRIPTION: hasAvailableRequests: $hasRequests (осталось: $availableRequests/${subscription?.maxRequests}), тип подписки: ${subscription?.type}");

    return hasRequests;
  }

  /// Использование одного запроса
  Future<bool> useRequest() async {
    try {
      final currentSubscription = await getCurrentSubscription();
      if (currentSubscription == null) return false;

      debugPrint(
          "📝 SUBSCRIPTION: useRequest: Начало. Текущая подписка: тип=${currentSubscription.type}, осталось=${currentSubscription.availableRequests}/${currentSubscription.maxRequests}");

      // Если нет доступных запросов, возвращаем false
      if (currentSubscription.availableRequests <= 0) {
        debugPrint(
            "❌ SUBSCRIPTION: Не удалось использовать запрос: лимит исчерпан");
        return false;
      }

      // Уменьшаем счетчик запросов
      await _repository.useRequest();

      // Логируем оставшиеся запросы после уменьшения счетчика
      final updatedSubscription = await getCurrentSubscription();
      debugPrint(
          "✅ SUBSCRIPTION: Запрос использован. Было: ${currentSubscription.availableRequests}, осталось: ${updatedSubscription?.availableRequests}/${updatedSubscription?.maxRequests}");

      return true;
    } catch (e) {
      debugPrint("❌ SUBSCRIPTION: Ошибка при использовании запроса: $e");
      return false;
    }
  }

  /// Получение количества оставшихся запросов
  Future<int> getRemainingRequests() async {
    final subscription = await getCurrentSubscription();
    debugPrint(
        "🔢 SUBSCRIPTION: getRemainingRequests: ${subscription?.availableRequests}/${subscription?.maxRequests}, тип: ${subscription?.type}");
    return subscription?.availableRequests ?? 0;
  }

  /// Получение максимального количества запросов
  Future<int> getMaxRequests() async {
    final subscription = await getCurrentSubscription();
    return subscription?.maxRequests ?? 0;
  }

  /// Получение сообщения о состоянии лимита для пользователя
  Future<String> getUsageLimitMessage(BuildContext context) async {
    final subscription = await getCurrentSubscription();
    final bool isPaid = subscription?.type != SubscriptionType.free;

    String message = "";
    if (subscription?.availableRequests != null &&
        subscription!.availableRequests <= 0) {
      message = isPaid
          ? context.tr('daily_limit_reached')
          : context.tr('free_limit_reached');
    } else {
      message = context.trParams('remaining_usages_count',
          [subscription?.availableRequests.toString() ?? "0"]);
    }

    debugPrint(
        "📊 SUBSCRIPTION: getUsageLimitMessage: \"$message\", осталось: ${subscription?.availableRequests}/${subscription?.maxRequests}, тип: ${subscription?.type}");

    return message;
  }

  /// Получение сообщения о достижении дневного лимита
  Future<String> getDailyLimitMessage(BuildContext context) async {
    final subscription = await getCurrentSubscription();
    final bool isPaid = subscription?.type != SubscriptionType.free;

    String message = "";
    if (isPaid) {
      String key;
      switch (subscription?.type) {
        case SubscriptionType.monthly:
          key = 'monthly_limit_reached';
          break;
        case SubscriptionType.yearly:
          key = 'yearly_limit_reached';
          break;
        default:
          key = 'paid_limit_reached';
          break;
      }
      message =
          context.trParams(key, [subscription?.maxRequests.toString() ?? "0"]);
    } else {
      message = context.tr('free_limit_reached_try_tomorrow');
    }

    debugPrint(
        "⚠️ SUBSCRIPTION: getDailyLimitMessage: \"$message\", тип: ${subscription?.type}");

    return message;
  }

  /// Возвращает правильную форму слова "использование"
  String _getUsagesString(int count) {
    // Этот метод уже не используется в текущей версии кода,
    // поскольку для форм слов теперь используются ключи локализации
    return '';
  }

  /// Показать экран подписки
  void showPaywall(BuildContext context) {
    debugPrint("💲 SUBSCRIPTION: showPaywall: Показываем экран подписки");
    Navigator.of(context).push(paywallRoute());
  }

  /// Показать экран подписки, если нет запросов или подписки
  Future<bool> showPaywallIfNeeded(BuildContext context) async {
    // Проверяем наличие запросов
    final hasRequests = await hasAvailableRequests();

    debugPrint(
        "🔍 SUBSCRIPTION: showPaywallIfNeeded: hasRequests=$hasRequests");

    // Если запросы есть, разрешаем продолжить
    if (hasRequests) {
      return true;
    }

    // Проверяем наличие платной подписки
    final hasPaid = await hasPaidSubscription();

    // Если есть платная подписка, разрешаем продолжить
    if (hasPaid) {
      debugPrint(
          "✅ SUBSCRIPTION: Найдена активная платная подписка в локальном хранилище");
      return true;
    }

    // Если запросов нет и платной подписки нет, показываем Paywall
    debugPrint(
        "🛒 SUBSCRIPTION: Показываем экран подписки (нет запросов и нет платной подписки)");
    showPaywall(context);
    return false;
  }

  /// Показать предупреждение о количестве оставшихся запросов
  Future<void> showRemainingRequestsWarning(BuildContext context) async {
    // Получаем количество оставшихся запросов
    final remainingRequests = await getRemainingRequests();

    // Проверка для всех типов пользователей
    if (remainingRequests <= 2) {
      debugPrint(
          "⚠️ SUBSCRIPTION: showRemainingRequestsWarning: Показываем предупреждение (осталось: $remainingRequests)");

      // Показываем SnackBar с предупреждением
      if (remainingRequests > 0) {
        String message = context.trParams(
            'remaining_usages_warning', [remainingRequests.toString()]);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ));
      } else {
        // Если запросов не осталось, показываем другое сообщение
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            context.tr('no_usages_left'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  /// Получение правильного склонения слова "запрос"
  String _getRequestsString(int count) {
    // Этот метод уже не используется в текущей версии кода,
    // поскольку для форм слов теперь используются ключи локализации
    return '';
  }

  /// Получает значение по умолчанию для максимального количества запросов для типа подписки
  int getDefaultMaxRequests(SubscriptionType type) {
    switch (type) {
      case SubscriptionType.free:
        return 2; // Для бесплатных пользователей - 2 запроса
      case SubscriptionType.weekly:
      case SubscriptionType.monthly:
      case SubscriptionType.yearly:
        return 10; // Для всех платных пользователей - 10 запросов
      default:
        return 2; // По умолчанию - бесплатный лимит
    }
  }
}
