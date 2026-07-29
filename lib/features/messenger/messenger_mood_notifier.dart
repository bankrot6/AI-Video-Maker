import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/messenger_mood_state.dart';
import 'services/messenger_mood_service.dart';

class MessengerMoodNotifier
    extends StateNotifier<AsyncValue<MessengerMoodState>> {
  final MessengerMoodService _service;
  final String _contactId;

  MessengerMoodNotifier(
    this._service,
    this._contactId,
  ) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final mood = await _service.load(_contactId);
      if (mounted) {
        state = AsyncValue.data(mood);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> refresh() async {
    await _load();
  }

  Future<void> applyDelta(MessengerMoodDelta delta) async {
    if (delta.isEmpty) return;
    final previous = state.valueOrNull;
    try {
      final updated =
          await _service.applyDelta(contactId: _contactId, delta: delta);
      if (mounted) {
        state = AsyncValue.data(updated);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
      if (previous != null && mounted) {
        state = AsyncValue.data(previous);
      }
    }
  }

  Future<void> setManual(MessengerMoodState mood) async {
    final previous = state.valueOrNull;
    try {
      final updated = await _service.save(mood);
      if (mounted) {
        state = AsyncValue.data(updated);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
      if (previous != null && mounted) {
        state = AsyncValue.data(previous);
      }
    }
  }
}
