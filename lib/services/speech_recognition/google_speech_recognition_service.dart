import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Locale;
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'speech_recognition_service.dart';

/// Реализация сервиса распознавания речи с использованием Google Cloud Speech-to-Text API
class GoogleSpeechRecognitionService implements SpeechRecognitionService {
  final String? apiKey;
  final _recorder = AudioRecorder();
  String _recognizedText = '';
  bool _isListening = false;
  Function(String)? _onRecognitionComplete;
  String? _tempFilePath;
  String? _lastRecordingPath;
  bool _preserveAudioFile = false;
  // Зарезервировано под будущие кодеки
  // Сохраняем текущую локаль, которую можно установить при запуске распознавания
  Locale? _currentLocale;

  GoogleSpeechRecognitionService({this.apiKey});

  @override
  Future<bool> isAvailable() async {
    // Проверка наличия API ключа
    if (apiKey == null || apiKey!.isEmpty) {
      if (kDebugMode) {
        print('🎤 Google Speech: API ключ отсутствует');
      }
      // Возвращаем true для тестового режима
      return true;
    }

    try {
      // Явно запрашиваем разрешение на использование микрофона
      final hasPermission = await _recorder.hasPermission();

      if (!hasPermission) {
        if (kDebugMode) {
          print('🎤 Google Speech: нет разрешения на использование микрофона');
        }
        return false;
      }

      if (kDebugMode) {
        print('🎤 Google Speech: сервис доступен, разрешения получены');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('🎤 Google Speech: ошибка при проверке доступности: $e');
      }
      return false;
    }
  }

  @override
  Future<void> startListening({Locale? locale}) async {
    // Сохраняем предоставленную локаль для последующего использования при отправке аудио
    _currentLocale = locale;

    if (apiKey == null || apiKey!.isEmpty) {
      throw Exception('Google Cloud Speech API ключ не предоставлен');
    }

    // Проверяем и запрашиваем необходимые разрешения
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (kDebugMode) {
        print('🎤 Google Speech: запрашиваем разрешение на доступ к микрофону');
      }

      // На iOS и Android это вызовет системный диалог с запросом разрешения
      // если пользователь еще не предоставил его
      final permissionResult = await _recorder.hasPermission();

      if (!permissionResult) {
        throw Exception('Разрешение на запись аудио не предоставлено');
      }
    }

    // Создаем временный файл для записи
    final tempDir = await getTemporaryDirectory();
    _tempFilePath =
        '${tempDir.path}/speech_${DateTime.now().millisecondsSinceEpoch}.wav';

    if (kDebugMode) {
      print('🎤 Google Speech: начало записи в $_tempFilePath');
    }

