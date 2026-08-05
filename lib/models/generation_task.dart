import '../features/photosession/photosession_support_error.dart';
import 'photosession_provider.dart';

enum GenerationStatus {
  generating,
  uploading,
  saving,
  completed,
  error,
}

enum GenerationTaskType {
  /// Генерация по готовой карточке из галереи.
  preset,

  /// Замена лица / перенос стиля по референсу.
  faceSwap,

  /// Изображение, созданное пользователем по собственному запросу.
  userImage,
}

enum FaceSwapMode {
  exact,
  style,
}

class GenerationTask {
  const GenerationTask({
    required this.id,
    required this.presetId,
    this.presetTitle,
    this.presetPreviewUrl,
    required this.status,
    this.statusMessage = '',
    this.resultImageUrl,
    this.errorMessage,
    required this.userPhotoPath,
    required this.prompt,
    required this.createdAt,
    this.provider = PhotosessionProvider.veoFast,
    this.taskType = GenerationTaskType.preset,
    this.referenceImageUrl,
    this.faceSwapMode,
    this.createdPresetId,
    this.aspectRatio = '3:4',
  });

  final String id;
  final String presetId;
  final String? presetTitle;
  final String? presetPreviewUrl;
  final GenerationStatus status;
  final String statusMessage;
  final String? resultImageUrl;
  final String? errorMessage;
  final String userPhotoPath;
  final String prompt;
  final DateTime createdAt;
  final PhotosessionProvider provider;
  final GenerationTaskType taskType;
  final String? referenceImageUrl;
  final FaceSwapMode? faceSwapMode;
  final String? createdPresetId;
  final String aspectRatio;

  bool get isActive =>
      status != GenerationStatus.completed &&
      status != GenerationStatus.error;

  bool get isCompleted => status == GenerationStatus.completed;
  bool get isError => status == GenerationStatus.error;

  String get displayError {
    if (errorMessage == null) return '';
    return normalizePhotosessionErrorMessage(errorMessage);
  }
}
