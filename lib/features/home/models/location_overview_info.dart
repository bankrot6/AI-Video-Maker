import 'package:equatable/equatable.dart';

class LocationOverviewInfo extends Equatable {
  final String name;
  final String generalInfo;
  final String history;
  final String culture;
  final String interestingFacts;
  final String practicalInfo;
  final String? error;

  const LocationOverviewInfo({
    required this.name,
    required this.generalInfo,
    required this.history,
    required this.culture,
    required this.interestingFacts,
    required this.practicalInfo,
    this.error,
  });

  factory LocationOverviewInfo.empty() {
    return const LocationOverviewInfo(
      name: '',
      generalInfo: '',
      history: '',
      culture: '',
      interestingFacts: '',
      practicalInfo: '',
      error: null,
    );
  }

  LocationOverviewInfo copyWith({
    String? name,
    String? generalInfo,
    String? history,
    String? culture,
    String? interestingFacts,
    String? practicalInfo,
    String? error,
  }) {
    return LocationOverviewInfo(
      name: name ?? this.name,
      generalInfo: generalInfo ?? this.generalInfo,
      history: history ?? this.history,
      culture: culture ?? this.culture,
      interestingFacts: interestingFacts ?? this.interestingFacts,
      practicalInfo: practicalInfo ?? this.practicalInfo,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
        name,
        generalInfo,
        history,
        culture,
        interestingFacts,
        practicalInfo,
        error,
      ];

  factory LocationOverviewInfo.fromJson(Map<String, dynamic> json) {
    return LocationOverviewInfo(
      name: json['name'] as String? ?? '',
      generalInfo: json['generalInfo'] as String? ?? '',
      history: json['history'] as String? ?? '',
      culture: json['culture'] as String? ?? '',
      interestingFacts: json['interestingFacts'] as String? ?? '',
      practicalInfo: json['practicalInfo'] as String? ?? '',
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'generalInfo': generalInfo,
      'history': history,
      'culture': culture,
      'interestingFacts': interestingFacts,
      'practicalInfo': practicalInfo,
      'error': error,
    };
  }
}












