import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../services/nutrition_analysis/deepseek/deepseek_client.dart';
import '../../../services/nutrition_analysis/deepseek/deepseek_models.dart';
import '../../personalization/models/friend_persona.dart';
import '../models/friend_profile.dart';
import '../models/messenger_message.dart';
import '../models/messenger_mood_state.dart';
import '../models/messenger_thread.dart';
import 'messenger_context_builder.dart';
import 'messenger_prompt_builder.dart';

class MessengerAiService {
  final Map<MessengerAiModel, DeepSeekClient> _clientsByModel;
  final MessengerPromptBuilder _promptBuilder;
  final MessengerContextBuilder _contextBuilder;

  MessengerAiService({
    DeepSeekClient? client,
    DeepSeekClient? reasonerClient,
    MessengerPromptBuilder? promptBuilder,
    MessengerContextBuilder? contextBuilder,
  })  : _clientsByModel = {
          MessengerAiModel.chat: client ??
              DeepSeekClient.fromEnvironment(
                fastMode: false,
                enableCaching: false,
              ),
          MessengerAiModel.reasoner: reasonerClient ??
              DeepSeekClient.fromEnvironment(
                fastMode: false,
                enableCaching: false,
                model: DeepSeekModels.reasoner,
              ),
        },
        _promptBuilder = promptBuilder ?? const MessengerPromptBuilder(),
        _contextBuilder = contextBuilder ?? const MessengerContextBuilder();

  Stream<String> generateReplyStream({
    required MessengerThread thread,
    required String userMessage,
    required List<MessengerMessage> context,
    FriendPersona? friendPersona,
    FriendProfile? friendProfile,
    MessengerMoodState? moodState,
    String? userGender,
  }) async* {
    try {
      final personaNotes = friendPersona ?? const FriendPersona();
      final conversationContext = _contextBuilder.build(
        contact: thread.contact,
        persona: thread.persona,
        friendPersona: personaNotes,
        recentMessages: context,
        userMessage: userMessage,
        moodState: moodState,
      );
      final prompt = _promptBuilder.buildChatPrompt(
        contact: thread.contact,
        persona: thread.persona,
        memory: thread.memory,
        recentMessages: context,
        userMessage: userMessage,
        friendPersona: personaNotes,
        conversationContext: conversationContext,
        relationshipType: friendProfile?.relationshipType,
        userGender: userGender,
        totalMessageCount: thread.messages.length,
      );
      yield* _clientForThread(thread).generateTextStream(prompt);
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка DeepSeek streaming: $e');
    }
  }

  Future<String> generateProactiveMessage({
    required MessengerThread thread,
    required List<MessengerMessage> recentMessages,
    FriendPersona? friendPersona,
    FriendProfile? friendProfile,
    String? lastUserMessage,
    String? activityHint,
    MessengerMoodState? moodState,
    String? userGender,
  }) async {
    try {
      final personaNotes = friendPersona ?? const FriendPersona();
      final conversationContext = _contextBuilder.build(
        contact: thread.contact,
        persona: thread.persona,
        friendPersona: personaNotes,
        recentMessages: recentMessages,
        userMessage: lastUserMessage ?? '',
        moodState: moodState,
      );
      final prompt = _promptBuilder.buildProactiveMessagePrompt(
        contact: thread.contact,
        persona: thread.persona,
        memory: thread.memory,
        recentMessages: recentMessages,
        friendPersona: personaNotes,
        conversationContext: conversationContext,
        relationshipType: friendProfile?.relationshipType,
        userGender: userGender,
        activityHint: activityHint,
      );
      final response = await _clientForThread(thread).generateText(prompt);
      return _cleanProactiveText(response);
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка proactive сообщения: $e');
      return '';
    }
  }

