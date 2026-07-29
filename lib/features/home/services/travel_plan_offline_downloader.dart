import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/attraction_info.dart';
import '../models/attraction_place.dart';
import '../models/location_overview_info.dart';
import '../models/travel_plan.dart';
import '../services/attraction_cache_service.dart';
import '../services/attraction_details_service.dart';
import '../services/google_places_service.dart';
import '../services/location_overview_cache_service.dart';
import '../services/location_overview_service.dart';
import '../attraction_providers.dart';
import '../travel_plans_provider.dart';
import '../../../services/nutrition_analysis/deepseek/deepseek_client.dart';
import '../../../services/providers.dart' as services;
import '../../../services/image_search/google_image_search_service.dart';
import 'travel_plan_offline_storage.dart';

enum TravelPlanOfflineDownloadStatus {
  idle,
  downloading,
  completed,
  cancelled,
  error,
}

class TravelPlanOfflineDownloadState {
  final TravelPlanOfflineDownloadStatus status;
  final double progress; // 0..1
  final int done;
  final int total;
  final String? label;
  final String? error;
  final bool isDownloaded;

  const TravelPlanOfflineDownloadState({
    required this.status,
    required this.progress,
    required this.done,
    required this.total,
    required this.label,
    required this.error,
    required this.isDownloaded,
  });

  factory TravelPlanOfflineDownloadState.idle({required bool isDownloaded}) {
    return TravelPlanOfflineDownloadState(
      status: TravelPlanOfflineDownloadStatus.idle,
      progress: 0,
      done: 0,
      total: 0,
      label: null,
      error: null,
      isDownloaded: isDownloaded,
    );
  }

  TravelPlanOfflineDownloadState copyWith({
    TravelPlanOfflineDownloadStatus? status,
    double? progress,
    int? done,
    int? total,
    String? label,
    String? error,
    bool? isDownloaded,
  }) {
    return TravelPlanOfflineDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      done: done ?? this.done,
      total: total ?? this.total,
      label: label ?? this.label,
      error: error,
      isDownloaded: isDownloaded ?? this.isDownloaded,
    );
  }
}

final travelPlanOfflineStorageProvider =
    Provider<TravelPlanOfflineStorage>((_) {
  return TravelPlanOfflineStorage();
});

final _attractionCacheProvider = Provider<AttractionCacheService>((ref) {
  return AttractionCacheService();
});

final _attractionDetailsProvider = Provider<AttractionDetailsService>((ref) {
  return AttractionDetailsService(
    client: DeepSeekClient.fromEnvironment(
      fastMode: false,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 30),
    ),
  );
});

final _locationOverviewCacheProvider =
    Provider<LocationOverviewCacheService>((ref) {
  return LocationOverviewCacheService();
});

final _locationOverviewProvider = Provider<LocationOverviewService>((ref) {
  return LocationOverviewService(
    client: DeepSeekClient.fromEnvironment(
      fastMode: false,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 30),
    ),
  );
});

final travelPlanOfflineDownloadProvider = StateNotifierProvider.family<
    TravelPlanOfflineDownloadNotifier,
    TravelPlanOfflineDownloadState,
    String>((ref, planId) {
  return TravelPlanOfflineDownloadNotifier(ref, planId);
});

