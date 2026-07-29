import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';

import '../../../services/providers.dart' as services;
import 'attraction_cache_service.dart';

@immutable
class CityImageRequest {
  final String cacheKey;
  final String label;
  final String? countryHint;
  final double? latitude;
  final double? longitude;

  const CityImageRequest({
    required this.cacheKey,
    required this.label,
    this.countryHint,
    this.latitude,
    this.longitude,
  });
}

final cityImageProvider =
    FutureProvider.family<MemoryImage?, CityImageRequest>((ref, request) async {
  final service = ref.read(cityImageServiceProvider);
  return service.loadCityImage(
    cacheKey: request.cacheKey,
    cityLabel: request.label,
    countryHint: request.countryHint,
    latitude: request.latitude,
    longitude: request.longitude,
  );
});

final cityImageMemoryCacheProvider =
    StateNotifierProvider<CityImageMemoryCache, Map<String, MemoryImage>>(
        (ref) {
  return CityImageMemoryCache();
});

class CityImageMemoryCache extends StateNotifier<Map<String, MemoryImage>> {
  CityImageMemoryCache() : super(const {});

  void put(String key, MemoryImage image) {
    if (state[key] == image) return;
    state = {...state, key: image};
  }
}

final cityImageServiceProvider = Provider<CityImageService>((ref) {
  return CityImageService(ref);
});

final _cityImageCacheProvider = Provider<AttractionCacheService>((ref) {
  return AttractionCacheService();
});

String cityImageCacheKey(String rawKey) =>
    'home_city_${rawKey.toLowerCase().trim()}';

class CityImageService {
  CityImageService(this._ref);

  final Ref _ref;
  final Map<String, Future<MemoryImage?>> _inFlight = {};

  Future<MemoryImage?> loadCityImage({
    required String cacheKey,
    required String cityLabel,
    String? countryHint,
    double? latitude,
    double? longitude,
  }) async {
    return _getOrFetch(
      cacheKey: cacheKey,
      cityLabel: cityLabel,
      countryHint: countryHint,
      latitude: latitude,
      longitude: longitude,
      resolveCountry: true,
      alsoCacheByLabel: false,
    );
  }

  Future<MemoryImage?> prefetchCityImage({
    required String cityLabel,
    String? cacheKey,
    String? countryHint,
  }) async {
    final trimmedLabel = cityLabel.trim();
    if (trimmedLabel.isEmpty) return null;
    final key = (cacheKey ?? trimmedLabel).trim();
    if (key.isEmpty) return null;
    return _getOrFetch(
      cacheKey: key,
      cityLabel: trimmedLabel,
      countryHint: countryHint,
      resolveCountry: true,
      alsoCacheByLabel: true,
    );
  }

  Future<MemoryImage?> _getOrFetch({
    required String cacheKey,
    required String cityLabel,
    String? countryHint,
    double? latitude,
    double? longitude,
    required bool resolveCountry,
    required bool alsoCacheByLabel,
  }) {
    final normalizedCacheKey = cityImageCacheKey(cacheKey);
    final memoryCached =
        _ref.read(cityImageMemoryCacheProvider)[normalizedCacheKey];
    if (memoryCached != null) {
      return Future.value(memoryCached);
    }

    final inFlight = _inFlight[normalizedCacheKey];
    if (inFlight != null) return inFlight;

    final task = _getOrFetchInternal(
      normalizedCacheKey: normalizedCacheKey,
      cityLabel: cityLabel,
      countryHint: countryHint,
      latitude: latitude,
      longitude: longitude,
      resolveCountry: resolveCountry,
      alsoCacheByLabel: alsoCacheByLabel,
    );
    _inFlight[normalizedCacheKey] = task;
    return task.whenComplete(() => _inFlight.remove(normalizedCacheKey));
  }

  Future<MemoryImage?> _getOrFetchInternal({
    required String normalizedCacheKey,
    required String cityLabel,
    String? countryHint,
    double? latitude,
    double? longitude,
    required bool resolveCountry,
    required bool alsoCacheByLabel,
  }) async {
    final cacheService = _ref.read(_cityImageCacheProvider);
    File? cached = await cacheService.getCachedImage(normalizedCacheKey);

    final normalizedLabel = _normalizeLabel(cityLabel);
    final inputLabelKey = normalizedLabel.isEmpty
        ? null
        : cityImageCacheKey(normalizedLabel);

    if (cached == null &&
        inputLabelKey != null &&
        inputLabelKey != normalizedCacheKey) {
      cached = await cacheService.getCachedImage(inputLabelKey);
      if (cached != null) {
        await cacheService.cacheAttractionImage(normalizedCacheKey, cached);
      }
    }

    if (cached != null) {
      final memoryImage = await _loadMemoryImage(cached);
      if (memoryImage != null) {
        _ref
            .read(cityImageMemoryCacheProvider.notifier)
            .put(normalizedCacheKey, memoryImage);
      }
      return memoryImage;
    }

    if (normalizedLabel.isEmpty) return null;

    final queryParts = await _resolveQueryParts(
      normalizedLabel,
      countryHint: countryHint,
      latitude: latitude,
      longitude: longitude,
      resolveCountry: resolveCountry,
    );

    final queries = _buildQueries(queryParts);
    if (queries.isEmpty) return null;

    final imageService = _ref.read(services.imageSearchServiceProvider);
    File? imageFile;
    for (final query in queries) {
      imageFile = await imageService.findImage(query);
      if (imageFile != null) break;
    }

    if (imageFile == null) return null;

    await cacheService.cacheAttractionImage(normalizedCacheKey, imageFile);

    final resolvedLabelKey =
        cityImageCacheKey(queryParts.resolvedLabel.toLowerCase());

    if (alsoCacheByLabel &&
        resolvedLabelKey != normalizedCacheKey &&
        resolvedLabelKey != inputLabelKey) {
      await cacheService.cacheAttractionImage(resolvedLabelKey, imageFile);
    }

    if (alsoCacheByLabel &&
        inputLabelKey != null &&
        inputLabelKey != normalizedCacheKey) {
      await cacheService.cacheAttractionImage(inputLabelKey, imageFile);
    }

    final memoryImage = await _loadMemoryImage(imageFile);
    if (memoryImage != null) {
      final notifier = _ref.read(cityImageMemoryCacheProvider.notifier);
      notifier.put(normalizedCacheKey, memoryImage);
      if (alsoCacheByLabel &&
          resolvedLabelKey != normalizedCacheKey &&
          resolvedLabelKey != inputLabelKey) {
        notifier.put(resolvedLabelKey, memoryImage);
      }
      if (alsoCacheByLabel &&
          inputLabelKey != null &&
          inputLabelKey != normalizedCacheKey) {
        notifier.put(inputLabelKey, memoryImage);
      }
    }

    return memoryImage;
  }

