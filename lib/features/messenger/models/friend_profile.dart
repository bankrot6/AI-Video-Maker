class FriendProfile {
  static const String relationshipFriend = 'friend';
  static const String relationshipRomantic = 'relationship';
  static const String aiModelChat = 'chat';
  static const String aiModelReasoner = 'reasoner';
  static const String avatarStatusReady = 'ready';
  static const String avatarStatusPending = 'pending';
  static const String avatarStatusFailed = 'failed';

  final String name;
  final String gender;
  final int age;
  final String hairColor;
  final String eyeColor;
  final String hairstyle;
  final String ethnicity;
  final String skinTone;
  final String bodyType;
  final String heightCategory;
  final String facialFeatures;
  final String relationshipType;
  final String? avatarPath;
  final String aiModel;
  final String avatarStatus;
  final String appearanceDescription;
  final String? appearanceCheckAvatarPath;
  final String? voiceId;
  final double? voiceSpeed;
  final double? voiceStability;
  final double? voiceSimilarityBoost;

  const FriendProfile({
    required this.name,
    required this.gender,
    required this.age,
    required this.hairColor,
    required this.eyeColor,
    this.hairstyle = '',
    this.ethnicity = '',
    this.skinTone = '',
    this.bodyType = '',
    this.heightCategory = '',
    this.facialFeatures = '',
    this.relationshipType = relationshipFriend,
    this.avatarPath,
    this.aiModel = aiModelChat,
    this.avatarStatus = avatarStatusReady,
    this.appearanceDescription = '',
    this.appearanceCheckAvatarPath,
    this.voiceId,
    this.voiceSpeed,
    this.voiceStability,
    this.voiceSimilarityBoost,
  });

  factory FriendProfile.fromJson(Map<String, dynamic> json) {
    final relationshipType =
        _normalizeRelationshipType(json['relationshipType'] as String?);
    final aiModel = _normalizeAiModel(json['aiModel'] as String?);
    final avatarStatus =
        _normalizeAvatarStatus(json['avatarStatus'] as String?);
    return FriendProfile(
      name: (json['name'] as String?)?.trim() ?? '',
      gender: (json['gender'] as String?)?.trim() ?? 'male',
      age: (json['age'] as num?)?.toInt() ?? 25,
      hairColor: (json['hairColor'] as String?)?.trim() ?? 'blonde',
      eyeColor: (json['eyeColor'] as String?)?.trim() ?? 'blue',
      hairstyle: (json['hairstyle'] as String?)?.trim() ?? '',
      ethnicity: (json['ethnicity'] as String?)?.trim() ?? '',
      skinTone: (json['skinTone'] as String?)?.trim() ?? '',
      bodyType: (json['bodyType'] as String?)?.trim() ?? '',
      heightCategory: (json['heightCategory'] as String?)?.trim() ?? '',
      facialFeatures: (json['facialFeatures'] as String?)?.trim() ?? '',
      relationshipType: relationshipType,
      avatarPath: (json['avatarPath'] as String?)?.trim(),
      aiModel: aiModel,
      avatarStatus: avatarStatus,
      appearanceDescription:
          (json['appearanceDescription'] as String?)?.trim() ?? '',
      appearanceCheckAvatarPath:
          (json['appearanceCheckAvatarPath'] as String?)?.trim(),
      voiceId: (json['voiceId'] ?? json['voice_id'])?.toString().trim(),
      voiceSpeed: _toDouble(json['voiceSpeed']),
      voiceStability: _toDouble(json['voiceStability']),
      voiceSimilarityBoost: _toDouble(json['voiceSimilarityBoost']),
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString().trim());
    return parsed;
  }

  bool get isRomantic => relationshipType == relationshipRomantic;
  bool get isAvatarGenerating => avatarStatus == avatarStatusPending;

  Map<String, dynamic> toJson() => {
        'name': name,
        'gender': gender,
        'age': age,
        'hairColor': hairColor,
        'eyeColor': eyeColor,
        'hairstyle': hairstyle,
        'ethnicity': ethnicity,
        'skinTone': skinTone,
        'bodyType': bodyType,
        'heightCategory': heightCategory,
        'facialFeatures': facialFeatures,
        'relationshipType': relationshipType,
        'avatarPath': avatarPath,
        'aiModel': aiModel,
        'avatarStatus': avatarStatus,
        'appearanceDescription': appearanceDescription,
        'appearanceCheckAvatarPath': appearanceCheckAvatarPath,
        'voiceId': voiceId,
        'voiceSpeed': voiceSpeed,
        'voiceStability': voiceStability,
        'voiceSimilarityBoost': voiceSimilarityBoost,
      };

  FriendProfile copyWith({
    String? name,
    String? gender,
    int? age,
    String? hairColor,
    String? eyeColor,
    String? hairstyle,
    String? ethnicity,
    String? skinTone,
    String? bodyType,
    String? heightCategory,
    String? facialFeatures,
    String? relationshipType,
    String? avatarPath,
    String? aiModel,
    String? avatarStatus,
    String? appearanceDescription,
    String? appearanceCheckAvatarPath,
    String? voiceId,
    double? voiceSpeed,
    double? voiceStability,
    double? voiceSimilarityBoost,
  }) {
    return FriendProfile(
      name: name ?? this.name,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      hairColor: hairColor ?? this.hairColor,
      eyeColor: eyeColor ?? this.eyeColor,
      hairstyle: hairstyle ?? this.hairstyle,
      ethnicity: ethnicity ?? this.ethnicity,
      skinTone: skinTone ?? this.skinTone,
      bodyType: bodyType ?? this.bodyType,
      heightCategory: heightCategory ?? this.heightCategory,
      facialFeatures: facialFeatures ?? this.facialFeatures,
      relationshipType: relationshipType ?? this.relationshipType,
      avatarPath: avatarPath ?? this.avatarPath,
      aiModel: aiModel ?? this.aiModel,
      avatarStatus: avatarStatus ?? this.avatarStatus,
      appearanceDescription:
          appearanceDescription ?? this.appearanceDescription,
      appearanceCheckAvatarPath:
          appearanceCheckAvatarPath ?? this.appearanceCheckAvatarPath,
      voiceId: voiceId ?? this.voiceId,
      voiceSpeed: voiceSpeed ?? this.voiceSpeed,
      voiceStability: voiceStability ?? this.voiceStability,
      voiceSimilarityBoost: voiceSimilarityBoost ?? this.voiceSimilarityBoost,
    );
  }

  static String _normalizeRelationshipType(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == relationshipRomantic) return relationshipRomantic;
    return relationshipFriend;
  }

  static String _normalizeAiModel(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == aiModelReasoner) return aiModelReasoner;
    return aiModelChat;
  }

  static String _normalizeAvatarStatus(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == avatarStatusPending) return avatarStatusPending;
    if (normalized == avatarStatusFailed) return avatarStatusFailed;
    return avatarStatusReady;
  }
}