  Future<MessengerImageReplyPlan> generateImageReplyPlan({
    required MessengerThread thread,
    required String userMessage,
    required List<MessengerMessage> context,
    required List<String> activityOptions,
    required String fallbackCaption,
    String? fallbackReply,
    FriendPersona? friendPersona,
    FriendProfile? friendProfile,
    VoidCallback? onFirstChunk,
    String? previousOutfit,
    String? previousSceneKey,
    int? minutesSinceOutfit,
    int? outfitTtlMinutes,
    MessengerMoodState? moodState,
    String? userGender,
  }) async {
    final fallback = _fallbackImagePlan(
      userMessage: userMessage,
      fallbackCaption: fallbackCaption,
      fallbackReply: fallbackReply,
    );
    try {
      final personaNotes = friendPersona ?? const FriendPersona();
      final conversationContext = _contextBuilder.build(
        contact: thread.contact,
        persona: thread.persona,
        friendPersona: personaNotes,
        recentMessages: context,
        userMessage: userMessage,
        moodState: moodState,
      );
      final prompt = _promptBuilder.buildImageReplyPlanPrompt(
        contact: thread.contact,
        persona: thread.persona,
        memory: thread.memory,
        recentMessages: context,
        userMessage: userMessage,
        friendPersona: personaNotes,
        conversationContext: conversationContext,
        activityOptions: activityOptions,
        friendProfile: friendProfile,
        relationshipType: friendProfile?.relationshipType,
        userGender: userGender,
        previousOutfit: previousOutfit,
        previousSceneKey: previousSceneKey,
        minutesSinceOutfit: minutesSinceOutfit,
        outfitTtlMinutes: outfitTtlMinutes,
        totalMessageCount: thread.messages.length,
      );
      final stream = _clientForThread(thread).generateTextStream(prompt);
      final result = await _parseImageReplyPlanStream(
        stream,
        fallback: fallback,
        defaultWantsPhoto: true,
        onFirstChunk: onFirstChunk,
      );
      var raw = result.raw.trim();
      var plan = result.plan;
      if (raw.isEmpty || _extractJson(raw) == null) {
        final retry = await _clientForThread(thread).generateText(prompt);
        debugPrint('🟣 MESSENGER: DeepSeek фото-ответ retry raw: $retry');
        raw = retry.trim();
        plan = _parseImageReplyPlan(
          raw,
          fallback: fallback,
          defaultWantsPhoto: true,
        );
      }
      debugPrint('🟣 MESSENGER: DeepSeek фото-ответ raw: $raw');
      debugPrint(
        '🟣 MESSENGER: DeepSeek фото-ответ parsed: reply="${plan.replyText}", '
        'caption="${plan.imageCaption}", prompt="${plan.imagePrompt}"',
      );
      return plan;
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка плана фото: $e');
      return fallback;
    }
  }

  Future<MessengerImageReplyPlan> detectImageIntentPlan({
    required MessengerThread thread,
    required String userMessage,
    required List<MessengerMessage> context,
    required List<String> activityOptions,
    required bool fallbackWantsPhoto,
    String? fallbackReply,
    bool useFallbackPrompt = true,
    FriendPersona? friendPersona,
    FriendProfile? friendProfile,
    VoidCallback? onFirstChunk,
    String? previousOutfit,
    String? previousSceneKey,
    int? minutesSinceOutfit,
    int? outfitTtlMinutes,
    MessengerMoodState? moodState,
    String? userGender,
  }) async {
    var fallback = _fallbackImagePlan(
      userMessage: userMessage,
      fallbackCaption: activityOptions.isNotEmpty ? activityOptions.first : '',
      fallbackReply: fallbackReply,
      wantsPhoto: fallbackWantsPhoto,
    );
    if (!useFallbackPrompt) {
      fallback = MessengerImageReplyPlan(
        wantsPhoto: fallback.wantsPhoto,
        isSelfie: fallback.wantsPhoto ? fallback.isSelfie : false,
        replyText: fallback.replyText,
        imageCaption: fallback.imageCaption,
        imagePrompt: '',
        outfit: '',
        sceneKey: '',
        usePreviousOutfit: false,
      );
    }
    try {
      final personaNotes = friendPersona ?? const FriendPersona();
      final conversationContext = _contextBuilder.build(
        contact: thread.contact,
        persona: thread.persona,
        friendPersona: personaNotes,
        recentMessages: context,
        userMessage: userMessage,
        moodState: moodState,
      );
      final prompt = _promptBuilder.buildImageIntentPrompt(
        contact: thread.contact,
        persona: thread.persona,
        memory: thread.memory,
        recentMessages: context,
        userMessage: userMessage,
        friendPersona: personaNotes,
        conversationContext: conversationContext,
        activityOptions: activityOptions,
        friendProfile: friendProfile,
        relationshipType: friendProfile?.relationshipType,
        userGender: userGender,
        previousOutfit: previousOutfit,
        previousSceneKey: previousSceneKey,
        minutesSinceOutfit: minutesSinceOutfit,
        outfitTtlMinutes: outfitTtlMinutes,
        totalMessageCount: thread.messages.length,
      );
      final stream = _clientForThread(thread).generateTextStream(prompt);
      final result = await _parseImageReplyPlanStream(
        stream,
        fallback: fallback,
        defaultWantsPhoto: fallbackWantsPhoto,
        onFirstChunk: onFirstChunk,
      );
      var raw = result.raw.trim();
      var plan = result.plan;
      if (raw.isEmpty || _extractJson(raw) == null) {
        final retry = await _clientForThread(thread).generateText(prompt);
        debugPrint('🟣 MESSENGER: DeepSeek intent retry raw: $retry');
        raw = retry.trim();
        plan = _parseImageReplyPlan(
          raw,
          fallback: fallback,
          defaultWantsPhoto: fallbackWantsPhoto,
        );
      }
      debugPrint('🟣 MESSENGER: DeepSeek intent raw: $raw');
      debugPrint(
        '🟣 MESSENGER: DeepSeek intent parsed: wantsPhoto=${plan.wantsPhoto}, '
        'reply="${plan.replyText}", caption="${plan.imageCaption}", '
        'prompt="${plan.imagePrompt}"',
      );
      return plan;
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка intent фото: $e');
      return fallback;
    }
  }

