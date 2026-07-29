abstract class BaseTTSService {
  bool get isPlaying;
  bool get hasQueuedItems;
  int get queueSize;

  Future<void> speak(String text, {String languageCode = 'ru-RU'});

  Future<void> addToQueue(String text, {String languageCode = 'ru-RU'});

  Future<void> stop();

  Future<void> pause();

  Future<void> resume();

  Future<void> clearQueue();

  void dispose();
}

enum TTSServiceType {
  google,
  local,
}

extension TTSServiceTypeExtension on TTSServiceType {
  String get displayName {
    switch (this) {
      case TTSServiceType.google:
        return 'Google Cloud TTS';
      case TTSServiceType.local:
        return 'Локальный TTS';
    }
  }

  String get description {
    switch (this) {
      case TTSServiceType.google:
        return 'Высокое качество, требует интернет';
      case TTSServiceType.local:
        return 'Работает оффлайн, системный голос';
    }
  }
}












