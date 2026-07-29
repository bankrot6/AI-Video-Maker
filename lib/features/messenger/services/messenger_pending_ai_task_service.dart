import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../services/ai_image_generation_service.dart';
import '../../../services/credit_service.dart';
import '../../../services/notification/notification_manager.dart';
import '../../personalization/data/friend_persona_repository.dart';
import '../../personalization/models/friend_persona.dart';
import '../data/friend_profile_repository.dart';
import '../data/messenger_pending_ai_task_repository.dart';
import '../data/messenger_storage_repository.dart';
import '../models/friend_profile.dart';
import '../models/messenger_contact.dart';
import '../models/messenger_message.dart';
import '../models/messenger_pending_ai_task.dart';
import '../models/messenger_thread.dart';
import 'messenger_activity_suggester.dart';
import 'messenger_ai_service.dart';
import 'messenger_image_prompt_builder.dart';
import 'messenger_mood_service.dart';
import 'messenger_outfit_service.dart';
import 'messenger_voice_service.dart';

class MessengerPendingAiTaskService {
  static const Duration _freshTaskGracePeriod = Duration(seconds: 12);

  final MessengerPendingAiTaskRepository _taskRepository;
  final MessengerStorageRepository _storageRepository;
  final MessengerAiService _aiService;
  final MessengerVoiceService _voiceService;
  final AiImageGenerationService _imageService;
  final MessengerOutfitService _outfitService;
  final FriendPersonaRepository _personaRepository;
  final FriendProfileRepository _friendProfileRepository;
  final MessengerMoodService _moodService;
  final CreditService _creditService;
  final MessengerImagePromptBuilder _imagePromptBuilder;
  final MessengerActivitySuggester _activitySuggester;
  final Uuid _uuid;
  final NotificationManager _notificationManager;

  bool _isProcessing = false;

  MessengerPendingAiTaskService({
    required MessengerPendingAiTaskRepository taskRepository,
    required MessengerStorageRepository storageRepository,
    required MessengerAiService aiService,
    required MessengerVoiceService voiceService,
    required AiImageGenerationService imageService,
    required MessengerOutfitService outfitService,
    required FriendPersonaRepository personaRepository,
    required FriendProfileRepository friendProfileRepository,
    required MessengerMoodService moodService,
    CreditService? creditService,
    MessengerImagePromptBuilder? imagePromptBuilder,
    MessengerActivitySuggester? activitySuggester,
    Uuid? uuid,
    NotificationManager? notificationManager,
  })  : _taskRepository = taskRepository,
        _storageRepository = storageRepository,
        _aiService = aiService,
        _voiceService = voiceService,
        _imageService = imageService,
        _outfitService = outfitService,
        _personaRepository = personaRepository,
        _friendProfileRepository = friendProfileRepository,
        _moodService = moodService,
        _creditService = creditService ?? CreditService(),
        _imagePromptBuilder = imagePromptBuilder ?? const MessengerImagePromptBuilder(),
        _activitySuggester = activitySuggester ?? MessengerActivitySuggester(),
        _uuid = uuid ?? const Uuid(),
        _notificationManager = notificationManager ?? NotificationManager();

