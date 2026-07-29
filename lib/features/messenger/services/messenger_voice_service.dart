import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../services/elevenlabs_tts_service.dart';
import '../data/friend_profile_repository.dart';
import '../models/friend_profile.dart';

class MessengerVoiceResult {
  final String? audioPath;
  final String? errorMessage;
  final String? voiceId;

  const MessengerVoiceResult({
    this.audioPath,
    this.errorMessage,
    this.voiceId,
  });

  bool get isSuccess => audioPath != null && errorMessage == null;
}

class VoiceSelectionItem {
  final String voiceId;
  final String displayName;

  const VoiceSelectionItem({
    required this.voiceId,
    required this.displayName,
  });
}

class MessengerVoiceService {
  // ── Русские голоса ElevenLabs ──────────────────────────────────────
  // Заполните ID голосов с сайта https://elevenlabs.io/voice-library
  // Каждый массив: список voice_id строк.

  static const List<String> _maleYoungVoiceIds = [
    // Мужские молодые голоса (18-29 лет)
    'MWyJiWDobXN8FX3CJTdE',
    'M1CSR3PJBsfWU6ZquG3C',
    'bqbHGIIO5oETYIqhWmfk',
    'zp2G1GqPvAg5KDA55fjC',
    'gXMhWmiqsFkrcssqVb5k',
    'm0OQuJtWCw1V23P0pQmG',
    'uQRQyfqc46WuEktqwuiQ',
    'lsAmGFzUYusakA482527',
    'drOVtcvHhJKNEXv5h1l5',
    'WTn2eCRCpoFAC50VD351',
  ];

  static const List<String> _maleMidVoiceIds = [
    // Мужские голоса среднего возраста (30-45 лет)
    'rQOBu7YxCDxGiFdTm28w',
    '1EVds7FNGSXoKeOiMXuf',
    'qJBO8ZmKp4te7NTtYgzz',
    'RUB3PhT3UqHowKru61Ns',
    's0phbFBBp708ZeIy8oGx',
    'TUQNWEvVPBLzMBSVDPUA',
    '1qd9R09Ljlx9V1Ok0t5S',
    'XuEV9VY3VUASYgJVNBh0',
    'pvY1pikBdoI4SB62vEVo',
    'C1Jbh3J5Tp1r1TyKaVSY',
  ];

  static const List<String> _maleSeniorVoiceIds = [
    // Мужские старшие голоса (46+ лет)
    'NOpBlnGInO9m6vDvFkFC',
    '7p1Ofvcwsv7UBPoFNcpI',
    'L1aJrPa7pLJEyYlh3Ilq',
    'YXpFCvM1S3JbWEJhoskW',
    'wAGzRVkxKEs8La0lmdrE',
    'xZp4zaaBzoWhWxxrcAij',
    '6sFKzaJr574YWVu4UuJF',
    'cPoqAvGWCPfCfyPMwe4z',
    'MDLAMJ0jxkpYkjXbmG4t',
    'qAZH0aMXY8tw1QufPN0D',
  ];

  static const List<String> _femaleYoungVoiceIds = [
    // Женские молодые голоса (18-29 лет)
    'Jbte7ht1CqapnZvc4KpK',
    'GN4wbsbejSnGSa1AzjH5',
    'ycbyWsnf4hqZgdpKHqiU',
    'dHAwRJVaEPhU907QLTPW',
    'dVRDrbP5ULGXB94se4KZ',
    'xyu8HSCv1JYrhLx4m8UG',
    'wUndevsXFk0ArF7vJ61U',
    'USJ5Rjf2LwNEcibI3sN4',
    'AB9XsbSA4eLG12t2myjN',
    'sNQyZH8Wfcnv7zh3rHxR',
  ];

  static const List<String> _femaleMidVoiceIds = [
    // Женские голоса среднего возраста (30-45 лет)
    'ymDCYd8puC7gYjxIamPt',
    'IO0VLmDxIb8N5msewtV4',
    'EDpEYNf6XIeKYRzYcx4I',
    'FnNYfPjyvZwLwb043Kl1',
    'OowtKaZH9N7iuGbsd00l',
    'grmBv5c5ZJVFgXpRWyp7',
    '5X91H1Ba65xNiFpKbcg0',
    '7bZhyIZ2kvtWyP0oF21m',
    'TPIitICAZ8CqlGZ81AKm',
    'gCqVHuQpLDMkHrGiG95I',
  ];

