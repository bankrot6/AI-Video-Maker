import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:uuid/uuid.dart';

import 'attraction_providers.dart';
import 'models/travel_plan.dart';
import 'models/attraction_place.dart';
import 'models/attraction_route.dart';
import 'services/travel_plan_storage.dart';
import 'services/travel_plan_storage_provider.dart';
import 'services/route_stop_ordering_service.dart';
import '../../services/providers.dart' as services;
import '../../services/city_limit_service.dart';

final travelPlansProvider =
    StateNotifierProvider<TravelPlansNotifier, List<TravelPlan>>(
  (ref) => TravelPlansNotifier(ref),
);

class TravelPlansNotifier extends StateNotifier<List<TravelPlan>> {
  TravelPlansNotifier(this._ref)
      : _storage = _ref.read(travelPlanStorageProvider),
        super(const []) {
    _restoreFromCache();
  }

  final Ref _ref;
  final TravelPlanStorage _storage;
  bool _restored = false;
  Timer? _persistTimer;
  final Map<String, Future<void>> _previewTasks = {};
  final Set<String> _fullGenerationInFlight = {};

  static final math.Random _random = math.Random();

  Future<TravelPlan> createDefaultPlan() async {
    final seedPlan = _buildRandomSeedPlan();
    state = [...state, seedPlan];
    await _persistPlans();
    debugPrint(
        '📍 TravelPlansNotifier: Добавляем стартовую экскурсию для ${seedPlan.placeLabel}');
    return seedPlan;
  }

  Future<void> restoreFromCache() => _restoreFromCache();

