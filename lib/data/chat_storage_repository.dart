import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../features/ai_chat/models/chat_message.dart';

/// Репозиторий для хранения истории чата на устройстве
/// Использует SharedPreferences для персистентного хранения
class ChatStorageRepository {
  // Ключи для хранения в SharedPreferences
  static const String _currentSessionKey = 'current_chat_session';
  static const String _sessionListKey = 'chat_sessions_list';
  static const String _sessionPrefix = 'chat_session_';
  static const String _lastSessionIdKey = 'last_session_id';
  static const String _scrollPositionKey = 'chat_scroll_position';
  static const String _visibleMessageKey = 'chat_visible_message';

  final SharedPreferences _prefs;

  ChatStorageRepository(this._prefs);

  /// Фабричный метод для создания репозитория
  static Future<ChatStorageRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return ChatStorageRepository(prefs);
  }

  /// Сохранение текущей сессии чата
  Future<void> saveCurrentSession(List<ChatMessage> messages,
      {String? sessionId}) async {
    try {
      sessionId ??= DateTime.now().millisecondsSinceEpoch.toString();

      // Конвертируем сообщения в JSON
      final messagesJson = messages.map((msg) => msg.toJson()).toList();

      final sessionData = {
        'id': sessionId,
        'messages': messagesJson,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'messageCount': messages.length,
      };

      // Сохраняем текущую сессию
      await _prefs.setString(_currentSessionKey, jsonEncode(sessionData));

      // Сохраняем как именованную сессию
      await _prefs.setString(
          '$_sessionPrefix$sessionId', jsonEncode(sessionData));

      // Обновляем список сессий
      await _addToSessionsList(sessionId, messages.length, messages: messages);

      // Сохраняем ID последней сессии
      await _prefs.setString(_lastSessionIdKey, sessionId);

      debugPrint(
          '💾 CHAT: Сессия сохранена: $sessionId (${messages.length} сообщений)');
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка сохранения сессии: $e');
    }
  }

  /// Загрузка текущей сессии чата
  Future<List<ChatMessage>?> loadCurrentSession() async {
    try {
      final sessionJson = _prefs.getString(_currentSessionKey);
      if (sessionJson == null) {
        return null;
      }

      final sessionData = jsonDecode(sessionJson) as Map<String, dynamic>;
      final messagesJson = sessionData['messages'] as List<dynamic>;

      final messages = messagesJson
          .map((msgJson) =>
              ChatMessage.fromJson(msgJson as Map<String, dynamic>))
          .toList();

      debugPrint(
          '📥 CHAT: Текущая сессия загружена: ${messages.length} сообщений');
      return messages;
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка загрузки текущей сессии: $e');
      return null;
    }
  }

  /// Загрузка конкретной сессии по ID
  Future<List<ChatMessage>?> loadSession(String sessionId) async {
    try {
      final sessionJson = _prefs.getString('$_sessionPrefix$sessionId');
      if (sessionJson == null) {
        return null;
      }

      final sessionData = jsonDecode(sessionJson) as Map<String, dynamic>;
      final messagesJson = sessionData['messages'] as List<dynamic>;

      final messages = messagesJson
          .map((msgJson) =>
              ChatMessage.fromJson(msgJson as Map<String, dynamic>))
          .toList();

      debugPrint(
          '📥 CHAT: Сессия $sessionId загружена: ${messages.length} сообщений');
      return messages;
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка загрузки сессии $sessionId: $e');
      return null;
    }
  }

  /// Получение списка всех сохраненных сессий
  Future<List<ChatSession>> getAllSessions() async {
    try {
      final sessionsJson = _prefs.getString(_sessionListKey);
      if (sessionsJson == null) {
        return [];
      }

      final sessionsList = jsonDecode(sessionsJson) as List<dynamic>;
      return sessionsList
          .map((sessionJson) =>
              ChatSession.fromJson(sessionJson as Map<String, dynamic>))
          .toList()
        ..sort((a, b) =>
            b.lastUpdated.compareTo(a.lastUpdated)); // Сортируем по дате
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка загрузки списка сессий: $e');
      return [];
    }
  }

  /// Удаление сессии
  Future<void> deleteSession(String sessionId) async {
    try {
      // Удаляем данные сессии
      await _prefs.remove('$_sessionPrefix$sessionId');

      // Обновляем список сессий
      await _removeFromSessionsList(sessionId);

      debugPrint('🗑️ CHAT: Сессия $sessionId удалена');
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка удаления сессии $sessionId: $e');
    }
  }

  /// Очистка всей истории чата
  Future<void> clearAllHistory() async {
    try {
      // Получаем все сессии
      final sessions = await getAllSessions();

      // Удаляем каждую сессию
      for (final session in sessions) {
        await _prefs.remove('$_sessionPrefix${session.id}');
      }

      // Очищаем служебные ключи
      await _prefs.remove(_currentSessionKey);
      await _prefs.remove(_sessionListKey);
      await _prefs.remove(_lastSessionIdKey);
      await _prefs.remove(_scrollPositionKey);

      debugPrint('🗑️ CHAT: Вся история чата очищена');
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка очистки истории: $e');
    }
  }

  /// Создание новой сессии (очистка текущей)
  Future<String> createNewSession() async {
    final newSessionId = DateTime.now().millisecondsSinceEpoch.toString();

    // Очищаем текущую сессию
    await _prefs.remove(_currentSessionKey);
    await _prefs.setString(_lastSessionIdKey, newSessionId);

    debugPrint('🆕 CHAT: Новая сессия создана: $newSessionId');
    return newSessionId;
  }

  /// Получение ID последней сессии
  Future<String?> getLastSessionId() async {
    return _prefs.getString(_lastSessionIdKey);
  }

  /// Сохранение видимого сообщения для восстановления позиции
  Future<void> saveVisibleMessage(
      String messageId, double relativeOffset) async {
    try {
      final visibleMessageData = {
        'messageId': messageId,
        'relativeOffset': relativeOffset,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await _prefs.setString(
          _visibleMessageKey, jsonEncode(visibleMessageData));
      debugPrint(
          '📍 CHAT: Видимое сообщение сохранено: $messageId (offset: $relativeOffset)');
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка сохранения видимого сообщения: $e');
    }
  }

  /// Загрузка информации о видимом сообщении
  Future<VisibleMessageInfo?> loadVisibleMessage() async {
    try {
      final visibleMessageJson = _prefs.getString(_visibleMessageKey);
      if (visibleMessageJson == null) return null;

      final data = jsonDecode(visibleMessageJson) as Map<String, dynamic>;
      final messageInfo = VisibleMessageInfo(
        messageId: data['messageId'] as String,
        relativeOffset: data['relativeOffset'] as double,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
      );

      debugPrint(
          '📍 CHAT: Видимое сообщение загружено: ${messageInfo.messageId} (offset: ${messageInfo.relativeOffset})');
      return messageInfo;
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка загрузки видимого сообщения: $e');
      return null;
    }
  }

  /// Очистка информации о видимом сообщении
  Future<void> clearVisibleMessage() async {
    try {
      await _prefs.remove(_visibleMessageKey);
      debugPrint('📍 CHAT: Информация о видимом сообщении очищена');
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка очистки видимого сообщения: $e');
    }
  }

  /// [Deprecated] Сохранение позиции скролла для текущей сессии
  @Deprecated('Используйте saveVisibleMessage вместо этого')
  Future<void> saveScrollPosition(double scrollPosition) async {
    try {
      await _prefs.setDouble(_scrollPositionKey, scrollPosition);
      debugPrint('📍 CHAT: Позиция скролла сохранена: $scrollPosition');
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка сохранения позиции скролла: $e');
    }
  }

  /// [Deprecated] Загрузка сохраненной позиции скролла
  @Deprecated('Используйте loadVisibleMessage вместо этого')
  Future<double?> loadScrollPosition() async {
    try {
      final position = _prefs.getDouble(_scrollPositionKey);
      if (position != null) {
        debugPrint('📍 CHAT: Позиция скролла загружена: $position');
      }
      return position;
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка загрузки позиции скролла: $e');
      return null;
    }
  }

  /// Очистка всей информации о позиции скролла
  Future<void> clearScrollPosition() async {
    try {
      await _prefs.remove(_scrollPositionKey);
      await _prefs.remove(_visibleMessageKey);
      debugPrint('📍 CHAT: Вся информация о позиции скролла очищена');
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка очистки позиции скролла: $e');
    }
  }

  /// Добавление сессии в список
  Future<void> _addToSessionsList(String sessionId, int messageCount, {List<ChatMessage>? messages}) async {
    try {
      final sessions = await getAllSessions();

      // Удаляем сессию если она уже есть (обновление)
      sessions.removeWhere((session) => session.id == sessionId);

      // Добавляем новую/обновленную сессию
      final newSession = ChatSession(
        id: sessionId,
        lastUpdated: DateTime.now(),
        messageCount: messageCount,
        title: _generateSessionTitle(messageCount, messages: messages),
      );

      sessions.insert(0, newSession); // Добавляем в начало

      // Ограничиваем количество сохраненных сессий (максимум 20)
      if (sessions.length > 20) {
        final sessionsToRemove = sessions.sublist(20);
        for (final session in sessionsToRemove) {
          await _prefs.remove('$_sessionPrefix${session.id}');
        }
        sessions.removeRange(20, sessions.length);
      }

      // Сохраняем обновленный список
      final sessionsJson = sessions.map((session) => session.toJson()).toList();
      await _prefs.setString(_sessionListKey, jsonEncode(sessionsJson));
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка добавления сессии в список: $e');
    }
  }

  /// Удаление сессии из списка
  Future<void> _removeFromSessionsList(String sessionId) async {
    try {
      final sessions = await getAllSessions();
      sessions.removeWhere((session) => session.id == sessionId);

      final sessionsJson = sessions.map((session) => session.toJson()).toList();
      await _prefs.setString(_sessionListKey, jsonEncode(sessionsJson));
    } catch (e) {
      debugPrint('🔴 CHAT: Ошибка удаления сессии из списка: $e');
    }
  }

  /// Генерация заголовка для сессии на основе первого сообщения пользователя
  String _generateSessionTitle(int messageCount, {List<ChatMessage>? messages}) {
    if (messages != null && messages.isNotEmpty) {
      final userMessages = messages.where((m) => m.type == MessageType.user).toList();
      if (userMessages.isNotEmpty) {
        String firstMessage = userMessages.first.content.trim();
        if (firstMessage.length > 40) {
          firstMessage = '${firstMessage.substring(0, 40)}...';
        }
        if (firstMessage.isNotEmpty) {
          return firstMessage;
        }
      }
    }
    
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return 'Чат $timeStr';
  }
}

/// Модель информации о сессии чата
class ChatSession {
  final String id;
  final DateTime lastUpdated;
  final int messageCount;
  final String title;

  const ChatSession({
    required this.id,
    required this.lastUpdated,
    required this.messageCount,
    required this.title,
  });

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] as String,
        lastUpdated:
            DateTime.fromMillisecondsSinceEpoch(json['lastUpdated'] as int),
        messageCount: json['messageCount'] as int,
        title: json['title'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
        'messageCount': messageCount,
        'title': title,
      };
}

/// Информация о видимом сообщении для восстановления позиции скролла
class VisibleMessageInfo {
  final String messageId;
  final double
      relativeOffset; // Относительное смещение от начала сообщения (0.0 - 1.0)
  final DateTime timestamp;

  const VisibleMessageInfo({
    required this.messageId,
    required this.relativeOffset,
    required this.timestamp,
  });

  factory VisibleMessageInfo.fromJson(Map<String, dynamic> json) =>
      VisibleMessageInfo(
        messageId: json['messageId'] as String,
        relativeOffset: json['relativeOffset'] as double,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      );

  Map<String, dynamic> toJson() => {
        'messageId': messageId,
        'relativeOffset': relativeOffset,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };
}
