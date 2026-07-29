import 'dart:io';

/// Интерфейс для сервисов распознавания объектов на изображениях
/// Позволяет абстрагироваться от конкретной реализации (Google Cloud Vision, ML Kit, и т.д.)
abstract class ImageRecognitionService {
  /// Распознает объекты на изображении и возвращает список обнаруженных объектов
  /// [imageFile] - файл изображения для анализа
  Future<List<RecognizedObject>> recognizeObjects(File imageFile);

  /// Возвращает наиболее вероятное название блюда на основе распознанных объектов
  /// [objects] - список распознанных объектов
  Future<String?> identifyFoodName(List<RecognizedObject> objects);
}

/// Модель распознанного объекта
class RecognizedObject {
  /// Название объекта
  final String label;

  /// Уверенность в распознавании (0.0 - 1.0)
  final double confidence;

  /// Метаданные объекта (дополнительная информация от API)
  final Map<String, dynamic>? metadata;

  RecognizedObject({
    required this.label,
    required this.confidence,
    this.metadata,
  });

  @override
  String toString() {
    return 'RecognizedObject{label: $label, confidence: $confidence}';
  }
}
