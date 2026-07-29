import '../data/messenger_mood_repository.dart';
import '../models/messenger_mood_state.dart';

class MessengerMoodService {
  static const int minValue = 0;
  static const int maxValue = 100;
  static const int maxDelta = 10;

  final MessengerMoodRepository _repository;

  MessengerMoodService({required MessengerMoodRepository repository})
      : _repository = repository;

  Future<MessengerMoodState> load(String contactId, {DateTime? now}) async {
    final stored = _repository.load(contactId);
    if (stored != null) return _normalize(stored);
    final initial = MessengerMoodState.initial(contactId, now: now);
    await _repository.save(initial);
    return initial;
  }

  Future<MessengerMoodState> save(
    MessengerMoodState state, {
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final normalized = _normalize(state).copyWith(updatedAt: timestamp);
    await _repository.save(normalized);
    return normalized;
  }

  Future<MessengerMoodState> applyDelta({
    required String contactId,
    required MessengerMoodDelta delta,
    DateTime? now,
  }) async {
    final timestamp = now ?? DateTime.now();
    final current = await load(contactId, now: timestamp);
    final joyAxis = _clampAxis(
      (current.joy - current.anger) +
          _clampDelta(delta.joy) -
          _clampDelta(delta.anger),
    );
    final funAxis = _clampAxis(
      (current.fun - current.sadness) +
          _clampDelta(delta.fun) -
          _clampDelta(delta.sadness),
    );
    final humorAxis = _clampAxis(
      (current.humor - current.boring) +
          _clampDelta(delta.humor) -
          _clampDelta(delta.boring),
    );
    final updated = _normalize(
      current.copyWith(
        joy: joyAxis > 0 ? joyAxis : 0,
        anger: joyAxis < 0 ? -joyAxis : 0,
        fun: funAxis > 0 ? funAxis : 0,
        sadness: funAxis < 0 ? -funAxis : 0,
        humor: humorAxis > 0 ? humorAxis : 0,
        boring: humorAxis < 0 ? -humorAxis : 0,
        updatedAt: timestamp,
      ),
    );
    await _repository.save(updated);
    return updated;
  }

  MessengerMoodState _normalize(MessengerMoodState state) {
    final joyAxis = _clampAxis(state.joy - state.anger);
    final funAxis = _clampAxis(state.fun - state.sadness);
    final humorAxis = _clampAxis(state.humor - state.boring);
    return state.copyWith(
      joy: joyAxis > 0 ? joyAxis : 0,
      anger: joyAxis < 0 ? -joyAxis : 0,
      fun: funAxis > 0 ? funAxis : 0,
      sadness: funAxis < 0 ? -funAxis : 0,
      humor: humorAxis > 0 ? humorAxis : 0,
      boring: humorAxis < 0 ? -humorAxis : 0,
    );
  }

  int _clampDelta(int value) {
    if (value < -maxDelta) return -maxDelta;
    if (value > maxDelta) return maxDelta;
    return value;
  }

  int _clampAxis(int value) {
    if (value < -maxValue) return -maxValue;
    if (value > maxValue) return maxValue;
    return value;
  }
}
