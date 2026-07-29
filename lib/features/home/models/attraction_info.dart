import 'package:equatable/equatable.dart';

class AttractionInfo extends Equatable {
  final String name;

  final String history;

  final String historicalPeriods;

  final String architecturalDetails;

  final String culturalSignificance;

  final String interestingFacts;

  final String legendsAndStories;

  final String famousPeople;

  final String importantEvents;

  final String evolution;

  final String currentState;

  final String practicalInfo;

  final String photographyTips;

  final String bestViewpoints;

  final String nearbyAttractions;

  final String recommendation;

  final String? imageUrl;

  final String? error;

  const AttractionInfo({
    required this.name,
    required this.history,
    required this.historicalPeriods,
    required this.architecturalDetails,
    required this.culturalSignificance,
    required this.interestingFacts,
    required this.legendsAndStories,
    required this.famousPeople,
    required this.importantEvents,
    required this.evolution,
    required this.currentState,
    required this.practicalInfo,
    required this.photographyTips,
    required this.bestViewpoints,
    required this.nearbyAttractions,
    required this.recommendation,
    this.imageUrl,
    this.error,
  });

  factory AttractionInfo.empty() {
    return const AttractionInfo(
      name: '',
      history: '',
      historicalPeriods: '',
      architecturalDetails: '',
      culturalSignificance: '',
      interestingFacts: '',
      legendsAndStories: '',
      famousPeople: '',
      importantEvents: '',
      evolution: '',
      currentState: '',
      practicalInfo: '',
      photographyTips: '',
      bestViewpoints: '',
      nearbyAttractions: '',
      recommendation: '',
      imageUrl: null,
      error: null,
    );
  }

  AttractionInfo copyWith({
    String? name,
    String? history,
    String? historicalPeriods,
    String? architecturalDetails,
    String? culturalSignificance,
    String? interestingFacts,
    String? legendsAndStories,
    String? famousPeople,
    String? importantEvents,
    String? evolution,
    String? currentState,
    String? practicalInfo,
    String? photographyTips,
    String? bestViewpoints,
    String? nearbyAttractions,
    String? recommendation,
    String? imageUrl,
    String? error,
  }) {
    return AttractionInfo(
      name: name ?? this.name,
      history: history ?? this.history,
      historicalPeriods: historicalPeriods ?? this.historicalPeriods,
      architecturalDetails: architecturalDetails ?? this.architecturalDetails,
      culturalSignificance: culturalSignificance ?? this.culturalSignificance,
      interestingFacts: interestingFacts ?? this.interestingFacts,
      legendsAndStories: legendsAndStories ?? this.legendsAndStories,
      famousPeople: famousPeople ?? this.famousPeople,
      importantEvents: importantEvents ?? this.importantEvents,
      evolution: evolution ?? this.evolution,
      currentState: currentState ?? this.currentState,
      practicalInfo: practicalInfo ?? this.practicalInfo,
      photographyTips: photographyTips ?? this.photographyTips,
      bestViewpoints: bestViewpoints ?? this.bestViewpoints,
      nearbyAttractions: nearbyAttractions ?? this.nearbyAttractions,
      recommendation: recommendation ?? this.recommendation,
      imageUrl: imageUrl ?? this.imageUrl,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
        name,
        history,
        historicalPeriods,
        architecturalDetails,
        culturalSignificance,
        interestingFacts,
        legendsAndStories,
        famousPeople,
        importantEvents,
        evolution,
        currentState,
        practicalInfo,
        photographyTips,
        bestViewpoints,
        nearbyAttractions,
        recommendation,
        imageUrl,
        error,
      ];

  factory AttractionInfo.fromJson(Map<String, dynamic> json) {
    return AttractionInfo(
      name: json['name'] as String? ?? '',
      history: json['history'] as String? ?? '',
      historicalPeriods: json['historicalPeriods'] as String? ?? '',
      architecturalDetails: json['architecturalDetails'] as String? ?? '',
      culturalSignificance: json['culturalSignificance'] as String? ?? '',
      interestingFacts: json['interestingFacts'] as String? ?? '',
      legendsAndStories: json['legendsAndStories'] as String? ?? '',
      famousPeople: json['famousPeople'] as String? ?? '',
      importantEvents: json['importantEvents'] as String? ?? '',
      evolution: json['evolution'] as String? ?? '',
      currentState: json['currentState'] as String? ?? '',
      practicalInfo: json['practicalInfo'] as String? ?? '',
      photographyTips: json['photographyTips'] as String? ?? '',
      bestViewpoints: json['bestViewpoints'] as String? ?? '',
      nearbyAttractions: json['nearbyAttractions'] as String? ?? '',
      recommendation: json['recommendation'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'history': history,
      'historicalPeriods': historicalPeriods,
      'architecturalDetails': architecturalDetails,
      'culturalSignificance': culturalSignificance,
      'interestingFacts': interestingFacts,
      'legendsAndStories': legendsAndStories,
      'famousPeople': famousPeople,
      'importantEvents': importantEvents,
      'evolution': evolution,
      'currentState': currentState,
      'practicalInfo': practicalInfo,
      'photographyTips': photographyTips,
      'bestViewpoints': bestViewpoints,
      'nearbyAttractions': nearbyAttractions,
      'recommendation': recommendation,
      'imageUrl': imageUrl,
      'error': error,
    };
  }
}
