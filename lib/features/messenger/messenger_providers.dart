import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/localization/app_localization_service.dart';
import '../../services/ai_image_captioning_service.dart';
import '../../services/ai_image_generation_service.dart';
import '../../services/huggingface_video_generation_service.dart';
import '../../services/piapi_image_captioning_service.dart';
import '../../services/piapi_image_generation_service.dart';
import '../../services/piapi_kling_video_generation_service.dart';
import '../../services/veo2_video_generation_service.dart';
import '../../services/video_generation_service.dart';
import '../personalization/personalization_providers.dart';
import 'data/messenger_storage_repository.dart';
import 'data/messenger_story_repository.dart';
import 'data/messenger_story_schedule_repository.dart';
import 'data/messenger_proactive_repository.dart';
import 'data/messenger_pending_ai_task_repository.dart';
import 'data/messenger_outfit_repository.dart';
import 'data/messenger_mood_repository.dart';
import 'data/friend_profile_repository.dart';
import 'models/friend_profile.dart';
import 'models/messenger_mood_state.dart';
import 'messenger_mood_notifier.dart';
import 'services/friend_avatar_service.dart';
import 'services/friend_appearance_service.dart';
import 'services/messenger_activity_suggester.dart';
import 'services/messenger_ai_service.dart';
import 'services/messenger_outfit_service.dart';
import 'services/messenger_mood_service.dart';
import 'services/messenger_pending_ai_task_service.dart';
import 'services/messenger_proactive_service.dart';
import 'services/messenger_seed_data.dart';
import 'services/messenger_daily_story_service.dart';
import 'services/messenger_story_publisher.dart';
import 'services/messenger_voice_service.dart';

final friendProfileRepositoryProvider =
    Provider<FriendProfileRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return FriendProfileRepository(prefs);
});

final friendProfileProvider = StateProvider<FriendProfile?>((ref) {
  final repo = ref.watch(friendProfileRepositoryProvider);
  return repo.load('friend');
});

final messengerSeedDataProvider = Provider<MessengerSeedData>((ref) {
  final profile = ref.watch(friendProfileProvider);
  return MessengerSeedData(friendProfile: profile);
});

final messengerStorageRepositoryProvider =
    Provider<MessengerStorageRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final seedData = ref.watch(messengerSeedDataProvider);
  final repository = MessengerStorageRepository(
    prefs,
    seedData: seedData,
    friendProfileRepository: ref.watch(friendProfileRepositoryProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final activeMessengerChatIdProvider = StateProvider<String?>((ref) {
  return null;
});

final messengerStoryRepositoryProvider =
    Provider<MessengerStoryRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repository = MessengerStoryRepository(prefs);
  ref.onDispose(repository.dispose);
  return repository;
});

final messengerStoryScheduleRepositoryProvider =
    Provider<MessengerStoryScheduleRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return MessengerStoryScheduleRepository(prefs);
});

final userGenderProvider = Provider<String?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getString('user_gender');
});

final messengerAiServiceProvider = Provider<MessengerAiService>((ref) {
  return MessengerAiService();
});

final messengerVoiceServiceProvider = Provider<MessengerVoiceService>((ref) {
  return MessengerVoiceService(
    profileRepository: ref.watch(friendProfileRepositoryProvider),
  );
});

final imageGenerationServiceProvider =
    Provider<AiImageGenerationService>((ref) {
  return AiImageGenerationRouter(
    services: [
      PiApiImageGenerationService(),
    ],
  );
});

final avatarImageGenerationServiceProvider =
    Provider<AiImageGenerationService>((ref) {
  return AiImageGenerationRouter(
    services: [
      PiApiImageGenerationService(
        width: 512,
        height: 512,
      ),
    ],
  );
});

final chatImageGenerationServiceProvider =
    Provider<AiImageGenerationService>((ref) {
  return AiImageGenerationRouter(
    services: [
      PiApiImageGenerationService(
        width: 768,
        height: 768,
      ),
    ],
  );
});

final storyImageGenerationServiceProvider =
    Provider<AiImageGenerationService>((ref) {
  return AiImageGenerationRouter(
    services: [
      PiApiImageGenerationService(
        width: 720,
        height: 1280,
      ),
    ],
  );
});

final imageCaptioningServiceProvider =
    Provider<AiImageCaptioningService>((ref) {
  return AiImageCaptioningRouter(
    services: [
      PiApiImageCaptioningService(),
    ],
  );
});

