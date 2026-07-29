import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/attraction_place.dart';

class GooglePlacesService {
  final http.Client _client;
  final String _apiKey;

  final Map<String, _CacheEntry<AttractionPlace?>> _findCache = {};
  final Map<String, Future<AttractionPlace?>> _ongoingFinds = {};
  static const Duration _findCacheTtl = Duration(days: 7);

  GooglePlacesService({
    http.Client? client,
    String? apiKey,
  })  : _client = client ?? http.Client(),
        _apiKey = _pickKey(apiKey);

  Future<AttractionPlace?> findPlaceByName({
    required String name,
    required LatLng nearLocation,
    String? cityHint,
    int radiusMeters = 30000,
  }) async {
    if (_apiKey.isEmpty) {
      debugPrint('❌ GooglePlacesService: API ключ пуст');
      return null;
    }

    final query =
        cityHint != null && cityHint.isNotEmpty ? '$name, $cityHint' : name;
    final requestKey = _buildFindKey(
      query: query,
      nearLocation: nearLocation,
      radiusMeters: radiusMeters,
    );

    _cleanFindCache();
    if (_findCache.containsKey(requestKey)) {
      return _findCache[requestKey]!.value;
    }
    if (_ongoingFinds.containsKey(requestKey)) {
      return _ongoingFinds[requestKey]!;
    }

    final future = () async {
      try {
        debugPrint(
            '🔍 GooglePlacesService: Ищем "$query" около (${nearLocation.latitude}, ${nearLocation.longitude})');

        final params = {
          'input': query,
          'inputtype': 'textquery',
          'locationbias':
              'circle:$radiusMeters@${nearLocation.latitude},${nearLocation.longitude}',
          'fields': 'place_id,name,geometry,formatted_address,types',
          'key': _apiKey,
          'language': 'ru',
        };

        final uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/place/findplacefromtext/json',
          params,
        );

        final response = await _client.get(uri);

        if (response.statusCode != 200) {
          debugPrint('❌ Places API HTTP ${response.statusCode}');
          return null;
        }

        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final status = decoded['status']?.toString();

        if (status != 'OK') {
          final errorMsg = decoded['error_message']?.toString();
          debugPrint(
              '⚠️ Places API status: $status для "$query"${errorMsg != null ? ' - $errorMsg' : ''}');
          return null;
        }

        final candidates = decoded['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) {
          debugPrint('⚠️ Не найдено мест для "$query"');
          return null;
        }

        final place = candidates[0] as Map<String, dynamic>;
        final geometry = place['geometry'] as Map<String, dynamic>?;
        final location = geometry?['location'] as Map<String, dynamic>?;

        if (location == null) {
          debugPrint('⚠️ Нет координат для "$query"');
          return null;
        }

        final lat = (location['lat'] as num).toDouble();
        final lng = (location['lng'] as num).toDouble();
        final placeId = place['place_id']?.toString() ?? '';
        final foundName = place['name']?.toString() ?? name;
        final address = place['formatted_address']?.toString() ?? '';

        debugPrint('✅ Найдено: "$foundName" по адресу: $address');
        debugPrint('   Координаты: ($lat, $lng)');

        return AttractionPlace(
          id: placeId.isNotEmpty ? placeId : const Uuid().v4(),
          googlePlaceId: placeId.isNotEmpty ? placeId : null,
          name: foundName,
          description: '',
          latitude: lat,
          longitude: lng,
          category: _inferCategory(place['types']),
          distanceKm: null,
          highlight: null,
        );
      } catch (e) {
        debugPrint('❌ GooglePlacesService error: $e');
        return null;
      }
    }();

