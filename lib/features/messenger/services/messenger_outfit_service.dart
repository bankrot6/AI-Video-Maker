import '../data/messenger_outfit_repository.dart';
import '../models/messenger_outfit_state.dart';
import 'messenger_ai_service.dart';

class MessengerOutfitPromptContext {
  final String previousOutfit;
  final String previousSceneKey;
  final int minutesSince;
  final int outfitTtlMinutes;

  const MessengerOutfitPromptContext({
    required this.previousOutfit,
    required this.previousSceneKey,
    required this.minutesSince,
    required this.outfitTtlMinutes,
  });

  factory MessengerOutfitPromptContext.empty({
    required int outfitTtlMinutes,
  }) {
    return MessengerOutfitPromptContext(
      previousOutfit: '',
      previousSceneKey: '',
      minutesSince: 0,
      outfitTtlMinutes: outfitTtlMinutes,
    );
  }

  bool get hasPrevious => previousOutfit.trim().isNotEmpty;
}

class MessengerOutfitDecision {
  final String outfit;
  final String sceneKey;
  final bool reused;

  const MessengerOutfitDecision({
    required this.outfit,
    required this.sceneKey,
    required this.reused,
  });
}

class MessengerOutfitService {
  final MessengerOutfitRepository _repository;
  final Duration _ttl;

  MessengerOutfitService({
    required MessengerOutfitRepository repository,
    Duration? ttl,
  })  : _repository = repository,
        _ttl = ttl ?? const Duration(minutes: 90);

  int get ttlMinutes => _ttl.inMinutes;

  Future<MessengerOutfitPromptContext> buildPromptContext({
    required String contactId,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final state = await _loadFresh(contactId, timestamp);
    if (state == null) {
      return MessengerOutfitPromptContext.empty(
        outfitTtlMinutes: ttlMinutes,
      );
    }
    final minutesSince = timestamp.difference(state.updatedAt).inMinutes;
    return MessengerOutfitPromptContext(
      previousOutfit: state.outfit,
      previousSceneKey: state.sceneKey,
      minutesSince: minutesSince < 0 ? 0 : minutesSince,
      outfitTtlMinutes: ttlMinutes,
    );
  }

  Future<MessengerOutfitDecision?> resolveOutfit({
    required String contactId,
    required MessengerImageReplyPlan plan,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final previous = await _loadFresh(contactId, timestamp);
    final normalizedScene = _normalizeSceneKey(plan.sceneKey);
    final normalizedOutfit = _normalizeOutfit(plan.outfit);
    if (plan.usePreviousOutfit &&
        previous != null &&
        _canReuseScene(previous, normalizedScene)) {
      final refreshed = previous.copyWith(
        updatedAt: timestamp,
        lockedUntil: timestamp.add(_ttl),
      );
      await _repository.save(refreshed);
      return MessengerOutfitDecision(
        outfit: previous.outfit,
        sceneKey: previous.sceneKey,
        reused: true,
      );
    }
    if (normalizedOutfit.isNotEmpty) {
      final sceneKey = normalizedScene.isNotEmpty
          ? normalizedScene
          : (previous?.sceneKey.trim().isNotEmpty == true
              ? previous!.sceneKey
              : 'unknown');
      final state = MessengerOutfitState(
        contactId: contactId,
        sceneKey: sceneKey,
        outfit: normalizedOutfit,
        updatedAt: timestamp,
        lockedUntil: timestamp.add(_ttl),
      );
      await _repository.save(state);
      return MessengerOutfitDecision(
        outfit: normalizedOutfit,
        sceneKey: sceneKey,
        reused: false,
      );
    }
    return null;
  }

  Future<MessengerOutfitState?> _loadFresh(
    String contactId,
    DateTime now,
  ) async {
    final state = _repository.load(contactId);
    if (state == null) return null;
    if (state.outfit.trim().isEmpty || state.isExpired(now)) {
      await _repository.clear(contactId);
      return null;
    }
    return state;
  }

  bool _canReuseScene(MessengerOutfitState state, String sceneKey) {
    if (sceneKey.isEmpty) return true;
    return state.sceneKey.trim().toLowerCase() == sceneKey;
  }

  String _normalizeSceneKey(String value) {
    var text = value.trim().toLowerCase();
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r'[^a-z0-9_-]+'), '');
    if (text.length > 40) {
      text = text.substring(0, 40).trim();
    }
    return text;
  }

  String _normalizeOutfit(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 80) {
      text = text.substring(0, 80).trim();
    }
    return text;
  }
}
