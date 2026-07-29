import 'package:flutter/foundation.dart';
import '../data/chat_storage_repository.dart';
import '../features/ai_chat/models/chat_message.dart';
import 'voice_message_storage.dart';

/// Сервис для управления сохранением и загрузкой истории чата
/// Предоставляет высокоуровневый API для работы с чатом
class ChatStorageService {
  final ChatStorageRepository _repository;
  String? _currentSessionId;

  ChatStorageService(this._repository);

  /// Фабричный метод для создания сервиса
  static Future<ChatStorageService> create() async {
    final repository = await ChatStorageRepository.create();
    return ChatStorageService(repository);
  }

  /// Автоматическое сохранение сообщений (вызывается при каждом изменении)
  Future<void> autoSave(List<ChatMessage> messages) async {
    // Не сохраняем пустые чаты или только приветственные сообщения
    if (messages.isEmpty || _isOnlyWelcomeMessage(messages)) {
      return;
    }

    try {
      // Используем текущую сессию или создаем новую
      _currentSessionId ??= await _getOrCreateSessionId();

      await _repository.saveCurrentSession(messages,
          sessionId: _currentSessionId);

      debugPrint(
          '💾 CHAT SERVICE: Автосохранение выполнено (${messages.length} сообщений)');
    } catch (e) {
      debugPrint('🔴 CHAT SERVICE: Ошибка автосохранения: $e');
    }
  }

  /// Загрузка истории чата при запуске приложения
  Future<List<ChatMessage>?> loadChatHistory() async {
    try {
      final messages = await _repository.loadCurrentSession();

      if (messages != null) {
        _currentSessionId = await _repository.getLastSessionId();
        debugPrint(
            '📥 CHAT SERVICE: История загружена (${messages.length} сообщений)');
      }

      return messages;
    } catch (e) {
      debugPrint('🔴 CHAT SERVICE: Ошибка загрузки истории: $e');
      return null;
    }
  }

  /// Создание новой сессии чата
  Future<void> createNewSession() async {
    try {
      _currentSessionId = await _repository.createNewSession();
      debugPrint('🆕 CHAT SERVICE: Новая сессия создана: $_currentSessionId');
    } catch (e) {
      debugPrint('🔴 CHAT SERVICE: Ошибка создания новой сессии: $e');
    }
  }

  /// Получение всех сохраненных сессий
  Future<List<ChatSession>> getAllSessions() async {
    try {
      return await _repository.getAllSessions();
    } catch (e) {
      debugPrint('🔴 CHAT SERVICE: Ошибка загрузки сессий: $e');
      return [];
    }
  }

  /// Загрузка конкретной сессии
  Future<List<ChatMessage>?> loadSession(String sessionId) async {
    try {
      final messages = await _repository.loadSession(sessionId);
      if (messages != null) {
        _currentSessionId = sessionId;
        debugPrint('📥 CHAT SERVICE: Сессия $sessionId загружена');
      }
      return messages;
    } catch (e) {
      debugPrint('🔴 CHAT SERVICE: Ошибка загрузки сессии $sessionId: $e');
      return null;
    }
  }

  /// Удаление сессии
  Future<void> deleteSession(String sessionId) async {
    try {
      await _repository.deleteSession(sessionId);

      // Если удаляем текущую сессию, сбрасываем ID
      if (_currentSessionId == sessionId) {
        _currentSessionId = null;
      }

      debugPrint('🗑️ CHAT SERVICE: Сессия $sessionId удалена');
    } catch (e) {
      debugPrint('🔴 CHAT SERVICE: Ошибка удаления сессии $sessionId: $e');
    }
  }

  /// Очистка всей истории
  Future<void> clearAllHistory() async {
    try {
      // Удаляем локальные аудиофайлы всех текущих сообщений
      for (final m
          in await _repository.loadCurrentSession() ?? <ChatMessage>[]) {
        if (m.type == MessageType.voice) {
          await VoiceMessageStorage.deleteIfExists(m.audioPath);
        }
      }
      await _repository.clearAllHistory();
      _currentSessionId = null;
      debugPrint('🗑️ CHAT SERVICE: Вся история очищена');
    } catch (e) {
      debugPrint('🔴 CHAT SERVICE: Ошибка очистки истории: $e');
    }
  }

  /// Экспорт чата в текстовый формат
  String exportChatToText(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    buffer.writeln('=== ЭКСПОРТ ЧАТА С ИИ ДИЕТОЛОГОМ ===');
    buffer.writeln('Дата экспорта: ${DateTime.now().toLocal()}');
    buffer.writeln('Количество сообщений: ${messages.length}');
    buffer.writeln('=====================================\n');

    for (final message in messages) {
      final sender = _getSenderName(message.type);
      final timestamp = message.timestamp.toLocal();
      final timeStr =
          '${timestamp.day.toString().padLeft(2, '0')}.${timestamp.month.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

      buffer.writeln('[$timeStr] $sender:');
      buffer.writeln(message.content);
      buffer.writeln('');
    }

    buffer.writeln('=== КОНЕЦ ЭКСПОРТА ===');
    return buffer.toString();
  }

  /// Получение статистики чата
  ChatStatistics getChatStatistics(List<ChatMessage> messages) {
    final userMessages =
        messages.where((msg) => msg.type == MessageType.user).length;
    final aiMessages =
        messages.where((msg) => msg.type == MessageType.ai).length;
    final systemMessages =
        messages.where((msg) => msg.type == MessageType.system).length;

    final firstMessage = messages.isNotEmpty ? messages.first.timestamp : null;
    final lastMessage = messages.isNotEmpty ? messages.last.timestamp : null;

    Duration? sessionDuration;
    if (firstMessage != null && lastMessage != null) {
      sessionDuration = lastMessage.difference(firstMessage);
    }

    return ChatStatistics(
      totalMessages: messages.length,
      userMessages: userMessages,
      aiMessages: aiMessages,
      systemMessages: systemMessages,
      sessionDuration: sessionDuration,
      firstMessageTime: firstMessage,
      lastMessageTime: lastMessage,
    );
  }

  /// Получение или создание ID сессии
  Future<String> _getOrCreateSessionId() async {
    String? sessionId = await _repository.getLastSessionId();
    sessionId ??= DateTime.now().millisecondsSinceEpoch.toString();
    return sessionId;
  }

  /// Проверка, содержит ли чат только приветственное сообщение
  bool _isOnlyWelcomeMessage(List<ChatMessage> messages) {
    if (messages.length != 1) return false;

    final message = messages.first;
    return message.type == MessageType.ai &&
        message.metadata?['isWelcome'] == true;
  }

  /// Получение имени отправителя по типу сообщения
  String _getSenderName(MessageType type) {
    switch (type) {
      case MessageType.user:
        return 'Пользователь';
      case MessageType.ai:
        return 'ИИ Диетолог';
      case MessageType.system:
        return 'Система';
      case MessageType.quickAction:
        return 'Быстрое действие';
      case MessageType.voice:
        return 'Пользователь (голос)';
    }
  }

  /// Получение текущего ID сессии
  String? get currentSessionId => _currentSessionId;
}

/// Статистика чата
class ChatStatistics {
  final int totalMessages;
  final int userMessages;
  final int aiMessages;
  final int systemMessages;
  final Duration? sessionDuration;
  final DateTime? firstMessageTime;
  final DateTime? lastMessageTime;

  const ChatStatistics({
    required this.totalMessages,
    required this.userMessages,
    required this.aiMessages,
    required this.systemMessages,
    this.sessionDuration,
    this.firstMessageTime,
    this.lastMessageTime,
  });
}