  Future<String> generateImageCaption({
    required MessengerThread thread,
    required String userMessage,
    required List<MessengerMessage> context,
    required List<String> activityOptions,
    required String fallbackCaption,
    FriendPersona? friendPersona,
    FriendProfile? friendProfile,
    MessengerMoodState? moodState,
    String? userGender,
  }) async {
    try {
      final personaNotes = friendPersona ?? const FriendPersona();
      final conversationContext = _contextBuilder.build(
        contact: thread.contact,
        persona: thread.persona,
        friendPersona: personaNotes,
        recentMessages: context,
        userMessage: userMessage,
        moodState: moodState,
      );
      final prompt = _promptBuilder.buildImageCaptionPrompt(
        contact: thread.contact,
        persona: thread.persona,
        memory: thread.memory,
        recentMessages: context,
        userMessage: userMessage,
        friendPersona: personaNotes,
        conversationContext: conversationContext,
        activityOptions: activityOptions,
        relationshipType: friendProfile?.relationshipType,
        userGender: userGender,
      );
      final response = await _clientForThread(thread).generateText(prompt);
      return _cleanCaption(response, fallbackCaption);
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка подписи: $e');
      return fallbackCaption;
    }
  }

  Future<MessengerStoryPlan> generateStoryPlan({
    required MessengerThread thread,
    required String userMessage,
    required List<MessengerMessage> context,
    required List<String> activityOptions,
    required String fallbackCaption,
    FriendPersona? friendPersona,
    FriendProfile? friendProfile,
    MessengerMoodState? moodState,
    VoidCallback? onFirstChunk,
    String? userGender,
  }) async {
    final fallback = _fallbackStoryPlan(
      userMessage: userMessage,
      fallbackCaption: fallbackCaption,
    );
    try {
      final personaNotes = friendPersona ?? const FriendPersona();
      final conversationContext = _contextBuilder.build(
        contact: thread.contact,
        persona: thread.persona,
        friendPersona: personaNotes,
        recentMessages: context,
        userMessage: userMessage,
        moodState: moodState,
      );
      final prompt = _promptBuilder.buildStoryPlanPrompt(
        contact: thread.contact,
        persona: thread.persona,
        memory: thread.memory,
        recentMessages: context,
        userMessage: userMessage,
        friendPersona: personaNotes,
        conversationContext: conversationContext,
        activityOptions: activityOptions,
        friendProfile: friendProfile,
        relationshipType: friendProfile?.relationshipType,
        userGender: userGender,
      );
      final stream = _clientForThread(thread).generateTextStream(prompt);
      final result = await _parseStoryPlanStream(
        stream,
        fallback: fallback,
        defaultIsSelfie: fallback.isSelfie,
        onFirstChunk: onFirstChunk,
      );
      var raw = result.raw.trim();
      var plan = result.plan;
      if (raw.isEmpty || _extractJson(raw) == null) {
        final retry = await _clientForThread(thread).generateText(prompt);
        debugPrint('🟣 MESSENGER: DeepSeek story retry raw: $retry');
        raw = retry.trim();
        plan = _parseStoryPlan(
          raw,
          fallback: fallback,
          defaultIsSelfie: fallback.isSelfie,
        );
      }
      debugPrint('🟣 MESSENGER: DeepSeek story raw: $raw');
      debugPrint(
        '🟣 MESSENGER: DeepSeek story parsed: reply="${plan.replyText}", '
        'caption="${plan.caption}", prompt="${plan.prompt}"',
      );
      return plan;
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка плана сторис: $e');
      return fallback;
    }
  }

  Future<String> updateMemorySummary({
    required MessengerThread thread,
    required List<MessengerMessage> recentMessages,
    String? userGender,
  }) async {
    try {
      final prompt = _promptBuilder.buildMemoryUpdatePrompt(
        contact: thread.contact,
        persona: thread.persona,
        memory: thread.memory,
        recentMessages: recentMessages,
        userGender: userGender,
      );
      final response = await _clientForThread(thread).generateText(prompt);
      return response.trim();
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка обновления памяти: $e');
      return thread.memory.summary;
    }
  }

