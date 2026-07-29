class UserGeneration {
  UserGeneration({
    required this.id,
    required this.presetId,
    required this.userImageUrl,
    required this.resultImageUrl,
    this.referenceImageUrl,
    this.firebaseUid,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String presetId;
  final String userImageUrl;
  final String resultImageUrl;
  final String? referenceImageUrl;
  final String? firebaseUid;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'presetId': presetId,
        'userImageUrl': userImageUrl,
        'resultImageUrl': resultImageUrl,
        if (referenceImageUrl != null) 'referenceImageUrl': referenceImageUrl,
        if (firebaseUid != null) 'firebaseUid': firebaseUid,
        'createdAt': createdAt.toIso8601String(),
      };

  factory UserGeneration.fromJson(Map<String, dynamic> json) {
    return UserGeneration(
      id: json['id'] as String? ?? json['\$id'] as String? ?? '',
      presetId: json['presetId'] as String? ?? '',
      userImageUrl: json['userImageUrl'] as String? ?? '',
      resultImageUrl: json['resultImageUrl'] as String? ?? '',
      referenceImageUrl: json['referenceImageUrl'] as String?,
      firebaseUid: json['firebaseUid'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
