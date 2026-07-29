import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/messenger_proactive_repository.dart';
import '../data/messenger_storage_repository.dart';
import '../models/friend_profile.dart';
import '../models/messenger_message.dart';
import '../models/messenger_proactive_message.dart';
import '../models/messenger_thread.dart';
import 'messenger_activity_suggester.dart';
import 'messenger_ai_service.dart';
import 'messenger_mood_service.dart';
import '../../personalization/data/friend_persona_repository.dart';
import '../../personalization/models/friend_persona.dart';
import '../../../services/credit_service.dart';
import '../../../services/notification/notification_manager.dart';
import '../data/friend_profile_repository.dart';

class MessengerProactiveService {
  static const int _maxQueueSize = 2;
  static const Duration _firstDelayMin = Duration(minutes: 5);
  static const Duration _firstDelayMax = Duration(minutes: 10);
  static const Duration _followupDelayMin = Duration(hours: 1);
  static const Duration _followupDelayMax = Duration(hours: 3);
  static const Duration _deliveredRetention = Duration(days: 5);
  static const Duration _safeScheduleSkew = Duration(minutes: 2);
  static const int _quietHoursStart = 23;
  static const int _quietHoursEnd = 8;
  static const int _quietHoursResumeHour = 9;
  static const int _quietHoursResumeMinuteMax = 30;

  final MessengerStorageRepository _storageRepository;
  final MessengerAiService _aiService;
  final MessengerActivitySuggester _activitySuggester;
  final MessengerProactiveRepository _repository;
  final FriendPersonaRepository _personaRepository;
  final FriendProfileRepository _friendProfileRepository;
  final MessengerMoodService _moodService;
  final NotificationManager _notificationManager;
  final String? userGender;
  final Random _random;
  final Uuid _uuid;

  bool _syncInFlight = false;

  MessengerProactiveService({
    required MessengerStorageRepository storageRepository,
    required MessengerAiService aiService,
    required MessengerActivitySuggester activitySuggester,
    required MessengerProactiveRepository repository,
    required FriendPersonaRepository personaRepository,
    required FriendProfileRepository friendProfileRepository,
    required MessengerMoodService moodService,
    this.userGender,
    NotificationManager? notificationManager,
    Random? random,
    Uuid? uuid,
  })  : _storageRepository = storageRepository,
        _aiService = aiService,
        _activitySuggester = activitySuggester,
        _repository = repository,
        _personaRepository = personaRepository,
        _friendProfileRepository = friendProfileRepository,
        _moodService = moodService,
        _notificationManager = notificationManager ?? NotificationManager(),
        _random = random ?? Random(),
        _uuid = uuid ?? const Uuid();

  Future<int> processDueMessages() async {
    final items = await _repository.loadAll();
    if (items.isEmpty) return 0;
    final now = DateTime.now();
    final due = items
        .where((item) => !item.isDelivered && !item.scheduledAt.isAfter(now))
        .toList();
    if (due.isEmpty) {
      await _pruneOldDelivered(items, now);
      return 0;
    }
    var changed = false;
    for (final item in due) {
      _notificationManager.suppressMessengerNotification(item.id);
      if (item.notificationId != null) {
        await _notificationManager
            .cancelNotificationByNumericId(item.notificationId!);
      }
      await _notificationManager.dismissMessengerNotification(item.id);
      final deliveredAt = now;
      final updated = item.copyWith(deliveredAt: deliveredAt);
      await _appendMessage(updated, deliveredAt: deliveredAt);
      final index = items.indexWhere((entry) => entry.id == item.id);
      if (index != -1) {
        items[index] = updated;
        changed = true;
      }
    }
    if (changed) {
      await _repository.saveAll(items);
    }
    await _pruneOldDelivered(items, now);
    return due.length;
  }

  Future<bool> deliverMessageById(String messageId) async {
    _notificationManager.suppressMessengerNotification(messageId);
    final items = await _repository.loadAll();
    final index = items.indexWhere((item) => item.id == messageId);
    if (index == -1) return false;
    final item = items[index];
    if (item.isDelivered) return true;
    if (item.notificationId != null) {
      await _notificationManager
          .cancelNotificationByNumericId(item.notificationId!);
    }
    await _notificationManager.dismissMessengerNotification(messageId);
    final now = DateTime.now();
    await _appendMessage(item, deliveredAt: now);
    items[index] = item.copyWith(deliveredAt: now);
    await _repository.saveAll(items);
    return true;
  }