  static const List<String> _femaleSeniorVoiceIds = [
    // Женские старшие голоса (46+ лет)
    'RILOU7YmBhvwJGDGjNmP',
    'eBthAb30UYbt2nojGXeA',
    '7NsaqHdLuKNFvEfjpUno',
    'nEu1CRXDjHpQT7G4E6sZ',
    'lxYfHSkYm1EzQzGhdbfc',
  ];

  // ──────────────────────────────────────────────────────────────────

  final ElevenLabsTtsService _elevenlabs;
  final FriendProfileRepository _profileRepository;
  final Random _random;
  final List<ElevenLabsVoice> _elevenlabsVoices;

  MessengerVoiceService({
    required FriendProfileRepository profileRepository,
    ElevenLabsTtsService? elevenlabs,
    Random? random,
  })  : _profileRepository = profileRepository,
        _elevenlabs = elevenlabs ?? ElevenLabsTtsService(),
        _random = random ?? Random(),
        _elevenlabsVoices = _buildHardcodedVoices();

  Future<MessengerVoiceResult> generateVoiceReply({
    required String text,
    required String contactId,
    FriendProfile? friendProfile,
  }) async {
    return _generateElevenLabsReply(
      text: text,
      contactId: contactId,
      friendProfile: friendProfile,
    );
  }

  Future<MessengerVoiceResult> _generateElevenLabsReply({
    required String text,
    required String contactId,
    FriendProfile? friendProfile,
  }) async {
    if (!await _elevenlabs.isAvailable()) {
      return const MessengerVoiceResult(
        errorMessage: 'ElevenLabs TTS не настроен. Проверьте ключи .env.',
      );
    }
    final voices = await _resolveElevenLabsVoices();
    if (voices.isEmpty) {
      return const MessengerVoiceResult(
        errorMessage: 'Не настроены голоса ElevenLabs.',
      );
    }
    final profile = friendProfile ?? _profileRepository.load(contactId);
    final profileGender = _normalizeGender(profile?.gender);
    final profileAge = _ageGroup(profile?.age);
    debugPrint(
      '🟣 VOICE: генерация для contactId=$contactId, '
      'профиль пол=${profile?.gender}→$profileGender, '
      'возраст=${profile?.age}→$profileAge, '
      'voiceId=${profile?.voiceId}, голосов=${voices.length}',
    );
    final usedVoiceIds = _collectAssignedVoiceIds(exceptContactId: contactId);
    final tried = <String>{};
    String? lastError;

    final profileSettings = _profileVoiceSettings(profile);

    Future<MessengerVoiceResult?> tryVoices(
      List<ElevenLabsVoice> candidates,
      bool persistAssignment,
    ) async {
      if (candidates.isEmpty) return null;
      final shuffled = List<ElevenLabsVoice>.from(candidates);
      shuffled.shuffle(_random);
      for (final voice in shuffled) {
        final voiceId = voice.voiceId.trim();
        if (voiceId.isEmpty) continue;
        if (tried.contains(voiceId)) continue;
        tried.add(voiceId);
        final result = await _elevenlabs.synthesize(
          text: text,
          voice: voice,
          voiceSettings: profileSettings,
        );
        if (result.isSuccess) {
          if (persistAssignment) {
            await _storeAssignment(contactId, profile, voiceId);
            if (_findVoiceById(_elevenlabsVoices, voiceId) == null) {
              _elevenlabsVoices.add(voice);
            }
          }
          return MessengerVoiceResult(
            audioPath: result.audioFile?.path,
            voiceId: voiceId,
          );
        }
        lastError = result.errorMessage;
      }
      return null;
    }

    final assignedVoiceId = profile?.voiceId?.trim();
    if (assignedVoiceId != null && assignedVoiceId.isNotEmpty) {
      final localVoice = _findVoiceById(voices, assignedVoiceId);
      if (localVoice != null) {
        final matchesGender =
            profileGender == null || localVoice.gender == profileGender;
        if (matchesGender && !usedVoiceIds.contains(assignedVoiceId)) {
          debugPrint(
            '🟣 VOICE: пробуем назначенный голос $assignedVoiceId '
            '(пол=${localVoice.gender})',
          );
          final assignedResult = await tryVoices([localVoice], false);
          if (assignedResult != null) return assignedResult;
        }
      }
    }

    final primary = _filterElevenLabsVoices(profile, voices);
    if (primary.isNotEmpty) {
      final uniquePrimary = primary
          .where((voice) => !usedVoiceIds.contains(voice.voiceId.trim()))
          .toList();
      if (uniquePrimary.isNotEmpty) {
        final primaryResult = await tryVoices(uniquePrimary, true);
        if (primaryResult != null) return primaryResult;
      }
    }

    if (profileGender != null) {
      final genderOnly = voices
          .where((v) => v.gender == profileGender)
          .where((v) => !usedVoiceIds.contains(v.voiceId.trim()))
          .toList();
      if (genderOnly.isNotEmpty) {
        debugPrint(
          '🟣 VOICE: fallback по полу=$profileGender: '
          '${genderOnly.length} голосов',
        );
        final genderResult = await tryVoices(genderOnly, true);
        if (genderResult != null) return genderResult;
      }
    }

    if (voices.isNotEmpty) {
      final anyUnused = voices
          .where((voice) => !usedVoiceIds.contains(voice.voiceId.trim()))
          .toList();
      if (anyUnused.isNotEmpty) {
        debugPrint(
          '🟣 VOICE: ⚠️ последний fallback — любой доступный голос',
        );
        final fallbackResult = await tryVoices(anyUnused, true);
        if (fallbackResult != null) return fallbackResult;
      }
    }

    return MessengerVoiceResult(
      errorMessage: lastError ?? 'Не удалось озвучить сообщение.',
    );
  }

