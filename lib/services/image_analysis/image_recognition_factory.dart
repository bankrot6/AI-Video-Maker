import 'image_recognition_service.dart';
import 'google_vision_recognition_service.dart';

/// Тип распознавания изображений, используемый в приложении
enum RecognitionServiceType {
  /// Google Cloud Vision API
  googleVision,

  /// Возможность добавить другие провайдеры в будущем
  // Azure, AWS, etc.
}

/// Фабрика для создания экземпляров сервисов распознавания изображений
/// Позволяет легко переключаться между разными реализациями
class ImageRecognitionFactory {
  /// Создать сервис распознавания изображений указанного типа
  /// [type] - тип сервиса
  /// [apiKey] - опциональный API ключ
  static ImageRecognitionService createService({
    RecognitionServiceType type = RecognitionServiceType.googleVision,
    String? apiKey,
  }) {
    switch (type) {
      case RecognitionServiceType.googleVision:
        return GoogleVisionRecognitionService(apiKey: apiKey);
      // Будущие реализации могут быть добавлены здесь
      // case RecognitionServiceType.azure:
      //   return AzureRecognitionService(apiKey: apiKey);
    }
  }
}
