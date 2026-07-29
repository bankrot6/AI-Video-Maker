import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'base_tts_service.dart';
import 'google_tts_service.dart';
import 'flutter_tts_service.dart';

const String _ttsServiceTypeKey = 'tts_service_type';
const String _ttsVoiceKey = 'tts_selected_voice';
const String _ttsSpeechRateKey = 'tts_speech_rate';
const String _ttsPitchKey = 'tts_pitch';

final ttsServiceTypeProvider =
    StateNotifierProvider<TTSServiceTypeNotifier, TTSServiceType>(
  (ref) => TTSServiceTypeNotifier(),
);

class TTSServiceTypeNotifier extends StateNotifier<TTSServiceType> {
  TTSServiceTypeNotifier() : super(TTSServiceType.local) {
    _loadSavedType();
  }

  Future<void> _loadSavedType() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_ttsServiceTypeKey);
    if (savedIndex != null && savedIndex < TTSServiceType.values.length) {
      final savedType = TTSServiceType.values[savedIndex];
      if (savedType == TTSServiceType.local) {
        state = savedType;
        return;
      }
    }

    await _persistType(TTSServiceType.local);
  }

  Future<void> setType(TTSServiceType type) async {
    final forcedType = TTSServiceType.local;
    state = forcedType;
    await _persistType(forcedType);
  }

  Future<void> _persistType(TTSServiceType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ttsServiceTypeKey, type.index);
  }
}

final flutterTTSServiceProvider = Provider<FlutterTTSService>((ref) {
  return FlutterTTSService();
});

final attractionTTSServiceProvider = Provider<BaseTTSService>((ref) {
  final serviceType = ref.watch(ttsServiceTypeProvider);

  switch (serviceType) {
    case TTSServiceType.google:
      return GoogleTTSService();
    case TTSServiceType.local:
      return ref.watch(flutterTTSServiceProvider);
  }
});

final availableVoicesProvider = FutureProvider<List<TTSVoice>>((ref) async {
  final service = ref.watch(flutterTTSServiceProvider);
  return service.getAvailableVoices();
});

final voicesForCurrentLanguageProvider =
    FutureProvider.family<List<TTSVoice>, String>((ref, languageCode) async {
  final service = ref.watch(flutterTTSServiceProvider);
  return service.getVoicesForLanguage(languageCode);
});

final selectedVoiceProvider =
    StateNotifierProvider<SelectedVoiceNotifier, TTSVoice?>(
  (ref) => SelectedVoiceNotifier(ref),
);

class SelectedVoiceNotifier extends StateNotifier<TTSVoice?> {
  final Ref _ref;

  SelectedVoiceNotifier(this._ref) : super(null) {
    _loadSavedVoice();
  }

  Future<void> _loadSavedVoice() async {
    final prefs = await SharedPreferences.getInstance();
    final voiceJson = prefs.getString(_ttsVoiceKey);
    if (voiceJson != null) {
      try {
        final data = jsonDecode(voiceJson);
        state = TTSVoice(name: data['name'], locale: data['locale']);
        await _applyVoice();
      } catch (_) {}
    }
  }

  Future<void> setVoice(TTSVoice voice) async {
    state = voice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _ttsVoiceKey, jsonEncode({'name': voice.name, 'locale': voice.locale}));
    await _applyVoice();
  }

  Future<void> _applyVoice() async {
    if (state != null) {
      final service = _ref.read(flutterTTSServiceProvider);
      await service.setVoice(state!);
    }
  }
}

final speechRateProvider = StateNotifierProvider<SpeechRateNotifier, double>(
  (ref) => SpeechRateNotifier(ref),
);

class SpeechRateNotifier extends StateNotifier<double> {
  final Ref _ref;

  SpeechRateNotifier(this._ref) : super(0.5) {
    _loadSavedRate();
  }

  Future<void> _loadSavedRate() async {
    final prefs = await SharedPreferences.getInstance();
    final rate = prefs.getDouble(_ttsSpeechRateKey);
    if (rate != null) {
      state = rate;
      await _applyRate();
    }
  }

  Future<void> setRate(double rate) async {
    state = rate.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ttsSpeechRateKey, state);
    await _applyRate();
  }

  Future<void> _applyRate() async {
    final service = _ref.read(flutterTTSServiceProvider);
    await service.setSpeechRateValue(state);
  }
}

final pitchProvider = StateNotifierProvider<PitchNotifier, double>(
  (ref) => PitchNotifier(ref),
);

class PitchNotifier extends StateNotifier<double> {
  final Ref _ref;

  PitchNotifier(this._ref) : super(1.0) {
    _loadSavedPitch();
  }

  Future<void> _loadSavedPitch() async {
    final prefs = await SharedPreferences.getInstance();
    final pitch = prefs.getDouble(_ttsPitchKey);
    if (pitch != null) {
      state = pitch;
      await _applyPitch();
    }
  }

  Future<void> setPitch(double pitch) async {
    state = pitch.clamp(0.5, 2.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_ttsPitchKey, state);
    await _applyPitch();
  }

  Future<void> _applyPitch() async {
    final service = _ref.read(flutterTTSServiceProvider);
    await service.setPitchValue(state);
  }
}