  Future<void> ensureQueue({required bool notificationsEnabled}) async {
    if (_syncInFlight) return;
    _syncInFlight = true;
    try {
      final creditUsage = await CreditService().getCreditUsage();
      if (creditUsage.remainingCredits <= 0) return;
      final isFree = creditUsage.isFreeUser;
      final effectiveMaxQueue = isFree ? 1 : _maxQueueSize;

      final now = DateTime.now();
      var items = await _repository.loadAll();
      await _pruneOldDelivered(items, now);
      items = await _repository.loadAll();
      if (notificationsEnabled) {
        final updated = await _scheduleMissingNotifications(items, now);
        if (updated) {
          await _repository.saveAll(items);
        }
      }
      final pending = items
          .where((item) => !item.isDelivered && item.scheduledAt.isAfter(now))
          .toList();
      if (pending.length >= effectiveMaxQueue) {
        return;
      }
      final thread = await _selectThread();
      if (thread == null) return;
      if (!_isEligible(thread)) return;
      final needed =
          (effectiveMaxQueue - pending.length).clamp(0, effectiveMaxQueue);
      if (needed == 0) return;
      final existingTexts = items
          .where((item) => !item.isDelivered)
          .map((item) => item.text.trim().toLowerCase())
          .toSet();
      var lastScheduled = _latestScheduled(pending);
      for (var i = 0; i < needed; i += 1) {
        final nextTime =
            _pickScheduleTime(thread: thread, now: now, last: lastScheduled);
        final scheduledAt = _ensureFuture(nextTime, now);
        final messageText = await _generateMessage(thread);
        if (messageText.trim().isEmpty) continue;
        final normalizedText = messageText.trim().toLowerCase();
        if (existingTexts.contains(normalizedText)) continue;
        existingTexts.add(normalizedText);
        final proactive = MessengerProactiveMessage(
          id: _uuid.v4(),
          contactId: thread.contact.id,
          text: messageText,
          createdAt: now,
          scheduledAt: scheduledAt,
        );
        var stored = proactive;
        if (notificationsEnabled) {
          stored = await _scheduleNotification(thread, proactive);
        }
        await _repository.upsert(stored);
        lastScheduled = scheduledAt;
      }
    } catch (e) {
      debugPrint('Ошибка планирования proactive сообщений: $e');
    } finally {
      _syncInFlight = false;
    }
  }

  Future<bool> _scheduleMissingNotifications(
    List<MessengerProactiveMessage> items,
    DateTime now,
  ) async {
    var changed = false;
    for (var i = 0; i < items.length; i += 1) {
      final item = items[i];
      if (item.isDelivered) continue;
      if (item.notificationId != null) continue;
      if (!item.scheduledAt.isAfter(now.add(_safeScheduleSkew))) continue;
      try {
        final thread = await _storageRepository.loadThreadById(item.contactId);
        final updated = await _scheduleNotification(thread, item);
        items[i] = updated;
        changed = true;
      } catch (e) {
        debugPrint('Ошибка планирования уведомления: $e');
      }
    }
    return changed;
  }

  Future<MessengerProactiveMessage> _scheduleNotification(
    MessengerThread thread,
    MessengerProactiveMessage message,
  ) async {
    try {
      final numericId =
          await _notificationManager.scheduleMessengerNotification(
        title: thread.contact.name,
        body: message.text,
        scheduledDate: message.scheduledAt,
        contactId: message.contactId,
        messageId: message.id,
      );
      return message.copyWith(notificationId: numericId);
    } catch (_) {
      return message.copyWith(
        notificationId: _notificationManager.messengerNumericId(message.id),
      );
    }
  }

  Future<MessengerThread?> _selectThread() async {
    final threads = await _storageRepository.loadThreads();
    if (threads.isEmpty) return null;
    final preferred = threads.firstWhere(
      (thread) => thread.contact.id == 'friend' && _isThreadEligible(thread),
      orElse: () => threads.firstWhere(
        _isThreadEligible,
        orElse: () => threads.first,
      ),
    );
    if (!_isThreadEligible(preferred)) return null;
    return preferred;
  }

