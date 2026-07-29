class PresetEarnings {
  final String presetId;
  final String ownerId;
  final int totalLikes;
  final int creditsEarned;
  final int lastProcessedLikes;
  final DateTime lastProcessedAt;
  final DateTime createdAt;

  const PresetEarnings({
    required this.presetId,
    required this.ownerId,
    required this.totalLikes,
    required this.creditsEarned,
    required this.lastProcessedLikes,
    required this.lastProcessedAt,
    required this.createdAt,
  });

  static const int creditsPerLike = 1;
  static const int minLikesForReward = 3;
  static const int maxCreditsPerPreset = 50;

  int calculateNewCredits(int newLikes) {
    if (newLikes < minLikesForReward) return 0;

    final delta = newLikes - lastProcessedLikes;
    if (delta <= 0) return 0;

    final potentialEarnings = creditsEarned + delta;
    if (potentialEarnings > maxCreditsPerPreset) {
      return (maxCreditsPerPreset - creditsEarned).clamp(0, maxCreditsPerPreset);
    }

    return delta;
  }

  bool get hasReachedMaxReward => creditsEarned >= maxCreditsPerPreset;

  bool get isEligibleForReward => totalLikes >= minLikesForReward;

  PresetEarnings copyWith({
    int? totalLikes,
    int? creditsEarned,
    int? lastProcessedLikes,
    DateTime? lastProcessedAt,
  }) {
    return PresetEarnings(
      presetId: presetId,
      ownerId: ownerId,
      totalLikes: totalLikes ?? this.totalLikes,
      creditsEarned: creditsEarned ?? this.creditsEarned,
      lastProcessedLikes: lastProcessedLikes ?? this.lastProcessedLikes,
      lastProcessedAt: lastProcessedAt ?? this.lastProcessedAt,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'ownerId': ownerId,
        'totalLikes': totalLikes,
        'creditsEarned': creditsEarned,
        'lastProcessedLikes': lastProcessedLikes,
        'lastProcessedAt': lastProcessedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    
    // Если это строка, парсим как ISO8601
    if (value is String) {
      return DateTime.parse(value);
    }
    
    // Если это Timestamp из Firebase
    if (value.runtimeType.toString() == 'Timestamp') {
      return (value as dynamic).toDate();
    }
    
    // Если это уже DateTime
    if (value is DateTime) {
      return value;
    }
    
    // Fallback - пробуем преобразовать в строку и парсить
    try {
      return DateTime.parse(value.toString());
    } catch (e) {
      return DateTime.now();
    }
  }

  factory PresetEarnings.fromJson(Map<String, dynamic> json) {
    return PresetEarnings(
      presetId: json['presetId'] as String,
      ownerId: json['ownerId'] as String,
      totalLikes: json['totalLikes'] as int? ?? 0,
      creditsEarned: json['creditsEarned'] as int? ?? 0,
      lastProcessedLikes: json['lastProcessedLikes'] as int? ?? 0,
      lastProcessedAt: _parseDateTime(json['lastProcessedAt']),
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  factory PresetEarnings.initial({
    required String presetId,
    required String ownerId,
  }) {
    final now = DateTime.now();
    return PresetEarnings(
      presetId: presetId,
      ownerId: ownerId,
      totalLikes: 0,
      creditsEarned: 0,
      lastProcessedLikes: 0,
      lastProcessedAt: now,
      createdAt: now,
    );
  }

  @override
  String toString() =>
      'PresetEarnings(preset: $presetId, likes: $totalLikes, earned: $creditsEarned/$maxCreditsPerPreset)';
}
