import 'package:equatable/equatable.dart';

class FriendPersona extends Equatable {
  final String about;
  final String occupation;
  final String goodHabits;
  final String badHabits;
  final String hobbies;
  final String bestMoments;
  final String characterTraits;
  final String sharedSecrets;
  final String relationshipNotes;

  const FriendPersona({
    this.about = '',
    this.occupation = '',
    this.goodHabits = '',
    this.badHabits = '',
    this.hobbies = '',
    this.bestMoments = '',
    this.characterTraits = '',
    this.sharedSecrets = '',
    this.relationshipNotes = '',
  });

  FriendPersona copyWith({
    String? about,
    String? occupation,
    String? goodHabits,
    String? badHabits,
    String? hobbies,
    String? bestMoments,
    String? characterTraits,
    String? sharedSecrets,
    String? relationshipNotes,
  }) {
    return FriendPersona(
      about: about ?? this.about,
      occupation: occupation ?? this.occupation,
      goodHabits: goodHabits ?? this.goodHabits,
      badHabits: badHabits ?? this.badHabits,
      hobbies: hobbies ?? this.hobbies,
      bestMoments: bestMoments ?? this.bestMoments,
      characterTraits: characterTraits ?? this.characterTraits,
      sharedSecrets: sharedSecrets ?? this.sharedSecrets,
      relationshipNotes: relationshipNotes ?? this.relationshipNotes,
    );
  }

  factory FriendPersona.fromJson(Map<String, dynamic> json) {
    return FriendPersona(
      about: (json['about'] as String?)?.trim() ?? '',
      occupation: (json['occupation'] as String?)?.trim() ?? '',
      goodHabits: (json['goodHabits'] as String?)?.trim() ?? '',
      badHabits: (json['badHabits'] as String?)?.trim() ?? '',
      hobbies: (json['hobbies'] as String?)?.trim() ?? '',
      bestMoments: (json['bestMoments'] as String?)?.trim() ?? '',
      characterTraits: (json['characterTraits'] as String?)?.trim() ?? '',
      sharedSecrets: (json['sharedSecrets'] as String?)?.trim() ?? '',
      relationshipNotes: (json['relationshipNotes'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'about': about,
      'occupation': occupation,
      'goodHabits': goodHabits,
      'badHabits': badHabits,
      'hobbies': hobbies,
      'bestMoments': bestMoments,
      'characterTraits': characterTraits,
      'sharedSecrets': sharedSecrets,
      'relationshipNotes': relationshipNotes,
    };
  }

  bool get isEmpty =>
      about.isEmpty &&
      occupation.isEmpty &&
      goodHabits.isEmpty &&
      badHabits.isEmpty &&
      hobbies.isEmpty &&
      bestMoments.isEmpty &&
      characterTraits.isEmpty &&
      sharedSecrets.isEmpty &&
      relationshipNotes.isEmpty;

  @override
  List<Object?> get props => [
        about,
        occupation,
        goodHabits,
        badHabits,
        hobbies,
        bestMoments,
        characterTraits,
        sharedSecrets,
        relationshipNotes,
      ];
}
