import 'dart:io';

import '../../../services/ai_image_captioning_service.dart';
import '../data/friend_profile_repository.dart';
import '../models/friend_profile.dart';

class FriendAppearanceService {
  final AiImageCaptioningService _captioningService;
  final FriendProfileRepository _profileRepository;
  final Map<String, Future<FriendProfile>> _inFlight = {};

  FriendAppearanceService({
    required AiImageCaptioningService captioningService,
    required FriendProfileRepository profileRepository,
  })  : _captioningService = captioningService,
        _profileRepository = profileRepository;

  Future<FriendProfile> ensureAppearanceDescription({
    required FriendProfile profile,
    File? avatarFile,
    String contactId = 'friend',
  }) {
    final avatarPath = avatarFile?.path ?? 'no-avatar';
    final key = '$contactId|$avatarPath';
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _runAppearanceDescription(
      profile: profile,
      avatarFile: avatarFile,
      contactId: contactId,
    );
    _inFlight[key] = future;
    return future.whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<FriendProfile> _runAppearanceDescription({
    required FriendProfile profile,
    File? avatarFile,
    required String contactId,
  }) async {
    final avatar = avatarFile;
    final avatarExists = avatar != null && avatar.existsSync();
    final currentDescription = profile.appearanceDescription.trim();
    if (!avatarExists) {
      if (currentDescription.isNotEmpty) return profile;
      final fallback = _buildFallbackDescription(profile);
      if (fallback.isEmpty) return profile;
      final updated = profile.copyWith(
        appearanceDescription: fallback,
        appearanceCheckAvatarPath: null,
      );
      await _profileRepository.save(contactId, updated);
      return updated;
    }

    final avatarPath = avatar.path;
    FriendProfile marked = profile;
    if (profile.appearanceCheckAvatarPath != avatarPath) {
      marked = profile.copyWith(appearanceCheckAvatarPath: avatarPath);
      await _profileRepository.save(contactId, marked);
    }
    if (currentDescription.isNotEmpty) return marked;

    if (!await _captioningService.isAvailable()) {
      return marked;
    }
    final result = await _captioningService.generateCaptionFromImage(avatar);
    final normalized = _normalizeCaption(result.caption ?? '');
    if (normalized.isEmpty) return marked;
    final updated = marked.copyWith(appearanceDescription: normalized);
    await _profileRepository.save(contactId, updated);
    return updated;
  }

  String _normalizeCaption(String value) {
    var normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length > 240) {
      normalized = normalized.substring(0, 240).trim();
    }
    return normalized;
  }

  String _buildFallbackDescription(FriendProfile profile) {
    final hair = _normalizeColor(profile.hairColor);
    final eyes = _normalizeColor(profile.eyeColor);
    final hairstyle = _normalizeStyle(profile.hairstyle);
    final parts = <String>[];
    if (hair.isNotEmpty) {
      parts.add('Hair: $hair.');
    }
    if (eyes.isNotEmpty) {
      parts.add('Eyes: $eyes.');
    }
    if (hairstyle.isNotEmpty) {
      parts.add('Hairstyle: $hairstyle.');
    }
    return parts.join(' ');
  }

  String _normalizeColor(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalizeStyle(String value) {
    var normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length > 80) {
      normalized = normalized.substring(0, 80).trim();
    }
    return normalized;
  }
}
