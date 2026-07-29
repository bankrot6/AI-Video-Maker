class MessengerMemory {
  final String summary;
  final DateTime updatedAt;
  final bool userDeclinedPhotos;
  final DateTime? photoDeclineTimestamp;

  const MessengerMemory({
    required this.summary,
    required this.updatedAt,
    this.userDeclinedPhotos = false,
    this.photoDeclineTimestamp,
  });

  MessengerMemory copyWith({
    String? summary,
    DateTime? updatedAt,
    bool? userDeclinedPhotos,
    DateTime? photoDeclineTimestamp,
  }) {
    return MessengerMemory(
      summary: summary ?? this.summary,
      updatedAt: updatedAt ?? this.updatedAt,
      userDeclinedPhotos: userDeclinedPhotos ?? this.userDeclinedPhotos,
      photoDeclineTimestamp: photoDeclineTimestamp ?? this.photoDeclineTimestamp,
    );
  }

  factory MessengerMemory.fromJson(Map<String, dynamic> json) {
    return MessengerMemory(
      summary: json['summary'] as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
      userDeclinedPhotos: json['userDeclinedPhotos'] as bool? ?? false,
      photoDeclineTimestamp: json['photoDeclineTimestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['photoDeclineTimestamp'] as int)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'userDeclinedPhotos': userDeclinedPhotos,
        'photoDeclineTimestamp': photoDeclineTimestamp?.millisecondsSinceEpoch,
      };
}
