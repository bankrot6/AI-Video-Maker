import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/subscription_model.dart';

/// Сервис для хранения информации о подписке на устройстве
class SubscriptionStorageService {
  // Синглтон
  static final SubscriptionStorageService _instance =
      SubscriptionStorageService._internal();
  factory SubscriptionStorageService() => _instance;
  SubscriptionStorageService._internal();

  // Ключи для хранения в SharedPreferences
  static const String _subscriptionKey = 'subscription_data';
  static const String _yookassaPaymentKey = 'yookassa_payment_id';

  /// Сохранение информации о подписке
  Future<void> saveSubscription({
    required SubscriptionType type,
    required DateTime startDate,
    required DateTime endDate,
    required String paymentId,
    bool isYookassa = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Формируем данные подписки
      final Map<String, dynamic> subscriptionData = {
        'type': type.toString(),
        'startDate': startDate.millisecondsSinceEpoch,
        'endDate': endDate.millisecondsSinceEpoch,
        'paymentId': paymentId,
        'isYookassa': isYookassa,
      };

      // Сохраняем данные в SharedPreferences
      await prefs.setString(_subscriptionKey, jsonEncode(subscriptionData));

      // Если это платеж через ЮKassa, сохраняем его ID отдельно
      if (isYookassa) {
        await prefs.setString(_yookassaPaymentKey, paymentId);
      }

      debugPrint(
          '💾 SUBSCRIPTION: Подписка сохранена: $type, до ${endDate.toIso8601String()}');
    } catch (e) {
      debugPrint('🔴 SUBSCRIPTION: Ошибка сохранения подписки: $e');
    }
  }

  /// Получение информации о текущей подписке
  Future<SubscriptionInfo?> getSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? subscriptionData = prefs.getString(_subscriptionKey);

      if (subscriptionData == null) {
        return null;
      }

      final Map<String, dynamic> data = jsonDecode(subscriptionData);

      return SubscriptionInfo(
        type: _subscriptionTypeFromString(data['type']),
        startDate: DateTime.fromMillisecondsSinceEpoch(data['startDate']),
        endDate: DateTime.fromMillisecondsSinceEpoch(data['endDate']),
        paymentId: data['paymentId'],
        isYookassa: data['isYookassa'] ?? false,
      );
    } catch (e) {
      debugPrint('🔴 SUBSCRIPTION: Ошибка получения подписки: $e');
      return null;
    }
  }

  /// Проверка активности подписки
  Future<bool> isSubscriptionActive() async {
    final subscription = await getSubscription();

    if (subscription == null) {
      return false;
    }

    final now = DateTime.now();
    return now.isBefore(subscription.endDate);
  }

  /// Проверка типа активной подписки
  Future<SubscriptionType?> getActiveSubscriptionType() async {
    final isActive = await isSubscriptionActive();

    if (!isActive) {
      return null;
    }

    final subscription = await getSubscription();
    return subscription?.type;
  }

  /// Получение ID платежа ЮKassa
  Future<String?> getYookassaPaymentId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_yookassaPaymentKey);
    } catch (e) {
      debugPrint('🔴 SUBSCRIPTION: Ошибка получения ID платежа ЮKassa: $e');
      return null;
    }
  }

  /// Очистка информации о подписке (для отладки)
  Future<void> clearSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_subscriptionKey);
      await prefs.remove(_yookassaPaymentKey);
      debugPrint('🗑️ SUBSCRIPTION: Информация о подписке очищена');
    } catch (e) {
      debugPrint('🔴 SUBSCRIPTION: Ошибка очистки подписки: $e');
    }
  }

  /// Преобразование строки в тип подписки
  SubscriptionType _subscriptionTypeFromString(String typeStr) {
    switch (typeStr) {
      case 'SubscriptionType.weekly':
        return SubscriptionType.weekly;
      case 'SubscriptionType.monthly':
        return SubscriptionType.monthly;
      case 'SubscriptionType.yearly':
        return SubscriptionType.yearly;
      default:
        return SubscriptionType.free;
    }
  }
}

/// Класс для хранения информации о подписке
class SubscriptionInfo {
  final SubscriptionType type;
  final DateTime startDate;
  final DateTime endDate;
  final String paymentId;
  final bool isYookassa;

  SubscriptionInfo({
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.paymentId,
    this.isYookassa = false,
  });
}
