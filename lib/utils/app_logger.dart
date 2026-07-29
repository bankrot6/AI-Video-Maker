import 'dart:developer' as developer;
import 'dart:async';

/// Уровни логирования
enum LogLevel {
  verbose(0, '📋'),
  debug(500, '🔍'),
  info(800, '📘'),
  warning(900, '⚠️'),
  error(1000, '❌'),
  critical(1200, '🔥');

  const LogLevel(this.value, this.emoji);
  final int value;
  final String emoji;
}

/// Класс для логирования в приложении
class AppLogger {
  static final List<LogEntry> _buffer = <LogEntry>[];
  static const int _maxBufferSize = 1000;
  static final StreamController<LogEntry> _streamController =
      StreamController<LogEntry>.broadcast();

  static Stream<LogEntry> get logStream => _streamController.stream;
  static List<LogEntry> get bufferedLogs => List.unmodifiable(_buffer);

  /// Вывод лога с указанным сообщением, тегом и уровнем важности
  static void log(String message,
      {String tag = 'APP', LogLevel level = LogLevel.info}) {
    final emoji = level.emoji;
    final timestamp = DateTime.now().toString().substring(0, 19);
    final logMessage = '[$timestamp] $emoji $tag: $message';

    // Вывод в консоль
    print(logMessage);

    // Вывод через dart:developer для более детального логирования в DevTools
    developer.log(
      message,
      name: tag,
      level: level.value,
    );

    // Сохраняем в буфер и рассылаем подписчикам
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      level: level,
      message: message,
    );
    _buffer.add(entry);
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }
    if (!_streamController.isClosed) {
      _streamController.add(entry);
    }
  }
}

class LogEntry {
  final DateTime timestamp;
  final String tag;
  final LogLevel level;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.tag,
    required this.level,
    required this.message,
  });

  @override
  String toString() {
    final time = timestamp.toString().substring(0, 19);
    return '[$time] ${level.emoji} $tag: $message';
  }
}
