class MessengerStory {
  final String id;
  final String contactId;
  final String contactName;
  final String caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? videoPath;
  final String? videoUrl;
  final String? imagePath;
  final String? imageUrl;
  final String? avatarPath;
  final String? prompt;
  final String aspectRatio;
  final DateTime? viewedAt;
  final bool isLocked;

  const MessengerStory({
    required this.id,
    required this.contactId,
    required this.contactName,
    required this.caption,
    required this.createdAt,
    required this.expiresAt,
    required this.aspectRatio,
    this.videoPath,
    this.videoUrl,
    this.imagePath,
    this.imageUrl,
    this.avatarPath,
    this.prompt,
    this.viewedAt,
    this.isLocked = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isViewed => viewedAt != null;

  factory MessengerStory.fromJson(Map<String, dynamic> json) {
    return MessengerStory(
      id: json['id'] as String,
      contactId: json['contactId'] as String,
      contactName: json['contactName'] as String? ?? '',
      caption: json['caption'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
      aspectRatio: json['aspectRatio'] as String? ?? '9:16',
      videoPath: json['videoPath'] as String?,
      videoUrl: json['videoUrl'] as String?,
      imagePath: json['imagePath'] as String?,
      imageUrl: json['imageUrl'] as String?,
      avatarPath: json['avatarPath'] as String?,
      prompt: json['prompt'] as String?,
      viewedAt: json['viewedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['viewedAt'] as int)
          : null,
      isLocked: json['isLocked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'contactId': contactId,
        'contactName': contactName,
        'caption': caption,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'aspectRatio': aspectRatio,
        'videoPath': videoPath,
        'videoUrl': videoUrl,
        'imagePath': imagePath,
        'imageUrl': imageUrl,
        'avatarPath': avatarPath,
        'prompt': prompt,
        'viewedAt': viewedAt?.millisecondsSinceEpoch,
        'isLocked': isLocked,
      };

  MessengerStory copyWith({
    String? id,
    String? contactId,
    String? contactName,
    String? caption,
    DateTime? createdAt,
    DateTime? expiresAt,
    String? videoPath,
    String? videoUrl,
    String? imagePath,
    String? imageUrl,
    String? avatarPath,
    String? prompt,
    String? aspectRatio,
    DateTime? viewedAt,
    bool? isLocked,
  }) {
    return MessengerStory(
      id: id ?? this.id,
      contactId: contactId ?? this.contactId,
      contactName: contactName ?? this.contactName,
      caption: caption ?? this.caption,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      videoPath: videoPath ?? this.videoPath,
      videoUrl: videoUrl ?? this.videoUrl,
      imagePath: imagePath ?? this.imagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      avatarPath: avatarPath ?? this.avatarPath,
      prompt: prompt ?? this.prompt,
      viewedAt: viewedAt ?? this.viewedAt,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}
