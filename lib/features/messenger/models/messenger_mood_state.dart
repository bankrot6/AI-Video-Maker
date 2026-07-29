class MessengerMoodState {
  final String contactId;
  final int joy;
  final int anger;
  final int fun;
  final int sadness;
  final int humor;
  final int boring;
  final DateTime updatedAt;

  const MessengerMoodState({
    required this.contactId,
    required this.joy,
    required this.anger,
    required this.fun,
    required this.sadness,
    required this.humor,
    required this.boring,
    required this.updatedAt,
  });

  factory MessengerMoodState.initial(String contactId, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return MessengerMoodState(
      contactId: contactId,
      joy: 0,
      anger: 0,
      fun: 0,
      sadness: 0,
      humor: 0,
      boring: 0,
      updatedAt: timestamp,
    );
  }

  MessengerMoodState copyWith({
    String? contactId,
    int? joy,
    int? anger,
    int? fun,
    int? sadness,
    int? humor,
    int? boring,
    DateTime? updatedAt,
  }) {
    return MessengerMoodState(
      contactId: contactId ?? this.contactId,
      joy: joy ?? this.joy,
      anger: anger ?? this.anger,
      fun: fun ?? this.fun,
      sadness: sadness ?? this.sadness,
      humor: humor ?? this.humor,
      boring: boring ?? this.boring,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'contactId': contactId,
        'joy': joy,
        'anger': anger,
        'fun': fun,
        'sadness': sadness,
        'humor': humor,
        'boring': boring,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory MessengerMoodState.fromJson(Map<String, dynamic> json) {
    return MessengerMoodState(
      contactId: (json['contactId'] as String?)?.trim() ?? '',
      joy: (json['joy'] as num?)?.toInt() ?? 0,
      anger: (json['anger'] as num?)?.toInt() ?? 0,
      fun: (json['fun'] as num?)?.toInt() ?? 0,
      sadness: (json['sadness'] as num?)?.toInt() ?? 0,
      humor: (json['humor'] as num?)?.toInt() ?? 0,
      boring: (json['boring'] as num?)?.toInt() ?? 0,
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int? ?? 0),
    );
  }
}

class MessengerMoodDelta {
  final int joy;
  final int anger;
  final int fun;
  final int sadness;
  final int humor;
  final int boring;

  const MessengerMoodDelta({
    this.joy = 0,
    this.anger = 0,
    this.fun = 0,
    this.sadness = 0,
    this.humor = 0,
    this.boring = 0,
  });

  bool get isEmpty =>
      joy == 0 &&
      anger == 0 &&
      fun == 0 &&
      sadness == 0 &&
      humor == 0 &&
      boring == 0;
}