  Future<List<ElevenLabsVoice>> _resolveElevenLabsVoices() async {
    if (_elevenlabsVoices.isEmpty) {
      debugPrint('🟣 VOICE: список голосов пуст — заполните массивы в коде');
    } else {
      debugPrint('🟣 VOICE: доступно ${_elevenlabsVoices.length} голосов');
    }
    return _elevenlabsVoices;
  }

  static List<ElevenLabsVoice> _buildHardcodedVoices() {
    final voices = <ElevenLabsVoice>[];
    void addAll(List<String> ids, String gender, String ageGroup) {
      for (final id in ids) {
        voices.add(ElevenLabsVoice(
          id: id,
          voiceId: id,
          gender: gender,
          ageGroup: ageGroup,
          languageCode: 'ru-RU',
        ));
      }
    }

    addAll(_maleYoungVoiceIds, 'male', 'young');
    addAll(_maleMidVoiceIds, 'male', 'mid');
    addAll(_maleSeniorVoiceIds, 'male', 'senior');
    addAll(_femaleYoungVoiceIds, 'female', 'young');
    addAll(_femaleMidVoiceIds, 'female', 'mid');
    addAll(_femaleSeniorVoiceIds, 'female', 'senior');
    return voices;
  }

  List<ElevenLabsVoice> _filterElevenLabsVoices(
    FriendProfile? profile,
    List<ElevenLabsVoice> voices,
  ) {
    if (voices.isEmpty) return [];
    final normalizedGender = _normalizeGender(profile?.gender);
    final desiredAge = _ageGroup(profile?.age);
    debugPrint(
      '🟣 VOICE FILTER: пол=$normalizedGender, возраст=${profile?.age}'
      '→$desiredAge, всего=${voices.length}',
    );
    var candidates = voices;
    if (normalizedGender != null) {
      final byGender =
          candidates.where((v) => v.gender == normalizedGender).toList();
      if (byGender.isNotEmpty) {
        candidates = byGender;
      } else {
        debugPrint('🟣 VOICE FILTER: нет голосов пола=$normalizedGender');
        return [];
      }
    }
    if (desiredAge != null) {
      final byAge = candidates.where((v) => v.ageGroup == desiredAge).toList();
      if (byAge.isNotEmpty) {
        candidates = byAge;
      }
    }
    debugPrint(
      '🟣 VOICE FILTER: найдено ${candidates.length} подходящих голосов',
    );
    return candidates;
  }

  ElevenLabsVoice? _findVoiceById(
    List<ElevenLabsVoice> voices,
    String voiceId,
  ) {
    final target = voiceId.trim();
    if (target.isEmpty) return null;
    for (final voice in voices) {
      if (voice.voiceId.trim() == target) return voice;
    }
    return null;
  }

  Set<String> _collectAssignedVoiceIds({required String exceptContactId}) {
    final profiles = _profileRepository.loadAll();
    final ids = <String>{};
    profiles.forEach((contactId, profile) {
      if (contactId == exceptContactId) return;
      final voiceId = profile.voiceId?.trim();
      if (voiceId != null && voiceId.isNotEmpty) {
        ids.add(voiceId);
      }
    });
    return ids;
  }

  Future<void> _storeAssignment(
    String contactId,
    FriendProfile? profile,
    String voiceId,
  ) async {
    var targetProfile = profile ?? _profileRepository.load(contactId);
    if (targetProfile == null) return;
    if (targetProfile.voiceId == voiceId) return;
    final updated = targetProfile.copyWith(voiceId: voiceId);
    await _profileRepository.save(contactId, updated);
  }

