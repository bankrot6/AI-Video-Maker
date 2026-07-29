import 'dart:io';

class VideoGenerationResult {
  final File? file;
  final String? remoteUri;
  final String? errorMessage;

  const VideoGenerationResult({
    this.file,
    this.remoteUri,
    this.errorMessage,
  });

  bool get isSuccess => file != null || remoteUri != null;
}

abstract class VideoGenerationService {
  Future<bool> isAvailable();

  Future<VideoGenerationResult> generateVideo({
    required String prompt,
    File? referenceImage,
    int durationSeconds,
    String aspectRatio,
    int sampleCount,
    String? negativePrompt,
    bool enhancePrompt,
  });
}

class VideoGenerationRouter implements VideoGenerationService {
  final List<VideoGenerationService> _services;

  VideoGenerationRouter({required List<VideoGenerationService> services})
      : _services = List.unmodifiable(services);

  @override
  Future<bool> isAvailable() async {
    for (final service in _services) {
      if (await service.isAvailable()) return true;
    }
    return false;
  }

  @override
  Future<VideoGenerationResult> generateVideo({
    required String prompt,
    File? referenceImage,
    int durationSeconds = 6,
    String aspectRatio = '9:16',
    int sampleCount = 1,
    String? negativePrompt,
    bool enhancePrompt = true,
  }) async {
    for (final service in _services) {
      if (!await service.isAvailable()) continue;
      return service.generateVideo(
        prompt: prompt,
        referenceImage: referenceImage,
        durationSeconds: durationSeconds,
        aspectRatio: aspectRatio,
        sampleCount: sampleCount,
        negativePrompt: negativePrompt,
        enhancePrompt: enhancePrompt,
      );
    }
    return const VideoGenerationResult(
      errorMessage: 'Сервис генерации видео не настроен.',
    );
  }
}
