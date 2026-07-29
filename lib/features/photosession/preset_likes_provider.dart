import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/photo_session_preset.dart';
import 'photosession_providers.dart';

class PresetLikeSnapshot {
  const PresetLikeSnapshot({
    required this.likesCount,
    required this.likedBy,
  });

  final int likesCount;
  final List<String> likedBy;
}

class PresetLikesNotifier
    extends StateNotifier<Map<String, PresetLikeSnapshot>> {
  PresetLikesNotifier(this._ref) : super({});

  final Ref _ref;
  final Set<String> _pending = {};

  bool isPending(String presetId) => _pending.contains(presetId);

  PresetLikeSnapshot resolve(PhotoSessionPreset preset) {
    return state[preset.id] ??
        PresetLikeSnapshot(
          likesCount: preset.likesCount,
          likedBy: List<String>.from(preset.likedBy),
        );
  }

  bool isLikedBy(PhotoSessionPreset preset, String deviceId) {
    return resolve(preset).likedBy.contains(deviceId);
  }

  PhotoSessionPreset mergePreset(PhotoSessionPreset preset) {
    final snapshot = resolve(preset);
    if (snapshot.likesCount == preset.likesCount &&
        listEquals(snapshot.likedBy, preset.likedBy)) {
      return preset;
    }
    return preset.copyWith(
      likesCount: snapshot.likesCount,
      likedBy: snapshot.likedBy,
    );
  }

  List<PhotoSessionPreset> mergePresets(List<PhotoSessionPreset> presets) {
    if (state.isEmpty) return presets;
    return presets.map(mergePreset).toList(growable: false);
  }

  Future<void> toggle(PhotoSessionPreset preset, String deviceId) async {
    if (_pending.contains(preset.id)) return;

    final current = resolve(preset);
    final wasLiked = current.likedBy.contains(deviceId);
    final nextLikedBy = List<String>.from(current.likedBy);
    if (wasLiked) {
      nextLikedBy.remove(deviceId);
    } else {
      nextLikedBy.add(deviceId);
    }

    state = {
      ...state,
      preset.id: PresetLikeSnapshot(
        likesCount: nextLikedBy.length,
        likedBy: nextLikedBy,
      ),
    };
    _pending.add(preset.id);

    try {
      await _ref
          .read(showcaseRepositoryProvider)
          .toggleLike(preset.id, deviceId);
    } catch (e) {
      final next = Map<String, PresetLikeSnapshot>.from(state);
      next.remove(preset.id);
      state = next;
      rethrow;
    } finally {
      _pending.remove(preset.id);
    }
  }

  void syncFromPresets(List<PhotoSessionPreset> presets) {
    if (state.isEmpty) return;
    final next = Map<String, PresetLikeSnapshot>.from(state);
    for (final preset in presets) {
      final override = next[preset.id];
      if (override == null) continue;
      if (override.likesCount == preset.likesCount &&
          listEquals(override.likedBy, preset.likedBy)) {
        next.remove(preset.id);
      }
    }
    if (next.length != state.length) {
      state = next;
    }
  }
}

final presetLikesProvider =
    StateNotifierProvider<PresetLikesNotifier, Map<String, PresetLikeSnapshot>>(
  (ref) => PresetLikesNotifier(ref),
);
