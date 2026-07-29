class PhotoSessionPreset {
  PhotoSessionPreset({
    required this.id,
    required this.prompt,
    required this.previewImageUrl,
    this.thumbnailUrl,
    this.title,
    List<String>? tags,
    this.imageStyle,
    DateTime? createdAt,
    this.ownerId,
    this.isPublic = false,
    this.likesCount = 0,
    List<String>? likedBy,
  })  : tags = tags ?? const [],
        createdAt = createdAt ?? DateTime.now(),
        likedBy = likedBy ?? const [];

  final String id;
  final String prompt;
  final String previewImageUrl;
  final String? thumbnailUrl;
  final String? title;
  final List<String> tags;
  final String? imageStyle;
  final DateTime createdAt;
  final String? ownerId;
  final bool isPublic;
  final int likesCount;
  final List<String> likedBy;

  String get displayImageUrl => thumbnailUrl ?? previewImageUrl;

  bool hasTag(String tagId) =>
      tagId.isEmpty || tagId == 'all' || tags.contains(tagId);

  bool isLikedBy(String deviceId) => likedBy.contains(deviceId);

  PhotoSessionPreset copyWith({
    String? id,
    String? prompt,
    String? previewImageUrl,
    String? thumbnailUrl,
    String? title,
    List<String>? tags,
    String? imageStyle,
    DateTime? createdAt,
    String? ownerId,
    bool? isPublic,
    int? likesCount,
    List<String>? likedBy,
  }) {
    return PhotoSessionPreset(
      id: id ?? this.id,
      prompt: prompt ?? this.prompt,
      previewImageUrl: previewImageUrl ?? this.previewImageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      imageStyle: imageStyle ?? this.imageStyle,
      createdAt: createdAt ?? this.createdAt,
      ownerId: ownerId ?? this.ownerId,
      isPublic: isPublic ?? this.isPublic,
      likesCount: likesCount ?? this.likesCount,
      likedBy: likedBy ?? this.likedBy,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'prompt': prompt,
        'previewImageUrl': previewImageUrl,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        'title': title,
        'tags': tags,
        if (imageStyle != null && imageStyle!.isNotEmpty) 'imageStyle': imageStyle,
        'createdAt': createdAt.toIso8601String(),
        'ownerId': ownerId,
        'isPublic': isPublic,
        'likesCount': likesCount,
        'likedBy': likedBy,
      };

  factory PhotoSessionPreset.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tagsList = <String>[];
    if (tagsRaw is List) {
      for (final e in tagsRaw) {
        if (e is String) tagsList.add(e);
      }
    }
    final likedByRaw = json['likedBy'];
    final likedByList = <String>[];
    if (likedByRaw is List) {
      for (final e in likedByRaw) {
        if (e is String) likedByList.add(e);
      }
    }
    return PhotoSessionPreset(
      id: json['id'] as String? ?? json['\$id'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      previewImageUrl: json['previewImageUrl'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      title: json['title'] as String?,
      tags: tagsList,
      imageStyle: json['imageStyle'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      ownerId: json['ownerId'] as String?,
      isPublic: json['isPublic'] as bool? ?? false,
      likesCount: json['likesCount'] as int? ?? 0,
      likedBy: likedByList,
    );
  }
}
