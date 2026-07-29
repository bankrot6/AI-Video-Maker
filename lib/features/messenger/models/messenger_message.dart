enum MessengerMessageStatus {
  sending,
  delivered,
  read,
}

class MessengerMessageQuote {
  final String? messageId;
  final String authorName;
  final String text;
  final bool hasImage;

  const MessengerMessageQuote({
    required this.messageId,
    required this.authorName,
    required this.text,
    required this.hasImage,
  });

  factory MessengerMessageQuote.fromJson(Map<String, dynamic> json) {
    return MessengerMessageQuote(
      messageId: json['messageId'] as String?,
      authorName: json['authorName'] as String? ?? '',
      text: json['text'] as String? ?? '',
      hasImage: json['hasImage'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'authorName': authorName,
        'text': text,
        'hasImage': hasImage,
      };
}

class MessengerMessage {
  final String id;
  final String text;
  final DateTime time;
  final bool isMine;
  final MessengerMessageStatus status;
  final String? imagePath;
  final String? imageUrl;
  final String? audioPath;
  final String? audioUrl;
  final int? audioDurationMs;
  final String? storyId;
  final MessengerMessageQuote? quote;
  final String? forwardedFromName;
  final String? paywallAction;

  const MessengerMessage({
    required this.id,
    required this.text,
    required this.time,
    required this.isMine,
    this.status = MessengerMessageStatus.delivered,
    this.imagePath,
    this.imageUrl,
    this.audioPath,
    this.audioUrl,
    this.audioDurationMs,
    this.storyId,
    this.quote,
    this.forwardedFromName,
    this.paywallAction,
  });

  MessengerMessage copyWith({
    String? id,
    String? text,
    DateTime? time,
    bool? isMine,
    MessengerMessageStatus? status,
    String? imagePath,
    String? imageUrl,
    String? audioPath,
    String? audioUrl,
    int? audioDurationMs,
    String? storyId,
    MessengerMessageQuote? quote,
    String? forwardedFromName,
    String? paywallAction,
  }) {
    return MessengerMessage(
      id: id ?? this.id,
      text: text ?? this.text,
      time: time ?? this.time,
      isMine: isMine ?? this.isMine,
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      audioPath: audioPath ?? this.audioPath,
      audioUrl: audioUrl ?? this.audioUrl,
      audioDurationMs: audioDurationMs ?? this.audioDurationMs,
      storyId: storyId ?? this.storyId,
      quote: quote ?? this.quote,
      forwardedFromName: forwardedFromName ?? this.forwardedFromName,
      paywallAction: paywallAction ?? this.paywallAction,
    );
  }

  factory MessengerMessage.fromJson(Map<String, dynamic> json) {
    final statusValue = json['status'] as String?;
    final quoteJson = json['quote'] as Map<String, dynamic>?;
    return MessengerMessage(
      id: json['id'] as String,
      text: json['text'] as String,
      time: DateTime.fromMillisecondsSinceEpoch(json['time'] as int),
      isMine: json['isMine'] as bool,
      status: _parseStatus(statusValue),
      imagePath: json['imagePath'] as String?,
      imageUrl: json['imageUrl'] as String?,
      audioPath: json['audioPath'] as String?,
      audioUrl: json['audioUrl'] as String?,
      audioDurationMs: json['audioDurationMs'] as int?,
      storyId: json['storyId'] as String?,
      quote:
          quoteJson == null ? null : MessengerMessageQuote.fromJson(quoteJson),
      forwardedFromName: json['forwardedFromName'] as String?,
      paywallAction: json['paywallAction'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'time': time.millisecondsSinceEpoch,
        'isMine': isMine,
        'status': status.name,
        'imagePath': imagePath,
        'imageUrl': imageUrl,
        'audioPath': audioPath,
        'audioUrl': audioUrl,
        'audioDurationMs': audioDurationMs,
        'storyId': storyId,
        'quote': quote?.toJson(),
        'forwardedFromName': forwardedFromName,
        'paywallAction': paywallAction,
      };
}

MessengerMessageStatus _parseStatus(String? value) {
  switch (value) {
    case 'sending':
      return MessengerMessageStatus.sending;
    case 'delivered':
      return MessengerMessageStatus.delivered;
    case 'read':
      return MessengerMessageStatus.read;
    default:
      return MessengerMessageStatus.delivered;
  }
}
