import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../utils/text_cleaner.dart';
import 'base_tts_service.dart';
import 'speech_chunker.dart';

class GoogleTTSService implements BaseTTSService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentAudioPath;
  bool _isPlaying = false;
  bool _isProcessing = false;

  final List<_TextChunk> _queue = [];
  final List<String> _audioFiles = [];
  bool _isQueueActive = false;
  StreamSubscription? _playerCompleteSubscription;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get hasQueuedItems => _queue.isNotEmpty || _audioFiles.isNotEmpty;

  @override
  int get queueSize => _queue.length;

  @override
  Future<void> speak(String text,
      {String languageCode = 'ru-RU', bool useSSML = false}) async {
    try {
      debugPrint('🔊 TTS: Начало синтеза речи (WaveNet, OGG_OPUS)');
      debugPrint(
          '🔊 TTS: Текст: ${text.substring(0, text.length > 100 ? 100 : text.length)}...');

      if (_isPlaying) {
        await stop();
      }

      final audioPath = await _synthesizeSpeech(
        text,
        languageCode: languageCode,
        useSSML: useSSML,
      );

      if (audioPath == null) {
        throw Exception('Не удалось синтезировать речь');
      }

      _currentAudioPath = audioPath;

      debugPrint('🔊 TTS: Начало воспроизведения');

      _isPlaying = true;

      final completer = Completer<void>();

      _playerCompleteSubscription?.cancel();
      _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
        _isPlaying = false;
        _cleanupAudioFile();
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      await _audioPlayer.play(DeviceFileSource(audioPath));

      debugPrint('✅ TTS: Воспроизведение началось');

      await completer.future;
    } catch (e) {
      _isPlaying = false;
      debugPrint('❌ TTS: Ошибка: $e');
      rethrow;
    }
  }

  String _getVoiceName(String languageCode) {
    switch (languageCode) {
      case 'ru-RU':
        return 'ru-RU-Wavenet-E';
      case 'en-US':
        return 'en-US-Neural2-F';
      case 'en-GB':
        return 'en-GB-Neural2-F';
      case 'de-DE':
        return 'de-DE-Neural2-C';
      case 'fr-FR':
        return 'fr-FR-Neural2-C';
      case 'es-ES':
        return 'es-ES-Neural2-C';
      case 'it-IT':
        return 'it-IT-Neural2-A';
      case 'ja-JP':
        return 'ja-JP-Neural2-C';
      case 'ko-KR':
        return 'ko-KR-Neural2-C';
      case 'zh-CN':
        return 'cmn-CN-Neural2-A';
      default:
        return 'en-US-Neural2-F';
    }
  }

  String _getGender(String languageCode) {
    switch (languageCode) {
      case 'ru-RU':
        return 'FEMALE';
      case 'en-US':
        return 'FEMALE';
      case 'en-GB':
        return 'FEMALE';
      case 'de-DE':
        return 'FEMALE';
      case 'fr-FR':
        return 'FEMALE';
      case 'es-ES':
        return 'FEMALE';
      case 'it-IT':
        return 'FEMALE';
      case 'ja-JP':
        return 'FEMALE';
      case 'ko-KR':
        return 'FEMALE';
      case 'zh-CN':
        return 'FEMALE';
      default:
        return 'FEMALE';
    }
  }

  @override
  Future<void> stop() async {
    try {
      debugPrint('🔊 TTS: Остановка воспроизведения');

      _isPlaying = false;

      _playerCompleteSubscription?.cancel();
      _playerCompleteSubscription = null;

      await _audioPlayer.stop();

      _cleanupAudioFile();

      debugPrint('✅ TTS: Воспроизведение остановлено');
    } catch (e) {
      debugPrint('❌ TTS: Ошибка при остановке: $e');
      _isPlaying = false;
    }
  }

  @override
  Future<void> pause() async {
    try {
      debugPrint('🔊 TTS: Пауза воспроизведения');
      await _audioPlayer.pause();
      _isPlaying = false;
    } catch (e) {
      debugPrint('❌ TTS: Ошибка при паузе: $e');
    }
  }

  @override
  Future<void> resume() async {
    try {
      debugPrint('🔊 TTS: Возобновление воспроизведения');
      await _audioPlayer.resume();
      _isPlaying = true;
    } catch (e) {
      debugPrint('❌ TTS: Ошибка при возобновлении: $e');
    }
  }

  void _cleanupAudioFile() {
    if (_currentAudioPath != null) {
      try {
        final file = File(_currentAudioPath!);
        if (file.existsSync()) {
          file.deleteSync();
          debugPrint('🧹 TTS: Аудио файл удалён: $_currentAudioPath');
        }
      } catch (e) {
        debugPrint('❌ TTS: Ошибка при удалении файла: $e');
      }
      _currentAudioPath = null;
    }
  }

  String _prepareSSMLText(String text) {
    String cleaned = TextCleaner.cleanForSpeech(text);

    // Разбиваем на предложения для добавления естественных пауз
    final sentences = cleaned.split(RegExp(r'[.!?]\s+'));

    final ssmlParts = <String>[];

    for (var sentence in sentences) {
      if (sentence.trim().isEmpty) continue;

      // Определяем тип предложения для настройки интонации
      String prosody = '<prosody rate="0.92" pitch="-1.5st">';

      // Вопросы произносим с чуть более высоким тоном
      if (sentence.trim().endsWith('?')) {
        prosody = '<prosody rate="0.90" pitch="-0.5st">';
      }
      // Восклицания - с чуть большей энергией
      else if (sentence.trim().endsWith('!')) {
        prosody = '<prosody rate="0.95" pitch="-1.0st">';
      }

      ssmlParts.add('$prosody${sentence.trim()}.</prosody>');
      // Добавляем естественные паузы между предложениями
      ssmlParts.add('<break time="650ms"/>');
    }

    // Убираем последнюю лишнюю паузу
    if (ssmlParts.isNotEmpty && ssmlParts.last.contains('break')) {
      ssmlParts.removeLast();
    }

    return '<speak>${ssmlParts.join(' ')}</speak>';
  }

  @override
  Future<void> addToQueue(String text, {String languageCode = 'ru-RU'}) async {
    if (text.isEmpty || text.length < 20) {
      debugPrint('⏭️ TTS_QUEUE: Текст слишком короткий, пропускаем');
      return;
    }

    final chunks = _chunkText(text);

    for (final chunkText in chunks) {
      final chunk = _TextChunk(
        text: chunkText,
        languageCode: languageCode,
      );
      _queue.add(chunk);
      debugPrint(
          '➕ TTS_QUEUE: Добавлен блок в очередь (${chunkText.length} символов)');
    }

    if (!_isQueueActive) {
      _startQueue();
    }
  }

  List<String> _chunkText(String text) {
    final normalized = SpeechChunker.normalize(text);
    if (normalized.isEmpty) return const <String>[];
    final extracted = SpeechChunker.extractFromBuffer(
      normalized,
      flush: true,
      minChunkChars: 70,
      maxChunkChars: 320,
      softLookAheadChars: 140,
    );
    debugPrint(
        '📦 TTS_QUEUE: Текст разбит на ${extracted.chunks.length} блоков');
    return extracted.chunks;
  }

  Future<void> _startQueue() async {
    if (_isQueueActive) return;

    _isQueueActive = true;
    debugPrint('▶️ TTS_QUEUE: Запуск очереди озвучки');

    while (_isQueueActive && (_queue.isNotEmpty || _audioFiles.isNotEmpty)) {
      // СТРАТЕГИЯ: Look-ahead buffering
      // Начинаем подготовку следующего блока, пока есть текст в очереди
      // и меньше 2 готовых аудиофайлов (держим буфер)
      if (_queue.isNotEmpty && _audioFiles.length < 2 && !_isProcessing) {
        // Асинхронно подготавливаем следующий блок, не блокируя воспроизведение
        _prepareNextChunk();
      }

      if (_audioFiles.isNotEmpty && !_isPlaying) {
        await _playNextAudioFile();
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    debugPrint('⏹️ TTS_QUEUE: Очередь завершена');
    _isQueueActive = false;
  }

  Future<void> _prepareNextChunk() async {
    if (_queue.isEmpty || _isProcessing) return;

    _isProcessing = true;
    final chunk = _queue.removeAt(0);

    try {
      debugPrint(
          '🔄 TTS_QUEUE: Подготовка блока (${chunk.text.length} символов)');

      final audioPath = await _synthesizeSpeech(
        chunk.text,
        languageCode: chunk.languageCode,
      );

      if (audioPath != null) {
        _audioFiles.add(audioPath);
        debugPrint('✅ TTS_QUEUE: Блок подготовлен: $audioPath');
      }
    } catch (e) {
      debugPrint('❌ TTS_QUEUE: Ошибка подготовки блока: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _playNextAudioFile() async {
    if (_audioFiles.isEmpty || _isPlaying) return;

    final filePath = _audioFiles.removeAt(0);

    try {
      debugPrint('🔊 TTS_QUEUE: Воспроизведение: $filePath');

      _isPlaying = true;
      _currentAudioPath = filePath;

      final completer = Completer<void>();

      _playerCompleteSubscription?.cancel();
      _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
        debugPrint('✅ TTS_QUEUE: Воспроизведение завершено');
        _isPlaying = false;
        _cleanupAudioFile();
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      await _audioPlayer.play(DeviceFileSource(filePath));

      await completer.future;
    } catch (e) {
      debugPrint('❌ TTS_QUEUE: Ошибка воспроизведения: $e');
      _isPlaying = false;
      _cleanupAudioFile();
    }
  }

  Future<String?> _synthesizeSpeech(
    String text, {
    String languageCode = 'ru-RU',
    bool useSSML = false,
  }) async {
    try {
      final processedText =
          useSSML ? _prepareSSMLText(text) : TextCleaner.cleanForSpeech(text);

      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      if (apiKey == null || apiKey.isEmpty || apiKey.contains('your_')) {
        debugPrint('❌ TTS: API ключ не настроен');
        throw Exception('Google Maps API ключ не настроен в .env файле');
      }

      final url = Uri.parse(
          'https://texttospeech.googleapis.com/v1/text:synthesize?key=$apiKey');

      final voiceName = _getVoiceName(languageCode);

      final inputType = useSSML ? 'ssml' : 'text';
      final requestBody = jsonEncode({
        'input': {inputType: processedText},
        'voice': {
          'languageCode': languageCode,
          'name': voiceName,
          'ssmlGender': _getGender(languageCode),
        },
        'audioConfig': {
          'audioEncoding': 'OGG_OPUS',
          'pitch': -1.5,
          'speakingRate': 0.92,
          'volumeGainDb': 3.0,
          'effectsProfileId': [
            'headphone-class-device',
            'large-home-entertainment-class-device',
          ],
          'sampleRateHertz': 48000,
        },
      });

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );

      if (response.statusCode != 200) {
        debugPrint('❌ TTS: Ошибка API: ${response.statusCode}');
        debugPrint('❌ TTS: Ответ: ${response.body}');
        throw Exception('Ошибка синтеза речи: ${response.statusCode}');
      }

      final responseData = jsonDecode(response.body);
      final audioContent = responseData['audioContent'] as String;

      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/tts_$timestamp.ogg';

      final audioBytes = base64Decode(audioContent);
      final file = File(filePath);
      await file.writeAsBytes(audioBytes);

      debugPrint('💾 TTS: Аудио файл сохранён: $filePath');

      return filePath;
    } catch (e) {
      debugPrint('❌ TTS: Ошибка синтеза: $e');
      return null;
    }
  }

  @override
  Future<void> clearQueue() async {
    debugPrint('🧹 TTS_QUEUE: Очистка очереди');
    debugPrint('🧹 TTS_QUEUE: - Элементов в очереди: ${_queue.length}');
    debugPrint('🧹 TTS_QUEUE: - Аудиофайлов готово: ${_audioFiles.length}');
    debugPrint('🧹 TTS_QUEUE: - Сейчас играет: $_isPlaying');
    debugPrint('🧹 TTS_QUEUE: - Очередь активна: $_isQueueActive');

    _isQueueActive = false;
    _isProcessing = false;

    if (_isPlaying) {
      debugPrint('🧹 TTS_QUEUE: Остановка текущего воспроизведения');
      await stop();
    }

    _queue.clear();
    debugPrint('🧹 TTS_QUEUE: Очередь текстов очищена');

    final fileCount = _audioFiles.length;
    for (final audioPath in _audioFiles) {
      try {
        final file = File(audioPath);
        if (file.existsSync()) {
          file.deleteSync();
          debugPrint('🧹 TTS_QUEUE: Удален файл: $audioPath');
        }
      } catch (e) {
        debugPrint('❌ TTS_QUEUE: Ошибка удаления файла: $e');
      }
    }

    _audioFiles.clear();

    debugPrint(
        '✅ TTS_QUEUE: Очередь полностью очищена (удалено файлов: $fileCount)');
  }

  @override
  void dispose() {
    clearQueue();
    _playerCompleteSubscription?.cancel();
    _audioPlayer.dispose();
    _cleanupAudioFile();
  }
}

class _TextChunk {
  final String text;
  final String languageCode;

  _TextChunk({
    required this.text,
    required this.languageCode,
  });
}
