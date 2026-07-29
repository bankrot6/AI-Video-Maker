import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../utils/text_cleaner.dart';
import 'base_tts_service.dart';
import 'speech_chunker.dart';

class TTSVoice {
  final String name;
  final String locale;

  const TTSVoice({required this.name, required this.locale});

  String get displayName {
    final parts = name.split('.');
    final shortName = parts.length > 1 ? parts.last : name;
    return '$shortName ($locale)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TTSVoice &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          locale == other.locale;

  @override
  int get hashCode => name.hashCode ^ locale.hashCode;
}

class FlutterTTSService implements BaseTTSService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;
  bool _isInitialized = false;
  TTSVoice? _currentVoice;
  double _speechRate = 0.5;
  double _pitch = 1.0;

  final List<_TextChunk> _queue = [];
  bool _isQueueActive = false;
  bool _isQueueStopped = false;
  int _queueSessionId = 0;

  String? _currentPlayingText;
  String _currentLanguageCode = 'ru-RU';

  FlutterTts get flutterTts => _flutterTts;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get hasQueuedItems => _queue.isNotEmpty || _isQueueActive;

  @override
  int get queueSize => _queue.length;

  TTSVoice? get currentVoice => _currentVoice;
  double get speechRate => _speechRate;
  double get pitch => _pitch;

  Future<List<TTSVoice>> getAvailableVoices() async {
    await _ensureInitialized();
    try {
      final voices = await _flutterTts.getVoices;
      if (voices == null) return [];

      final voiceList = <TTSVoice>[];
      for (final voice in voices) {
        if (voice is Map) {
          final name = voice['name']?.toString() ?? '';
          final locale = voice['locale']?.toString() ?? '';
          if (name.isNotEmpty && locale.isNotEmpty) {
            voiceList.add(TTSVoice(name: name, locale: locale));
          }
        }
      }

      voiceList.sort((a, b) => a.locale.compareTo(b.locale));
      debugPrint('🎤 FLUTTER_TTS: Найдено ${voiceList.length} голосов');
      return voiceList;
    } catch (e) {
      debugPrint('❌ FLUTTER_TTS: Ошибка получения голосов: $e');
      return [];
    }
  }

  Future<List<TTSVoice>> getVoicesForLanguage(String languageCode) async {
    final allVoices = await getAvailableVoices();
    final langPrefix = languageCode.split('-').first.toLowerCase();

    return allVoices.where((voice) {
      final voiceLangPrefix = voice.locale.split('-').first.toLowerCase();
      return voiceLangPrefix == langPrefix;
    }).toList();
  }

  Future<void> setVoice(TTSVoice voice) async {
    await _ensureInitialized();
    try {
      await _flutterTts.setVoice({'name': voice.name, 'locale': voice.locale});
      _currentVoice = voice;
      debugPrint('🎤 FLUTTER_TTS: Голос установлен: ${voice.displayName}');
    } catch (e) {
      debugPrint('❌ FLUTTER_TTS: Ошибка установки голоса: $e');
    }
  }

  Future<void> setSpeechRateValue(double rate,
      {bool restartPlayback = true}) async {
    await _ensureInitialized();
    final oldRate = _speechRate;
    _speechRate = rate.clamp(0.0, 1.0);
    await _flutterTts.setSpeechRate(_speechRate);
    debugPrint('⚡ FLUTTER_TTS: Скорость установлена: $_speechRate');

    if (restartPlayback && _isPlaying && (oldRate - _speechRate).abs() > 0.01) {
      await _restartCurrentPlayback();
    }
  }

  Future<void> setPitchValue(double pitchValue,
      {bool restartPlayback = true}) async {
    await _ensureInitialized();
    final oldPitch = _pitch;
    _pitch = pitchValue.clamp(0.5, 2.0);
    await _flutterTts.setPitch(_pitch);
    debugPrint('🎵 FLUTTER_TTS: Тон установлен: $_pitch');

    if (restartPlayback && _isPlaying && (oldPitch - _pitch).abs() > 0.01) {
      await _restartCurrentPlayback();
    }
  }

