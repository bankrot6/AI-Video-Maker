import 'dart:io';

import '../data/messenger_story_repository.dart';
import '../models/friend_profile.dart';
import '../models/messenger_message.dart';
import '../models/messenger_mood_state.dart';
import '../models/messenger_story.dart';
import '../models/messenger_thread.dart';
import '../services/messenger_activity_suggester.dart';
import '../services/messenger_ai_service.dart';
import '../services/messenger_story_prompt_builder.dart';
import '../../../services/video_generation_service.dart';
import '../../personalization/models/friend_persona.dart';

class MessengerStoryPublishResult {
  final MessengerStory? story;
  final String? errorMessage;

  const MessengerStoryPublishResult({this.story, this.errorMessage});

  bool get isSuccess => story != null;
}

class MessengerStoryPublisher {
  final MessengerStoryRepository _repository;
  final MessengerAiService _aiService;
  final VideoGenerationService _videoService;
  final MessengerStoryPromptBuilder _promptBuilder;
  final MessengerActivitySuggester _activitySuggester;

  MessengerStoryPublisher({
    required MessengerStoryRepository repository,
    required MessengerAiService aiService,
    required VideoGenerationService videoService,
    MessengerStoryPromptBuilder? promptBuilder,
    MessengerActivitySuggester? activitySuggester,
  })  : _repository = repository,
        _aiService = aiService,
        _videoService = videoService,
        _promptBuilder = promptBuilder ?? const MessengerStoryPromptBuilder(),
        _activitySuggester = activitySuggester ?? MessengerActivitySuggester();

  Future<MessengerStoryPublishResult> publishStory({
    required MessengerThread thread,
    required String userMessage,
    required List<MessengerMessage> context,
    FriendPersona? friendPersona,
    FriendProfile? friendProfile,
    MessengerMoodState? moodState,
    File? avatarFile,
    MessengerStoryPlan? plan,
    String? userGender,
    Duration ttl = const Duration(hours: 24),
  }) async {
    final suggestion = _activitySuggester.buildSuggestion(
      userMessage: userMessage,
      recentMessages: context,
    );
    final resolvedPlan = plan ??
        await _aiService.generateStoryPlan(
          thread: thread,
          userMessage: userMessage,
          context: context,
          activityOptions: suggestion.options,
          fallbackCaption: suggestion.fallback,
          friendPersona: friendPersona,
          friendProfile: friendProfile,
          moodState: moodState,
          userGender: userGender,
        );
    final caption = _resolveCaption(
      resolvedPlan.caption,
      suggestion.fallback,
    );
    final prompt = _resolvePrompt(
      planPrompt: resolvedPlan.prompt,
      friendName: thread.contact.name,
      activity: suggestion.fallback,
      caption: caption,
      profile: friendProfile,
      isSelfie: resolvedPlan.isSelfie,
    );

    final videoResult = await _videoService.generateVideo(
      prompt: prompt,
      referenceImage: resolvedPlan.isSelfie ? avatarFile : null,
      durationSeconds: 5,
      aspectRatio: '9:16',
      sampleCount: 1,
      negativePrompt: 'text, watermark, logo, subtitles, UI elements',
      enhancePrompt: true,
    );

    if (!videoResult.isSuccess) {
      return MessengerStoryPublishResult(
        errorMessage: videoResult.errorMessage ?? 'Video generation failed.',
      );
    }

    final createdAt = DateTime.now();
    final story = MessengerStory(
      id: '${createdAt.microsecondsSinceEpoch}-${thread.contact.id}',
      contactId: thread.contact.id,
      contactName: thread.contact.name,
      caption: caption,
      createdAt: createdAt,
      expiresAt: createdAt.add(ttl),
      aspectRatio: '9:16',
      videoPath: videoResult.file?.path,
      videoUrl: videoResult.remoteUri,
      avatarPath: thread.contact.avatarPath,
      prompt: prompt,
    );
    await _repository.saveStory(story);
    return MessengerStoryPublishResult(story: story);
  }

  String _resolveCaption(String caption, String fallback) {
    final trimmed = caption.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final fallbackTrimmed = fallback.trim();
    if (fallbackTrimmed.isNotEmpty) return fallbackTrimmed;
    return 'моя сторис';
  }

  String _resolvePrompt({
    required String planPrompt,
    required String friendName,
    required String activity,
    required String caption,
    required FriendProfile? profile,
    required bool isSelfie,
  }) {
    final trimmed = planPrompt.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return _promptBuilder.buildStoryPrompt(
      friendName: friendName,
      activity: activity,
      caption: caption,
      profile: profile,
      isSelfie: isSelfie,
    );
  }
}
