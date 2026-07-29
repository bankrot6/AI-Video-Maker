class MessengerOutfitState {
  final String contactId;
  final String sceneKey;
  final String outfit;
  final DateTime updatedAt;
  final DateTime lockedUntil;

  const MessengerOutfitState({
    required this.contactId,
    required this.sceneKey,
    required this.outfit,
    required this.updatedAt,
    required this.lockedUntil,
  });

  bool isExpired(DateTime now) => !lockedUntil.isAfter(now);

  MessengerOutfitState copyWith({
    String? contactId,
    String? sceneKey,
    String? outfit,
    DateTime? updatedAt,
    DateTime? lockedUntil,
  }) {
    return MessengerOutfitState(
      contactId: contactId ?? this.contactId,
      sceneKey: sceneKey ?? this.sceneKey,
      outfit: outfit ?? this.outfit,
      updatedAt: updatedAt ?? this.updatedAt,
      lockedUntil: lockedUntil ?? this.lockedUntil,
    );
  }

  Map<String, dynamic> toJson() => {
        'contactId': contactId,
        'sceneKey': sceneKey,
        'outfit': outfit,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'lockedUntil': lockedUntil.millisecondsSinceEpoch,
      };

  factory MessengerOutfitState.fromJson(Map<String, dynamic> json) {
    return MessengerOutfitState(
      contactId: (json['contactId'] as String?)?.trim() ?? '',
      sceneKey: (json['sceneKey'] as String?)?.trim() ?? '',
      outfit: (json['outfit'] as String?)?.trim() ?? '',
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int? ?? 0),
      lockedUntil:
          DateTime.fromMillisecondsSinceEpoch(json['lockedUntil'] as int? ?? 0),
    );
  }
}
