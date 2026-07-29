import 'package:equatable/equatable.dart';

/// Тип источника видео
enum ExerciseVideoSource {
  vk,
  rutube,
}

/// Кандидат видео для упражнения
class ExerciseVideoCandidate extends Equatable {
  final ExerciseVideoSource source;

  /// Для VK: ownerId и videoId
  final String? ownerId;
  final String? videoId;

  /// Метаданные (необязательно)
  final String? title;
  final int? views;
  final int? durationSec;
  final String? thumbnailUrl;
  final String? playerUrl; // готовый embed URL, если есть

  const ExerciseVideoCandidate({
    required this.source,
    this.ownerId,
    this.videoId,
    this.title,
    this.views,
    this.durationSec,
    this.thumbnailUrl,
    this.playerUrl,
  });

  /// Уникальный идентификатор кандидата
  String get uniqueKey {
    switch (source) {
      case ExerciseVideoSource.vk:
        return 'vk:${ownerId ?? ''}:${videoId ?? ''}';
      case ExerciseVideoSource.rutube:
        return 'rutube:${videoId ?? ''}';
    }
  }

  @override
  List<Object?> get props => [
        source,
        ownerId,
        videoId,
        title,
        views,
        durationSec,
        thumbnailUrl,
        playerUrl
      ];
}