final friendAppearanceServiceProvider =
    Provider<FriendAppearanceService>((ref) {
  return FriendAppearanceService(
    captioningService: ref.watch(imageCaptioningServiceProvider),
    profileRepository: ref.watch(friendProfileRepositoryProvider),
  );
});

final friendAvatarServiceProvider = Provider<FriendAvatarService>((ref) {
  return FriendAvatarService(
    imageService: ref.watch(avatarImageGenerationServiceProvider),
    profileRepository: ref.watch(friendProfileRepositoryProvider),
    appearanceService: ref.watch(friendAppearanceServiceProvider),
    dailyStoryService: ref.watch(messengerDailyStoryServiceProvider),
  );
});

final videoGenerationServiceProvider = Provider<VideoGenerationService>((ref) {
  return VideoGenerationRouter(
    services: [
      PiApiKlingVideoGenerationService(),
      HuggingFaceVideoGenerationService(),
      Veo2VideoGenerationService(),
    ],
  );
});

final messengerStoryPublisherProvider =
    Provider<MessengerStoryPublisher>((ref) {
  return MessengerStoryPublisher(
    repository: ref.watch(messengerStoryRepositoryProvider),
    aiService: ref.watch(messengerAiServiceProvider),
    videoService: ref.watch(videoGenerationServiceProvider),
  );
});

final messengerDailyStoryServiceProvider =
    Provider<MessengerDailyStoryService>((ref) {
  return MessengerDailyStoryService(
    storageRepository: ref.watch(messengerStorageRepositoryProvider),
    storyRepository: ref.watch(messengerStoryRepositoryProvider),
    scheduleRepository: ref.watch(messengerStoryScheduleRepositoryProvider),
    imageService: ref.watch(storyImageGenerationServiceProvider),
    personaRepository: ref.watch(friendPersonaRepositoryProvider),
    friendProfileRepository: ref.watch(friendProfileRepositoryProvider),
  );
});

final messengerProactiveRepositoryProvider =
    Provider<MessengerProactiveRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return MessengerProactiveRepository(prefs);
});

final messengerOutfitRepositoryProvider =
    Provider<MessengerOutfitRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return MessengerOutfitRepository(prefs);
});

final messengerOutfitServiceProvider = Provider<MessengerOutfitService>((ref) {
  return MessengerOutfitService(
    repository: ref.watch(messengerOutfitRepositoryProvider),
  );
});

final messengerMoodRepositoryProvider =
    Provider<MessengerMoodRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return MessengerMoodRepository(prefs);
});

final messengerMoodServiceProvider = Provider<MessengerMoodService>((ref) {
  return MessengerMoodService(
    repository: ref.watch(messengerMoodRepositoryProvider),
  );
});

final messengerPendingAiTaskRepositoryProvider =
    Provider<MessengerPendingAiTaskRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return MessengerPendingAiTaskRepository(prefs);
});

final messengerPendingAiTaskServiceProvider =
    Provider<MessengerPendingAiTaskService>((ref) {
  return MessengerPendingAiTaskService(
    taskRepository: ref.watch(messengerPendingAiTaskRepositoryProvider),
    storageRepository: ref.watch(messengerStorageRepositoryProvider),
    aiService: ref.watch(messengerAiServiceProvider),
    voiceService: ref.watch(messengerVoiceServiceProvider),
    imageService: ref.watch(chatImageGenerationServiceProvider),
    outfitService: ref.watch(messengerOutfitServiceProvider),
    personaRepository: ref.watch(friendPersonaRepositoryProvider),
    friendProfileRepository: ref.watch(friendProfileRepositoryProvider),
    moodService: ref.watch(messengerMoodServiceProvider),
  );
});

final messengerMoodProvider = StateNotifierProvider.family<
    MessengerMoodNotifier, AsyncValue<MessengerMoodState>, String>(
  (ref, contactId) {
    return MessengerMoodNotifier(
      ref.watch(messengerMoodServiceProvider),
      contactId,
    );
  },
);

final messengerProactiveServiceProvider = Provider<MessengerProactiveService>(
  (ref) {
    final gender = ref.watch(userGenderProvider);
    return MessengerProactiveService(
      storageRepository: ref.watch(messengerStorageRepositoryProvider),
      aiService: ref.watch(messengerAiServiceProvider),
      activitySuggester: MessengerActivitySuggester(),
      repository: ref.watch(messengerProactiveRepositoryProvider),
      personaRepository: ref.watch(friendPersonaRepositoryProvider),
      friendProfileRepository: ref.watch(friendProfileRepositoryProvider),
      moodService: ref.watch(messengerMoodServiceProvider),
      userGender: gender,
    );
  },
);
