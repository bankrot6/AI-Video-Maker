import 'dart:math' as math;

import '../models/attraction_place.dart';

class RouteStopOrderingService {
  const RouteStopOrderingService();

  List<AttractionPlace> orderStops({
    required List<AttractionPlace> stops,
    required double originLat,
    required double originLng,
  }) {
    if (stops.length < 3) return stops;

    final withCoords = <AttractionPlace>[];
    final withoutCoords = <AttractionPlace>[];

    for (final s in stops) {
      if (_hasValidCoordinates(s)) {
        withCoords.add(s);
      } else {
        withoutCoords.add(s);
      }
    }

    if (withCoords.length < 3) return stops;

    final origin = _Point(originLat, originLng);

    final remaining = List<AttractionPlace>.from(withCoords);
    final ordered = <AttractionPlace>[];

    remaining.sort(
      (a, b) => _distanceKm(origin, _Point(a.latitude, a.longitude))
          .compareTo(_distanceKm(origin, _Point(b.latitude, b.longitude))),
    );

    ordered.add(remaining.removeAt(0));

    while (remaining.isNotEmpty) {
      final last = ordered.last;
      final lastPoint = _Point(last.latitude, last.longitude);

      int bestIndex = 0;
      double bestDistance = double.infinity;

      for (int i = 0; i < remaining.length; i++) {
        final candidate = remaining[i];
        final d = _distanceKm(
            lastPoint, _Point(candidate.latitude, candidate.longitude));
        if (d < bestDistance) {
          bestDistance = d;
          bestIndex = i;
        }
      }

      ordered.add(remaining.removeAt(bestIndex));
    }

    if (withoutCoords.isEmpty) return ordered;

    return [...ordered, ...withoutCoords];
  }

  bool _hasValidCoordinates(AttractionPlace place) {
    final latOk = place.latitude.abs() <= 90;
    final lngOk = place.longitude.abs() <= 180;
    final notZero = place.latitude != 0 || place.longitude != 0;
    return latOk && lngOk && notZero;
  }

  double _distanceKm(_Point a, _Point b) {
    const r = 6371.0;
    final dLat = _degToRad(b.lat - a.lat);
    final dLon = _degToRad(b.lng - a.lng);

    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);

    final aa = sinDLat * sinDLat +
        math.cos(_degToRad(a.lat)) *
            math.cos(_degToRad(b.lat)) *
            sinDLon *
            sinDLon;
    final c = 2 * math.atan2(math.sqrt(aa), math.sqrt(1 - aa));
    return r * c;
  }

  double _degToRad(double deg) => deg * 0.017453292519943295;
}

class _Point {
  final double lat;
  final double lng;

  const _Point(this.lat, this.lng);
}











