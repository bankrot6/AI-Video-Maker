import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Locale;
import 'speech_recognition_service.dart';

/// Реализация сервиса распознавания речи с использованием Web Speech API
class WebSpeechRecognitionService implements SpeechRecognitionService {
  final String _recognizedText = '';
  bool _isListening = false;
  Function(String)? _onRecognitionComplete;
  String? _lastRecordingPath;

  @override
  Future<bool> isAvailable() async {
    // Web Speech API доступен только в веб-среде
    return kIsWeb;
  }

  @override
  Future<void> startListening({Locale? locale}) async {
    if (!kIsWeb) {
      throw UnsupportedError('Web Speech API доступен только в браузере');
    }

    // В реальной имплементации вызов JS-интерфейса для Web Speech API
    _isListening = true;

    // Используем переданную локаль, если она указана
    final String? languageCode = locale?.languageCode;
    if (kDebugMode) {
      print(
          '🎤 Web Speech API: начало прослушивания... Язык: ${languageCode ?? "по умолчанию"}');
    }
  }

  @override
  Future<void> stopListening() async {
    await stopRecording(transcribe: true);
  }

  @override
  Future<String?> stopRecording({bool transcribe = true}) async {
    if (!_isListening) return _lastRecordingPath;

    _isListening = false;

    if (kDebugMode) {
      print('🎤 Web Speech API: прослушивание остановлено');
    }

    if (transcribe && _onRecognitionComplete != null) {
      _onRecognitionComplete!(_recognizedText);
    }

    return _lastRecordingPath;
  }

  @override
  String getRecognizedText() {
    return _recognizedText;
  }

  @override
  void setRecognitionCompleteHandler(Function(String) onComplete) {
    _onRecognitionComplete = onComplete;
  }

  @override
  void setPreserveAudioFile(bool preserve) {
    // В вебе не поддерживается сохранение аудиофайла в текущей реализации
  }

  @override
  String? getLastRecordingPath() {
    return _lastRecordingPath;
  }

  @override
  Future<String> transcribeFile(String audioFilePath, {Locale? locale}) async {
    // В веб-реализации транскрибация файла не поддерживается
    return '';
  }
}
