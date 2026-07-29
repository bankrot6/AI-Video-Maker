import 'dart:io';

class AiImageCaptioningResult {
  final String? caption;
  final String? errorMessage;

  const AiImageCaptioningResult({this.caption, this.errorMessage});

  bool get isSuccess => (caption ?? '').trim().isNotEmpty;
}

abstract class AiImageCaptioningService {
  Future<bool> isAvailable();

  Future<AiImageCaptioningResult> generateCaptionFromImage(File imageFile);
}

class AiImageCaptioningRouter implements AiImageCaptioningService {
  final List<AiImageCaptioningService> _services;

  AiImageCaptioningRouter({required List<AiImageCaptioningService> services})
      : _services = List.unmodifiable(services);

  @override
  Future<bool> isAvailable() async {
    for (final service in _services) {
      if (await service.isAvailable()) return true;
    }
    return false;
  }

  @override
  Future<AiImageCaptioningResult> generateCaptionFromImage(
    File imageFile,
  ) async {
    for (final service in _services) {
      if (!await service.isAvailable()) continue;
      return service.generateCaptionFromImage(imageFile);
    }
    return const AiImageCaptioningResult(
      errorMessage: 'Сервис подписи изображений не настроен.',
    );
  }
}
