import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/localization/app_localization_service.dart';
import 'data/friend_persona_repository.dart';
import 'models/friend_persona.dart';

final friendPersonaRepositoryProvider = Provider<FriendPersonaRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SharedPrefsFriendPersonaRepository(prefs);
});

final friendPersonaProvider = StateNotifierProvider.family<
    FriendPersonaNotifier,
    AsyncValue<FriendPersona>,
    String>(
  (ref, contactId) {
    final repository = ref.watch(friendPersonaRepositoryProvider);
    return FriendPersonaNotifier(repository, contactId);
  },
);

class FriendPersonaNotifier extends StateNotifier<AsyncValue<FriendPersona>> {
  final FriendPersonaRepository _repository;
  final String _contactId;

  FriendPersonaNotifier(this._repository, this._contactId)
      : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final persona = await _repository.load(_contactId);
      if (mounted) {
        state = AsyncValue.data(persona);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<bool> save(FriendPersona persona) async {
    final previous = state.valueOrNull ?? const FriendPersona();
    try {
      await _repository.save(_contactId, persona);
      if (mounted) {
        state = AsyncValue.data(persona);
      }
      return true;
    } catch (e) {
      if (mounted) {
        state = AsyncValue.data(previous);
      }
      return false;
    }
  }
}
