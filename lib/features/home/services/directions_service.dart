import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class DirectionsService {
  final http.Client _client;
  final String _apiKey;

  DirectionsService({
    http.Client? client,
    String? apiKey,
  })  : _client = client ?? http.Client(),
        _apiKey = _pickKey(apiKey);

  Future<List<LatLng>> buildWalkingPath({
    required LatLng origin,
    required List<LatLng> stops,
  }) async {
    if (_apiKey.isEmpty) {
      debugPrint('❌ DirectionsService: API ключ пуст');
      throw Exception(
          'Directions API key is empty. Проверь MAPS_API_KEY/GOOGLE_MAPS_API_KEY');
    }
    if (stops.isEmpty) {
      debugPrint('⚠️ DirectionsService: Нет остановок для маршрута');
      return [];
    }

    debugPrint(
        '🚶 DirectionsService: Строим маршрут от (${origin.latitude}, ${origin.longitude}) через ${stops.length} остановок');

    final destination = stops.last;
    final waypointList =
        stops.length > 1 ? stops.sublist(0, stops.length - 1) : <LatLng>[];

    final params = <String, String>{
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'mode': 'walking',
      'alternatives': 'false',
      'language': 'ru',
      'region': 'ru',
      'key': _apiKey,
    };

    if (waypointList.isNotEmpty) {
      final waypoints =
          waypointList.map((p) => '${p.latitude},${p.longitude}').join('|');
      params['waypoints'] = 'optimize:true|$waypoints';
      debugPrint(
          '🚶 DirectionsService: Промежуточных точек: ${waypointList.length}');
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      params,
    );

    try {
      final response = await _client.get(uri);

      if (response.statusCode != 200) {
        debugPrint('❌ DirectionsService: HTTP ${response.statusCode}');
        throw Exception('Directions HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final status = decoded['status']?.toString();

      if (status != 'OK') {
        debugPrint('❌ DirectionsService: Status $status');
        final errorMessage = decoded['error_message']?.toString();
        if (errorMessage != null) {
          debugPrint('❌ DirectionsService: $errorMessage');
        }
        throw Exception('Directions status: $status');
      }

      final routes = decoded['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        debugPrint('⚠️ DirectionsService: Нет маршрутов в ответе');
        return [];
      }

      final route = routes[0] as Map<String, dynamic>;

      // Логируем информацию о маршруте
      final legs = route['legs'] as List<dynamic>?;
      if (legs != null) {
        var totalDistance = 0;
        var totalDuration = 0;
        for (final leg in legs) {
          final distance = leg['distance']?['value'] as int? ?? 0;
          final duration = leg['duration']?['value'] as int? ?? 0;
          totalDistance += distance;
          totalDuration += duration;
        }
        debugPrint(
            '🚶 DirectionsService: Общая дистанция: ${(totalDistance / 1000).toStringAsFixed(1)} км');
        debugPrint(
            '🚶 DirectionsService: Время в пути: ${(totalDuration / 60).toStringAsFixed(0)} мин');
      }

      final encoded = route['overview_polyline']?['points']?.toString();
      if (encoded == null || encoded.isEmpty) {
        debugPrint('⚠️ DirectionsService: Нет polyline в ответе');
        return [];
      }

      final polyline = _decodePolyline(encoded);
      debugPrint(
          '✅ DirectionsService: Маршрут построен, точек: ${polyline.length}');

      return polyline;
    } catch (e) {
      debugPrint('❌ DirectionsService: Ошибка $e');
      rethrow;
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int b;
      int shift = 0;
      int result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(
        LatLng(lat / 1e5, lng / 1e5),
      );
    }

    return points;
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