  MessengerChatReply parseChatReply(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const MessengerChatReply(reply: '');
    }
    final jsonText = _extractJson(trimmed);
    if (jsonText == null) {
      return MessengerChatReply(reply: trimmed);
    }
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) {
        payload = decoded;
      }
    } catch (_) {
      payload = null;
    }
    if (payload == null) {
      return MessengerChatReply(reply: trimmed);
    }
    final reply = _cleanChatReply(
      _readFirst(payload, const ['reply', 'message', 'response', 'text']),
    );
    final moodDelta = _parseMoodDelta(payload);
    final photoOffer = _parsePhotoOffer(payload);
    if (reply.isNotEmpty) {
      return MessengerChatReply(
        reply: reply,
        moodDelta: moodDelta,
        photoOffer: photoOffer,
      );
    }
    return MessengerChatReply(
      reply: '',
      moodDelta: moodDelta,
      photoOffer: photoOffer,
    );
  }

  DeepSeekClient _clientForThread(MessengerThread thread) {
    final model = thread.persona.aiModel;
    if (model == MessengerAiModel.reasoner) {
      return _clientsByModel[MessengerAiModel.chat]!;
    }
    return _clientsByModel[model] ?? _clientsByModel[MessengerAiModel.chat]!;
  }

  String _cleanCaption(String raw, String fallbackCaption) {
    var value = raw.trim();
    if (value.isEmpty) return fallbackCaption;
    if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
      value = value.substring(1, value.length - 1).trim();
    }
    value = value.replaceAll(RegExp(r'[^a-zA-Zа-яА-ЯёЁ0-9 ]'), ' ');
    value = value.replaceAll(RegExp(r'\s+'), ' ');
    if (value.length > 80) {
      value = value.substring(0, 80).trim();
    }
    return value.isEmpty ? fallbackCaption : value;
  }

  String _cleanProactiveText(String raw) {
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

  String _cleanChatReply(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    value = _stripWrappingQuotes(value);
    value = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value;
  }

  MessengerMoodDelta? _parseMoodDelta(Map<String, dynamic> payload) {
    final rawDelta = payload['mood_delta'] ?? payload['moodDelta'];
    if (rawDelta is Map<String, dynamic>) {
      return _deltaFromMap(rawDelta);
    }
    if (rawDelta is Map) {
      return _deltaFromMap(rawDelta.cast<String, dynamic>());
    }
    if (payload.containsKey('joy') ||
        payload.containsKey('anger') ||
        payload.containsKey('fun') ||
        payload.containsKey('sadness') ||
        payload.containsKey('humor') ||
        payload.containsKey('boring')) {
      return _deltaFromMap(payload);
    }
    return null;
  }

  MessengerMoodDelta? _deltaFromMap(Map<String, dynamic> map) {
    final delta = MessengerMoodDelta(
      joy: _readInt(map['joy']),
      anger: _readInt(map['anger']),
      fun: _readInt(map['fun']),
      sadness: _readInt(map['sadness']),
      humor: _readInt(map['humor']),
      boring: _readInt(map['boring']),
    );
    return delta.isEmpty ? null : delta;
  }

  MessengerImageReplyPlan? _parsePhotoOffer(Map<String, dynamic> payload) {
    final raw = payload['photo_offer'] ?? payload['photoOffer'];
    if (raw == null) return null;
    if (raw is! Map) return null;
    final map =
        raw is Map<String, dynamic> ? raw : raw.cast<String, dynamic>();
    final imagePrompt = _cleanPromptText(
      _readFirst(map, const ['image_prompt', 'imagePrompt', 'prompt']),
    );
    if (imagePrompt.isEmpty) return null;
    final replyText = _cleanShortText(
      _readFirst(
          map, const ['reply_on_accept', 'replyOnAccept', 'reply']),
      maxLen: 200,
    );
    final imageCaption = _cleanCaptionText(
      _readFirst(map, const ['image_caption', 'imageCaption', 'caption']),
    );
    final isSelfie = _readBool(
      map,
      const ['is_selfie', 'isSelfie', 'selfie'],
      defaultValue: false,
    );
    final outfit = _cleanOutfitText(
      _readFirst(map, const ['outfit', 'clothes']),
    );
    final sceneKey = _cleanSceneKey(
      _readFirst(map, const ['scene_key', 'sceneKey', 'scene']),
    );
    return MessengerImageReplyPlan(
      wantsPhoto: true,
      isSelfie: isSelfie,
      replyText: replyText.isEmpty ? 'Сек, щас скину' : replyText,
      imagePrompt: imagePrompt,
      imageCaption: imageCaption.isEmpty ? 'фото' : imageCaption,
      outfit: outfit,
      sceneKey: sceneKey,
      usePreviousOutfit: false,
    );
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      return parsed ?? 0;
    }
    return 0;
  }

  MessengerImageReplyPlan _parseImageReplyPlan(
    String raw, {
    required MessengerImageReplyPlan fallback,
    required bool defaultWantsPhoto,
  }) {
    final jsonText = _extractJson(raw) ?? raw;
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) {
        payload = decoded;
      }
    } catch (_) {
      payload = null;
    }
    if (payload == null) return fallback;
    final reply = _cleanShortText(
      _readFirst(payload, const ['reply', 'message', 'response']),
      maxLen: 200,
    );
    final caption = _cleanCaptionText(
      _readFirst(payload, const ['image_caption', 'caption', 'imageCaption']),
    );
    final prompt = _cleanPromptText(
      _readFirst(payload, const ['image_prompt', 'prompt', 'imagePrompt']),
    );
    final outfit = _cleanOutfitText(
      _readFirst(payload, const ['outfit', 'clothes', 'clothing']),
    );
    final sceneKey = _cleanSceneKey(
      _readFirst(payload, const ['scene_key', 'scene', 'sceneKey']),
    );
    final usePreviousOutfit = _readBool(
      payload,
      const [
        'use_previous_outfit',
        'usePreviousOutfit',
        'reuse_outfit',
        'reuseOutfit',
      ],
      defaultValue: false,
    );
    final wantsPhoto = _readBool(
      payload,
      const ['wants_photo', 'wantsPhoto', 'needs_photo', 'needsPhoto'],
      defaultValue: defaultWantsPhoto,
    );
    final isSelfie = wantsPhoto
        ? _readBool(
            payload,
            const [
              'is_selfie',
              'isSelfie',
              'selfie',
              'selfie_photo',
              'selfiePhoto',
              'is_self_photo',
              'image_selfie',
            ],
            defaultValue: fallback.isSelfie,
          )
        : false;
    var replyText = reply.isEmpty ? fallback.replyText : reply;
    if (wantsPhoto) {
      replyText = _ensurePositivePhotoReply(replyText, fallback.replyText);
    }
    var effectiveWantsPhoto = wantsPhoto;
    if (effectiveWantsPhoto && _isPhotoRefusalOrPostponeReply(replyText)) {
      effectiveWantsPhoto = false;
      debugPrint(
        '🟣 MESSENGER: Текст ответа — отказ/отложить, отключаем генерацию фото',
      );
    }
    return MessengerImageReplyPlan(
      wantsPhoto: effectiveWantsPhoto,
      isSelfie: isSelfie,
      replyText: replyText,
      imageCaption: caption.isEmpty ? fallback.imageCaption : caption,
      imagePrompt: prompt.isEmpty ? fallback.imagePrompt : prompt,
      outfit: outfit.isEmpty ? fallback.outfit : outfit,
      sceneKey: sceneKey.isEmpty ? fallback.sceneKey : sceneKey,
      usePreviousOutfit: usePreviousOutfit,
    );
  }

  Future<_PlanStreamResult> _parseImageReplyPlanStream(
    Stream<String> stream, {
    required MessengerImageReplyPlan fallback,
    required bool defaultWantsPhoto,
    VoidCallback? onFirstChunk,
  }) async {
    final buffer = StringBuffer();
    var hasChunk = false;
    await for (final chunk in stream) {
      if (!hasChunk) {
        hasChunk = true;
        onFirstChunk?.call();
      }
      buffer.write(chunk);
      final plan = _tryParseImageReplyPlan(
        buffer.toString(),
        fallback: fallback,
        defaultWantsPhoto: defaultWantsPhoto,
      );
      if (plan != null) {
        return _PlanStreamResult(plan, buffer.toString());
      }
    }
    final raw = buffer.toString();
    final plan = _parseImageReplyPlan(
      raw,
      fallback: fallback,
      defaultWantsPhoto: defaultWantsPhoto,
    );
    return _PlanStreamResult(plan, raw);
  }

  MessengerImageReplyPlan? _tryParseImageReplyPlan(
    String raw, {
    required MessengerImageReplyPlan fallback,
    required bool defaultWantsPhoto,
  }) {
    final jsonText = _extractJson(raw);
    if (jsonText == null) return null;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
    } catch (_) {
      return null;
    }
    return _parseImageReplyPlan(
      jsonText,
      fallback: fallback,
      defaultWantsPhoto: defaultWantsPhoto,
    );
  }

  MessengerImageReplyPlan _fallbackImagePlan({
    required String userMessage,
    required String fallbackCaption,
    String? fallbackReply,
    bool wantsPhoto = true,
    bool? isSelfie,
  }) {
    final resolvedSelfie =
        wantsPhoto && (isSelfie ?? _looksLikeSelfieRequest(userMessage));
    final replyText = (fallbackReply != null && fallbackReply.trim().isNotEmpty)
        ? fallbackReply.trim()
        : _fallbackReplyText(userMessage);
    final imageCaption = _fallbackImageCaption(
      userMessage,
      fallbackCaption,
      isSelfie: resolvedSelfie,
    );
    final imagePrompt = _fallbackImagePrompt(
      userMessage,
      isSelfie: resolvedSelfie,
    );
    return MessengerImageReplyPlan(
      wantsPhoto: wantsPhoto,
      isSelfie: resolvedSelfie,
      replyText: replyText,
      imageCaption: imageCaption,
      imagePrompt: imagePrompt,
      outfit: '',
      sceneKey: '',
      usePreviousOutfit: false,
    );
  }

  MessengerStoryPlan _fallbackStoryPlan({
    required String userMessage,
    required String fallbackCaption,
  }) {
    final isSelfie = _looksLikeSelfieRequest(userMessage);
    final replyText = 'Сейчас сделаю сторис и скоро выложу.';
    final caption = fallbackCaption.trim().isNotEmpty
        ? fallbackCaption.trim()
        : (isSelfie ? 'мои дела' : 'мой день');
    return MessengerStoryPlan(
      replyText: replyText,
      caption: caption,
      prompt: '',
      isSelfie: isSelfie,
    );
  }

  MessengerStoryPlan _parseStoryPlan(
    String raw, {
    required MessengerStoryPlan fallback,
    required bool defaultIsSelfie,
  }) {
    final jsonText = _extractJson(raw) ?? raw;
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) {
        payload = decoded;
      }
    } catch (_) {
      payload = null;
    }
    if (payload == null) return fallback;
    final reply = _cleanShortText(
      _readFirst(payload, const ['reply', 'message', 'response', 'text']),
      maxLen: 200,
    );
    final caption = _cleanCaptionText(
      _readFirst(payload, const ['caption', 'story_caption', 'storyCaption']),
    );
    final prompt = _cleanStoryPrompt(
      _readFirst(payload, const [
        'story_prompt',
        'storyPrompt',
        'prompt',
        'video_prompt',
        'videoPrompt',
      ]),
    );
    final isSelfie = _readBool(
      payload,
      const ['is_selfie', 'isSelfie', 'selfie', 'selfie_story'],
      defaultValue: defaultIsSelfie,
    );
    return MessengerStoryPlan(
      replyText: reply.isEmpty ? fallback.replyText : reply,
      caption: caption.isEmpty ? fallback.caption : caption,
      prompt: prompt.isEmpty ? fallback.prompt : prompt,
      isSelfie: isSelfie,
    );
  }

  Future<_StoryPlanStreamResult> _parseStoryPlanStream(
    Stream<String> stream, {
    required MessengerStoryPlan fallback,
    required bool defaultIsSelfie,
    VoidCallback? onFirstChunk,
  }) async {
    final buffer = StringBuffer();
    var hasChunk = false;
    await for (final chunk in stream) {
      if (!hasChunk) {
        hasChunk = true;
        onFirstChunk?.call();
      }
      buffer.write(chunk);
      final plan = _tryParseStoryPlan(
        buffer.toString(),
        fallback: fallback,
        defaultIsSelfie: defaultIsSelfie,
      );
      if (plan != null) {
        return _StoryPlanStreamResult(plan, buffer.toString());
      }
    }
    final raw = buffer.toString();
    final plan = _parseStoryPlan(
      raw,
      fallback: fallback,
      defaultIsSelfie: defaultIsSelfie,
    );
    return _StoryPlanStreamResult(plan, raw);
  }

  MessengerStoryPlan? _tryParseStoryPlan(
    String raw, {
    required MessengerStoryPlan fallback,
    required bool defaultIsSelfie,
  }) {
    final jsonText = _extractJson(raw);
    if (jsonText == null) return null;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
    } catch (_) {
      return null;
    }
    return _parseStoryPlan(
      jsonText,
      fallback: fallback,
      defaultIsSelfie: defaultIsSelfie,
    );
  }

  String _fallbackReplyText(String userMessage) {
    final normalized = userMessage.toLowerCase();
    if (normalized.contains('селфи') || normalized.contains('фото')) {
      return 'Сейчас, минутку, сделаю фото.';
    }
    return 'Сейчас, секундочку, пришлю.';
  }

  String _ensurePositivePhotoReply(String reply, String fallbackReply) {
    final normalizedReply = reply.trim();
    if (normalizedReply.isNotEmpty &&
        !_looksLikeNegativePhotoReply(normalizedReply)) {
      return normalizedReply;
    }
    final normalizedFallback = fallbackReply.trim();
    if (normalizedFallback.isNotEmpty &&
        !_looksLikeNegativePhotoReply(normalizedFallback)) {
      return normalizedFallback;
    }
    return 'Сейчас, минутку, сделаю фото.';
  }

  bool _looksLikeNegativePhotoReply(String reply) {
    final text = reply.toLowerCase();
    const negativeSeeds = [
      'не могу',
      'не смогу',
      'не получится',
      'не выйдет',
      'не умею',
      'невозможно',
      'не стану',
    ];
    const photoTokens = [
      'фото',
      'селфи',
      'картин',
      'изображен',
      'снимок',
      'фотк',
      'фотограф',
      'сфотк',
    ];
    const actionTokens = [
      'сделать',
      'прислать',
      'отправить',
      'скинуть',
      'показать',
    ];
    final hasNegative = negativeSeeds.any((phrase) => text.contains(phrase));
    if (!hasNegative) return false;
    final hasPhoto = photoTokens.any((token) => text.contains(token));
    final hasAction = actionTokens.any((token) => text.contains(token));
    return hasPhoto || hasAction;
  }

  bool _isPhotoRefusalOrPostponeReply(String reply) {
    final text = reply.trim().toLowerCase();
    if (text.isEmpty) return false;
    const refusalPhrases = [
      'так сразу',
      'сначала пообщаемся',
      'пообщаемся потом',
      'давай сначала',
      'узнать тебя',
      'узнать тебя поближе',
      'поближе, а там',
      'а там посмотрим',
      'только начали общаться',
      'не так быстро',
      'потом снова',
      'дай лучше узнать',
      'get to know',
      'know you better',
      'not so fast',
    ];
    return refusalPhrases.any((phrase) => text.contains(phrase));
  }

  String _fallbackImageCaption(
    String userMessage,
    String fallbackCaption, {
    required bool isSelfie,
  }) {
    if (!isSelfie) {
      return 'Вот запрошенное фото';
    }
    final normalized = userMessage.toLowerCase();
    if (normalized.contains('пробеж') || normalized.contains('бег')) {
      return 'Вот так я на пробежке';
    }
    if (normalized.contains('спорт') ||
        normalized.contains('трен') ||
        normalized.contains('зал')) {
      return 'Вот так я на тренировке';
    }
    if (normalized.contains('ванн') || normalized.contains('душ')) {
      return 'Вот так я в ванной';
    }
    if (normalized.contains('работ')) return 'Вот так я работаю';
    if (normalized.contains('учеб') || normalized.contains('учусь')) {
      return 'Вот так я учусь';
    }
    if (normalized.contains('дорог') || normalized.contains('еду')) {
      return 'Вот так я в дороге';
    }
    if (_looksLikeOutdoor(normalized) &&
        _seasonLabel(DateTime.now()) == 'зима') {
      return 'Вот так я зимой на улице';
    }
    if (normalized.contains('кофе') || normalized.contains('кафе')) {
      return 'Вот так я пью кофе';
    }
    if (fallbackCaption.trim().isNotEmpty) {
      return 'Вот так я ${fallbackCaption.trim()}';
    }
    return 'Вот так я сейчас';
  }

  String _fallbackImagePrompt(
    String userMessage, {
    required bool isSelfie,
  }) {
    if (!isSelfie) {
      return 'photorealistic phone photo of the requested subject, natural light, no people, no text';
    }
    final normalized = userMessage.toLowerCase();
    if (normalized.contains('пробеж') || normalized.contains('бег')) {
      return 'phone selfie outdoors while running, athletic wear, natural light';
    }
    if (normalized.contains('спорт') ||
        normalized.contains('трен') ||
        normalized.contains('зал')) {
      return 'phone selfie at the gym, athletic wear, fitness studio, natural light';
    }
    if (normalized.contains('ванн') || normalized.contains('душ')) {
      return 'phone selfie in a clean bathroom, mirror selfie, soft indoor light, casual homewear or bathrobe';
    }
    if (normalized.contains('работ')) {
      return 'phone selfie, working at desk with laptop, modern office, natural light';
    }
    if (normalized.contains('учеб') || normalized.contains('учусь')) {
      return 'phone selfie, studying with notebooks, cozy room, natural light';
    }
    if (_looksLikeOutdoor(normalized) &&
        _seasonLabel(DateTime.now()) == 'зима') {
      return 'phone selfie outdoors in winter, warm coat, scarf, cold weather, soft daylight';
    }
    if (normalized.contains('дорог') || normalized.contains('еду')) {
      return 'phone selfie in transit, casual, natural light';
    }
    if (normalized.contains('кофе') || normalized.contains('кафе')) {
      return 'phone selfie in a cozy cafe, coffee cup, warm light';
    }
    return 'phone selfie, casual setting, natural light';
  }

  bool _looksLikeSelfieRequest(String message) {
    final text = message.toLowerCase();
    const directPhrases = [
      'селфи',
      'selfie',
      'сфоткайся',
      'сфотографируйся',
      'покажи себя',
      'покажи себя сейчас',
      'покажи как ты',
      'фото себя',
      'фото тебя',
      'фотку себя',
      'фотку тебя',
      'снимок себя',
      'снимок тебя',
      'твое фото',
      'твоя фотка',
      'твоя фотография',
      'как ты выглядишь',
      'как ты сейчас',
      'что на тебе',
      'как ты работаешь',
      'покажи как ты работаешь',
      'что ты делаешь',
      'что ты сейчас делаешь',
      'чем ты занимаешься',
    ];
    for (final phrase in directPhrases) {
      if (text.contains(phrase)) return true;
    }
    const photoTokens = ['фото', 'фотк', 'снимок', 'селфи', 'selfie'];
    const personTokens = ['тебя', 'себя'];
    final hasPhoto = photoTokens.any((token) => text.contains(token));
    final hasPerson = personTokens.any((token) => text.contains(token));
    return hasPhoto && hasPerson;
  }

  bool _looksLikeOutdoor(String normalized) {
    const outdoorHints = [
      'улиц',
      'парк',
      'прогул',
      'двор',
      'на улице',
      'outdoor',
      'street',
      'park',
      'outside',
      'walking',
    ];
    for (final hint in outdoorHints) {
      if (normalized.contains(hint)) return true;
    }
    return false;
  }

  String _seasonLabel(DateTime date) {
    switch (date.month) {
      case 12:
      case 1:
      case 2:
        return 'зима';
      case 3:
      case 4:
      case 5:
        return 'весна';
      case 6:
      case 7:
      case 8:
        return 'лето';
      default:
        return 'осень';
    }
  }

  String _readFirst(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  bool _readBool(
    Map<String, dynamic> payload,
    List<String> keys, {
    required bool defaultValue,
  }) {
    for (final key in keys) {
      final value = payload[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (['true', 'yes', 'y', '1'].contains(normalized)) return true;
        if (['false', 'no', 'n', '0'].contains(normalized)) return false;
      }
    }
    return defaultValue;
  }

  String _cleanShortText(String value, {int maxLen = 160}) {
    var text = value.trim();
    text = _stripWrappingQuotes(text);
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > maxLen) {
      text = text.substring(0, maxLen).trim();
    }
    return text;
  }

  String _cleanCaptionText(String value) {
    var text = _cleanShortText(value, maxLen: 120);
    text = text.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    return text;
  }

  String _cleanPromptText(String value) {
    var text = value.trim();
    text = _stripWrappingQuotes(text);
    text = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 380) {
      text = text.substring(0, 380).trim();
    }
    return text;
  }

  String _cleanStoryPrompt(String value) {
    var text = value.trim();
    text = _stripWrappingQuotes(text);
    text = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 520) {
      text = text.substring(0, 520).trim();
    }
    return text;
  }

  String _cleanOutfitText(String value) {
    var text = _cleanShortText(value, maxLen: 80);
    text = text.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    return text;
  }

  String _cleanSceneKey(String value) {
    var text = value.trim().toLowerCase();
    if (text.isEmpty) return '';
    text = _stripWrappingQuotes(text);
    text = text.replaceAll(RegExp(r'[^a-z0-9_-]+'), '');
    if (text.length > 40) {
      text = text.substring(0, 40).trim();
    }
    return text;
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

  String? _extractJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      return null;
    }
    return raw.substring(start, end + 1);
  }
}