  Future<TravelPlan> createPlan({
    required String placeQuery,
    required int stayDays,
    required List<String> interests,
    int? previewAttractionsLimit,
    bool prioritizePreviewAttractions = false,
    String? existingPlanId,
    bool previewOnly = false,
    bool keepOriginalPlaceLabel = false,
  }) async {
    final trimmed = placeQuery.trim();
    if (trimmed.isEmpty) {
      throw Exception('Укажи место для поиска.');
    }

    if (existingPlanId == null && !previewOnly) {
      final limitService = _ref.read(services.cityLimitServiceProvider);
      final limitResult = await limitService.checkAndRecordCityCreation();
      if (!limitResult.allowed) {
        throw CityLimitException(limitResult);
      }
    }

    final existingPlan = existingPlanId == null
        ? null
        : state.where((p) => p.id == existingPlanId).firstOrNull;

    // Сразу показываем карточку в списке (без ожидания геокодинга/AI).
    final provisionalPlan = existingPlan?.copyWith(
          placeLabel: existingPlan.placeLabel.trim().isNotEmpty
              ? existingPlan.placeLabel
              : trimmed,
          query: trimmed,
          stayDays: stayDays,
          interests: List.unmodifiable(interests),
          status: TravelPlanStatus.loading,
          errorMessage: null,
        ) ??
        TravelPlan.create(
          placeLabel: trimmed,
          query: trimmed,
          stayDays: stayDays,
          interests: interests,
          latitude: 0,
          longitude: 0,
          routes: const [],
          attractions: const [],
          status: TravelPlanStatus.loading,
        );

    if (existingPlan == null) {
      state = [...state, provisionalPlan];
    } else {
      state = state
          .map((p) => p.id == provisionalPlan.id ? provisionalPlan : p)
          .toList(growable: false);
    }
    await _persistPlans();
    debugPrint(
        '📍 TravelPlansNotifier: Создаём кастомный план для ${provisionalPlan.placeLabel} на $stayDays дн.');

    // ВАЖНО: не блокируем UI ожиданием генерации маршрутов/мест.
    // План добавлен сразу, далее наполняем его потоково в фоне.
    unawaited(() async {
      if (!previewOnly) {
        if (_fullGenerationInFlight.contains(provisionalPlan.id)) return;
        _fullGenerationInFlight.add(provisionalPlan.id);
      }
      List<AttractionRoute> routes = provisionalPlan.routes;
      List<AttractionPlace> attractions = provisionalPlan.attractions;
      Location? resolvedTarget;
      String displayLabel = provisionalPlan.placeLabel;

      try {
        final aiService = _ref.read(attractionAiServiceProvider);
        const routeOrderer = RouteStopOrderingService();
        final interestsHint =
            interests.isNotEmpty ? interests.join(', ') : null;

        void updatePlan({
          List<AttractionRoute>? routesValue,
          List<AttractionPlace>? attractionsValue,
          TravelPlanStatus? status,
          String? placeLabel,
          double? latitude,
          double? longitude,
        }) {
          final current =
              state.where((p) => p.id == provisionalPlan.id).firstOrNull;
          if (current == null) return;
          final updatedPlan = current.copyWith(
            routes: routesValue ?? current.routes,
            attractions: attractionsValue ?? current.attractions,
            status: status ?? current.status,
            placeLabel: placeLabel ?? current.placeLabel,
            latitude: latitude ?? current.latitude,
            longitude: longitude ?? current.longitude,
          );
          state = state
              .map((p) => p.id == provisionalPlan.id ? updatedPlan : p)
              .toList(growable: false);
        }

        void emitPartial() => updatePlan(
              routesValue: routes,
              attractionsValue: attractions,
              status: TravelPlanStatus.partial,
            );

        Future<void> emitAttractionsIncremental(
            List<AttractionPlace> next) async {
          if (next.length <= attractions.length) return;
          for (int i = attractions.length; i < next.length; i++) {
            attractions = [...attractions, next[i]];
            emitPartial();
            _schedulePersist();
            await Future<void>.delayed(Duration.zero);
          }
        }

        Future<void> fetchAttractionsStreamFirst({
          required double latitude,
          required double longitude,
          required String cityHint,
          required int limit,
        }) async {
          await for (final partialAttractions
              in aiService.fetchAttractionsStream(
            latitude: latitude,
            longitude: longitude,
            cityHint: cityHint,
            limit: limit,
            interestsHint: interestsHint,
          )) {
            if (partialAttractions.isEmpty) continue;
            await emitAttractionsIncremental(partialAttractions);
            debugPrint(
                '📍 TravelPlansNotifier: Обновление - мест: ${attractions.length} (limit=$limit)');
          }
        }

        Future<void> fetchAttractionsFastPreview(int limit) async {
          if (attractions.length >= limit) return;
          try {
            final fetched = await aiService.fetchTopAttractions(
              cityHint: trimmed,
              limit: limit,
              interestsHint: interestsHint,
            );
            if (fetched.isNotEmpty) {
              await emitAttractionsIncremental(fetched);
              debugPrint(
                  '📍 TravelPlansNotifier: PREVIEW short: ${fetched.length}');
              if (attractions.length >= limit) {
                return;
              }
            }
          } catch (e) {
            debugPrint('📍 TravelPlansNotifier: PREVIEW short failed: $e');
          }

          await fetchAttractionsStreamFirst(
            latitude: 0,
            longitude: 0,
            cityHint: trimmed,
            limit: limit,
          );
        }

        final attractionsLimitFull =
            math.min(120, math.max(40, stayDays * 15)); // 7 дней -> ~105
        final previewLimit = previewAttractionsLimit == null
            ? null
            : previewAttractionsLimit.clamp(1, attractionsLimitFull);

        // Для онбординга: сначала быстро получаем 5-7 мест, чтобы UI мог заполниться.
        if (prioritizePreviewAttractions && previewLimit != null) {
          debugPrint(
              '📍 TravelPlansNotifier: PREVIEW мест: limit=$previewLimit');
          final existingTask = _previewTasks[provisionalPlan.id];
          if (existingTask != null) {
            await existingTask;
            final refreshed =
                state.where((p) => p.id == provisionalPlan.id).firstOrNull;
            if (refreshed != null) {
              attractions = refreshed.attractions;
              routes = refreshed.routes;
            }
          } else {
            final task = fetchAttractionsFastPreview(previewLimit);
            _previewTasks[provisionalPlan.id] = task;
            try {
              await task;
            } finally {
              if (_previewTasks[provisionalPlan.id] == task) {
                _previewTasks.remove(provisionalPlan.id);
              }
            }
          }
          if (attractions.length < previewLimit) {
            await fetchAttractionsStreamFirst(
              latitude: 0,
              longitude: 0,
              cityHint: trimmed,
              limit: previewLimit,
            );
          }
        }

        if (previewOnly) {
          return;
        }

        final coordinates = await locationFromAddress(trimmed);
        if (coordinates.isEmpty) {
          throw Exception('Не удалось найти координаты места.');
        }

        final target = coordinates.first;
        resolvedTarget = target;
        final resolvedLabel = await _resolveLabel(target, fallback: trimmed);
        final cityHint = keepOriginalPlaceLabel ? trimmed : resolvedLabel;
        displayLabel = keepOriginalPlaceLabel ? trimmed : resolvedLabel;

        // Обновляем заголовок/координаты как только нашли их.
        updatePlan(
          placeLabel: displayLabel,
          latitude: target.latitude,
          longitude: target.longitude,
          status: (routes.isNotEmpty || attractions.isNotEmpty)
              ? TravelPlanStatus.partial
              : TravelPlanStatus.loading,
        );
        _schedulePersist();

        Future<void> fetchAttractionsStreamOnly(int limit) async {
          try {
            await fetchAttractionsStreamFirst(
              latitude: target.latitude,
              longitude: target.longitude,
            cityHint: cityHint,
              limit: limit,
            );
          } catch (e) {
            debugPrint('📍 TravelPlansNotifier: stream мест не удался: $e');
          }
        }

        debugPrint(
            '📍 TravelPlansNotifier: Получаем маршруты с интересами: $interestsHint');
        final routeCount = stayDays >= 6 ? 6 : (stayDays >= 4 ? 5 : 4);

        if (routes.isEmpty) {
          try {
            await for (final partialRoutes in aiService.fetchRoutesStream(
              latitude: target.latitude,
              longitude: target.longitude,
              cityHint: cityHint,
              routesCount: routeCount,
              stopsPerRoute: 9,
              interestsHint: interestsHint,
            )) {
              routes = partialRoutes
                  .map(
                    (r) => r.copyWith(
                      stops: routeOrderer.orderStops(
                        stops: r.stops,
                        originLat: target.latitude,
                        originLng: target.longitude,
                      ),
                    ),
                  )
                  .toList(growable: false);
              debugPrint(
                  '📍 TravelPlansNotifier: Обновление - маршрутов: ${routes.length}');
              updatePlan(routesValue: routes, status: TravelPlanStatus.partial);
              _schedulePersist();
            }
          } catch (e) {
            debugPrint('📍 TravelPlansNotifier: stream маршрутов не удался: $e');
          }
        }

        if (routes.isEmpty) {
          debugPrint(
              '📍 TravelPlansNotifier: Маршруты пусты, создаём запасной');
          routes = [_fallbackRoute(displayLabel, target)];
          emitPartial();
          _schedulePersist();
        }

        // Полная догрузка мест в фоне (если preview уже был — расширяем лимит).
        if (!prioritizePreviewAttractions ||
            previewLimit != attractionsLimitFull) {
          debugPrint(
              '📍 TravelPlansNotifier: FULL мест: limit=$attractionsLimitFull');
          await fetchAttractionsStreamOnly(attractionsLimitFull);
          if (attractions.isEmpty) {
            debugPrint(
                '📍 TravelPlansNotifier: Места пусты, создаём запасное');
            attractions = [_fallbackPlace(displayLabel, target)];
            emitPartial();
            _schedulePersist();
          }
        }

        // ВАЖНО: сохраняем id/createdAt у provisional-плана, иначе UI,
        // который держит ссылку по id (например, TripPlanScreen/DetailsScreen),
        // "теряет" план после завершения генерации.
        final completedPlan = provisionalPlan.copyWith(
          placeLabel: displayLabel,
          latitude: target.latitude,
          longitude: target.longitude,
          routes: routes,
          attractions: attractions,
          status: TravelPlanStatus.completed,
          errorMessage: null,
        );

        debugPrint(
            '📍 TravelPlansNotifier: Кастомный план завершен - маршрутов: ${routes.length}, мест: ${attractions.length}');
        state = state
            .map((p) => p.id == provisionalPlan.id ? completedPlan : p)
            .toList(growable: false);
        await _flushPersist();
      } catch (e) {
        debugPrint(
            '📍 TravelPlansNotifier: Ошибка создания кастомного плана: $e');
        final current =
            state.where((p) => p.id == provisionalPlan.id).firstOrNull;
        final hasData = routes.isNotEmpty || attractions.isNotEmpty;
        final target = resolvedTarget;

        if (!hasData && target != null) {
          routes = [_fallbackRoute(displayLabel, target)];
          attractions = [_fallbackPlace(displayLabel, target)];
        }

        final hasFallback = routes.isNotEmpty || attractions.isNotEmpty;
        final status =
            hasFallback ? TravelPlanStatus.completed : TravelPlanStatus.error;
        final errorMessage = hasFallback
            ? null
            : 'Не удалось загрузить экскурсию. Проверьте подключение.';

        final base = current ?? provisionalPlan;
        final errorPlan = base.copyWith(
          placeLabel: displayLabel,
          latitude: target?.latitude ?? base.latitude,
          longitude: target?.longitude ?? base.longitude,
          routes: routes,
          attractions: attractions,
          status: status,
          errorMessage: errorMessage,
        );
        state = state
            .map((p) => p.id == provisionalPlan.id ? errorPlan : p)
            .toList(growable: false);
        await _flushPersist();
      } finally {
        if (!previewOnly) {
          _fullGenerationInFlight.remove(provisionalPlan.id);
        }
      }
    }());

    return provisionalPlan;
  }