  Future<void> _restartCurrentPlayback() async {
    if (_currentPlayingText == null || _currentPlayingText!.isEmpty) {
      debugPrint('⚠️ FLUTTER_TTS: Нет текста для перезапуска');
      return;
    }

    debugPrint(
        '🔄 FLUTTER_TTS: Перезапуск воспроизведения с новыми настройками');

    final textToRestart = _currentPlayingText!;
    final langCode = _currentLanguageCode;

    await _flutterTts.stop();
    _isPlaying = false;

    await Future.delayed(const Duration(milliseconds: 50));

    await _setLanguage(langCode);
    _isPlaying = true;
    await _flutterTts.speak(textToRestart);
    debugPrint('✅ FLUTTER_TTS: Воспроизведение перезапущено');
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    await _flutterTts.setSharedInstance(true);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(_pitch);

    _flutterTts.setStartHandler(() {
      _isPlaying = true;
      debugPrint('🔊 FLUTTER_TTS: Воспроизведение началось');
    });

    _flutterTts.setCompletionHandler(() {
      _isPlaying = false;
      _currentPlayingText = null;
      debugPrint('✅ FLUTTER_TTS: Воспроизведение завершено');
    });

    _flutterTts.setCancelHandler(() {
      _isPlaying = false;
      _currentPlayingText = null;
      debugPrint('⏹️ FLUTTER_TTS: Воспроизведение отменено');
    });

    _flutterTts.setErrorHandler((msg) {
      _isPlaying = false;
      _currentPlayingText = null;
      debugPrint('❌ FLUTTER_TTS: Ошибка: $msg');
    });

    _isInitialized = true;
    debugPrint('✅ FLUTTER_TTS: Инициализирован');
  }

  Future<void> _setLanguage(String languageCode) async {
    await _ensureInitialized();

    final ttsLanguageCode = _convertLanguageCode(languageCode);

    final isAvailable = await _flutterTts.isLanguageAvailable(ttsLanguageCode);
    if (isAvailable == true) {
      await _flutterTts.setLanguage(ttsLanguageCode);
      debugPrint('🌍 FLUTTER_TTS: Язык установлен: $ttsLanguageCode');
    } else {
      debugPrint(
          '⚠️ FLUTTER_TTS: Язык $ttsLanguageCode недоступен, используем en-US');
      await _flutterTts.setLanguage('en-US');
    }
  }

  String _convertLanguageCode(String languageCode) {
    switch (languageCode) {
      case 'ru-RU':
        return 'ru-RU';
      case 'en-US':
        return 'en-US';
      case 'en-GB':
        return 'en-GB';
      case 'de-DE':
        return 'de-DE';
      case 'fr-FR':
        return 'fr-FR';
      case 'es-ES':
        return 'es-ES';
      case 'it-IT':
        return 'it-IT';
      case 'ja-JP':
        return 'ja-JP';
      case 'ko-KR':
        return 'ko-KR';
      case 'zh-CN':
        return 'zh-CN';
      default:
        return 'en-US';
    }
  }

  @override
  Future<void> speak(String text, {String languageCode = 'ru-RU'}) async {
    try {
      debugPrint('🔊 FLUTTER_TTS: Начало озвучивания');
      debugPrint(
          '🔊 FLUTTER_TTS: Текст: ${text.substring(0, text.length > 100 ? 100 : text.length)}...');

      if (_isPlaying) {
        await stop();
      }

      await _setLanguage(languageCode);

      final cleanedText = TextCleaner.cleanForSpeech(text);

      _currentPlayingText = cleanedText;
      _currentLanguageCode = languageCode;
      _isPlaying = true;

      await _flutterTts.speak(cleanedText);
      debugPrint('✅ FLUTTER_TTS: Воспроизведение запущено');

      // Ждём завершения
      while (_isPlaying) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } catch (e) {
      _isPlaying = false;
      _currentPlayingText = null;
      debugPrint('❌ FLUTTER_TTS: Ошибка: $e');
      rethrow;
    }
  }

  @override
  Future<void> addToQueue(String text, {String languageCode = 'ru-RU'}) async {
    if (text.trim().isEmpty) {
      debugPrint('⏭️ FLUTTER_TTS_QUEUE: Пустой текст, пропускаем');
      return;
    }

    // Автоматически сбрасываем флаг остановки при добавлении новых элементов
    _isQueueStopped = false;

    final chunks = _chunkText(text);

    for (final chunkText in chunks) {
      if (_isQueueStopped) break;

      final chunk = _TextChunk(
        text: chunkText,
        languageCode: languageCode,
      );
      _queue.add(chunk);
      debugPrint(
          '➕ FLUTTER_TTS_QUEUE: Добавлен блок (${chunkText.length} символов), всего: ${_queue.length}');
    }

    if (!_isQueueActive && !_isQueueStopped) {
      _startQueue();
    }
  }

  List<String> _chunkText(String text) {
    final normalized = SpeechChunker.normalize(text);
    if (normalized.isEmpty) return const <String>[];
    final extracted = SpeechChunker.extractFromBuffer(
      normalized,
      flush: true,
      minChunkChars: 60,
      maxChunkChars: 420,
      softLookAheadChars: 160,
    );
    debugPrint(
        '📦 FLUTTER_TTS_QUEUE: Текст разбит на ${extracted.chunks.length} блоков');
    return extracted.chunks;
  }