    // Начинаем запись в файл
    try {
      // Для Google Speech API оптимально подходит LINEAR16 формат
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder
              .pcm16bits, // LINEAR16 WAV. Внимание: bitRate не задаём для PCM
          sampleRate: 16000,
          numChannels: 1, // моно
        ),
        path: _tempFilePath!,
      );
      _isListening = true;

      if (kDebugMode) {
        print('🎤 Google Speech: запись начата успешно с LINEAR16 кодеком');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎤 Google Speech: ошибка при начале записи: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> stopListening() async {
    await stopRecording(transcribe: true);
  }

  @override
  Future<String?> stopRecording({bool transcribe = true}) async {
    if (!_isListening) return _lastRecordingPath ?? _tempFilePath;

    _isListening = false;
    String? path;

    try {
      path = await _recorder.stop();

      if (path != null && path.isNotEmpty) {
        _lastRecordingPath = path;
      }

      if (transcribe && path != null && path.isNotEmpty) {
        if (kDebugMode) {
          print('🎤 Google Speech: запись завершена, отправка на анализ...');
        }

        final result = await _sendAudioToGoogleSpeech(path);
        _recognizedText = result;

        if (_onRecognitionComplete != null) {
          _onRecognitionComplete!(_recognizedText);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎤 Google Speech: ошибка при остановке записи: $e');
      }
      rethrow;
    } finally {
      if (!_preserveAudioFile) {
        _cleanupTempFile();
      }
    }

    return path;
  }

  /// Отправляет аудиофайл в Google Cloud Speech API и возвращает распознанный текст
  Future<String> _sendAudioToGoogleSpeech(String audioFilePath) async {
    try {
      if (kDebugMode) {
        print('🎤 Подготовка аудиофайла для отправки: $audioFilePath');
      }

      // Чтение аудиофайла
      final File audioFile = File(audioFilePath);

      // Проверяем существование файла
      if (!await audioFile.exists()) {
        throw Exception('Аудиофайл не найден: $audioFilePath');
      }

      final bytes = await audioFile.readAsBytes();

      // Проверяем размер файла
      if (bytes.isEmpty) {
        throw Exception('Аудиофайл пуст');
      }

      if (kDebugMode) {
        print('🎤 Размер аудиофайла: ${bytes.length} bytes');
      }

      final base64Audio = base64Encode(bytes);

      // Определяем язык для распознавания на основе переданной локали или языка устройства
      String baseLanguageCode;
      String primaryLanguageCode;
      String alternativeLanguageCode;

      if (_currentLocale != null) {
        // Используем локаль, переданную при запуске распознавания
        baseLanguageCode = _currentLocale!.languageCode;
        primaryLanguageCode =
            '$baseLanguageCode-${_currentLocale!.countryCode ?? baseLanguageCode.toUpperCase()}';
      } else {
        // Если локаль не задана, используем язык устройства
        final deviceLocale = ui.PlatformDispatcher.instance.locale;
        baseLanguageCode = deviceLocale.languageCode;
        primaryLanguageCode =
            '$baseLanguageCode-${deviceLocale.countryCode ?? baseLanguageCode.toUpperCase()}';
      }

      // Указываем альтернативный язык в зависимости от основного
      alternativeLanguageCode = baseLanguageCode == 'ru' ? 'en-US' : 'ru-RU';

      if (kDebugMode) {
        print(
            '🎤 Используемый язык для распознавания: $primaryLanguageCode, альтернативный: $alternativeLanguageCode');
      }

      // Словарь контекстных фраз в зависимости от языка
      List<String> contextPhrases = [];
      if (baseLanguageCode == 'ru') {
        contextPhrases = [
          'борщ',
          'суп',
          'салат',
          'каша',
          'картофель',
          'мясо',
          'рыба',
          'овощи',
          'фрукты',
          'десерт',
          'напиток',
          'завтрак',
          'обед',
          'ужин',
          'украинский',
          'русский',
          'грибной',
          'куриный',
          'говядина',
          'свинина'
        ];
      } else {
        contextPhrases = [
          'soup',
          'salad',
          'steak',
          'chicken',
          'fish',
          'pork',
          'beef',
          'vegetable',
          'fruit',
          'dessert',
          'drink',
          'breakfast',
          'lunch',
          'dinner',
          'snack',
          'burger',
          'pizza',
          'pasta',
          'rice',
          'bread',
          'sandwich',
          'sauce',
          'cheese',
          'milk',
          'yogurt',
          'eggs',
          'bacon'
        ];
      }

      // Оптимальные параметры для высококачественного распознавания речи с учетом языка устройства
      final config = {
        'encoding': 'LINEAR16',
        'sampleRateHertz': 16000,
        'languageCode': primaryLanguageCode,
        'model':
            'command_and_search', // Более точная модель для коротких команд
        'audioChannelCount': 1,
        'enableAutomaticPunctuation': true,
        'useEnhanced': true,
        'speechContexts': [
          {
            'phrases': contextPhrases,
            'boost': 20 // Увеличиваем вероятность распознавания кулинарных слов
          }
        ],
        'alternativeLanguageCodes': [
          alternativeLanguageCode
        ], // Используем альтернативный язык как запасной вариант
      };

      if (kDebugMode) {
        print(
            '🎤 Отправка запроса в Google Speech API с конфигурацией: $config');
      }

      // Формируем запрос к Google Cloud Speech API
      final response = await http.post(
        Uri.parse(
            'https://speech.googleapis.com/v1/speech:recognize?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'config': config,
          'audio': {
            'content': base64Audio,
          },
        }),
      );

      if (kDebugMode) {
        print('🎤 Google Speech API статус: ${response.statusCode}');
        print('🎤 Google Speech API ответ: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Проверка наличия результатов в ответе
        if (data['results'] == null || data['results'].isEmpty) {
          if (kDebugMode) {
            print(
                '🎤 API вернул пустые результаты, возможно речь не распознана');
          }
          return ''; // Возвращаем пустую строку вместо тестового режима
        }

        if (data['results'] != null && data['results'].isNotEmpty) {
          final alternatives = data['results'][0]['alternatives'];
          if (alternatives != null && alternatives.isNotEmpty) {
            final transcript = alternatives[0]['transcript'] ?? '';

            if (kDebugMode) {
              print('🎤 Распознанный текст: "$transcript"');
            }

            return transcript;
          }
        }

        return ''; // Если структура ответа не содержит результатов
      } else {
        if (kDebugMode) {
          print('🎤 Ошибка Google Speech API: ${response.body}');
        }
        throw Exception('Ошибка распознавания: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎤 Ошибка при отправке аудио в Google Speech API: $e');
      }
      throw Exception('Ошибка при обработке аудио: $e');
    }
  }

  /// Удаляет временный файл записи
  void _cleanupTempFile() {
    if (_tempFilePath != null) {
      try {
        final file = File(_tempFilePath!);
        if (file.existsSync()) {
          file.deleteSync();
          if (kDebugMode) {
            print('🎤 Временный файл записи удален: $_tempFilePath');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('🎤 Ошибка при удалении временного файла: $e');
        }
      }
    }
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
    _preserveAudioFile = preserve;
  }

  @override
  String? getLastRecordingPath() {
    return _lastRecordingPath ?? _tempFilePath;
  }

  @override
  Future<String> transcribeFile(String audioFilePath, {Locale? locale}) async {
    // Устанавливаем локаль для транскрибации, если передана
    _currentLocale = locale ?? _currentLocale;
    return await _sendAudioToGoogleSpeech(audioFilePath);
  }
}
