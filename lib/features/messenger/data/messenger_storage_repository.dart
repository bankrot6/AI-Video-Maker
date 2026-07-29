import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/messenger_memory.dart';
import '../models/messenger_message.dart';
import '../models/messenger_thread.dart';
import '../services/messenger_seed_data.dart';
import 'friend_profile_repository.dart';

enum MessengerThreadUpdateType {
  message,
  memory,
  thread,
}

class MessengerThreadUpdate {
  final String contactId;
  final MessengerThreadUpdateType type;
  final MessengerMessage? message;
  final bool isNewMessage;

  const MessengerThreadUpdate({
    required this.contactId,
    required this.type,
    this.message,
    this.isNewMessage = false,
  });

  const MessengerThreadUpdate.thread({required String contactId})
      : this(contactId: contactId, type: MessengerThreadUpdateType.thread);

  const MessengerThreadUpdate.message({
    required String contactId,
    required MessengerMessage message,
    bool isNewMessage = false,
  }) : this(
          contactId: contactId,
          type: MessengerThreadUpdateType.message,
          message: message,
          isNewMessage: isNewMessage,
        );

  const MessengerThreadUpdate.memory({required String contactId})
      : this(contactId: contactId, type: MessengerThreadUpdateType.memory);

  bool get isIncomingMessage =>
      isNewMessage && message != null && !(message!.isMine);
}

class MessengerStorageRepository {
  static const String _threadPrefix = 'messenger_thread_';
  static const String _memoryPrefix = 'messenger_memory_';
  static const String _readAtPrefix = 'messenger_thread_read_at_';
  static const int _maxMessagesPerThread = 120;

  final SharedPreferences _prefs;
  final MessengerSeedData _seedData;
  final FriendProfileRepository _friendProfileRepository;
  final StreamController<MessengerThreadUpdate> _updatesController =
      StreamController<MessengerThreadUpdate>.broadcast();

  MessengerStorageRepository(
    this._prefs, {
    MessengerSeedData? seedData,
    FriendProfileRepository? friendProfileRepository,
  })  : _seedData = seedData ?? const MessengerSeedData(),
        _friendProfileRepository =
            friendProfileRepository ?? FriendProfileRepository(_prefs);

  Future<List<MessengerThread>> loadThreads() async {
    final seedThreads = _seedData.buildThreads();
    final List<MessengerThread> threads = [];

    for (final seed in seedThreads) {
      threads.add(await _loadOrSeedThread(seed));
    }

    final customProfiles = _friendProfileRepository.loadAll();
    for (final entry in customProfiles.entries) {
      if (entry.key == 'friend') continue;
      final seed = _seedData.buildFriendThread(
        contactId: entry.key,
        profile: entry.value,
      );
      threads.add(await _loadOrSeedThread(seed));
    }

    threads.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    return threads;
  }

  Future<MessengerThread> loadThreadById(String contactId) async {
    final seedThreads = _seedData.buildThreads();
    MessengerThread? seed;
    for (final thread in seedThreads) {
      if (thread.contact.id == contactId) {
        seed = thread;
        break;
      }
    }
    if (seed != null) {
      return _loadOrSeedThread(seed);
    }
    final profile = _friendProfileRepository.load(contactId);
    if (profile == null) {
      throw StateError('Thread not found: $contactId');
    }
    final customSeed = _seedData.buildFriendThread(
      contactId: contactId,
      profile: profile,
    );
    return _loadOrSeedThread(customSeed);
  }

  Stream<MessengerThreadUpdate> get threadUpdates => _updatesController.stream;

  void dispose() {
    _updatesController.close();
  }

  void _emitUpdate(MessengerThreadUpdate update) {
    if (_updatesController.isClosed) return;
    _updatesController.add(update);
  }

