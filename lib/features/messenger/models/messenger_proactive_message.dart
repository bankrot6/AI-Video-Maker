class MessengerProactiveMessage {
  final String id;
  final String contactId;
  final String text;
  final DateTime createdAt;
  final DateTime scheduledAt;
  final DateTime? deliveredAt;
  final int? notificationId;

  const MessengerProactiveMessage({
    required this.id,
    required this.contactId,
    required this.text,
    required this.createdAt,
    required this.scheduledAt,
    this.deliveredAt,
    this.notificationId,
  });

  bool get isDelivered => deliveredAt != null;

  MessengerProactiveMessage copyWith({
    String? id,
    String? contactId,
    String? text,
    DateTime? createdAt,
    DateTime? scheduledAt,
    DateTime? deliveredAt,
    int? notificationId,
  }) {
    return MessengerProactiveMessage(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      notificationId: notificationId ?? this.notificationId,
    );
  }

  factory MessengerProactiveMessage.fromJson(Map<String, dynamic> json) {
    return MessengerProactiveMessage(
      id: json['id'] as String,
      contactId: json['contactId'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      scheduledAt: DateTime.parse(json['scheduledAt'] as String),
      deliveredAt: json['deliveredAt'] == null
          ? null
          : DateTime.parse(json['deliveredAt'] as String),
      notificationId: json['notificationId'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'contactId': contactId,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'scheduledAt': scheduledAt.toIso8601String(),
      'deliveredAt': deliveredAt?.toIso8601String(),
      'notificationId': notificationId,
    };
  }
}
