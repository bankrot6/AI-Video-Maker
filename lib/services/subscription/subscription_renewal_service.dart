import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'subscription_storage_service.dart';
import 'subscription_validation_service.dart';
import '../../models/subscription_model.dart';
import '../notification/local_notification_service.dart';
import '../notification/notification_service_interface.dart';

/// Сервис для управления напоминаниями о продлении подписки
class SubscriptionRenewalService {
  // Синглтон
  static final SubscriptionRenewalService _instance =
      SubscriptionRenewalService._internal();
  factory SubscriptionRenewalService() => _instance;
  SubscriptionRenewalService._internal();

  // Ключи для хранения в SharedPreferences
  static const String _lastPlanKey = 'last_subscription_plan';
  static const String _reminderEnabledKey = 'renewal_reminders_enabled';
  static const String _reminderScheduledKey = 'renewal_reminder_scheduled';

  // Идентификатор для уведомления о продлении
  static const int _renewalNotificationId = 10001;

  // Сервисы
  final SubscriptionStorageService _storageService =
      SubscriptionStorageService();
  final SubscriptionValidationService _validationService =
      SubscriptionValidationService();
  final LocalNotificationService _notificationService =
      LocalNotificationService();

  // Количество дней до окончания подписки, когда должно быть отправлено уведомление
  static const List<int> _reminderDays = [7, 3, 1];

  /// Инициализация сервиса
  Future<void> initialize() async {
    try {
      await _notificationService.initialize();
      await _scheduleRenewalCheckIfNeeded();
      debugPrint(
          '✅ RENEWAL: Сервис напоминаний о продлении подписки инициализирован');
    } catch (e) {
      debugPrint('🔴 RENEWAL: Ошибка инициализации сервиса напоминаний: $e');
    }
  }

  /// Проверяет и при необходимости планирует напоминания
  Future<void> _scheduleRenewalCheckIfNeeded() async {
    // Проверяем, включены ли напоминания
    final bool enabled = await isReminderEnabled();
    if (!enabled) {
      debugPrint('ℹ️ RENEWAL: Напоминания о продлении отключены пользователем');
      return;
    }

    // Проверяем активность подписки
    final bool isActive = await _validationService.isSubscriptionActive();
    if (!isActive) {
      debugPrint('ℹ️ RENEWAL: Нет активной подписки для напоминаний');
      return;
    }

    // Получаем информацию о подписке
    final subscriptionInfo = await _storageService.getSubscription();
    if (subscriptionInfo == null) {
      debugPrint('⚠️ RENEWAL: Не найдена информация о подписке');
      return;
    }

    // Пропускаем бесплатные и пожизненные подписки
    if (subscriptionInfo.type == SubscriptionType.free ||
        subscriptionInfo.type == SubscriptionType.lifetime) {
      debugPrint('ℹ️ RENEWAL: Тип подписки не требует продления');
      return;
    }

    // Планируем уведомления
    await _scheduleRenewalReminders(subscriptionInfo);
  }

