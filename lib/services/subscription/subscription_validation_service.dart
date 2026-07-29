import 'package:flutter/foundation.dart';
import '../../models/subscription_model.dart';
import 'subscription_storage_service.dart';

/// Сервис для валидации подписки
class SubscriptionValidationService {
  // Синглтон
  static final SubscriptionValidationService _instance =
      SubscriptionValidationService._internal();
  factory SubscriptionValidationService() => _instance;
  SubscriptionValidationService._internal();

  // Сервис хранения подписок
  final SubscriptionStorageService _storageService =
      SubscriptionStorageService();

  /// Проверка активности подписки
  Future<bool> isSubscriptionActive() async {
    try {
      // Проверяем активность подписки через сервис хранения
      final isActive = await _storageService.isSubscriptionActive();

      if (isActive) {
        // Получаем данные подписки для логирования
        final subscription = await _storageService.getSubscription();
        debugPrint(
            '✅ SUBSCRIPTION_VALIDATION: Активная подписка найдена: ${subscription?.type}');
        debugPrint(
            '📅 SUBSCRIPTION_VALIDATION: Действует до: ${subscription?.endDate.toIso8601String()}');
      } else {
        debugPrint('ℹ️ SUBSCRIPTION_VALIDATION: Активная подписка не найдена');
      }

      return isActive;
    } catch (e) {
      debugPrint('🔴 SUBSCRIPTION_VALIDATION: Ошибка проверки подписки: $e');
      return false;
    }
  }

  /// Получение типа активной подписки
  Future<SubscriptionType> getActiveSubscriptionType() async {
    try {
      // Проверяем активность подписки
      final isActive = await _storageService.isSubscriptionActive();

      if (!isActive) {
        debugPrint(
            'ℹ️ SUBSCRIPTION_VALIDATION: Активная подписка не найдена, возвращаем Free');
        return SubscriptionType.free;
      }

      // Получаем тип активной подписки
      final type = await _storageService.getActiveSubscriptionType();

      if (type == null) {
        debugPrint(
            'ℹ️ SUBSCRIPTION_VALIDATION: Тип подписки не определен, возвращаем Free');
        return SubscriptionType.free;
      }

      debugPrint('✅ SUBSCRIPTION_VALIDATION: Тип активной подписки: $type');
      return type;
    } catch (e) {
      debugPrint(
          '🔴 SUBSCRIPTION_VALIDATION: Ошибка получения типа подписки: $e');
      return SubscriptionType.free;
    }
  }

  /// Получение лимита запросов для текущей подписки
  Future<int> getRequestLimit() async {
    try {
      final type = await getActiveSubscriptionType();

      switch (type) {
        case SubscriptionType.free:
          return 3; // Бесплатный лимит
        case SubscriptionType.trial:
          return 10; // Лимит для пробной версии
        case SubscriptionType.weekly:
        case SubscriptionType.monthly:
        case SubscriptionType.yearly:
        case SubscriptionType.lifetime:
          return 10; // Для всех платных пользователей - 10 запросов
        default:
          return 3; // По умолчанию - бесплатный лимит
      }
    } catch (e) {
      debugPrint(
          '🔴 SUBSCRIPTION_VALIDATION: Ошибка получения лимита запросов: $e');
      return 3; // По умолчанию - бесплатный лимит
    }
  }

  /// Получение информации о подписке для отображения пользователю
  Future<SubscriptionInfo?> getSubscriptionInfo() async {
    try {
      return await _storageService.getSubscription();
    } catch (e) {
      debugPrint(
          '🔴 SUBSCRIPTION_VALIDATION: Ошибка получения информации о подписке: $e');
      return null;
    }
  }

  /// Получение количества дней до окончания подписки
  Future<int> getDaysLeft() async {
    try {
      final subscription = await _storageService.getSubscription();

      if (subscription == null) {
        return 0;
      }

      final now = DateTime.now();
      final difference = subscription.endDate.difference(now).inDays;

      return difference > 0 ? difference : 0;
    } catch (e) {
      debugPrint(
          '🔴 SUBSCRIPTION_VALIDATION: Ошибка получения оставшихся дней: $e');
      return 0;
    }
  }
}