  bool _isThreadEligible(MessengerThread thread) {
    return thread.aiEnabled &&
        thread.persona.chatMode == MessengerChatMode.text;
  }

  bool _isEligible(MessengerThread thread) {
    return _isThreadEligible(thread);
  }

  DateTime _pickScheduleTime({
    required MessengerThread thread,
    required DateTime now,
    DateTime? last,
  }) {
    if (last != null) {
      final base = last.isAfter(now) ? last : now;
      final delay = _randomDelay(_followupDelayMin, _followupDelayMax);
      return _avoidQuietHours(base.add(delay));
    }
    final lastMessageAt = _latestMessageTime(thread.messages) ?? now;
    final base = lastMessageAt.isAfter(now) ? lastMessageAt : now;
    final delay = _randomDelay(_firstDelayMin, _firstDelayMax);
    return _avoidQuietHours(base.add(delay));
  }

  DateTime _avoidQuietHours(DateTime value) {
    final hour = value.hour;
    if (hour >= _quietHoursStart || hour < _quietHoursEnd) {
      final nextDay =
          hour >= _quietHoursStart ? value.add(const Duration(days: 1)) : value;
      final minute = _random.nextInt(_quietHoursResumeMinuteMax);
      return DateTime(
        nextDay.year,
        nextDay.month,
        nextDay.day,
        _quietHoursResumeHour,
        minute,
      );
    }
    return value;
  }

  DateTime _ensureFuture(DateTime value, DateTime now) {
    if (value.isAfter(now.add(_safeScheduleSkew))) return value;
    return now.add(_safeScheduleSkew);
  }

  Duration _randomDelay(Duration min, Duration max) {
    final safeMin = min.inMinutes;
    final safeMax = max.inMinutes <= safeMin ? safeMin : max.inMinutes;
    final minutes = safeMin + _random.nextInt(safeMax - safeMin + 1);
    return Duration(minutes: minutes);
  }

  DateTime? _latestScheduled(List<MessengerProactiveMessage> items) {
    DateTime? latest;
    for (final item in items) {
      if (latest == null || item.scheduledAt.isAfter(latest)) {
        latest = item.scheduledAt;
      }
    }
    return latest;
  }

