import 'package:uuid/uuid.dart';

import '../services/notification/notification_service_interface.dart';

/// Модель данных для уведомления
class NotificationModel {
  /// Уникальный идентификатор уведомления
  final String id;

  /// Заголовок уведомления
  final String title;

  /// Текст уведомления
  final String body;

  /// Тип уведомления
  final NotificationType type;

  /// Полезная нагрузка для обработки при открытии уведомления
  final String? payload;

  /// Дата и время отправки уведомления
  final DateTime createdAt;

  /// Дата и время запланированной отправки уведомления (если уведомление запланировано)
  final DateTime? scheduledAt;

  /// Флаг, указывающий, было ли уведомление прочитано
  final bool isRead;

  /// Флаг, указывающий, было ли уведомление отправлено
  final bool isSent;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    this.type = NotificationType.info,
    this.payload,
    required this.createdAt,
    this.scheduledAt,
    this.isRead = false,
    this.isSent = false,
  });

  /// Создание уведомления из JSON
  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      type: _typeFromString(json['type'] as String?),
      payload: json['payload'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      scheduledAt: json['scheduledAt'] != null
          ? DateTime.parse(json['scheduledAt'] as String)
          : null,
      isRead: json['isRead'] as bool? ?? false,
      isSent: json['isSent'] as bool? ?? false,
    );
  }

  /// Преобразование в JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'type': type.toString(),
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'scheduledAt': scheduledAt?.toIso8601String(),
      'isRead': isRead,
      'isSent': isSent,
    };
  }

  /// Создание уведомления с новым ID и текущей датой
  factory NotificationModel.create({
    required String title,
    required String body,
    NotificationType type = NotificationType.info,
    String? payload,
    DateTime? scheduledAt,
  }) {
    return NotificationModel(
      id: const Uuid().v4(),
      title: title,
      body: body,
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
      scheduledAt: scheduledAt,
    );
  }

  /// Возвращает числовой ID для использования в уведомлениях
  ///
  /// Преобразует UUID строку в целое число
  int get numericId {
    // Используем хеш от ID, ограничивая его 7-значным числом
    return id.hashCode.abs() % 10000000;
  }

  /// Возвращает новую копию уведомления с установленным флагом прочтения
  NotificationModel markAsRead() {
    return copyWith(isRead: true);
  }

  /// Возвращает новую копию уведомления с установленным флагом отправки
  NotificationModel markAsSent() {
    return copyWith(isSent: true);
  }

  /// Проверяет, является ли уведомление запланированным
  bool get isScheduled => scheduledAt != null;

  /// Проверяет, просрочено ли запланированное уведомление
  bool get isOverdue {
    if (scheduledAt == null) return false;
    return scheduledAt!.isBefore(DateTime.now()) && !isSent;
  }

  /// Создает копию уведомления с обновленными полями
  NotificationModel copyWith({
    String? id,
    String? title,
    String? body,
    NotificationType? type,
    String? payload,
    DateTime? createdAt,
    DateTime? scheduledAt,
    bool? isRead,
    bool? isSent,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      isRead: isRead ?? this.isRead,
      isSent: isSent ?? this.isSent,
    );
  }

  /// Парсинг типа уведомления из строки
  static NotificationType _typeFromString(String? typeString) {
    switch (typeString) {
      case 'NotificationType.reminder':
        return NotificationType.reminder;
      case 'NotificationType.warning':
        return NotificationType.warning;
      case 'NotificationType.critical':
        return NotificationType.critical;
      default:
        return NotificationType.info;
    }
  }
}