class MessengerImageReplyPlan {
  final bool wantsPhoto;
  final bool isSelfie;
  final String replyText;
  final String imagePrompt;
  final String imageCaption;
  final String outfit;
  final String sceneKey;
  final bool usePreviousOutfit;

  const MessengerImageReplyPlan({
    required this.wantsPhoto,
    required this.isSelfie,
    required this.replyText,
    required this.imagePrompt,
    required this.imageCaption,
    required this.outfit,
    required this.sceneKey,
    required this.usePreviousOutfit,
  });
}

class MessengerChatReply {
  final String reply;
  final MessengerMoodDelta? moodDelta;
  final MessengerImageReplyPlan? photoOffer;

  const MessengerChatReply({
    required this.reply,
    this.moodDelta,
    this.photoOffer,
  });
}

class _PlanStreamResult {
  final MessengerImageReplyPlan plan;
  final String raw;

  const _PlanStreamResult(this.plan, this.raw);
}

class MessengerStoryPlan {
  final String replyText;
  final String caption;
  final String prompt;
  final bool isSelfie;

  const MessengerStoryPlan({
    required this.replyText,
    required this.caption,
    required this.prompt,
    required this.isSelfie,
  });
}

class _StoryPlanStreamResult {
  final MessengerStoryPlan plan;
  final String raw;

  const _StoryPlanStreamResult(this.plan, this.raw);
}