  MessengerMessage? _lastMessage(List<MessengerMessage> messages, bool isMine) {
    for (final message in messages.reversed) {
      if (message.isMine == isMine && message.text.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  DateTime? _latestMessageTime(List<MessengerMessage> messages) {
    DateTime? latest;
    for (final message in messages) {
      final time = message.time;
      if (latest == null || time.isAfter(latest)) {
        latest = time;
      }
    }
    return latest;
  }

  List<MessengerMessage> _buildContext(List<MessengerMessage> messages) {
    final filtered = messages
        .where((message) => message.text.trim().isNotEmpty)
        .toList(growable: false);
    if (filtered.length <= 12) return List.of(filtered);
    return filtered.sublist(filtered.length - 12);
  }

  Future<String> _generateMessage(MessengerThread thread) async {
    final hasCredits = await CreditService().hasCreditsForText();
    if (!hasCredits) return '';

    final context = _buildContext(thread.messages);
    final lastUser = _lastMessage(thread.messages, true);
    final lastFriend = _lastMessage(thread.messages, false);
    final awaitingUser = lastFriend != null &&
        (lastUser == null || lastFriend.time.isAfter(lastUser.time));
    final avoidGreeting = _hasGreetingToday(thread.messages);
    final activityHint = _pickActivityHint(lastUser?.text ?? '', context);
    final friendPersona = await _loadPersona(thread.contact.id);
    final friendProfile = _loadFriendProfile(thread.contact.id);
    final moodState = await _moodService.load(thread.contact.id);
    final raw = await _aiService.generateProactiveMessage(
      thread: thread,
      recentMessages: context,
      friendPersona: friendPersona,
      friendProfile: friendProfile,
      lastUserMessage: lastUser?.text,
      activityHint: activityHint,
      moodState: moodState,
      userGender: userGender,
    );
    final cleaned = _cleanText(raw);
    final relType = friendProfile?.relationshipType;
    if (cleaned.isEmpty) {
      return _fallbackMessage(
        thread,
        activityHint,
        lastUser?.text,
        awaitingUser: awaitingUser,
        lastFriendText: lastFriend?.text,
        avoidGreeting: avoidGreeting,
        relationshipType: relType,
      );
    }
    final lastText = thread.messages.isEmpty
        ? ''
        : thread.messages.last.text.trim().toLowerCase();
    if (lastText.isNotEmpty && lastText == cleaned.toLowerCase()) {
      return _fallbackMessage(
        thread,
        activityHint,
        lastUser?.text,
        awaitingUser: awaitingUser,
        lastFriendText: lastFriend?.text,
        avoidGreeting: avoidGreeting,
        relationshipType: relType,
      );
    }
    final adjusted = _adjustGreetingIfNeeded(
      text: cleaned,
      avoidGreeting: avoidGreeting,
      thread: thread,
      activityHint: activityHint,
      lastUserMessage: lastUser?.text,
      awaitingUser: awaitingUser,
      lastFriendText: lastFriend?.text,
      relationshipType: relType,
    );
    if (adjusted.isNotEmpty) {
      await CreditService().useTextCredits('', adjusted);
    }
    return adjusted;
  }

  String _pickActivityHint(String userMessage, List<MessengerMessage> context) {
    final suggestion = _activitySuggester.buildSuggestion(
      userMessage: userMessage,
      recentMessages: context,
    );
    if (suggestion.options.isNotEmpty) {
      return suggestion.options.first;
    }
    return suggestion.fallback;
  }

  Future<FriendPersona> _loadPersona(String contactId) async {
    try {
      return await _personaRepository.load(contactId);
    } catch (_) {
      return const FriendPersona();
    }
  }

  FriendProfile? _loadFriendProfile(String contactId) {
    if (!contactId.startsWith('friend')) return null;
    return _friendProfileRepository.load(contactId);
  }

  String _fallbackMessage(
    MessengerThread thread,
    String activityHint,
    String? lastUserMessage, {
    required bool awaitingUser,
    String? lastFriendText,
    required bool avoidGreeting,
    String? relationshipType,
  }) {
    final isRomantic = relationshipType == FriendProfile.relationshipRomantic;
    if (awaitingUser) {
      final shortLast = _shortSnippet(lastUserMessage);
      final candidates = isRomantic
          ? <String>[
              'Скучаю. Ты где?',
              'Думаю о тебе. Напиши, когда сможешь.',
              'Ты как? Хочу поговорить с тобой.',
              'Не пропадай, жду.',
              'Ты на связи? Я тут, скучаю.',
              if (shortLast != null)
                'Про "$shortLast": расскажи, мне интересно.',
            ]
          : <String>[
              'Ты где? Я сейчас $activityHint.',
              'Ты ещё тут? Я на связи.',
              '${userGender == 'female' ? 'Пропала' : 'Пропал'}? Я тут, если что.',
              'Проверяю: ты на месте?',
              'Напиши, как будешь на связи.',
              'Не теряйся, если сможешь — ответь.',
              if (shortLast != null) 'Про "$shortLast": что думаешь?',
            ];
      return _pickNonRepeating(candidates, lastFriendText);
    }
    final normalizedLast = (lastUserMessage ?? '').trim().toLowerCase();
    if (normalizedLast.isNotEmpty && normalizedLast.length < 20) {
      return isRomantic
          ? 'Я сейчас $activityHint. Как ты?'
          : 'Я сейчас $activityHint. Ты как?';
    }
    final autoReplies = thread.persona.autoReplies;
    if (autoReplies.isNotEmpty) {
      final candidates = autoReplies.where((text) {
        final trimmed = text.trim();
        if (trimmed.isEmpty) return false;
        if (avoidGreeting && _isGreetingMessage(trimmed)) return false;
        return true;
      }).toList(growable: false);
      if (candidates.isNotEmpty) {
        return candidates[_random.nextInt(candidates.length)];
      }
    }
    return isRomantic
        ? 'Я сейчас $activityHint. Скучаю, как ты?'
        : 'Я сейчас $activityHint. Что нового?';
  }

  String _adjustGreetingIfNeeded({
    required String text,
    required bool avoidGreeting,
    required MessengerThread thread,
    required String activityHint,
    required String? lastUserMessage,
    required bool awaitingUser,
    required String? lastFriendText,
    String? relationshipType,
  }) {
    if (!avoidGreeting) return text;
    if (!_isGreetingMessage(text)) return text;
    final stripped = _stripGreetingPrefix(text);
    if (stripped.isNotEmpty && !_isGreetingMessage(stripped)) {
      return stripped;
    }
    return _fallbackMessage(
      thread,
      activityHint,
      lastUserMessage,
      awaitingUser: awaitingUser,
      lastFriendText: lastFriendText,
      avoidGreeting: true,
      relationshipType: relationshipType,
    );
  }

  bool _hasGreetingToday(List<MessengerMessage> messages) {
    final today = DateTime.now();
    for (final message in messages) {
      if (!_isSameDay(message.time, today)) continue;
      if (_isGreetingMessage(message.text)) return true;
    }
    return false;
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  bool _isGreetingMessage(String text) {
    var normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    normalized = normalized.replaceFirst(RegExp(r'^[^a-zа-я0-9]+'), '');
    if (normalized.isEmpty) return false;
    const greetings = [
      'доброе утро',
      'добрый день',
      'добрый вечер',
      'доброй ночи',
      'доброго утра',
      'доброго дня',
      'доброго вечера',
      'приветик',
      'привет',
      'здравств',
      'здраст',
      'здоров',
      'хай',
      'hello',
      'hi',
      'hey',
    ];
    for (final greeting in greetings) {
      if (normalized.startsWith(greeting)) return true;
    }
    return false;
  }

  String _stripGreetingPrefix(String text) {
    var normalized = text.trim();
    normalized = normalized.replaceFirst(RegExp(r'^[^a-zA-Zа-яА-Я0-9]+'), '');
    final lower = normalized.toLowerCase();
    final greetings = <String>[
      'доброе утро',
      'добрый день',
      'добрый вечер',
      'доброй ночи',
      'доброго утра',
      'доброго дня',
      'доброго вечера',
      'приветик',
      'привет',
      'здравств',
      'здраст',
      'здоров',
      'хай',
      'hello',
      'hi',
      'hey',
    ]..sort((a, b) => b.length.compareTo(a.length));
    for (final greeting in greetings) {
      if (lower.startsWith(greeting)) {
        final trimmed = normalized.substring(greeting.length).replaceFirst(
              RegExp(r'^[^a-zA-Zа-яА-Я0-9]+'),
              '',
            );
        return trimmed.trim();
      }
    }
    return normalized.trim();
  }

  String _pickNonRepeating(List<String> options, String? lastText) {
    final normalizedLast = (lastText ?? '').trim().toLowerCase();
    final filtered = options
        .where((text) => text.trim().toLowerCase() != normalizedLast)
        .toList();
    final pool = filtered.isNotEmpty ? filtered : options;
    return pool[_random.nextInt(pool.length)];
  }

  String? _shortSnippet(String? value) {
    if (value == null) return null;
    var text = value.trim();
    if (text.isEmpty) return null;
    if (text.length > 48) {
      text = '${text.substring(0, 45).trim()}...';
    }
    return text;
  }

  String _cleanText(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    value = _stripWrappingQuotes(value);
    value = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.length > 220) {
      value = value.substring(0, 220).trim();
    }
    return value;
  }

  String _stripWrappingQuotes(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith('“') && value.endsWith('”')) ||
            (value.startsWith('«') && value.endsWith('»')))) {
      return value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  Future<void> _appendMessage(
    MessengerProactiveMessage message, {
    DateTime? deliveredAt,
  }) async {
    final time = deliveredAt ?? DateTime.now();
    await _storageRepository.upsertMessage(
      contactId: message.contactId,
      message: MessengerMessage(
        id: message.id,
        text: message.text,
        time: time,
        isMine: false,
      ),
    );
  }

  Future<void> _pruneOldDelivered(
    List<MessengerProactiveMessage> items,
    DateTime now,
  ) async {
    final idsToRemove = items
        .where((item) =>
            item.deliveredAt != null &&
            now.difference(item.deliveredAt!) > _deliveredRetention)
        .map((item) => item.id)
        .toList();
    if (idsToRemove.isEmpty) return;
    await _repository.removeByIds(idsToRemove);
  }
}
