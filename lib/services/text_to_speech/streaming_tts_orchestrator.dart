import 'base_tts_service.dart';
import 'speech_chunker.dart';

class StreamingTtsOrchestrator {
  final BaseTTSService _tts;
  final String _languageCode;

  final int _minStartBufferChars;
  final int _targetQueueChunks;
  final int _maxQueueChunks;

  final int _minChunkChars;
  final int _maxChunkChars;
  final int _softLookAheadChars;

  String _lastFullText = '';
  String _buffer = '';
  bool _started = false;
  bool _disposed = false;

  Future<void> _serial = Future.value();

  StreamingTtsOrchestrator({
    required BaseTTSService tts,
    String languageCode = 'ru-RU',
    int minStartBufferChars = 180,
    int targetQueueChunks = 3,
    int maxQueueChunks = 8,
    int minChunkChars = 80,
    int maxChunkChars = 320,
    int softLookAheadChars = 140,
  })  : _tts = tts,
        _languageCode = languageCode,
        _minStartBufferChars = minStartBufferChars,
        _targetQueueChunks = targetQueueChunks,
        _maxQueueChunks = maxQueueChunks,
        _minChunkChars = minChunkChars,
        _maxChunkChars = maxChunkChars,
        _softLookAheadChars = softLookAheadChars;

  void reset() {
    _lastFullText = '';
    _buffer = '';
    _started = false;
  }

  int get bufferedChars => _buffer.trim().length;

  bool get hasBufferedText => _buffer.trim().isNotEmpty;

  Future<void> updateFullText(
    String fullText, {
    bool isFinal = false,
  }) {
    if (_disposed) return Future.value();
    _serial = _serial
        .then((_) => _updateFullTextInternal(fullText, isFinal: isFinal));
    return _serial;
  }

  Future<void> flush() {
    if (_disposed) return Future.value();
    _serial = _serial.then((_) => _pump(flush: true));
    return _serial;
  }

  Future<void> pump() {
    if (_disposed) return Future.value();
    _serial = _serial.then((_) => _pump(flush: false));
    return _serial;
  }

  void dispose() {
    _disposed = true;
  }

  Future<void> _updateFullTextInternal(
    String fullText, {
    required bool isFinal,
  }) async {
    final normalized = fullText.replaceAll('\u00A0', ' ');

    String delta;
    if (normalized.startsWith(_lastFullText)) {
      delta = normalized.substring(_lastFullText.length);
    } else {
      final common = _commonPrefixLength(_lastFullText, normalized);
      if (common == 0) {
        _lastFullText = '';
        _buffer = '';
        _started = false;
        delta = normalized;
      } else {
        final rollback = _lastFullText.substring(0, common);
        _lastFullText = rollback;
        _buffer = '';
        _started = false;
        delta = normalized.substring(common);
      }
    }

    _lastFullText = normalized;
    if (delta.trim().isEmpty && !isFinal) return;

    final cleanedDelta = delta.replaceAll(RegExp(r'\s+'), ' ');
    _buffer += cleanedDelta;
    _buffer = _buffer.replaceAll(RegExp(r'\s+'), ' ').trimLeft();

    await _pump(flush: isFinal);
  }

  Future<void> _pump({required bool flush}) async {
    if (_disposed) return;

    if (!_started) {
      final normalized = SpeechChunker.normalize(_buffer);
      if (normalized.length < _minStartBufferChars && !flush) return;
      _buffer = normalized;
      _started = true;
    }

    if (_tts.queueSize >= _maxQueueChunks) return;

    while (_tts.queueSize < _targetQueueChunks && !_disposed) {
      final extracted = SpeechChunker.extractFromBuffer(
        _buffer,
        flush: flush,
        minChunkChars: _minChunkChars,
        maxChunkChars: _maxChunkChars,
        softLookAheadChars: _softLookAheadChars,
      );

      if (extracted.chunks.isEmpty) {
        _buffer = extracted.remainder;
        break;
      }

      _buffer = extracted.remainder;

      for (final chunk in extracted.chunks) {
        if (_disposed) return;
        if (_tts.queueSize >= _maxQueueChunks) return;
        if (chunk.trim().isEmpty) continue;
        await _tts.addToQueue(chunk, languageCode: _languageCode);
      }

      if (!flush && _buffer.length < _minChunkChars) break;
    }
  }

  static int _commonPrefixLength(String a, String b) {
    final minLen = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < minLen && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return i;
  }
}