  /// Планирует уведомления о продлении на заданные дни до окончания срока
  Future<void> _scheduleRenewalReminders(SubscriptionInfo subscription) async {
    try {
      // Получаем дату окончания подписки
      final DateTime endDate = subscription.endDate;
      final DateTime now = DateTime.now();

      // Проверяем, не истекла ли уже подписка
      if (endDate.isBefore(now)) {
        debugPrint(
            'ℹ️ RENEWAL: Подписка уже истекла, напоминания не требуются');
        return;
      }

      // Сохраняем тип подписки как последний использованный
      await saveLastSubscriptionType(subscription.type);

      // Отменяем любые предыдущие запланированные напоминания
      await _notificationService.cancelAllNotifications();

      // Планируем напоминания на разные дни до окончания подписки
      bool hasScheduled = false;

      for (int days in _reminderDays) {
        // Вычисляем дату для напоминания
        final DateTime reminderDate = endDate.subtract(Duration(days: days));

        // Если дата напоминания уже в прошлом, пропускаем
        if (reminderDate.isBefore(now)) {
          continue;
        }

        // Формируем тексты уведомления
        String title, body;
        switch (subscription.type) {
          case SubscriptionType.weekly:
            title = 'Продлите недельную подписку';
            body =
                'Ваша недельная подписка истекает через $days ${_getDaysWordForm(days)}. Продлите подписку, чтобы сохранить доступ.';
            break;
          case SubscriptionType.monthly:
            title = 'Продлите месячную подписку';
            body =
                'Ваша месячная подписка истекает через $days ${_getDaysWordForm(days)}. Продлите подписку, чтобы сохранить доступ.';
            break;
          case SubscriptionType.yearly:
            title = 'Продлите годовую подписку';
            body =
                'Ваша годовая подписка истекает через $days ${_getDaysWordForm(days)}. Продлите подписку, чтобы сохранить доступ.';
            break;
          case SubscriptionType.trial:
            title = 'Пробный период заканчивается';
            body =
                'Ваш пробный период заканчивается через $days ${_getDaysWordForm(days)}. Оформите подписку, чтобы сохранить доступ.';
            break;
          default:
            continue;
        }

        // Планируем уведомление
        await _notificationService.scheduleNotification(
          id: _renewalNotificationId + days,
          title: title,
          body: body,
          scheduledDate: reminderDate,
          payload: 'renewal_reminder',
          type: NotificationType.reminder,
        );

        hasScheduled = true;
        debugPrint(
            '✅ RENEWAL: Запланировано напоминание о продлении на $reminderDate (за $days дней)');
      }

      // Отмечаем, что напоминания запланированы
      if (hasScheduled) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_reminderScheduledKey, true);
      }
    } catch (e) {
      debugPrint('🔴 RENEWAL: Ошибка при планировании напоминаний: $e');
    }
  }

  /// Возвращает правильную форму слова "день" в зависимости от числа
  String _getDaysWordForm(int days) {
    if (days % 10 == 1 && days % 100 != 11) {
      return 'день';
    } else if ((days % 10 >= 2 && days % 10 <= 4) &&
        (days % 100 < 10 || days % 100 >= 20)) {
      return 'дня';
    } else {
      return 'дней';
    }
  }

  /// Сохраняет тип последней подписки пользователя для быстрого возобновления
  Future<void> saveLastSubscriptionType(SubscriptionType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastPlanKey, type.index);
      debugPrint('💾 RENEWAL: Сохранен последний план подписки: $type');
    } catch (e) {
      debugPrint('🔴 RENEWAL: Ошибка сохранения типа подписки: $e');
    }
  }

  /// Получает тип последней подписки пользователя
  Future<SubscriptionType?> getLastSubscriptionType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final typeIndex = prefs.getInt(_lastPlanKey);

      if (typeIndex == null) {
        return null;
      }

      // Проверяем, что индекс находится в пределах перечисления
      if (typeIndex >= 0 && typeIndex < SubscriptionType.values.length) {
        return SubscriptionType.values[typeIndex];
      }

      return null;
    } catch (e) {
      debugPrint('🔴 RENEWAL: Ошибка получения типа подписки: $e');
      return null;
    }
  }

  /// Включает или отключает напоминания о продлении
  Future<void> setReminderEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_reminderEnabledKey, enabled);

      if (enabled) {
        // Если включаем напоминания, планируем их сразу
        await _scheduleRenewalCheckIfNeeded();
        debugPrint(
            '✅ RENEWAL: Напоминания о продлении включены и запланированы');
      } else {
        // Если отключаем, отменяем все запланированные напоминания
        await _notificationService.cancelAllNotifications();
        debugPrint('ℹ️ RENEWAL: Напоминания о продлении отключены');
      }
    } catch (e) {
      debugPrint('🔴 RENEWAL: Ошибка при изменении статуса напоминаний: $e');
    }
  }

  /// Проверяет, включены ли напоминания о продлении
  Future<bool> isReminderEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // По умолчанию напоминания включены
      return prefs.getBool(_reminderEnabledKey) ?? true;
    } catch (e) {
      debugPrint('🔴 RENEWAL: Ошибка при проверке статуса напоминаний: $e');
      return true;
    }
  }

  /// Проверяет, запланированы ли уже напоминания
  Future<bool> areRemindersScheduled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_reminderScheduledKey) ?? false;
    } catch (e) {
      debugPrint(
          '🔴 RENEWAL: Ошибка при проверке запланированных напоминаний: $e');
      return false;
    }
  }

  /// Обновляет напоминания при изменении подписки
  Future<void> updateRemindersAfterSubscriptionChange() async {
    try {
      final enabled = await isReminderEnabled();
      if (!enabled) {
        return;
      }

      await _scheduleRenewalCheckIfNeeded();
      debugPrint('✅ RENEWAL: Напоминания обновлены после изменения подписки');
    } catch (e) {
      debugPrint('🔴 RENEWAL: Ошибка при обновлении напоминаний: $e');
    }
  }
}
