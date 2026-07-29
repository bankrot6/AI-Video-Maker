import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'speech_recognition/speech_recognition_factory.dart';
import 'speech_recognition/speech_recognition_service.dart';
import 'screenshot/screenshot_theme.dart';

final speechRecognitionServiceProvider =
    Provider<SpeechRecognitionService>((ref) {
  final serviceType = kIsWeb
      ? SpeechRecognitionType.webSpeech
      : SpeechRecognitionType.googleCloud;

  try {
    final service = SpeechRecognitionFactory.create(type: serviceType);
    service.isAvailable().then((available) {
      if (!available && kDebugMode) {
        debugPrint('🎤 Предупреждение: Сервис распознавания речи недоступен');
      }
    });
    return service;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('🎤 Ошибка при создании сервиса распознавания речи: $e');
    }
    return SpeechRecognitionFactory.create(
      type: SpeechRecognitionType.webSpeech,
    );
  }
});

final screenshotThemeProvider = Provider<ScreenshotTheme>((ref) {
  return ScreenshotTheme();
});
