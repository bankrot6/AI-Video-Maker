import 'speech_recognition_service.dart';
import 'web_speech_recognition_service.dart';
import 'google_speech_recognition_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Фабрика для создания сервисов распознавания речи
class SpeechRecognitionFactory {
  /// Создать сервис распознавания речи указанного типа
  ///
  /// [type] - тип сервиса распознавания речи
  /// [apiKey] - API ключ (для сервисов, которые требуют аутентификацию)
  static SpeechRecognitionService create({
    SpeechRecognitionType type = SpeechRecognitionType.webSpeech,
    String? apiKey,
  }) {
    // Пробуем получить API ключ из .env если он не передан явно
    final googleSpeechApiKey = apiKey ?? dotenv.env['GOOGLE_SPEECH_API_KEY'];

    switch (type) {
      case SpeechRecognitionType.webSpeech:
        return WebSpeechRecognitionService();
      case SpeechRecognitionType.googleCloud:
        return GoogleSpeechRecognitionService(apiKey: googleSpeechApiKey);
    }
  }
}
