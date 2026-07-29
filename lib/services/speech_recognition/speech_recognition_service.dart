import 'dart:ui';

/// Интерфейс для сервисов распознавания речи
/// Позволяет абстрагироваться от конкретной реализации (Google Cloud Speech, Web Speech API и т.д.)
abstract class SpeechRecognitionService {
  /// Запустить распознавание речи
  /// [locale] - Локаль для распознавания речи (опционально)
  Future<void> startListening({Locale? locale});

  /// Остановить распознавание речи
  Future<void> stopListening();

  Future<String?> stopRecording({bool transcribe = true});

  /// Проверить доступность сервиса распознавания речи
  Future<bool> isAvailable();

  /// Получить текущие результаты распознавания
  String getRecognizedText();

  /// Установить обработчик завершения распознавания
  void setRecognitionCompleteHandler(Function(String) onComplete);

  /// Включить сохранение аудиофайла последней записи (для голосовых сообщений в чате)
  void setPreserveAudioFile(bool preserve);

  /// Получить путь к последнему сохраненному аудиофайлу записи (если preserve=true)
  String? getLastRecordingPath();

  /// Выполнить распознавание речи по готовому аудиофайлу
  Future<String> transcribeFile(String audioFilePath, {Locale? locale});
}

/// Типы сервисов распознавания речи
enum SpeechRecognitionType {
  /// Web Speech API (для браузеров)
  webSpeech,

  /// Google Cloud Speech-to-Text API
  googleCloud,
}
