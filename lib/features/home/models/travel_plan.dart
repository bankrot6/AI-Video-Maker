import 'package:uuid/uuid.dart';

import 'attraction_place.dart';
import 'attraction_route.dart';

enum TravelPlanStatus {
  loading,
  partial,
  completed,
  error,
}

class TravelPlan {
  final String id;
  final String placeLabel;
  final String query;
  final int stayDays;
  final List<String> interests;
  final double latitude;
  final double longitude;
  final List<AttractionRoute> routes;
  final List<AttractionPlace> attractions;
  final DateTime createdAt;
  final TravelPlanStatus status;
  final String? errorMessage;

  TravelPlan({
    required this.id,
    required this.placeLabel,
    required this.query,
    required this.stayDays,
    required this.interests,
    required this.latitude,
    required this.longitude,
    required this.routes,
    required this.attractions,
    required this.createdAt,
    this.status = TravelPlanStatus.completed,
    this.errorMessage,
  });

  factory TravelPlan.create({
    required String placeLabel,
    required String query,
    required int stayDays,
    required List<String> interests,
    required double latitude,
    required double longitude,
    required List<AttractionRoute> routes,
    required List<AttractionPlace> attractions,
    TravelPlanStatus status = TravelPlanStatus.completed,
    String? errorMessage,
  }) {
    return TravelPlan(
      id: const Uuid().v4(),
      placeLabel: placeLabel,
      query: query,
      stayDays: stayDays,
      interests: List.unmodifiable(interests),
      latitude: latitude,
      longitude: longitude,
      routes: List.unmodifiable(routes),
      attractions: List.unmodifiable(attractions),
      createdAt: DateTime.now(),
      status: status,
      errorMessage: errorMessage,
    );
  }

  TravelPlan copyWith({
    String? id,
    String? placeLabel,
    String? query,
    int? stayDays,
    List<String>? interests,
    double? latitude,
    double? longitude,
    List<AttractionRoute>? routes,
    List<AttractionPlace>? attractions,
    DateTime? createdAt,
    TravelPlanStatus? status,
    String? errorMessage,
  }) {
    return TravelPlan(
      id: id ?? this.id,
      placeLabel: placeLabel ?? this.placeLabel,
      query: query ?? this.query,
      stayDays: stayDays ?? this.stayDays,
      interests: interests ?? this.interests,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      routes: routes ?? this.routes,
      attractions: attractions ?? this.attractions,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      errorMessage: errorMessage,
    );
  }

  bool get isLoading => status == TravelPlanStatus.loading;
  bool get isPartial => status == TravelPlanStatus.partial;
  bool get isCompleted => status == TravelPlanStatus.completed;
  bool get hasError => status == TravelPlanStatus.error;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'placeLabel': placeLabel,
      'query': query,
      'stayDays': stayDays,
      'interests': interests,
      'latitude': latitude,
      'longitude': longitude,
      'routes': routes.map((e) => e.toJson()).toList(),
      'attractions': attractions.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'status': status.name,
      'errorMessage': errorMessage,
    };
  }

  factory TravelPlan.fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString();
    final status = TravelPlanStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => TravelPlanStatus.completed,
    );
    return TravelPlan(
      id: json['id']?.toString() ?? const Uuid().v4(),
      placeLabel: (json['placeLabel'] ?? '').toString(),
      query: (json['query'] ?? '').toString(),
      stayDays: json['stayDays'] is int
          ? json['stayDays'] as int
          : int.tryParse(json['stayDays']?.toString() ?? '0') ?? 0,
      interests: (json['interests'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      latitude: json['latitude'] is num
          ? (json['latitude'] as num).toDouble()
          : double.tryParse(json['latitude']?.toString() ?? '') ?? 0,
      longitude: json['longitude'] is num
          ? (json['longitude'] as num).toDouble()
          : double.tryParse(json['longitude']?.toString() ?? '') ?? 0,
      routes: (json['routes'] as List<dynamic>?)
              ?.map((e) => AttractionRoute.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      attractions: (json['attractions'] as List<dynamic>?)
              ?.map((e) => AttractionPlace.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      status: status,
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}
