import 'dart:io';

class AiImageGenerationResult {
  final File? file;
  final List<File> files;
  final String? errorMessage;

  const AiImageGenerationResult({
    this.file,
    this.files = const [],
    this.errorMessage,
  });

  bool get isSuccess => file != null || files.isNotEmpty;

  File? get primaryFile => file ?? (files.isNotEmpty ? files.first : null);
}

abstract class AiImageGenerationService {
  Future<bool> isAvailable();

  Future<AiImageGenerationResult> generateImageFromPrompt(
    String prompt, {
    int batchSize = 1,
  });

  Future<AiImageGenerationResult> generateImageFromPromptWithReference({
    required String prompt,
    required File referenceImage,
  });
}

class AiImageGenerationRouter implements AiImageGenerationService {
  final List<AiImageGenerationService> _services;

  AiImageGenerationRouter({required List<AiImageGenerationService> services})
      : _services = List.unmodifiable(services);

  @override
  Future<bool> isAvailable() async {
    for (final service in _services) {
      if (await service.isAvailable()) return true;
    }
    return false;
  }

  @override
  Future<AiImageGenerationResult> generateImageFromPrompt(
    String prompt, {
    int batchSize = 1,
  }) async {
    for (final service in _services) {
      if (!await service.isAvailable()) continue;
      return service.generateImageFromPrompt(
        prompt,
        batchSize: batchSize,
      );
    }
    return const AiImageGenerationResult(
      errorMessage: 'Сервис генерации изображений не настроен.',
    );
  }

  @override
  Future<AiImageGenerationResult> generateImageFromPromptWithReference({
    required String prompt,
    required File referenceImage,
  }) async {
    for (final service in _services) {
      if (!await service.isAvailable()) continue;
      return service.generateImageFromPromptWithReference(
        prompt: prompt,
        referenceImage: referenceImage,
      );
    }
    return const AiImageGenerationResult(
      errorMessage: 'Сервис генерации изображений не настроен.',
    );
  }
}