  Future<void> _startQueue() async {
    if (_isQueueActive) {
      debugPrint('⚠️ FLUTTER_TTS_QUEUE: Очередь уже активна');
      return;
    }

    _isQueueActive = true;
    _isQueueStopped = false;
    _queueSessionId++;
    final currentSession = _queueSessionId;

    debugPrint('▶️ FLUTTER_TTS_QUEUE: Запуск очереди (сессия $currentSession)');

    int emptyQueueCounter = 0;
    const maxEmptyWaitCycles =
        100; // 100 × 100мс = 10 секунд ожидания новых элементов

    while (!_isQueueStopped && currentSession == _queueSessionId) {
      if (_queue.isEmpty && !_isPlaying) {
        emptyQueueCounter++;

        if (emptyQueueCounter >= maxEmptyWaitCycles) {
          debugPrint(
              '✅ FLUTTER_TTS_QUEUE: Очередь пуста 10 секунд, завершение');
          break;
        }

        await Future.delayed(const Duration(milliseconds: 100));
        continue;
      }

      // Сбрасываем счётчик если появились элементы или идёт воспроизведение
      emptyQueueCounter = 0;

      if (!_isPlaying && _queue.isNotEmpty && !_isQueueStopped) {
        await _playNextChunk(currentSession);
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (currentSession == _queueSessionId) {
      _isQueueActive = false;
      debugPrint(
          '⏹️ FLUTTER_TTS_QUEUE: Очередь завершена (сессия $currentSession)');
    }
  }

  Future<void> _playNextChunk(int sessionId) async {
    if (_queue.isEmpty || _isPlaying || _isQueueStopped) return;
    if (sessionId != _queueSessionId) return;

    final chunk = _queue.removeAt(0);

    try {
      debugPrint(
          '🔊 FLUTTER_TTS_QUEUE: Воспроизведение ${chunk.text.length} символов (осталось: ${_queue.length})');

      await _setLanguage(chunk.languageCode);

      final cleanedText = TextCleaner.cleanForSpeech(chunk.text);

      _currentPlayingText = cleanedText;
      _currentLanguageCode = chunk.languageCode;
      _isPlaying = true;

      await _flutterTts.speak(cleanedText);

      // Ждём завершения через polling флага _isPlaying
      while (_isPlaying && !_isQueueStopped && sessionId == _queueSessionId) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      debugPrint('✅ FLUTTER_TTS_QUEUE: Chunk завершён');
    } catch (e) {
      debugPrint('❌ FLUTTER_TTS_QUEUE: Ошибка воспроизведения: $e');
      _isPlaying = false;
      _currentPlayingText = null;
    }
  }

  @override
  Future<void> stop() async {
    try {
      debugPrint('⏹️ FLUTTER_TTS: Остановка воспроизведения');
      _isPlaying = false;
      _currentPlayingText = null;
      await _flutterTts.stop();
      debugPrint('✅ FLUTTER_TTS: Воспроизведение остановлено');
    } catch (e) {
      debugPrint('❌ FLUTTER_TTS: Ошибка при остановке: $e');
      _isPlaying = false;
      _currentPlayingText = null;
    }
  }

  @override
  Future<void> pause() async {
    try {
      debugPrint('⏸️ FLUTTER_TTS: Пауза воспроизведения');
      await _flutterTts.pause();
      _isPlaying = false;
    } catch (e) {
      debugPrint('❌ FLUTTER_TTS: Ошибка при паузе: $e');
    }
  }

  @override
  Future<void> resume() async {
    debugPrint('⚠️ FLUTTER_TTS: Resume не поддерживается flutter_tts');
  }

  @override
  Future<void> clearQueue() async {
    debugPrint('🧹 FLUTTER_TTS_QUEUE: Очистка очереди');
    debugPrint(
        '🧹 FLUTTER_TTS_QUEUE: - Элементов: ${_queue.length}, играет: $_isPlaying, активна: $_isQueueActive');

    _isQueueStopped = true;
    _isQueueActive = false;
    _queueSessionId++;

    _queue.clear();

    if (_isPlaying) {
      debugPrint('🧹 FLUTTER_TTS_QUEUE: Остановка текущего воспроизведения');
      await stop();
    }

    debugPrint('✅ FLUTTER_TTS_QUEUE: Очередь полностью очищена');
  }

  void resetQueueState() {
    _isQueueStopped = false;
    debugPrint('🔄 FLUTTER_TTS_QUEUE: Состояние очереди сброшено');
  }

  @override
  void dispose() {
    _isQueueStopped = true;
    _isQueueActive = false;
    _isPlaying = false;
    _queue.clear();
    _flutterTts.stop();
    debugPrint('🧹 FLUTTER_TTS: Disposed');
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