  Future<_CityImageQueryParts> _resolveQueryParts(
    String label, {
    String? countryHint,
    double? latitude,
    double? longitude,
    required bool resolveCountry,
  }) async {
    final normalizedLabel = _normalizeLabel(label);
    final parsed = _CityImageQueryParts.fromLabel(
      normalizedLabel,
      countryHint: countryHint,
    );

    if (!resolveCountry || parsed.country != null) {
      return parsed;
    }

    try {
      final hasCoords = _hasValidCoordinates(latitude, longitude);
      double resolvedLat = latitude ?? 0;
      double resolvedLng = longitude ?? 0;
      if (!hasCoords) {
        final locations = await locationFromAddress(parsed.city);
        if (locations.isEmpty) return parsed;
        final target = locations.first;
        resolvedLat = target.latitude;
        resolvedLng = target.longitude;
      }

      final placemarks = await placemarkFromCoordinates(
        resolvedLat,
        resolvedLng,
      );
      if (placemarks.isEmpty) return parsed;
      final place = placemarks.first;
      final resolvedCity = (place.locality ?? parsed.city).trim();
      final resolvedRegion = place.administrativeArea?.trim();
      final resolvedCountry = place.country?.trim();
      return parsed.copyWith(
        city: resolvedCity.isEmpty ? parsed.city : resolvedCity,
        region: resolvedRegion,
        country: resolvedCountry ?? countryHint,
      );
    } catch (_) {
      return parsed;
    }
  }

  List<String> _buildQueries(_CityImageQueryParts parts) {
    final city = parts.city;
    if (city.isEmpty) return const [];

    final country = parts.country;
    final region = parts.region;

    final locationWords = [
      city,
      if (region != null && region.isNotEmpty) region,
      if (country != null && country.isNotEmpty) country,
    ].join(' ');

    final locationLabel = [
      city,
      if (region != null && region.isNotEmpty) region,
      if (country != null && country.isNotEmpty) country,
    ].join(', ');

    return _dedupeQueries([
      if (country != null && country.isNotEmpty)
        '"$city" $country skyline panorama',
      if (country != null && country.isNotEmpty)
        '"$city" $country cityscape',
      if (locationLabel.isNotEmpty && locationLabel != city)
        '"$locationLabel" skyline',
      '$locationWords skyline',
      '$locationWords city skyline',
      '$locationWords cityscape',
      '$locationWords панорама',
      '$locationWords город панорама skyline',
      '$locationWords архитектура панорама',
      '$locationWords landmarks panorama',
      '$city skyline',
      '$city панорама',
    ]);
  }

  List<String> _dedupeQueries(List<String> raw) {
    final result = <String>[];
    final seen = <String>{};
    for (final entry in raw) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  Future<MemoryImage?> _loadMemoryImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  String _normalizeLabel(String label) =>
      label.replaceAll(RegExp(r'\s+'), ' ').trim();

  bool _hasValidCoordinates(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return false;
    if (latitude == 0 && longitude == 0) return false;
    return latitude.abs() <= 90 && longitude.abs() <= 180;
  }
}

class _CityImageQueryParts {
  final String city;
  final String? region;
  final String? country;

  const _CityImageQueryParts({
    required this.city,
    this.region,
    this.country,
  });

  factory _CityImageQueryParts.fromLabel(
    String label, {
    String? countryHint,
  }) {
    final parts = label
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final city = parts.isNotEmpty ? parts.first : label;
    String? region;
    String? country;

    if (parts.length >= 2) {
      country = parts.last;
      if (parts.length >= 3) {
        region = parts.sublist(1, parts.length - 1).join(', ');
      }
    }

    country ??= countryHint?.trim();
    if (country != null && country.isEmpty) {
      country = null;
    }

    return _CityImageQueryParts(
      city: city,
      region: region,
      country: country,
    );
  }

  _CityImageQueryParts copyWith({
    String? city,
    String? region,
    String? country,
  }) {
    return _CityImageQueryParts(
      city: city ?? this.city,
      region: region ?? this.region,
      country: country ?? this.country,
    );
  }

  String get resolvedLabel {
    final parts = <String>[
      city,
      if (region != null && region!.isNotEmpty) region!,
      if (country != null && country!.isNotEmpty) country!,
    ];
    return parts.join(', ').trim();
  }
}