  static String? _normalizeGender(String? value) {
    final raw = value?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('муж')) return 'male';
    if (raw.startsWith('жен')) return 'female';
    if (raw.startsWith('m')) return 'male';
    if (raw.startsWith('f')) return 'female';
    if (raw == 'man') return 'male';
    if (raw == 'woman') return 'female';
    return raw;
  }

  static String? _ageGroup(int? age) {
    if (age == null || age <= 0) return null;
    if (age <= 29) return 'young';
    if (age <= 45) return 'mid';
    return 'senior';
  }

  static bool _apiAgeMatchesOur(String? apiAgeGroup, String? ourAgeGroup) {
    if (ourAgeGroup == null || apiAgeGroup == null) return true;
    if (ourAgeGroup == 'young') return apiAgeGroup == 'young';
    if (ourAgeGroup == 'mid') return apiAgeGroup == 'adult';
    if (ourAgeGroup == 'senior') return apiAgeGroup == 'mature';
    return apiAgeGroup == ourAgeGroup;
  }

  static String _displayNameForHardcoded(ElevenLabsVoice v) {
    final genderLabel =
        v.gender == 'male' ? 'Мужской' : v.gender == 'female' ? 'Женский' : '';
    final ageLabel = v.ageGroup == 'young'
        ? 'молодой'
        : v.ageGroup == 'mid'
            ? 'средний возраст'
            : v.ageGroup == 'senior'
                ? 'старший'
                : '';
    if (genderLabel.isEmpty && ageLabel.isEmpty) return v.voiceId;
    if (ageLabel.isEmpty) return genderLabel;
    return '$genderLabel, $ageLabel';
  }

  Future<List<VoiceSelectionItem>> getVoicesForSelection(
    FriendProfile? profile,
  ) async {
    final normalizedGender = _normalizeGender(profile?.gender);
    final ourAgeGroup = _ageGroup(profile?.age);
    final fromApi = await _elevenlabs.fetchVoices();
    if (fromApi.isNotEmpty) {
      final filtered = fromApi.where((v) {
        final genderOk =
            normalizedGender == null || v.gender == normalizedGender;
        final ageOk = _apiAgeMatchesOur(v.ageGroup, ourAgeGroup);
        return genderOk && ageOk;
      }).toList();
      if (filtered.isNotEmpty) {
        return filtered
            .map((v) => VoiceSelectionItem(
                  voiceId: v.voiceId,
                  displayName: (v.id != v.voiceId ? v.id : v.voiceId).trim().isEmpty
                      ? _displayNameForHardcoded(v)
                      : v.id,
                ))
            .toList();
      }
    }
    final hardcoded = _filterElevenLabsVoices(profile, _elevenlabsVoices);
    var index = 0;
    return hardcoded
        .map((v) => VoiceSelectionItem(
              voiceId: v.voiceId,
              displayName: '${_displayNameForHardcoded(v)} ${++index}',
            ))
        .toList();
  }

  Map<String, dynamic>? _profileVoiceSettings(FriendProfile? profile) {
    if (profile == null) return null;
    final map = <String, dynamic>{};
    if (profile.voiceStability != null) {
      map['stability'] = (profile.voiceStability!).clamp(0.0, 1.0);
    }
    if (profile.voiceSimilarityBoost != null) {
      map['similarity_boost'] =
          (profile.voiceSimilarityBoost!).clamp(0.0, 1.0);
    }
    if (profile.voiceSpeed != null) {
      map['speed'] = (profile.voiceSpeed!).clamp(0.7, 1.2);
    }
    return map.isEmpty ? null : map;
  }

  Future<MessengerVoiceResult> previewVoice({
    required String voiceId,
    String sampleText = 'Привет! Это пример голоса.',
    FriendProfile? profile,
  }) async {
    final voices = await _resolveElevenLabsVoices();
    final voice = _findVoiceById(voices, voiceId);
    if (voice == null) {
      return const MessengerVoiceResult(
        errorMessage: 'Голос не найден.',
      );
    }
    final settings = _profileVoiceSettings(profile);
    final result = await _elevenlabs.synthesize(
      text: sampleText,
      voice: voice,
      voiceSettings: settings,
    );
    return MessengerVoiceResult(
      audioPath: result.audioFile?.path,
      errorMessage: result.errorMessage,
      voiceId: voiceId,
    );
  }
}
