enum MessengerPendingAiTaskType {
  aiFlow,
}

class MessengerPendingAiTask {
  final String id;
  final MessengerPendingAiTaskType type;
  final String contactId;
  final String userMessageId;
  final String rawText;
  final bool wantsVoiceReply;
  final bool shouldWaitForImage;
  final bool shouldStory;
  final bool isImageChat;
  final bool isVoiceMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int retryCount;
  final DateTime? nextRetryAt;
  final String? lastError;

  const MessengerPendingAiTask({
    required this.id,
    required this.type,
    required this.contactId,
    required this.userMessageId,
    required this.rawText,
    required this.wantsVoiceReply,
    required this.shouldWaitForImage,
    required this.shouldStory,
    required this.isImageChat,
    required this.isVoiceMessage,
    required this.createdAt,
    required this.updatedAt,
    this.retryCount = 0,
    this.nextRetryAt,
    this.lastError,
  });

  MessengerPendingAiTask copyWith({
    String? id,
    MessengerPendingAiTaskType? type,
    String? contactId,
    String? userMessageId,
    String? rawText,
    bool? wantsVoiceReply,
    bool? shouldWaitForImage,
    bool? shouldStory,
    bool? isImageChat,
    bool? isVoiceMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? retryCount,
    DateTime? nextRetryAt,
    String? lastError,
  }) {
    return MessengerPendingAiTask(
      id: id ?? this.id,
      type: type ?? this.type,
      contactId: contactId ?? this.contactId,
      userMessageId: userMessageId ?? this.userMessageId,
      rawText: rawText ?? this.rawText,
      wantsVoiceReply: wantsVoiceReply ?? this.wantsVoiceReply,
      shouldWaitForImage: shouldWaitForImage ?? this.shouldWaitForImage,
      shouldStory: shouldStory ?? this.shouldStory,
      isImageChat: isImageChat ?? this.isImageChat,
      isVoiceMessage: isVoiceMessage ?? this.isVoiceMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      retryCount: retryCount ?? this.retryCount,
      nextRetryAt: nextRetryAt,
      lastError: lastError,
    );
  }

  factory MessengerPendingAiTask.fromJson(Map<String, dynamic> json) {
    return MessengerPendingAiTask(
      id: json['id'] as String,
      type: _taskTypeFromString(json['type'] as String?),
      contactId: json['contactId'] as String,
      userMessageId: json['userMessageId'] as String,
      rawText: json['rawText'] as String? ?? '',
      wantsVoiceReply: json['wantsVoiceReply'] as bool? ?? false,
      shouldWaitForImage: json['shouldWaitForImage'] as bool? ?? false,
      shouldStory: json['shouldStory'] as bool? ?? false,
      isImageChat: json['isImageChat'] as bool? ?? false,
      isVoiceMessage: json['isVoiceMessage'] as bool? ?? false,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int? ?? 0),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int? ?? 0),
      retryCount: json['retryCount'] as int? ?? 0,
      nextRetryAt: json['nextRetryAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(json['nextRetryAt'] as int),
      lastError: json['lastError'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'contactId': contactId,
        'userMessageId': userMessageId,
        'rawText': rawText,
        'wantsVoiceReply': wantsVoiceReply,
        'shouldWaitForImage': shouldWaitForImage,
        'shouldStory': shouldStory,
        'isImageChat': isImageChat,
        'isVoiceMessage': isVoiceMessage,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'retryCount': retryCount,
        'nextRetryAt': nextRetryAt?.millisecondsSinceEpoch,
        'lastError': lastError,
      };
}

MessengerPendingAiTaskType _taskTypeFromString(String? raw) {
  switch (raw) {
    case 'aiFlow':
      return MessengerPendingAiTaskType.aiFlow;
    default:
      return MessengerPendingAiTaskType.aiFlow;
  }
}