class TravelPlanOfflineDownloadNotifier
    extends StateNotifier<TravelPlanOfflineDownloadState> {
  TravelPlanOfflineDownloadNotifier(this._ref, this._planId)
      : super(const TravelPlanOfflineDownloadState(
          status: TravelPlanOfflineDownloadStatus.idle,
          progress: 0,
          done: 0,
          total: 0,
          label: null,
          error: null,
          isDownloaded: false,
        )) {
    _restore();
  }

  final Ref _ref;
  final String _planId;
  bool _cancelRequested = false;
  Future<void>? _active;

  Future<void> _restore() async {
    final storage = _ref.read(travelPlanOfflineStorageProvider);
    final downloaded = await storage.isDownloaded(_planId);
    state = TravelPlanOfflineDownloadState.idle(isDownloaded: downloaded);
  }

  Future<void> start(TravelPlan plan) async {
    if (_active != null) return;
    _cancelRequested = false;

    final storage = _ref.read(travelPlanOfflineStorageProvider);
    final downloaded = await storage.isDownloaded(_planId);

    final uniquePlaces = _uniquePlaces(plan);
    final total = uniquePlaces.length + 1; // + обзор локации

    state = state.copyWith(
      status: TravelPlanOfflineDownloadStatus.downloading,
      progress: 0,
      done: 0,
      total: total,
      label: 'Подготовка…',
      error: null,
      isDownloaded: downloaded,
    );

    _active = _run(plan, uniquePlaces, storage).whenComplete(() {
      _active = null;
    });
    await _active;
  }

  void cancel() {
    if (_active == null) return;
    _cancelRequested = true;
  }

  Future<void> _run(
    TravelPlan plan,
    List<AttractionPlace> places,
    TravelPlanOfflineStorage storage,
  ) async {
    try {
      int done = 0;

      Future<void> tick(String label) async {
        final progress = state.total == 0 ? 0 : done / state.total;
        state = state.copyWith(
          status: TravelPlanOfflineDownloadStatus.downloading,
          done: done,
          progress: progress.clamp(0.0, 1.0).toDouble(),
          label: label,
          error: null,
        );
        await Future<void>.delayed(Duration.zero);
      }

      Future<void> bump(String label) async {
        done++;
        await tick(label);
      }

      await tick('Скачиваем «О месте»…');
      await _downloadLocationOverview(plan.placeLabel);
      await bump('«О месте» готово');

      final cache = _ref.read(_attractionCacheProvider);
      final details = _ref.read(_attractionDetailsProvider);
      final placesService = _ref.read(googlePlacesServiceProvider);
      final imageSearchService = _ref.read(services.imageSearchServiceProvider);

      final center = LatLng(plan.latitude, plan.longitude);
      String? cityName;
      String? countryName;
      try {
        final placemarks =
            await placemarkFromCoordinates(plan.latitude, plan.longitude);
        if (placemarks.isNotEmpty) {
          cityName =
              placemarks.first.locality ?? placemarks.first.administrativeArea;
          countryName = placemarks.first.country;
        }
      } catch (_) {
        // ignore
      }

      // Ускорение: сначала одним/несколькими batch-запросами получаем тексты сразу
      // (обычный streaming экранов не трогаем)
      await _prefetchAttractionInfosBatch(
        places: places,
        cache: cache,
        details: details,
      );

      Future<void> handlePlace(AttractionPlace place) async {
        if (_cancelRequested) return;

        final updated = await _ensurePlaceId(
          plan: plan,
          place: place,
          center: center,
          placesService: placesService,
        );

        final placeId = _normalizePlaceId(updated.name);
        final cachedInfo =
            await cache.getCachedAttractionInfo(placeId, allowPartial: false);
        if (cachedInfo == null && !_cancelRequested) {
          final info = await details.analyzeAttraction(
            updated.name,
            updated.category,
            context: null,
          );
          if (_cancelRequested) return;
          await cache.cacheAttractionInfo(
            placeId,
            info,
            isComplete: _isAttractionInfoComplete(info),
          );
        }

        if (_cancelRequested) return;
        final cachedImages = await cache.getCachedImages(updated.name);
        if (cachedImages.isEmpty &&
            imageSearchService is GoogleImageSearchService &&
            !_cancelRequested) {
          final suffixes = <String>[
            '',
            'photo',
            'достопримечательность',
            'landmark',
          ];
          final collected = <File>[];
          await for (final file in imageSearchService.streamImages(
            baseName: updated.name,
            cityName: cityName,
            countryName: countryName,
            searchSuffixes: suffixes,
            maxImages: 1,
          )) {
            collected.add(file);
            if (_cancelRequested || collected.isNotEmpty) break;
          }
          if (!_cancelRequested && collected.isNotEmpty) {
            await cache.cacheAttractionImages(updated.name, collected);
          }
        }
      }

      await _runWithConcurrency(
        items: places,
        concurrency: 3,
        onItem: (place) async {
          if (_cancelRequested) return;
          await tick('Скачиваем: ${place.name}');
          await handlePlace(place);
          if (_cancelRequested) return;
          await bump('Готово: ${place.name}');
        },
      );

      if (_cancelRequested) {
        state = state.copyWith(
          status: TravelPlanOfflineDownloadStatus.cancelled,
          label: 'Отменено',
          error: null,
        );
        return;
      }

      await storage.markDownloaded(_planId, totalPlaces: places.length);
      state = state.copyWith(
        status: TravelPlanOfflineDownloadStatus.completed,
        progress: 1,
        done: state.total,
        label: 'Скачано',
        error: null,
        isDownloaded: true,
      );
    } catch (e) {
      state = state.copyWith(
        status: TravelPlanOfflineDownloadStatus.error,
        error: e.toString(),
        label: 'Ошибка',
      );
    }
  }

  Future<void> _downloadLocationOverview(String placeLabel) async {
    final cache = _ref.read(_locationOverviewCacheProvider);
    final service = _ref.read(_locationOverviewProvider);

    final cached =
        await cache.getCachedLocationOverview(placeLabel, allowPartial: false);
    if (cached != null && _isLocationInfoComplete(cached)) return;

    if (_cancelRequested) return;
    final last = await service.analyzeLocation(placeLabel, context: null);
    if (_cancelRequested) return;

    await cache.cacheLocationOverview(
      placeLabel,
      last,
      isComplete: _isLocationInfoComplete(last),
    );
  }

  Future<void> _runWithConcurrency<T>({
    required List<T> items,
    required int concurrency,
    required Future<void> Function(T item) onItem,
  }) async {
    if (items.isEmpty) return;
    final workers = <Future<void>>[];
    var nextIndex = 0;
    final limit = concurrency < 1 ? 1 : concurrency;

    for (var w = 0; w < limit; w++) {
      workers.add(() async {
        while (true) {
          if (_cancelRequested) return;
          if (nextIndex >= items.length) return;
          final i = nextIndex;
          nextIndex = i + 1;
          if (i >= items.length) return;
          await onItem(items[i]);
        }
      }());
    }
    await Future.wait(workers);
  }

  Future<void> _prefetchAttractionInfosBatch({
    required List<AttractionPlace> places,
    required AttractionCacheService cache,
    required AttractionDetailsService details,
  }) async {
    if (_cancelRequested) return;

    final toLoad = <AttractionPlace>[];
    for (final p in places) {
      if (_cancelRequested) return;
      final key = _normalizePlaceId(p.name);
      final cached =
          await cache.getCachedAttractionInfo(key, allowPartial: false);
      if (cached == null) {
        toLoad.add(p);
      }
    }
    if (toLoad.isEmpty) return;

    // Best practice: не "всё сразу", а чанки + ограниченная параллельность,
    // чтобы не упираться в лимиты/таймауты API и не завалить сеть.
    const batchSize = 3;
    const concurrency = 2;

    final batches = <List<AttractionPlace>>[];
    for (var i = 0; i < toLoad.length; i += batchSize) {
      batches.add(toLoad.skip(i).take(batchSize).toList(growable: false));
    }

    await _runWithConcurrency<List<AttractionPlace>>(
      items: batches,
      concurrency: concurrency,
      onItem: (batch) async {
        if (_cancelRequested) return;
        final infos = await details.analyzeAttractionsBatch(
          batch,
          context: null,
        );
        for (final info in infos) {
          if (_cancelRequested) return;
          if (!_isAttractionInfoComplete(info)) continue;
          final id = _normalizePlaceId(info.name);
          await cache.cacheAttractionInfo(id, info, isComplete: true);
        }
      },
    );
  }

  Future<AttractionPlace> _ensurePlaceId({
    required TravelPlan plan,
    required AttractionPlace place,
    required LatLng center,
    required GooglePlacesService placesService,
  }) async {
    final hasPlaceId = (place.googlePlaceId ?? '').trim().isNotEmpty;
    final hasCoords = _hasValidCoordinates(place);
    if (hasPlaceId && hasCoords) return place;

    try {
      final real = await placesService.findPlaceByName(
        name: place.name,
        nearLocation: center,
        cityHint: plan.placeLabel,
        radiusMeters: 50000,
      );
      if (real == null) return place;

      final updated = place.copyWith(
        googlePlaceId: real.googlePlaceId ?? real.id,
        latitude: real.latitude,
        longitude: real.longitude,
      );

      await _ref.read(travelPlansProvider.notifier).replacePlaceInPlan(
            planId: plan.id,
            oldName: place.name,
            updated: updated,
          );

      return updated;
    } catch (_) {
      return place;
    }
  }

  static List<AttractionPlace> _uniquePlaces(TravelPlan plan) {
    final input = <AttractionPlace>[
      for (final r in plan.routes) ...r.stops,
      ...plan.attractions,
    ];
    final seen = <String>{};
    final out = <AttractionPlace>[];
    for (final p in input) {
      final key = _nameKey(p.name);
      if (key.isEmpty) continue;
      if (seen.add(key)) out.add(p);
    }
    return out;
  }

  static String _nameKey(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _normalizePlaceId(String placeName) =>
      placeName.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');

  static bool _hasValidCoordinates(AttractionPlace place) {
    final latOk = place.latitude.abs() <= 90;
    final lngOk = place.longitude.abs() <= 180;
    final notZero = place.latitude != 0 || place.longitude != 0;
    return latOk && lngOk && notZero;
  }

  static bool _isAttractionInfoComplete(AttractionInfo info) {
    return info.practicalInfo.isNotEmpty &&
        info.history.isNotEmpty &&
        info.architecturalDetails.isNotEmpty &&
        info.interestingFacts.isNotEmpty &&
        (info.error == null || info.error!.isEmpty);
  }

  static bool _isLocationInfoComplete(LocationOverviewInfo info) {
    return info.generalInfo.length > 300 &&
        info.history.length > 300 &&
        info.culture.length > 300 &&
        info.interestingFacts.length > 300 &&
        info.practicalInfo.length > 300 &&
        (info.error == null || info.error!.isEmpty);
  }
}