    _ongoingFinds[requestKey] = future;
    try {
      final result = await future;
      _findCache[requestKey] = _CacheEntry(value: result);
      return result;
    } finally {
      _ongoingFinds.remove(requestKey);
    }
  }

  Future<List<AttractionPlace>> findNearbyAttractions({
    required LatLng location,
    int radius = 5000,
    String? type,
    int limit = 20,
  }) async {
    if (_apiKey.isEmpty) {
      debugPrint('❌ GooglePlacesService: API ключ пуст');
      return [];
    }

    try {
      debugPrint(
          '🔍 GooglePlacesService: Поиск рядом с (${location.latitude}, ${location.longitude})');

      final params = {
        'location': '${location.latitude},${location.longitude}',
        'radius': radius.toString(),
        'key': _apiKey,
        'language': 'ru',
      };

      if (type != null && type.isNotEmpty) {
        params['type'] = type;
      }

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/nearbysearch/json',
        params,
      );

      final response = await _client.get(uri);

      if (response.statusCode != 200) {
        debugPrint('❌ Places API HTTP ${response.statusCode}');
        return [];
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final status = decoded['status']?.toString();

      if (status != 'OK' && status != 'ZERO_RESULTS') {
        debugPrint('⚠️ Places API status: $status');
        return [];
      }

      final results = decoded['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) {
        debugPrint('⚠️ Ничего не найдено рядом');
        return [];
      }

      final places = <AttractionPlace>[];
      for (final result in results.take(limit)) {
        final place = result as Map<String, dynamic>;
        final geometry = place['geometry'] as Map<String, dynamic>?;
        final locationData = geometry?['location'] as Map<String, dynamic>?;

        if (locationData == null) continue;

        final lat = (locationData['lat'] as num).toDouble();
        final lng = (locationData['lng'] as num).toDouble();
        final name = place['name']?.toString() ?? '';
        final placeId = place['place_id']?.toString() ?? '';

        places.add(AttractionPlace(
          id: placeId,
          name: name,
          description: '',
          latitude: lat,
          longitude: lng,
          category: _inferCategory(place['types']),
          distanceKm: null,
          highlight: null,
        ));
      }

      debugPrint('✅ Найдено ${places.length} мест');
      return places;
    } catch (e) {
      debugPrint('❌ GooglePlacesService error: $e');
      return [];
    }
  }

  String _inferCategory(dynamic types) {
    if (types == null) return 'sight';
    final typeList = types is List ? types : [types];

    for (final type in typeList) {
      final t = type.toString().toLowerCase();
      if (t.contains('museum')) {
        return 'museum';
      }
      if (t.contains('park')) {
        return 'park';
      }
      if (t.contains('cafe') || t.contains('coffee')) {
        return 'coffee';
      }
      if (t.contains('restaurant') || t.contains('food')) {
        return 'food';
      }
      if (t.contains('point_of_interest') || t.contains('tourist')) {
        return 'sight';
      }
    }

    return 'sight';
  }

  static String _pickKey(String? provided) {
    final candidates = <String?>[
      provided,
      dotenv.env['GOOGLE_MAPS_API_KEY'],
      dotenv.env['MAPS_API_KEY'],
      const String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: ''),
      const String.fromEnvironment('MAPS_API_KEY', defaultValue: ''),
      'AIzaSyD9zmdqkGdwP5ZZDM2Ha6eUbCogkSAdhhI',
    ];
    for (final value in candidates) {
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }
}

class _CacheEntry<T> {
  final T value;
  final DateTime createdAt;

  _CacheEntry({
    required this.value,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

extension on GooglePlacesService {
  String _buildFindKey({
    required String query,
    required LatLng nearLocation,
    required int radiusMeters,
  }) {
    final q = query.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    final lat = _roundCoord(nearLocation.latitude);
    final lng = _roundCoord(nearLocation.longitude);
    return 'find:$q|$lat,$lng|r=$radiusMeters';
  }

  String _roundCoord(double v) => v.toStringAsFixed(4);

  void _cleanFindCache() {
    if (_findCache.isEmpty) return;
    final now = DateTime.now();
    final expired = _findCache.entries
        .where(
          (e) =>
              now.difference(e.value.createdAt) >
              GooglePlacesService._findCacheTtl,
        )
        .map((e) => e.key)
        .toList(growable: false);
    for (final k in expired) {
      _findCache.remove(k);
    }
  }
}











