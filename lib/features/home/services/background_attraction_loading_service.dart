import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/attraction_info.dart';
import 'attraction_cache_service.dart';
import 'attraction_details_service.dart';

final attractionDetailsServiceProvider =
    Provider<AttractionDetailsService>((ref) {
  return AttractionDetailsService();
});

enum LoadingStatus { idle, loading, completed, error }

class AttractionLoadingState {
  final String placeId;
  final LoadingStatus status;
  final AttractionInfo? info;
  final String? error;
  final DateTime startedAt;

  AttractionLoadingState({
    required this.placeId,
    required this.status,
    this.info,
    this.error,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  AttractionLoadingState copyWith({
    LoadingStatus? status,
    AttractionInfo? info,
    String? error,
  }) {
    return AttractionLoadingState(
      placeId: placeId,
      status: status ?? this.status,
      info: info ?? this.info,
      error: error ?? this.error,
      startedAt: startedAt,
    );
  }
}

final attractionCacheServiceProvider = Provider<AttractionCacheService>((ref) {
  return AttractionCacheService();
});

final backgroundAttractionLoaderProvider =
    Provider<BackgroundAttractionLoadingService>((ref) {
  return BackgroundAttractionLoadingService(ref);
});

final attractionLoadingStateProvider = StateNotifierProvider<
    AttractionLoadingNotifier, Map<String, AttractionLoadingState>>((ref) {
  return AttractionLoadingNotifier();
});

class AttractionLoadingNotifier
    extends StateNotifier<Map<String, AttractionLoadingState>> {
  AttractionLoadingNotifier() : super({});

  void updateState(String placeId, AttractionLoadingState newState) {
    state = {...state, placeId: newState};
  }

  void removeState(String placeId) {
    final newState = Map<String, AttractionLoadingState>.from(state);
    newState.remove(placeId);
    state = newState;
  }

  AttractionLoadingState? getState(String placeId) {
    return state[placeId];
  }

  bool isLoading(String placeId) {
    return state[placeId]?.status == LoadingStatus.loading;
  }

  bool hasCompletedData(String placeId) {
    final s = state[placeId];
    return s != null && s.status == LoadingStatus.completed && s.info != null;
  }
}

class BackgroundAttractionLoadingService {
  final ProviderRef _ref;
  final Map<String, StreamSubscription<AttractionInfo>> _activeSubscriptions =
      {};
  final Map<String, StreamController<AttractionInfo>> _streamControllers = {};

  BackgroundAttractionLoadingService(this._ref);

  String _normalizeId(String placeName) {
    return placeName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
  }

  Future<AttractionInfo?> getAttractionInfo({
    required String placeName,
    required String category,
    required BuildContext context,
    bool forceRefresh = false,
  }) async {
    final placeId = _normalizeId(placeName);
    final cacheService = _ref.read(attractionCacheServiceProvider);
    final loadingNotifier = _ref.read(attractionLoadingStateProvider.notifier);

    if (!forceRefresh) {
      final cached = await cacheService.getCachedAttractionInfo(placeId);
      if (cached != null) {
        final isComplete = await cacheService.isCacheComplete(placeId);
        debugPrint(
            '🎯 BACKGROUND_LOADER: Данные из кэша: $placeName (complete: $isComplete)');
        loadingNotifier.updateState(
          placeId,
          AttractionLoadingState(
            placeId: placeId,
            status:
                isComplete ? LoadingStatus.completed : LoadingStatus.loading,
            info: cached,
          ),
        );
        return cached;
      }
    }

    if (_activeSubscriptions.containsKey(placeId)) {
      debugPrint(
          '🎯 BACKGROUND_LOADER: Загрузка уже идёт, подключаемся: $placeName');
      final currentState = loadingNotifier.getState(placeId);
      return currentState?.info;
    }

    return null;
  }

  Stream<AttractionInfo> streamAttractionInfo({
    required String placeName,
    required String category,
    required BuildContext context,
    bool forceRefresh = false,
  }) async* {
    final placeId = _normalizeId(placeName);
    final cacheService = _ref.read(attractionCacheServiceProvider);
    final loadingNotifier = _ref.read(attractionLoadingStateProvider.notifier);

    if (!forceRefresh) {
      final cached = await cacheService.getCachedAttractionInfo(placeId);
      if (cached != null) {
        final isComplete = await cacheService.isCacheComplete(placeId);
        debugPrint(
            '🎯 BACKGROUND_LOADER: Кэш найден: $placeName (complete: $isComplete)');

        loadingNotifier.updateState(
          placeId,
          AttractionLoadingState(
            placeId: placeId,
            status:
                isComplete ? LoadingStatus.completed : LoadingStatus.loading,
            info: cached,
          ),
        );
        yield cached;

        if (isComplete) {
          debugPrint('🎯 BACKGROUND_LOADER: Полный кэш, загрузка не нужна');
          return;
        }

        debugPrint('🎯 BACKGROUND_LOADER: Частичный кэш, дозагрузка...');
      }
    }

    if (_streamControllers.containsKey(placeId)) {
      debugPrint(
          '🎯 BACKGROUND_LOADER: Подключение к существующему стриму: $placeName');
      final currentState = loadingNotifier.getState(placeId);
      if (currentState?.info != null) {
        yield currentState!.info!;
      }
      yield* _streamControllers[placeId]!.stream;
      return;
    }

    debugPrint('🎯 BACKGROUND_LOADER: Запуск новой загрузки: $placeName');

    loadingNotifier.updateState(
      placeId,
      AttractionLoadingState(
        placeId: placeId,
        status: LoadingStatus.loading,
      ),
    );

    final controller = StreamController<AttractionInfo>.broadcast();
    _streamControllers[placeId] = controller;

    final detailsService = _ref.read(attractionDetailsServiceProvider);
    AttractionInfo? lastInfo;
    int lastSavedSectionsCount = 0;

    final subscription = detailsService
        .analyzeAttractionStream(placeName, category, context: context)
        .listen(
      (info) async {
        lastInfo = info;

        loadingNotifier.updateState(
          placeId,
          AttractionLoadingState(
            placeId: placeId,
            status: LoadingStatus.loading,
            info: info,
          ),
        );

        controller.add(info);

        int currentSectionsCount = 0;
        if (info.practicalInfo.length > 100) currentSectionsCount++;
        if (info.history.length > 100) currentSectionsCount++;
        if (info.architecturalDetails.length > 100) currentSectionsCount++;
        if (info.interestingFacts.length > 100) currentSectionsCount++;

        if (currentSectionsCount > lastSavedSectionsCount &&
            _hasUsefulContent(info)) {
          lastSavedSectionsCount = currentSectionsCount;
          final isComplete = _isInfoComplete(info);
          await cacheService.cacheAttractionInfo(placeId, info,
              isComplete: isComplete);
          debugPrint(
              '💾 BACKGROUND_LOADER: Инкрементальное сохранение ($currentSectionsCount секций, complete: $isComplete)');
        }
      },
      onError: (error) async {
        debugPrint('❌ BACKGROUND_LOADER: Ошибка: $error');

        if (lastInfo != null && _hasUsefulContent(lastInfo!)) {
          await cacheService.cacheAttractionInfo(placeId, lastInfo!,
              isComplete: false);
          debugPrint(
              '💾 BACKGROUND_LOADER: Сохранены частичные данные при ошибке');
        }

        loadingNotifier.updateState(
          placeId,
          AttractionLoadingState(
            placeId: placeId,
            status: LoadingStatus.error,
            info: lastInfo,
            error: error.toString(),
          ),
        );

        controller.addError(error);
        _cleanup(placeId);
      },
      onDone: () async {
        debugPrint('✅ BACKGROUND_LOADER: Загрузка завершена: $placeName');

        if (lastInfo != null && _hasUsefulContent(lastInfo!)) {
          final isComplete = _isInfoComplete(lastInfo!);
          await cacheService.cacheAttractionInfo(placeId, lastInfo!,
              isComplete: isComplete);
          debugPrint(
              '💾 BACKGROUND_LOADER: Финальное сохранение (complete: $isComplete)');
        }

        loadingNotifier.updateState(
          placeId,
          AttractionLoadingState(
            placeId: placeId,
            status: LoadingStatus.completed,
            info: lastInfo,
          ),
        );

        controller.close();
        _cleanup(placeId);
      },
    );

    _activeSubscriptions[placeId] = subscription;

    yield* controller.stream;
  }

  void startBackgroundLoading({
    required String placeName,
    required String category,
    BuildContext? context,
  }) {
    final placeId = _normalizeId(placeName);

    if (_activeSubscriptions.containsKey(placeId)) {
      debugPrint('🎯 BACKGROUND_LOADER: Фоновая загрузка уже идёт: $placeName');
      return;
    }

    debugPrint('🎯 BACKGROUND_LOADER: Запуск фоновой загрузки: $placeName');

    final loadingNotifier = _ref.read(attractionLoadingStateProvider.notifier);
    final cacheService = _ref.read(attractionCacheServiceProvider);
    final detailsService = _ref.read(attractionDetailsServiceProvider);

    loadingNotifier.updateState(
      placeId,
      AttractionLoadingState(
        placeId: placeId,
        status: LoadingStatus.loading,
      ),
    );

    final controller = StreamController<AttractionInfo>.broadcast();
    _streamControllers[placeId] = controller;

    AttractionInfo? lastInfo;
    int lastSavedSectionsCount = 0;

    final subscription = detailsService
        .analyzeAttractionStream(placeName, category, context: context)
        .listen(
      (info) async {
        lastInfo = info;
        loadingNotifier.updateState(
          placeId,
          AttractionLoadingState(
            placeId: placeId,
            status: LoadingStatus.loading,
            info: info,
          ),
        );
        controller.add(info);

        int currentSectionsCount = 0;
        if (info.practicalInfo.length > 100) currentSectionsCount++;
        if (info.history.length > 100) currentSectionsCount++;
        if (info.architecturalDetails.length > 100) currentSectionsCount++;
        if (info.interestingFacts.length > 100) currentSectionsCount++;

        if (currentSectionsCount > lastSavedSectionsCount &&
            _hasUsefulContent(info)) {
          lastSavedSectionsCount = currentSectionsCount;
          final isComplete = _isInfoComplete(info);
          await cacheService.cacheAttractionInfo(placeId, info,
              isComplete: isComplete);
          debugPrint(
              '💾 BACKGROUND: Инкрементальное сохранение ($currentSectionsCount секций)');
        }
      },
      onError: (error) async {
        debugPrint('❌ BACKGROUND_LOADER: Фоновая ошибка: $error');

        if (lastInfo != null && _hasUsefulContent(lastInfo!)) {
          await cacheService.cacheAttractionInfo(placeId, lastInfo!,
              isComplete: false);
          debugPrint('💾 BACKGROUND: Сохранены частичные данные при ошибке');
        }

        loadingNotifier.updateState(
          placeId,
          AttractionLoadingState(
            placeId: placeId,
            status: LoadingStatus.error,
            info: lastInfo,
            error: error.toString(),
          ),
        );
        controller.addError(error);
        _cleanup(placeId);
      },
      onDone: () async {
        debugPrint(
            '✅ BACKGROUND_LOADER: Фоновая загрузка завершена: $placeName');

        if (lastInfo != null && _hasUsefulContent(lastInfo!)) {
          final isComplete = _isInfoComplete(lastInfo!);
          await cacheService.cacheAttractionInfo(placeId, lastInfo!,
              isComplete: isComplete);
          debugPrint(
              '💾 BACKGROUND: Финальное сохранение (complete: $isComplete)');
        }

        loadingNotifier.updateState(
          placeId,
          AttractionLoadingState(
            placeId: placeId,
            status: LoadingStatus.completed,
            info: lastInfo,
          ),
        );

        controller.close();
        _cleanup(placeId);
      },
    );

    _activeSubscriptions[placeId] = subscription;
  }

  void detachFromUI(String placeName) {
    debugPrint(
        '🔌 BACKGROUND_LOADER: UI отключился, загрузка продолжается: $placeName');
  }

  void cancelLoading(String placeName) {
    final normalizedId = _normalizeId(placeName);
    debugPrint('🛑 BACKGROUND_LOADER: Отмена загрузки: $placeName');

    _activeSubscriptions[normalizedId]?.cancel();
    _streamControllers[normalizedId]?.close();
    _cleanup(normalizedId);

    final loadingNotifier = _ref.read(attractionLoadingStateProvider.notifier);
    loadingNotifier.removeState(normalizedId);
  }

  bool isLoading(String placeName) {
    final placeId = _normalizeId(placeName);
    return _activeSubscriptions.containsKey(placeId);
  }

  AttractionLoadingState? getLoadingState(String placeName) {
    final placeId = _normalizeId(placeName);
    return _ref.read(attractionLoadingStateProvider)[placeId];
  }

  Stream<AttractionInfo>? getExistingStream(String placeName) {
    final placeId = _normalizeId(placeName);
    return _streamControllers[placeId]?.stream;
  }

  void _cleanup(String placeId) {
    _activeSubscriptions.remove(placeId);
    _streamControllers.remove(placeId);
  }

  bool _isInfoComplete(AttractionInfo info) {
    return info.practicalInfo.isNotEmpty &&
        info.history.isNotEmpty &&
        info.architecturalDetails.isNotEmpty &&
        info.interestingFacts.isNotEmpty;
  }

  bool _hasUsefulContent(AttractionInfo info) {
    int filledSections = 0;
    if (info.practicalInfo.length > 50) filledSections++;
    if (info.history.length > 50) filledSections++;
    if (info.architecturalDetails.length > 50) filledSections++;
    if (info.interestingFacts.length > 50) filledSections++;
    return filledSections >= 1;
  }

  void dispose() {
    for (final subscription in _activeSubscriptions.values) {
      subscription.cancel();
    }
    for (final controller in _streamControllers.values) {
      controller.close();
    }
    _activeSubscriptions.clear();
    _streamControllers.clear();
  }
}



















