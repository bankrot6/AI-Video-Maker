import 'dart:async';

import '../../../services/ai_image_generation_service.dart';
import '../data/friend_profile_repository.dart';
import '../models/friend_profile.dart';
import 'friend_avatar_prompt_builder.dart';
import 'friend_appearance_service.dart';
import 'messenger_daily_story_service.dart';

class FriendAvatarService {
  final AiImageGenerationService _imageService;
  final FriendAvatarPromptBuilder _promptBuilder;
  final FriendProfileRepository _profileRepository;
  final FriendAppearanceService _appearanceService;
  final MessengerDailyStoryService? _dailyStoryService;

  FriendAvatarService({
    required AiImageGenerationService imageService,
    required FriendProfileRepository profileRepository,
    required FriendAppearanceService appearanceService,
    MessengerDailyStoryService? dailyStoryService,
    FriendAvatarPromptBuilder? promptBuilder,
  })  : _imageService = imageService,
        _profileRepository = profileRepository,
        _appearanceService = appearanceService,
        _dailyStoryService = dailyStoryService,
        _promptBuilder = promptBuilder ?? FriendAvatarPromptBuilder();

  Future<FriendProfile> generateAvatar({
    required String contactId,
    required FriendProfile profile,
    String? userWishes,
  }) async {
    final promptResult = _promptBuilder.build(
      gender: profile.gender,
      age: profile.age,
      hairColor: profile.hairColor,
      eyeColor: profile.eyeColor,
      relationshipType: profile.relationshipType,
      hairstyle: profile.hairstyle,
      ethnicity: profile.ethnicity,
      skinTone: profile.skinTone,
      bodyType: profile.bodyType,
      heightCategory: profile.heightCategory,
      userWishes: userWishes,
    );
    try {
      final result =
          await _imageService.generateImageFromPrompt(promptResult.prompt);
      final file = result.file;
      if (result.isSuccess && file != null) {
        final updated = profile.copyWith(
          avatarPath: file.path,
          avatarStatus: FriendProfile.avatarStatusReady,
          appearanceDescription: '',
          appearanceCheckAvatarPath: null,
          hairstyle: promptResult.hairstyle,
          ethnicity: promptResult.ethnicity,
          skinTone: promptResult.skinTone,
          bodyType: promptResult.bodyType,
          heightCategory: promptResult.heightCategory,
          facialFeatures: promptResult.facialFeatures,
        );
        await _profileRepository.save(contactId, updated);
        unawaited(() async {
          try {
            await _appearanceService.ensureAppearanceDescription(
              profile: updated,
              avatarFile: file,
              contactId: contactId,
            );
            await _dailyStoryService?.generateInitialStories(
              contactId: contactId,
            );
          } catch (_) {}
        }());
        return updated;
      }
      final failed = profile.copyWith(
        avatarStatus: FriendProfile.avatarStatusFailed,
      );
      await _profileRepository.save(contactId, failed);
      return failed;
    } catch (_) {
      final failed = profile.copyWith(
        avatarStatus: FriendProfile.avatarStatusFailed,
      );
      await _profileRepository.save(contactId, failed);
      return failed;
    }
  }
}