  DateTime? getLastReadAt(String contactId) {
    final raw = _prefs.getString(_readAtKey(contactId));
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<DateTime> ensureLastReadAt(MessengerThread thread) async {
    final existing = getLastReadAt(thread.contact.id);
    if (existing != null) return existing;
    final fallback = _fallbackReadAt(thread);
    await markThreadRead(thread.contact.id, fallback, emitUpdate: false);
    return fallback;
  }

  Future<void> markThreadRead(
    String contactId,
    DateTime readAt, {
    bool emitUpdate = true,
  }) async {
    final existing = getLastReadAt(contactId);
    if (existing != null && !readAt.isAfter(existing)) return;
    await _prefs.setString(_readAtKey(contactId), readAt.toIso8601String());
    if (emitUpdate) {
      _emitUpdate(MessengerThreadUpdate.thread(contactId: contactId));
    }
  }

  int unreadCountForThread(MessengerThread thread, DateTime? lastReadAt) {
    if (lastReadAt == null) return 0;
    return thread.messages
        .where(
          (message) => !message.isMine && message.time.isAfter(lastReadAt),
        )
        .length;
  }

  DateTime _fallbackReadAt(MessengerThread thread) {
    for (final message in thread.messages.reversed) {
      if (message.isMine) {
        return message.time;
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> saveThread(
    MessengerThread thread, {
    MessengerThreadUpdate? update,
  }) async {
    final messages = _trimMessages(thread.messages);
    final messagesJson = messages.map((message) => message.toJson()).toList();
    await _prefs.setString(
      _threadKey(thread.contact.id),
      jsonEncode(messagesJson),
    );
    await _prefs.setString(
      _memoryKey(thread.contact.id),
      jsonEncode(thread.memory.toJson()),
    );

    debugPrint(
        '💾 MESSENGER: Сохранен поток ${thread.contact.id} (${messages.length} сообщений)');
    _emitUpdate(
      update ?? MessengerThreadUpdate.thread(contactId: thread.contact.id),
    );
  }

  Future<MessengerThread> appendMessage({
    required String contactId,
    required MessengerMessage message,
  }) async {
    final thread = await loadThreadById(contactId);
    thread.messages.add(message);
    await saveThread(
      thread,
      update: MessengerThreadUpdate.message(
        contactId: contactId,
        message: message,
        isNewMessage: true,
      ),
    );
    return thread;
  }

  Future<MessengerThread> upsertMessage({
    required String contactId,
    required MessengerMessage message,
  }) async {
    final thread = await loadThreadById(contactId);
    final index =
        thread.messages.indexWhere((existing) => existing.id == message.id);
    final isNewMessage = index == -1;
    if (index == -1) {
      thread.messages.add(message);
    } else {
      thread.messages[index] = message;
    }
    await saveThread(
      thread,
      update: MessengerThreadUpdate.message(
        contactId: contactId,
        message: message,
        isNewMessage: isNewMessage,
      ),
    );
    return thread;
  }

  Future<MessengerThread?> updateMessage({
    required String contactId,
    required String messageId,
    required MessengerMessage Function(MessengerMessage) update,
  }) async {
    final thread = await loadThreadById(contactId);
    final index =
        thread.messages.indexWhere((existing) => existing.id == messageId);
    if (index == -1) return null;
    thread.messages[index] = update(thread.messages[index]);
    await saveThread(
      thread,
      update: MessengerThreadUpdate.message(
        contactId: contactId,
        message: thread.messages[index],
      ),
    );
    return thread;
  }

  Future<MessengerThread?> deleteMessage({
    required String contactId,
    required String messageId,
  }) async {
    final thread = await loadThreadById(contactId);
    final updatedMessages = List<MessengerMessage>.from(thread.messages);
    final index =
        updatedMessages.indexWhere((existing) => existing.id == messageId);
    if (index == -1) return null;
    updatedMessages.removeAt(index);
    final updatedThread = thread.copyWith(messages: updatedMessages);
    await saveThread(updatedThread);
    return updatedThread;
  }

  Future<void> updateMemory(
    String contactId,
    MessengerMemory memory,
  ) async {
    await _prefs.setString(_memoryKey(contactId), jsonEncode(memory.toJson()));
    debugPrint('🧠 MESSENGER: Обновлена память для $contactId');
    _emitUpdate(MessengerThreadUpdate.memory(contactId: contactId));
  }

  Future<void> clearThread(String contactId) async {
    await _prefs.remove(_threadKey(contactId));
    await _prefs.remove(_memoryKey(contactId));
    await _prefs.remove(_readAtKey(contactId));
  }

  Future<MessengerThread> _loadOrSeedThread(MessengerThread seed) async {
    final storedMessages = await _loadMessages(seed.contact.id);
    final storedMemory = await _loadMemory(seed.contact.id);
    final messages = storedMessages ?? seed.messages;
    final memory = storedMemory ?? seed.memory;

    if (storedMessages == null || storedMemory == null) {
      await saveThread(seed.copyWith(messages: messages, memory: memory));
    }

    return seed.copyWith(messages: List.of(messages), memory: memory);
  }

  Future<List<MessengerMessage>?> _loadMessages(String contactId) async {
    try {
      final raw = _prefs.getString(_threadKey(contactId));
      if (raw == null) return null;
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .map(
              (item) => MessengerMessage.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка загрузки сообщений $contactId: $e');
      return null;
    }
  }

  Future<MessengerMemory?> _loadMemory(String contactId) async {
    try {
      final raw = _prefs.getString(_memoryKey(contactId));
      if (raw == null) return null;
      return MessengerMemory.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка загрузки памяти $contactId: $e');
      return null;
    }
  }

  List<MessengerMessage> _trimMessages(List<MessengerMessage> messages) {
    if (messages.length <= _maxMessagesPerThread) return messages;
    return messages.sublist(messages.length - _maxMessagesPerThread);
  }

  String _threadKey(String contactId) => '$_threadPrefix$contactId';

  String _memoryKey(String contactId) => '$_memoryPrefix$contactId';

  String _readAtKey(String contactId) => '$_readAtPrefix$contactId';
}
