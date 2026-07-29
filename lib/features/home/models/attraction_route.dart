import 'package:uuid/uuid.dart';

import 'attraction_place.dart';

class AttractionRoute {
  final String id;
  final String title;
  final String summary;
  final String theme;
  final double? estimatedDistanceKm;
  final int? estimatedDurationMin;
  final List<AttractionPlace> stops;

  const AttractionRoute({
    required this.id,
    required this.title,
    required this.summary,
    required this.theme,
    required this.stops,
    this.estimatedDistanceKm,
    this.estimatedDurationMin,
  });

  factory AttractionRoute.fromJson(Map<String, dynamic> json) {
    final rawStops = json['stops'] ?? json['places'] ?? [];
    final stops = rawStops is List
        ? rawStops
            .map((e) => AttractionPlace.fromJson(e as Map<String, dynamic>))
            .toList()
        : <AttractionPlace>[];

    return AttractionRoute(
      id: json['id']?.toString() ??
          json['title']?.toString() ??
          const Uuid().v4(),
      title: (json['title'] ?? json['name'] ?? 'Маршрут').toString(),
      summary: (json['summary'] ?? json['description'] ?? '').toString(),
      theme: (json['theme'] ?? 'classic').toString(),
      estimatedDistanceKm: _toDouble(
            json['estimated_distance_km'],
          ) ??
          _toDouble(json['distance_km']),
      estimatedDurationMin: _toInt(
            json['estimated_duration_min'],
          ) ??
          _toInt(json['duration_min']),
      stops: stops,
    );
  }

  AttractionRoute copyWith({
    String? id,
    String? title,
    String? summary,
    String? theme,
    double? estimatedDistanceKm,
    int? estimatedDurationMin,
    List<AttractionPlace>? stops,
  }) {
    return AttractionRoute(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      theme: theme ?? this.theme,
      estimatedDistanceKm: estimatedDistanceKm ?? this.estimatedDistanceKm,
      estimatedDurationMin: estimatedDurationMin ?? this.estimatedDurationMin,
      stops: stops ?? this.stops,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      'theme': theme,
      'estimated_distance_km': estimatedDistanceKm,
      'estimated_duration_min': estimatedDurationMin,
      'stops': stops.map((e) => e.toJson()).toList(),
    };
  }
}

















