class TTSVoiceConfig {
  final String name;
  final String gender;
  final double pitch;
  final double speakingRate;
  final String description;

  const TTSVoiceConfig({
    required this.name,
    required this.gender,
    required this.pitch,
    required this.speakingRate,
    required this.description,
  });

  static const russianVoices = {
    'energetic_female': TTSVoiceConfig(
      name: 'ru-RU-Wavenet-E',
      gender: 'FEMALE',
      pitch: -1.5,
      speakingRate: 0.92,
      description: 'Энергичный женский голос - идеален для гида',
    ),
    'warm_female': TTSVoiceConfig(
      name: 'ru-RU-Wavenet-A',
      gender: 'FEMALE',
      pitch: -2.0,
      speakingRate: 0.88,
      description: 'Мягкий теплый женский голос - для расслабляющих экскурсий',
    ),
    'professional_female': TTSVoiceConfig(
      name: 'ru-RU-Wavenet-C',
      gender: 'FEMALE',
      pitch: -1.0,
      speakingRate: 0.95,
      description: 'Профессиональный женский голос - для деловых туров',
    ),
    'confident_male': TTSVoiceConfig(
      name: 'ru-RU-Wavenet-B',
      gender: 'MALE',
      pitch: -2.0,
      speakingRate: 0.90,
      description: 'Уверенный мужской голос - для исторических экскурсий',
    ),
    'calm_male': TTSVoiceConfig(
      name: 'ru-RU-Wavenet-D',
      gender: 'MALE',
      pitch: -1.5,
      speakingRate: 0.88,
      description: 'Спокойный мужской голос - для природных локаций',
    ),
  };

  static const englishVoices = {
    'energetic_female': TTSVoiceConfig(
      name: 'en-US-Neural2-F',
      gender: 'FEMALE',
      pitch: -1.5,
      speakingRate: 0.92,
      description: 'Energetic female voice - ideal for tour guide',
    ),
    'warm_female': TTSVoiceConfig(
      name: 'en-US-Neural2-C',
      gender: 'FEMALE',
      pitch: -2.0,
      speakingRate: 0.88,
      description: 'Warm female voice - for relaxing tours',
    ),
  };

  static TTSVoiceConfig getDefaultForLanguage(String languageCode) {
    switch (languageCode) {
      case 'ru-RU':
        return russianVoices['energetic_female']!;
      case 'en-US':
      case 'en-GB':
        return englishVoices['energetic_female']!;
      default:
        return russianVoices['energetic_female']!;
    }
  }
}




















