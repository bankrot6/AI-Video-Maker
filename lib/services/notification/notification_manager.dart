import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/notification_model.dart';
import 'local_notification_service.dart';
import 'notification_service_interface.dart';
import '../../main.dart'; // Импортируем для использования appLog и localizeMessage
import '../../utils/app_logger.dart'; // Импортируем LogLevel
import '../../utils/deep_link_handler.dart'; // Для appNavigatorKey навигации из уведомлений

class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();
  factory NotificationManager() => _instance;
  NotificationManager._internal();

  final NotificationServiceInterface _notificationService =
      LocalNotificationService();

  static const String _notificationsKey = 'notifications';

  List<NotificationModel> _notifications = [];

  bool _isInitialized = false;

  final _notificationReceivedController =
      StreamController<NotificationModel>.broadcast();
  final _notificationTappedController =
      StreamController<NotificationModel>.broadcast();

  final Set<String> _suppressedMessengerIds = {};
  final Set<String> _sentMessengerIds = {};
  static const int _maxSentCacheSize = 200;

  String? _activeChatContactId;

  String? get activeChatContactId => _activeChatContactId;

  set activeChatContactId(String? value) {
    _activeChatContactId = value;
  }

  Stream<NotificationModel> get onNotificationReceived =>
      _notificationReceivedController.stream;
  Stream<NotificationModel> get onNotificationTapped =>
      _notificationTappedController.stream;

  /// Инициализирует менеджер уведомлений
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Инициализация сервиса уведомлений
    await _notificationService.initialize();

    // Загрузка сохраненных уведомлений
    await _loadNotifications();

    _notificationService.setOnNotificationReceived(_handleNotificationReceived);
    _notificationService.setOnNotificationTapped(_handleNotificationTapped);

    await _processPendingNotifications();

    _isInitialized = true;

    final pendingPayload = LocalNotificationService.pendingTapPayload;
    if (pendingPayload != null) {
      LocalNotificationService.pendingTapPayload = null;
      _handleNotificationTapped(pendingPayload);
    }

    appLog(localizeMessage('notification_manager_initialized'),
        tag: 'FLUTTER', level: LogLevel.debug);
  }

  /// Запрашивает разрешения на отправку уведомлений
  Future<bool> requestPermissions() async {
    if (!_isInitialized) {
      await initialize();
    }

    return await _notificationService.requestPermissions();
  }

  /// Проверяет, включены ли уведомления
  Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized) {
      await initialize();
    }

    return await _notificationService.areNotificationsEnabled();
  }

  /// Отправляет уведомление немедленно
  ///
  /// Создает новое уведомление и отправляет его пользователю немедленно.
  /// Возвращает созданное уведомление.
  Future<NotificationModel> sendNotification({
    required String title,
    required String body,
    NotificationType type = NotificationType.info,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Создание модели уведомления
    final notification = NotificationModel.create(
      title: title,
      body: body,
      type: type,
      payload: payload,
    );

    // Отправка уведомления через сервис
    await _notificationService.showLocalNotification(
      id: notification.numericId,
      title: notification.title,
      body: notification.body,
      payload: notification.id, // Используем ID как payload для идентификации
      type: notification.type,
    );

    // Сохранение уведомления в списке как отправленное
    final sentNotification = notification.markAsSent();
    await _saveNotification(sentNotification);

    return sentNotification;
  }

  /// Планирует отправку уведомления
  ///
  /// Создает новое уведомление и планирует его отправку на указанное время.
  /// Возвращает созданное уведомление.
  Future<NotificationModel> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledDate,
    NotificationType type = NotificationType.reminder,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Проверка, что дата в будущем
    if (scheduledDate.isBefore(DateTime.now())) {
      throw ArgumentError('Дата отправки должна быть в будущем');
    }

    // Создание модели уведомления
    final notification = NotificationModel.create(
      title: title,
      body: body,
      type: type,
      payload: payload,
      scheduledAt: scheduledDate,
    );

    // Проверяем, нет ли уже уведомления с таким же numericId
    final existingIndex =
        _notifications.indexWhere((n) => n.numericId == notification.numericId);
    if (existingIndex != -1) {
      // Отменяем существующее уведомление
      await _notificationService.cancelNotification(notification.numericId);
      _notifications.removeAt(existingIndex);
      debugPrint(
          'Отменено дублирующееся уведомление с ID: ${notification.numericId}');
    }

    // Планирование уведомления через сервис
    await _notificationService.scheduleNotification(
      id: notification.numericId,
      title: notification.title,
      body: notification.body,
      scheduledDate: scheduledDate,
      payload: notification.id, // Используем ID как payload для идентификации
      type: notification.type,
    );

    // Сохранение уведомления в списке
    await _saveNotification(notification);

    return notification;
  }

  /// Настраивает повторяющееся уведомление
  ///
  /// Создает новое уведомление, которое будет отправляться с указанным интервалом.
  /// Возвращает созданное уведомление.
  Future<NotificationModel> scheduleRepeatingNotification({
    required String title,
    required String body,
    required Duration interval,
    NotificationType type = NotificationType.reminder,
    String? payload,
    DateTime? initialDateTime,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Создание модели уведомления
    final notification = NotificationModel.create(
      title: title,
      body: body,
      type: type,
      payload: payload,
    );

    // Проверяем, нет ли уже уведомления с таким же numericId
    final existingIndex =
        _notifications.indexWhere((n) => n.numericId == notification.numericId);
    if (existingIndex != -1) {
      // Отменяем существующее уведомление
      await _notificationService.cancelNotification(notification.numericId);
      _notifications.removeAt(existingIndex);
      debugPrint(
          'Отменено дублирующееся повторяющееся уведомление с ID: ${notification.numericId}');
    }

    // Настройка периодического уведомления через сервис
    await _notificationService.periodicallyShowNotification(
      id: notification.numericId,
      title: notification.title,
      body: notification.body,
      interval: interval,
      payload: notification.id, // Используем ID как payload для идентификации
      type: notification.type,
      initialDateTime: initialDateTime,
    );

    // Сохранение уведомления в списке
    await _saveNotification(notification);

    return notification;
  }

  Future<void> cancelNotification(String id) async {
    if (!_isInitialized) {
      await initialize();
    }

    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;

    final notification = _notifications[index];
    await _notificationService.cancelNotification(notification.numericId);
    _notifications.removeAt(index);
    await _saveNotifications();
  }

  Future<void> cancelNotificationByNumericId(int numericId) async {
    if (!_isInitialized) {
      await initialize();
    }

    await _notificationService.cancelNotification(numericId);
    final index = _notifications.indexWhere((n) => n.numericId == numericId);
    if (index != -1) {
      _notifications.removeAt(index);
      await _saveNotifications();
    }
  }

  /// Отменяет все уведомления
  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Отмена всех уведомлений через сервис
    await _notificationService.cancelAllNotifications();

    // Очистка списка уведомлений
    _notifications.clear();
    await _saveNotifications();

    appLog(localizeMessage('all_notifications_cancelled'),
        tag: 'FLUTTER', level: LogLevel.debug);
  }

  void suppressMessengerNotification(String messageId) {
    _suppressedMessengerIds.add(messageId);
    _sentMessengerIds.add(messageId);
    Future.delayed(const Duration(minutes: 10), () {
      _suppressedMessengerIds.remove(messageId);
    });
    _trimSentCache();
  }

  bool isMessengerNotificationSuppressed(String messageId) {
    return _suppressedMessengerIds.contains(messageId);
  }

  int messengerNumericId(String messageId) {
    return messageId.hashCode.abs() % 2147483647;
  }

  Future<void> sendMessengerNotification({
    required String title,
    required String body,
    required String contactId,
    required String messageId,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_activeChatContactId == contactId) return;

    if (_suppressedMessengerIds.contains(messageId)) return;

    if (_sentMessengerIds.contains(messageId)) return;
    _sentMessengerIds.add(messageId);
    _trimSentCache();

    final numericId = messengerNumericId(messageId);

    await _notificationService.cancelNotification(numericId);

    final notification = NotificationModel.create(
      title: title,
      body: body,
      type: NotificationType.info,
      payload: 'messenger:$contactId:$messageId',
    );

    await _notificationService.showLocalNotification(
      id: numericId,
      title: title,
      body: body,
      payload: notification.id,
      type: NotificationType.info,
    );

    final sentNotification = notification.markAsSent();
    await _saveNotification(sentNotification);
  }

  Future<int> scheduleMessengerNotification({
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String contactId,
    required String messageId,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (scheduledDate.isBefore(DateTime.now())) {
      throw ArgumentError('Дата отправки должна быть в будущем');
    }

    final numericId = messengerNumericId(messageId);

    await _notificationService.cancelNotification(numericId);

    final notification = NotificationModel.create(
      title: title,
      body: body,
      type: NotificationType.info,
      payload: 'messenger:$contactId:$messageId',
      scheduledAt: scheduledDate,
    );

    await _notificationService.scheduleNotification(
      id: numericId,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      payload: notification.id,
      type: NotificationType.info,
    );

    await _saveNotification(notification);
    return numericId;
  }

  Future<void> dismissMessengerNotification(String messageId) async {
    if (!_isInitialized) {
      await initialize();
    }
    final numericId = messengerNumericId(messageId);
    await _notificationService.cancelNotification(numericId);
  }

  void _trimSentCache() {
    if (_sentMessengerIds.length > _maxSentCacheSize) {
      final toRemove =
          _sentMessengerIds.take(_sentMessengerIds.length - _maxSentCacheSize);
      _sentMessengerIds.removeAll(toRemove.toList());
    }
  }

  List<NotificationModel> getAllNotifications() {
    return List<NotificationModel>.unmodifiable(_notifications);
  }

  /// Возвращает список запланированных уведомлений
  List<NotificationModel> getScheduledNotifications() {
    return _notifications
        .where((n) => n.isScheduled && !n.isSent)
        .toList(growable: false);
  }

  /// Возвращает список отправленных уведомлений
  List<NotificationModel> getSentNotifications() {
    return _notifications.where((n) => n.isSent).toList(growable: false);
  }

  /// Возвращает уведомление по его ID
  NotificationModel? getNotificationById(String id) {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return null;
    return _notifications[index];
  }

  /// Помечает уведомление как прочитанное
  Future<void> markNotificationAsRead(String id) async {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1) return;

    final notification = _notifications[index];
    final updatedNotification = notification.markAsRead();
    _notifications[index] = updatedNotification;
    await _saveNotifications();
  }

  /// Обработчик получения уведомления
  void _handleNotificationReceived(String? payload) {
    if (payload == null) return;

    final notification = getNotificationById(payload);
    if (notification != null) {
      _notificationReceivedController.add(notification);
    }
  }

  void _handleNotificationTapped(String? payload) {
    if (payload == null) return;

    final notification = getNotificationById(payload);
    final messengerTarget =
        _parseMessengerPayload(notification?.payload ?? payload);

    if (messengerTarget != null) {
      if (notification != null) {
        markNotificationAsRead(notification.id);
        _notificationTappedController.add(notification);
      }
      suppressMessengerNotification(messengerTarget.messageId);
      _navigateToMessengerChat(messengerTarget);
      return;
    }

    String? action;

    final lowerRaw = payload.toLowerCase();
    if (lowerRaw.contains('water')) {
      action = 'add_water';
    } else if (lowerRaw.contains('meal')) {
      action = 'add_food_menu';
    }

    if (action == null && notification != null) {
      final combined =
          ('${notification.payload ?? ''} ${notification.title} ${notification.body}')
              .toLowerCase();
      if (combined.contains('water') || combined.contains('💧')) {
        action = 'add_water';
      } else {
        action = 'add_food_menu';
      }
    }

    if (notification != null) {
      markNotificationAsRead(notification.id);
      _notificationTappedController.add(notification);
    }

    if (action != null) {
      try {
        final context = appNavigatorKey.currentContext;
        if (context != null) {
          Future.microtask(() {
            Navigator.of(context).pushNamedAndRemoveUntil(
              '/home',
              (route) => false,
              arguments: {'widget_action': action},
            );
          });
        }
      } catch (e) {
        debugPrint('Ошибка навигации при нажатии уведомления: $e');
      }
    }
  }

  _MessengerNotificationTarget? _parseMessengerPayload(String? payload) {
    if (payload == null) return null;
    final trimmed = payload.trim();
    if (!trimmed.startsWith('messenger:')) return null;
    final parts = trimmed.split(':');
    if (parts.length < 3) return null;
    final contactId = parts[1].trim();
    final messageId = parts[2].trim();
    if (contactId.isEmpty || messageId.isEmpty) return null;
    return _MessengerNotificationTarget(
      contactId: contactId,
      messageId: messageId,
    );
  }

  bool _messengerNavigationInFlight = false;

  void _navigateToMessengerChat(_MessengerNotificationTarget target) {
    if (_messengerNavigationInFlight) return;
    _messengerNavigationInFlight = true;
    try {
      final context = appNavigatorKey.currentContext;
      if (context == null) {
        _messengerNavigationInFlight = false;
        return;
      }
      Future.microtask(() {
        try {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/home',
            (route) => false,
            arguments: {
              'open_chat_contact_id': target.contactId,
              'open_chat_message_id': target.messageId,
            },
          );
        } finally {
          Future.delayed(const Duration(seconds: 2), () {
            _messengerNavigationInFlight = false;
          });
        }
      });
    } catch (e) {
      _messengerNavigationInFlight = false;
      debugPrint('Ошибка навигации к чату: $e');
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsJson = prefs.getStringList(_notificationsKey) ?? [];

      _notifications = notificationsJson
          .map((json) => NotificationModel.fromJson(jsonDecode(json)))
          .toList();

      _pruneOldNotifications();

      appLog(
          localizeMessage('notifications_loaded', ['${_notifications.length}']),
          tag: 'FLUTTER',
          level: LogLevel.debug);
    } catch (e) {
      debugPrint('Ошибка при загрузке уведомлений: $e');
      _notifications = [];
    }
  }

  void _pruneOldNotifications() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final before = _notifications.length;
    _notifications.removeWhere(
      (n) => n.isSent && n.createdAt.isBefore(cutoff),
    );
    if (_notifications.length != before) {
      _saveNotifications();
    }
  }

  /// Сохраняет уведомления в локальное хранилище
  Future<void> _saveNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsJson = _notifications
          .map((notification) => jsonEncode(notification.toJson()))
          .toList();

      await prefs.setStringList(_notificationsKey, notificationsJson);
    } catch (e) {
      debugPrint('Ошибка при сохранении уведомлений: $e');
    }
  }

  /// Сохраняет одно уведомление в списке и обновляет локальное хранилище
  Future<void> _saveNotification(NotificationModel notification) async {
    // Добавляем уведомление в список или обновляем существующее
    final index = _notifications.indexWhere((n) => n.id == notification.id);
    if (index != -1) {
      _notifications[index] = notification;
    } else {
      _notifications.add(notification);
    }

    // Сохраняем обновленный список
    await _saveNotifications();
  }

  Future<void> _processPendingNotifications() async {
    final pendingNotifications = getScheduledNotifications();

    for (final notification in pendingNotifications) {
      if (notification.isOverdue) {
        await _notificationService.cancelNotification(notification.numericId);
        await _saveNotification(notification.markAsSent());

        final messengerTarget = _parseMessengerPayload(notification.payload);
        if (messengerTarget != null) {
          suppressMessengerNotification(messengerTarget.messageId);
          await dismissMessengerNotification(messengerTarget.messageId);
        }
      }
    }
  }
}

class _MessengerNotificationTarget {
  final String contactId;
  final String messageId;

  const _MessengerNotificationTarget({
    required this.contactId,
    required this.messageId,
  });
}
