import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'models/attraction_place.dart';
import 'models/attraction_route.dart';
import 'services/attraction_ai_service.dart';
import 'services/directions_service.dart';
import 'services/google_places_service.dart';

final attractionAiServiceProvider = Provider<AttractionAiService>((ref) {
  return AttractionAiService();
});

final directionsServiceProvider = Provider<DirectionsService>((ref) {
  return DirectionsService();
});

final googlePlacesServiceProvider = Provider<GooglePlacesService>((ref) {
  return GooglePlacesService();
});

final userLocationProvider = FutureProvider<Position>((ref) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Службы геолокации отключены');
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied) {
    throw Exception('Доступ к геолокации запрещён');
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception('Разрешения на геолокацию навсегда запрещены');
  }

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
    ),
  );
});

final attractionsProvider = FutureProvider.autoDispose
    .family<List<AttractionPlace>, Position>((ref, position) async {
  final service = ref.read(attractionAiServiceProvider);
  final placesService = ref.read(googlePlacesServiceProvider);
  final city = await _resolveCity(position);

  final raw = await service.fetchAttractions(
    latitude: position.latitude,
    longitude: position.longitude,
    cityHint: city,
  );

  final enriched = <AttractionPlace>[];
  for (final place in raw) {
    final realPlace = await placesService.findPlaceByName(
      name: place.name,
      nearLocation: LatLng(position.latitude, position.longitude),
      cityHint: city,
    );

    if (realPlace != null) {
      enriched.add(realPlace.copyWith(
        description: place.description,
        category: place.category,
        highlight: place.highlight,
      ));
    } else {
      enriched.add(place);
    }
  }

  return enriched;
});

final attractionRoutesProvider = FutureProvider.autoDispose
    .family<List<AttractionRoute>, Position>((ref, position) async {
  final service = ref.read(attractionAiServiceProvider);
  final placesService = ref.read(googlePlacesServiceProvider);
  final city = await _resolveCity(position);

  final routes = await service.fetchRoutes(
    latitude: position.latitude,
    longitude: position.longitude,
    cityHint: city,
  );

  final enrichedRoutes = <AttractionRoute>[];
  for (final route in routes) {
    final updatedStops = <AttractionPlace>[];
    for (final stop in route.stops) {
      final realPlace = await placesService.findPlaceByName(
        name: stop.name,
        nearLocation: LatLng(position.latitude, position.longitude),
        cityHint: city,
      );

      if (realPlace != null) {
        updatedStops.add(realPlace.copyWith(
          description: stop.description,
          category: stop.category,
          highlight: stop.highlight,
        ));
      } else {
        updatedStops.add(stop);
      }
    }
    enrichedRoutes.add(route.copyWith(stops: updatedStops));
  }

  return enrichedRoutes;
});

Future<String?> _resolveCity(Position position) async {
  try {
    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    if (placemarks.isNotEmpty) {
      final city =
          placemarks.first.locality ?? placemarks.first.administrativeArea;
      if (city != null && city.isNotEmpty) {
        return city;
      }
    }
  } catch (_) {
    // Игнорируем ошибки геокодинга
  }
  return null;
}
