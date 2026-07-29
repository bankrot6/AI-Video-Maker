import 'package:uuid/uuid.dart';

class AttractionPlace {
  final String id;
  final String? googlePlaceId;
  final String name;
  final String description;
  final double latitude;
  final double longitude;
  final String category;
  final double? distanceKm;
  final String? highlight;

  const AttractionPlace({
    required this.id,
    this.googlePlaceId,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.category,
    this.distanceKm,
    this.highlight,
  });

  factory AttractionPlace.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString() ?? '';
    final googlePlaceId = json['google_place_id']?.toString() ??
        json['place_id']?.toString() ??
        (_looksLikeGooglePlaceId(rawId) ? rawId : null);

    return AttractionPlace(
      id: rawId.isNotEmpty
          ? rawId
          : (json['name']?.toString() ?? _generateId()),
      googlePlaceId: googlePlaceId,
      name: (json['name'] ?? 'Без названия').toString(),
      description: (json['description'] ?? '').toString(),
      latitude: _toDouble(json['latitude']) ?? _toDouble(json['lat']) ?? 0,
      longitude: _toDouble(json['longitude']) ?? _toDouble(json['lng']) ?? 0,
      category: (json['category'] ?? 'sight').toString(),
      distanceKm: _toDouble(json['distance_km']),
      highlight: json['highlight']?.toString(),
    );
  }

  AttractionPlace copyWith({
    String? id,
    String? googlePlaceId,
    String? name,
    String? description,
    double? latitude,
    double? longitude,
    String? category,
    double? distanceKm,
    String? highlight,
  }) {
    return AttractionPlace(
      id: id ?? this.id,
      googlePlaceId: googlePlaceId ?? this.googlePlaceId,
      name: name ?? this.name,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      category: category ?? this.category,
      distanceKm: distanceKm ?? this.distanceKm,
      highlight: highlight ?? this.highlight,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static String _generateId() => const Uuid().v4();

  static bool _looksLikeGooglePlaceId(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    // Частый префикс place_id у Google: "ChI..."
    return v.startsWith('ChI') && v.length > 10;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'google_place_id': googlePlaceId,
      'name': name,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'category': category,
      'distance_km': distanceKm,
      'highlight': highlight,
    };
  }
}

extension AttractionPlaceCategoryLocalization on AttractionPlace {
  String get categoryRu => localizeAttractionCategoryRu(category);
}

String localizeAttractionCategoryRu(String raw) {
  final key = raw.toLowerCase().trim();
  switch (key) {
    case 'museum':
      return 'Музей';
    case 'sight':
      return 'Объект';
    case 'park':
      return 'Парк';
    case 'view':
    case 'viewpoint':
      return 'Видовая точка';
    case 'walk':
      return 'Прогулка';
    case 'history':
    case 'historical':
      return 'История';
    case 'food':
    case 'restaurant':
      return 'Еда';
    case 'coffee':
    case 'cafe':
      return 'Кофе';
    case 'shopping':
      return 'Шопинг';
    case 'entertainment':
      return 'Развлечения';
    default:
      return raw.trim().isEmpty ? '' : raw;
  }
}