  Future<void> processPendingTasks({int maxTasks = 20}) async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      final now = DateTime.now();
      final tasks = await _taskRepository.loadAll();
      var processed = 0;
      for (final task in tasks) {
        if (processed >= maxTasks) break;
        if (task.nextRetryAt != null && task.nextRetryAt!.isAfter(now)) {
          continue;
        }
        final taskAge = now.difference(task.updatedAt);
        if (task.retryCount == 0 && taskAge < _freshTaskGracePeriod) {
          continue;
        }
        final result = await _processTask(task);
        if (result.success) {
          await _taskRepository.removeById(task.id);
        } else {
          final retries = task.retryCount + 1;
          final delayMinutes = _retryDelayMinutes(retries);
          final next = DateTime.now().add(Duration(minutes: delayMinutes));
          await _taskRepository.upsert(
            task.copyWith(
              updatedAt: DateTime.now(),
              retryCount: retries,
              nextRetryAt: next,
              lastError: result.error,
            ),
          );
        }
        processed += 1;
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<_ProcessResult> _processTask(MessengerPendingAiTask task) async {
    try {
      final thread = await _storageRepository.loadThreadById(task.contactId);
      final userMessage = _findMessage(thread, task.userMessageId);
      if (userMessage == null) {
        return const _ProcessResult.success();
      }
      if (_isTaskAlreadyCompleted(task: task, thread: thread, userMessage: userMessage)) {
        return const _ProcessResult.success();
      }
      if (!thread.aiEnabled || userMessage.text.trim().isEmpty) {
        return const _ProcessResult.success();
      }
      await _storageRepository.updateMessage(
        contactId: thread.contact.id,
        messageId: userMessage.id,
        update: (message) => message.copyWith(
          status: MessengerMessageStatus.read,
        ),
      );
      if (task.type == MessengerPendingAiTaskType.aiFlow) {
        final done = await _processAiFlowTask(
          task: task,
          thread: thread,
          userMessage: userMessage,
        );
        if (!done) {
          return const _ProcessResult.failure('AI flow not finished');
        }
      }
      return const _ProcessResult.success();
    } catch (e) {
      debugPrint('Ошибка обработки pending AI задачи: $e');
      return _ProcessResult.failure(e.toString());
    }
  }

  Future<bool> _processAiFlowTask({
    required MessengerPendingAiTask task,
    required MessengerThread thread,
    required MessengerMessage userMessage,
  }) async {
    final creditUsage = await _creditService.getCreditUsage();
    if (creditUsage.remainingCredits <= 0) return true;
    final isFree = creditUsage.isFreeUser;

    final shouldVoiceReply = !isFree &&
        _shouldUseVoiceReply(
          thread: thread,
          wantsVoiceReply: task.wantsVoiceReply,
          isVoiceMessage: task.isVoiceMessage,
        );
    if (shouldVoiceReply) {
      return _processVoiceReply(
        thread: thread,
        userMessage: userMessage,
      );
    }
    if (!isFree && task.shouldWaitForImage) {
      await _appendIncomingMessage(
        contactId: thread.contact.id,
        text: _pickImageWaitReply(),
      );
      return true;
    }
    if (!isFree && task.isImageChat) {
      return _processImageChatReply(
        thread: thread,
        userMessage: userMessage,
      );
    }
    if (!isFree &&
        _looksLikeImageRequest(task.rawText) &&
        _isImageEligibleThread(thread)) {
      final generated = await _processAvatarImageReply(
        thread: thread,
        userMessage: userMessage,
      );
      if (generated) {
        return true;
      }
    }
    return _processTextReply(
      thread: thread,
      userMessage: userMessage,
    );
  }

  Future<bool> _processTextReply({
    required MessengerThread thread,
    required MessengerMessage userMessage,
  }) async {
    final reply = await _fetchAiReply(
      thread: thread,
      userMessage: userMessage,
    );
    if (reply == null || reply.trim().isEmpty) return false;
    await _appendIncomingMessage(
      contactId: thread.contact.id,
      text: reply.trim(),
    );
    return true;
  }

  Future<bool> _processVoiceReply({
    required MessengerThread thread,
    required MessengerMessage userMessage,
  }) async {
    final reply = await _fetchAiReply(
      thread: thread,
      userMessage: userMessage,
    );
    if (reply == null || reply.trim().isEmpty) return false;
    final canUseVoice = await _creditService.useVoiceCredits(reply);
    if (!canUseVoice) {
      await _appendIncomingMessage(
        contactId: thread.contact.id,
        text: reply.trim(),
      );
      return true;
    }
    final voiceResult = await _voiceService.generateVoiceReply(
      text: reply.trim(),
      contactId: thread.contact.id,
      friendProfile: _loadFriendProfile(thread.contact.id),
    );
    await _appendIncomingMessage(
      contactId: thread.contact.id,
      text: reply.trim(),
      audioPath: voiceResult.audioPath,
    );
    return true;
  }

  Future<bool> _processImageChatReply({
    required MessengerThread thread,
    required MessengerMessage userMessage,
  }) async {
    final hasCredits = await _creditService.hasCreditsForImage();
    if (!hasCredits) return false;
    final result = await _imageService.generateImageFromPrompt(userMessage.text);
    final file = result.file;
    if (file == null) return false;
    await _creditService.useImageCredits();
    await _appendIncomingMessage(
      contactId: thread.contact.id,
      text: 'Готово! Вот изображение.',
      imagePath: file.path,
    );
    return true;
  }

  Future<bool> _processAvatarImageReply({
    required MessengerThread thread,
    required MessengerMessage userMessage,
  }) async {
    final hasCredits = await _creditService.hasCreditsForImage();
    if (!hasCredits) return false;
    final context = _buildContextMessages(
      messages: thread.messages,
      excludeMessageId: userMessage.id,
    );
    final suggestion = _activitySuggester.buildSuggestion(
      userMessage: userMessage.text,
      recentMessages: context,
    );
    final friendPersona = await _safeLoadPersona(thread.contact.id);
    final friendProfile = _loadFriendProfile(thread.contact.id);
    final moodState = await _moodService.load(thread.contact.id);
    final outfitContext = await _outfitService.buildPromptContext(
      contactId: thread.contact.id,
    );
    final plan = await _aiService.detectImageIntentPlan(
      thread: thread,
      userMessage: userMessage.text,
      context: context,
      activityOptions: suggestion.options,
      fallbackWantsPhoto: true,
      fallbackReply: _pickImageWaitReply(),
      useFallbackPrompt: true,
      friendPersona: friendPersona,
      friendProfile: friendProfile,
      moodState: moodState,
      userGender: _readUserGender(),
      previousOutfit: outfitContext.previousOutfit,
      previousSceneKey: outfitContext.previousSceneKey,
      minutesSinceOutfit: outfitContext.minutesSince,
      outfitTtlMinutes: outfitContext.outfitTtlMinutes,
    );
    if (!plan.wantsPhoto || plan.imagePrompt.trim().isEmpty) return false;
    await _appendIncomingMessage(
      contactId: thread.contact.id,
      text: plan.replyText.trim().isEmpty ? _pickImageWaitReply() : plan.replyText,
    );
    MessengerOutfitDecision? outfitDecision;
    if (plan.isSelfie) {
      outfitDecision = await _outfitService.resolveOutfit(
        contactId: thread.contact.id,
        plan: plan,
      );
    }
    final prompt = _buildFinalImagePrompt(
      thread: thread,
      userMessage: userMessage.text,
      plan: plan,
      fallbackActivity: suggestion.fallback,
      friendProfile: friendProfile,
      outfitDecision: outfitDecision,
    );
    final avatarFile = _resolveAvatarFile(thread.contact);
    final result = plan.isSelfie && avatarFile != null
        ? await _imageService.generateImageFromPromptWithReference(
            prompt: prompt,
            referenceImage: avatarFile,
          )
        : await _imageService.generateImageFromPrompt(prompt);
    final file = result.file;
    if (file == null) return false;
    await _creditService.useImageCredits();
    final caption = plan.imageCaption.trim().isEmpty
        ? 'Вот так я сейчас'
        : plan.imageCaption.trim();
    await _appendIncomingMessage(
      contactId: thread.contact.id,
      text: caption,
      imagePath: file.path,
    );
    return true;
  }

  Future<String?> _fetchAiReply({
    required MessengerThread thread,
    required MessengerMessage userMessage,
  }) async {
    final hasCredits = await _creditService.hasCreditsForText();
    if (!hasCredits) return null;

    final friendPersona = await _safeLoadPersona(thread.contact.id);
    final friendProfile = _loadFriendProfile(thread.contact.id);
    final moodState = await _moodService.load(thread.contact.id);
    final context = _buildContextMessages(
      messages: thread.messages,
      excludeMessageId: userMessage.id,
    );
    String accumulated = '';
    try {
      await for (final chunk in _aiService.generateReplyStream(
        thread: thread,
        userMessage: userMessage.text,
        context: context,
        friendPersona: friendPersona,
        friendProfile: friendProfile,
        moodState: moodState,
        userGender: _readUserGender(),
      )) {
        accumulated += chunk;
      }
    } catch (e) {
      debugPrint('Ошибка генерации AI ответа из очереди: $e');
    }
    final parsed = _aiService.parseChatReply(accumulated);
    if (parsed.moodDelta != null && _isFriendContact(thread.contact.id)) {
      await _moodService.applyDelta(
        contactId: thread.contact.id,
        delta: parsed.moodDelta!,
      );
    }
    final reply = parsed.reply.trim();
    if (reply.isEmpty) return null;
    await _creditService.useTextCredits(userMessage.text, reply);
    return reply;
  }

  Future<void> _appendIncomingMessage({
    required String contactId,
    required String text,
    String? imagePath,
    String? audioPath,
  }) async {
    final message = MessengerMessage(
      id: _uuid.v4(),
      text: text,
      time: DateTime.now(),
      isMine: false,
      imagePath: imagePath,
      audioPath: audioPath,
    );
    await _storageRepository.upsertMessage(
      contactId: contactId,
      message: message,
    );
    await _notifyIncomingMessage(contactId: contactId, message: message);
  }

  Future<void> _notifyIncomingMessage({
    required String contactId,
    required MessengerMessage message,
  }) async {
    try {
      final enabled = await _notificationManager.areNotificationsEnabled();
      if (!enabled) return;
      await _notificationManager.sendMessengerNotification(
        title: _resolveNotificationTitle(contactId),
        body: _previewText(message),
        contactId: contactId,
        messageId: message.id,
      );
    } catch (e) {
      debugPrint('Ошибка отправки messenger уведомления: $e');
    }
  }

  String _resolveNotificationTitle(String contactId) {
    final profile = _loadFriendProfile(contactId);
    if (profile != null && profile.name.trim().isNotEmpty) {
      return profile.name.trim();
    }
    return 'Новое сообщение';
  }

  String _previewText(MessengerMessage message) {
    final hasAudio =
        (message.audioPath != null && message.audioPath!.isNotEmpty) ||
            (message.audioUrl != null && message.audioUrl!.isNotEmpty);
    if (hasAudio) return 'Голосовое сообщение';
    final text = message.text.trim();
    if (text.isNotEmpty) return text;
    if (message.imagePath != null || message.imageUrl != null) {
      return 'Изображение';
    }
    return 'Новое сообщение';
  }

  MessengerMessage? _findMessage(MessengerThread thread, String messageId) {
    for (final message in thread.messages) {
      if (message.id == messageId) return message;
    }
    return null;
  }

  bool _hasResponseAfter(MessengerThread thread, MessengerMessage userMessage) {
    for (final message in thread.messages) {
      if (!message.isMine && message.time.isAfter(userMessage.time)) {
        return true;
      }
    }
    return false;
  }

  bool _isTaskAlreadyCompleted({
    required MessengerPendingAiTask task,
    required MessengerThread thread,
    required MessengerMessage userMessage,
  }) {
    final expectsImage = task.isImageChat ||
        (_looksLikeImageRequest(task.rawText) && _isImageEligibleThread(thread));
    if (!expectsImage) {
      return _hasResponseAfter(thread, userMessage);
    }
    return _hasImageResponseAfter(thread, userMessage);
  }

  bool _hasImageResponseAfter(MessengerThread thread, MessengerMessage userMessage) {
    for (final message in thread.messages) {
      if (message.isMine || !message.time.isAfter(userMessage.time)) {
        continue;
      }
      final hasImagePath = message.imagePath != null && message.imagePath!.isNotEmpty;
      final hasImageUrl = message.imageUrl != null && message.imageUrl!.isNotEmpty;
      if (hasImagePath || hasImageUrl) {
        return true;
      }
    }
    return false;
  }

  int _retryDelayMinutes(int retryCount) {
    if (retryCount <= 1) return 1;
    if (retryCount == 2) return 2;
    if (retryCount == 3) return 5;
    if (retryCount == 4) return 10;
    if (retryCount == 5) return 20;
    if (retryCount == 6) return 40;
    return 60;
  }

  List<MessengerMessage> _buildContextMessages({
    required List<MessengerMessage> messages,
    String? excludeMessageId,
  }) {
    final filtered = messages
        .where(
          (message) =>
              message.text.trim().isNotEmpty && message.id != excludeMessageId,
        )
        .toList();
    if (filtered.length <= 12) return filtered;
    return filtered.sublist(filtered.length - 12);
  }

  Future<FriendPersona> _safeLoadPersona(String contactId) async {
    try {
      return await _personaRepository.load(contactId);
    } catch (_) {
      return const FriendPersona();
    }
  }

  FriendProfile? _loadFriendProfile(String contactId) {
    if (!_isFriendContact(contactId)) return null;
    return _friendProfileRepository.load(contactId);
  }

  String? _readUserGender() {
    return null;
  }

  bool _isFriendContact(String contactId) {
    return contactId.startsWith('friend');
  }

  bool _isImageEligibleThread(MessengerThread thread) {
    if (thread.persona.chatMode == MessengerChatMode.image) return false;
    return thread.contact.id.startsWith('friend');
  }

  bool _looksLikeImageRequest(String message) {
    final normalized = _normalizeMessage(message);
    if (normalized.isEmpty) return false;
    const photoRequestTokens = [
      'фото',
      'фотк',
      'селфи',
      'картин',
      'изображен',
      'снимок',
      'photo',
      'selfie',
      'picture',
      'pic',
    ];
    for (final token in photoRequestTokens) {
      if (normalized.contains(token)) return true;
    }
    const photoRequestActions = [
      'покажи',
      'скинь',
      'пришли',
      'отправь',
      'send',
      'show',
    ];
    const photoRequestTargets = [
      'себя',
      'лицо',
      'как ты',
      'как ты сейчас',
      'как выглядишь',
      'what do you look like',
    ];
    var hasAction = false;
    for (final action in photoRequestActions) {
      if (normalized.contains(action)) {
        hasAction = true;
        break;
      }
    }
    if (!hasAction) return false;
    for (final target in photoRequestTargets) {
      if (normalized.contains(target)) return true;
    }
    return false;
  }

  String _normalizeMessage(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _shouldUseVoiceReply({
    required MessengerThread thread,
    required bool wantsVoiceReply,
    required bool isVoiceMessage,
  }) {
    if (!thread.aiEnabled) return false;
    if (isVoiceMessage) return true;
    if (!wantsVoiceReply) return false;
    return thread.persona.chatMode == MessengerChatMode.text;
  }

  String _pickImageWaitReply() {
    const replies = [
      'Секунду, фото почти готово.',
      'Минутку, сейчас пришлю.',
      'Еще чуть-чуть, уже заканчиваю.',
      'Почти готово, еще пару секунд.',
      'Сейчас отправлю, буквально мгновение.',
    ];
    return replies[DateTime.now().millisecond % replies.length];
  }

  File? _resolveAvatarFile(MessengerContact contact) {
    final avatarPath = contact.avatarPath;
    if (avatarPath == null || avatarPath.isEmpty) return null;
    final file = File(avatarPath);
    if (!file.existsSync()) return null;
    return file;
  }

  String _buildFinalImagePrompt({
    required MessengerThread thread,
    required String userMessage,
    required MessengerImageReplyPlan plan,
    required String fallbackActivity,
    required FriendProfile? friendProfile,
    required MessengerOutfitDecision? outfitDecision,
  }) {
    final resolvedPrompt = _resolveImagePrompt(
      planPrompt: plan.imagePrompt,
      fallbackActivity: fallbackActivity,
      isSelfie: plan.isSelfie,
    );
    if (plan.isSelfie) {
      return _imagePromptBuilder.buildSelfiePrompt(
        userMessage: resolvedPrompt,
        caption: plan.imageCaption,
        friendName: thread.contact.name,
        profile: friendProfile,
        allowRandomLocation: true,
        outfit: outfitDecision?.outfit,
        totalMessageCount: thread.messages.length,
      );
    }
    return _imagePromptBuilder.buildScenePrompt(
      userMessage: resolvedPrompt,
      caption: plan.imageCaption,
      allowRandomLocation: true,
    );
  }

  String _resolveImagePrompt({
    required String planPrompt,
    required String fallbackActivity,
    required bool isSelfie,
  }) {
    final trimmedPlan = planPrompt.trim();
    if (trimmedPlan.isNotEmpty) return trimmedPlan;
    final fallback = fallbackActivity.trim();
    if (fallback.isEmpty) {
      return isSelfie
          ? 'phone selfie, casual setting, natural light'
          : 'photorealistic phone photo, natural light, no people';
    }
    if (isSelfie) {
      return 'phone selfie, $fallback, natural light';
    }
    return 'photorealistic phone photo of $fallback, natural light, no people';
  }
}

class _ProcessResult {
  final bool success;
  final String? error;

  const _ProcessResult._(this.success, this.error);

  const _ProcessResult.success() : this._(true, null);

  const _ProcessResult.failure(String? error) : this._(false, error);
}