  void removePlan(String id) {
    state = state.where((plan) => plan.id != id).toList(growable: false);
    _persistPlans();
  }

  Future<void> replacePlaceInPlan({
    required String planId,
    required String oldName,
    required AttractionPlace updated,
  }) async {
    String key(String v) =>
        v.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

    final plan = state.firstWhere(
      (p) => p.id == planId,
      orElse: () => throw Exception('План не найден'),
    );

    final oldKey = key(oldName);
    if (oldKey.isEmpty) return;

    final newRoutes = plan.routes
        .map((r) => r.copyWith(
              stops: r.stops
                  .map((s) => key(s.name) == oldKey ? updated : s)
                  .toList(growable: false),
            ))
        .toList(growable: false);

    final newAttractions = plan.attractions
        .map((p) => key(p.name) == oldKey ? updated : p)
        .toList(growable: false);

    final next = plan.copyWith(routes: newRoutes, attractions: newAttractions);
    state = state.map((p) => p.id == planId ? next : p).toList(growable: false);
    await _persistPlans();
  }

  Future<String> _resolveLabel(Location location,
      {required String fallback}) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final city = place.locality;
        final region = place.administrativeArea;
        final country = place.country;
        final buffer = [city, region, country]
            .where((item) => item != null && item.isNotEmpty)
            .map((e) => e!)
            .toList();
        if (buffer.isNotEmpty) {
          return buffer.join(', ');
        }
      }
    } catch (_) {
      // Игнорируем, используем fallback
    }
    return fallback;
  }

  TravelPlan _buildRandomSeedPlan() {
    final city = _popularCitySeeds[_random.nextInt(_popularCitySeeds.length)];
    final shuffledSpots = [...city.spots]..shuffle(_random);
    final stayDays = _randomRange(1, 3);

    final routeCount = math.max(
      1,
      math.min(3, (shuffledSpots.length / 3).ceil()),
    );

    final routes = <AttractionRoute>[];
    for (int index = 0; index < routeCount; index++) {
      final stops = shuffledSpots
          .skip(index * 3)
          .take(3)
          .map((spot) => _spotToPlace(city, spot))
          .toList();
      if (stops.isEmpty) continue;
      routes.add(
        AttractionRoute(
          id: const Uuid().v4(),
          title: '${city.city}: Маршрут ${index + 1}',
          summary: city.preview,
          theme: city.tags.isNotEmpty
              ? city.tags[index % city.tags.length]
              : 'classic',
          estimatedDistanceKm: _randomDistance(),
          estimatedDurationMin: _randomDuration(),
          stops: stops,
        ),
      );
    }

    final attractions =
        shuffledSpots.take(8).map((spot) => _spotToPlace(city, spot)).toList();

    return TravelPlan.create(
      placeLabel: '${city.city}, ${city.country}',
      query: city.city,
      stayDays: stayDays,
      interests: city.tags,
      latitude: city.lat,
      longitude: city.lng,
      routes: routes,
      attractions: attractions,
    );
  }

  AttractionPlace _spotToPlace(_CitySeed city, _SpotSeed spot) {
    final latOffset = _randomCoordOffset();
    final lngOffset = _randomCoordOffset();
    return AttractionPlace(
      id: const Uuid().v4(),
      name: spot.name,
      description: spot.description,
      latitude: city.lat + latOffset,
      longitude: city.lng + lngOffset,
      category: spot.category,
      distanceKm: null,
      highlight: spot.highlight,
    );
  }

  double _randomCoordOffset() => (_random.nextDouble() - 0.5) * 0.04;

  double _randomDistance() => 3 + _random.nextDouble() * 5;

  int _randomDuration() => 60 + _random.nextInt(91);

  int _randomRange(int lower, int upper) =>
      lower + _random.nextInt(upper - lower + 1);

  Future<void> _persistPlans() async {
    await _storage.save(state);
  }

  void _schedulePersist({Duration delay = const Duration(milliseconds: 2000)}) {
    _persistTimer?.cancel();
    _persistTimer = Timer(delay, () {
      unawaited(_persistPlans());
    });
  }

  Future<void> _flushPersist() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _persistPlans();
  }

  Future<void> _restoreFromCache() async {
    if (_restored) return;
    _restored = true;
    final cached = await _storage.load();
    if (cached.isNotEmpty) {
      state = cached;
      debugPrint(
          '💾 TravelPlansNotifier: Восстановлено ${cached.length} планов');
    }
  }

  AttractionRoute _fallbackRoute(String label, Location target) {
    final stop = AttractionPlace(
      id: const Uuid().v4(),
      name: label,
      description: 'Прогулка по городу',
      latitude: target.latitude,
      longitude: target.longitude,
      category: 'sight',
      distanceKm: 2.5,
      highlight: null,
    );
    return AttractionRoute(
      id: const Uuid().v4(),
      title: 'Маршрут по $label',
      summary: 'Краткая прогулка по ключевым точкам.',
      theme: 'classic',
      estimatedDistanceKm: 3.0,
      estimatedDurationMin: 90,
      stops: [stop],
    );
  }

  AttractionPlace _fallbackPlace(String label, Location target) {
    return AttractionPlace(
      id: const Uuid().v4(),
      name: label,
      description: 'Главная точка интереса в регионе.',
      latitude: target.latitude,
      longitude: target.longitude,
      category: 'sight',
      distanceKm: null,
      highlight: null,
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class _CitySeed {
  final String city;
  final String country;
  final double lat;
  final double lng;
  final String preview;
  final List<String> tags;
  final List<_SpotSeed> spots;

  const _CitySeed({
    required this.city,
    required this.country,
    required this.lat,
    required this.lng,
    required this.preview,
    required this.tags,
    required this.spots,
  });
}

class _SpotSeed {
  final String name;
  final String description;
  final String category;
  final String? highlight;

  const _SpotSeed({
    required this.name,
    required this.description,
    required this.category,
    this.highlight,
  });
}

const List<_CitySeed> _popularCitySeeds = [
  _CitySeed(
    city: 'Париж',
    country: 'Франция',
    lat: 48.8566,
    lng: 2.3522,
    preview: 'Классика Парижа: музеи, набережные и видовые площадки.',
    tags: ['Культура', 'Прогулки', 'Музеи'],
    spots: [
      _SpotSeed(
        name: 'Эйфелева башня',
        description: 'Главный символ города с панорамным видом.',
        category: 'sight',
        highlight: 'Вечерняя подсветка',
      ),
      _SpotSeed(
        name: 'Лувр',
        description: 'Коллекция мирового искусства и Монны Лизы.',
        category: 'museum',
      ),
      _SpotSeed(
        name: 'Нотр-Дам',
        description: 'Готический собор на острове Сите.',
        category: 'sight',
      ),
      _SpotSeed(
        name: 'Монмартр',
        description: 'Холм с уличными артистами и базиликой Сакре-Кёр.',
        category: 'view',
      ),
      _SpotSeed(
        name: 'Сена и набережные',
        description: 'Романтичная прогулка вдоль реки и книжных лавок.',
        category: 'walk',
      ),
      _SpotSeed(
        name: 'Музей Орсе',
        description: 'Импрессионисты в бывшем вокзале.',
        category: 'museum',
      ),
    ],
  ),
  _CitySeed(
    city: 'Барселона',
    country: 'Испания',
    lat: 41.3874,
    lng: 2.1686,
    preview: 'Гауди, море и тапас — идеальное сочетание.',
    tags: ['Архитектура', 'Море', 'Еда'],
    spots: [
      _SpotSeed(
        name: 'Саграда Фамилия',
        description: 'Шедевр Гауди, стройка века.',
        category: 'sight',
      ),
      _SpotSeed(
        name: 'Парк Гуэль',
        description: 'Мозаики, виды на город и ящерица-символ.',
        category: 'park',
      ),
      _SpotSeed(
        name: 'Готический квартал',
        description: 'Узкие улочки и кафедральный собор.',
        category: 'walk',
      ),
      _SpotSeed(
        name: 'Ла Рамбла',
        description: 'Главный бульвар с уличными артистами.',
        category: 'walk',
      ),
      _SpotSeed(
        name: 'Барселонета',
        description: 'Пляж, паэлья и вечерний променад.',
        category: 'food',
      ),
      _SpotSeed(
        name: 'Каса Батльо',
        description: 'Фантазийный дом с волнистым фасадом.',
        category: 'sight',
      ),
    ],
  ),
  _CitySeed(
    city: 'Рим',
    country: 'Италия',
    lat: 41.9028,
    lng: 12.4964,
    preview: 'Античность, фонтаны и уютные площади в одном дне.',
    tags: ['История', 'Еда', 'Прогулки'],
    spots: [
      _SpotSeed(
        name: 'Колизей',
        description: 'Амфитеатр гладиаторов и символ Рима.',
        category: 'sight',
      ),
      _SpotSeed(
        name: 'Форум',
        description: 'Руины Древнего Рима между холмами.',
        category: 'history',
      ),
      _SpotSeed(
        name: 'Фонтан Треви',
        description: 'Брось монетку и вернись в город.',
        category: 'sight',
      ),
      _SpotSeed(
        name: 'Пьяцца Навона',
        description: 'Барочная площадь с уличными кафе.',
        category: 'food',
      ),
      _SpotSeed(
        name: 'Пантеон',
        description: 'Храм с культовым окулюсом в куполе.',
        category: 'sight',
      ),
      _SpotSeed(
        name: 'Трастевере',
        description: 'Атмосферные улочки и вечерние траттории.',
        category: 'walk',
      ),
    ],
  ),
  _CitySeed(
    city: 'Нью-Йорк',
    country: 'США',
    lat: 40.7128,
    lng: -74.006,
    preview: 'Скайлайн, парки и культовые районы мегаполиса.',
    tags: ['Город', 'Парки', 'Еда'],
    spots: [
      _SpotSeed(
        name: 'Централ-Парк',
        description: 'Зелёный остров посреди Манхэттена.',
        category: 'park',
      ),
      _SpotSeed(
        name: 'Таймс-сквер',
        description: 'Неоновые экраны и поток людей.',
        category: 'sight',
      ),
      _SpotSeed(
        name: 'Бруклинский мост',
        description: 'Пешеходная прогулка с видом на небоскрёбы.',
        category: 'walk',
      ),
      _SpotSeed(
        name: 'Манхэттенский Сохо',
        description: 'Лофты, галереи и кофейни.',
        category: 'food',
      ),
      _SpotSeed(
        name: 'Метрополитен-музей',
        description: 'Одна из крупнейших коллекций искусства.',
        category: 'museum',
      ),
      _SpotSeed(
        name: 'Высокая линия',
        description: 'Парк на месте старой железной дороги.',
        category: 'park',
      ),
    ],
  ),
  _CitySeed(
    city: 'Токио',
    country: 'Япония',
    lat: 35.6762,
    lng: 139.6503,
    preview: 'Ультрасовременность, храмы и уличная еда.',
    tags: ['Технологии', 'Храмы', 'Еда'],
    spots: [
      _SpotSeed(
        name: 'Сибуя Кроссинг',
        description: 'Самый знаменитый перекрёсток мира.',
        category: 'sight',
      ),
      _SpotSeed(
        name: 'Храм Асакуса',
        description: 'Красные ворота Каминаримон и пагода.',
        category: 'history',
      ),
      _SpotSeed(
        name: 'Императорский дворец',
        description: 'Сады и тихие аллеи в центре города.',
        category: 'park',
      ),
      _SpotSeed(
        name: 'Цукидзи',
        description: 'Рынок свежей рыбы и суши-завтраки.',
        category: 'food',
      ),
      _SpotSeed(
        name: 'Одайба',
        description: 'Современный район у моря с футуристическими зданиями.',
        category: 'view',
      ),
      _SpotSeed(
        name: 'Синдзюку Гёэн',
        description: 'Большой сад с чайными домиками.',
        category: 'park',
      ),
    ],
  ),
];
