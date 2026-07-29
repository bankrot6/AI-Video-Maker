import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/nutrition_analysis/deepseek/deepseek_client.dart';

final onboardingAudioGuideServiceProvider =
    Provider<OnboardingAudioGuideService>((ref) {
  return OnboardingAudioGuideService();
});

class OnboardingAudioGuideService {
  final DeepSeekClient _client;
  final Map<String, _TourStreamSession> _tourSessions = {};
  final Map<String, OnboardingTourBundle> _tourBundleCache = {};

  OnboardingAudioGuideService({DeepSeekClient? client})
      : _client = client ??
            DeepSeekClient.fromEnvironment(
              fastMode: true,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 40),
              sendTimeout: const Duration(seconds: 20),
            );

  Stream<String> startTourStream({
    required String city,
    int placesCount = 7,
    int maxCityChars = 520,
    int maxPlaceChars = 520,
  }) {
    final key = _normalizeCityKey(city);
    if (key.isEmpty) return const Stream<String>.empty();
    final existing = _tourSessions[key];
    if (existing != null) return existing.controller.stream;

    final controller = StreamController<String>.broadcast();
    final session = _TourStreamSession(controller);
    _tourSessions[key] = session;
    unawaited(_runTourStream(
      session,
      city: city,
      key: key,
      placesCount: placesCount,
      maxCityChars: maxCityChars,
      maxPlaceChars: maxPlaceChars,
    ));
    return controller.stream;
  }

  String getTourText(String city) {
    final key = _normalizeCityKey(city);
    final session = _tourSessions[key];
    if (session == null) return '';
    return session.buffer.toString();
  }

  OnboardingTourBundle? getTourBundle(String city) {
    final key = _normalizeCityKey(city);
    return _tourBundleCache[key] ?? _tourSessions[key]?.bundle;
  }

  Future<String> fetchAttractionIntro({
    required String city,
    required String name,
    required String category,
    int maxChars = 500,
  }) async {
    final prompt = _buildAttractionPrompt(city, name, category, maxChars);
    try {
      final response = await _client.generateText(prompt);
      return _sanitize(response, maxChars);
    } catch (e) {
      debugPrint('🎧 OnboardingAudioGuide: place intro failed: $e');
      return '';
    }
  }

  String _buildTourPrompt({
    required String city,
    required int placesCount,
    required int maxCityChars,
    required int maxPlaceChars,
  }) {
    final safeCity = city.trim().isNotEmpty ? city.trim() : 'город';
    return '''
Ты опытный гид.
Сначала дай связный текст о городе "$safeCity" (4-6 предложений, около 500 символов, максимум $maxCityChars).
Затем выбери $placesCount самых интересных мест в этом городе.
Для каждого места дай краткий рассказ 4-6 предложений (около 500 символов, максимум $maxPlaceChars).
Порядок: сначала город, затем места.
Строгий формат (по одной строке на блок, без пустых строк):
CITY_NAME: <корректное название города>
CITY: <текст про город>
PLACE: <название места>
INFO: <текст про место>
PLACE: <название места>
INFO: <текст про место>
...
После всех мест выведи строку JSON_START и затем один JSON объект:
{"cityName":"...", "cityIntro":"...", "places":[{"name":"...", "intro":"..."}]}
Где cityName — корректное написание города (именительный падеж).
Без markdown, списков и лишнего текста.
''';
  }

  String _normalizeCityKey(String city) => city.trim().toLowerCase();

  String _buildAttractionPrompt(
    String city,
    String name,
    String category,
    int maxChars,
  ) {
    final safeCity = city.trim().isNotEmpty ? city.trim() : 'этот город';
    final safeName = name.trim().isNotEmpty ? name.trim() : 'достопримечательность';
    final safeCategory =
        category.trim().isNotEmpty ? category.trim() : 'объект';
    return '''
Ты опытный гид. Город: "$safeCity".
Дай краткий рассказ о достопримечательности "$safeName" (категория: $safeCategory).
ВАЖНО: начни текст с точного названия места "$safeName" (первые слова) и дальше сразу описание.
Текст до $maxChars символов, 2-4 предложения, связный, без списков и заголовков.
Пиши по-русски.
''';
  }

  String _sanitize(String input, int maxChars) {
    var text = input.trim();
    text = text.replaceAll(RegExp(r'```.*?```', dotAll: true), '').trim();
    if (text.startsWith('"') && text.endsWith('"') && text.length > 1) {
      text = text.substring(1, text.length - 1).trim();
    }
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > maxChars) {
      text = text.substring(0, maxChars).trimRight();
    }
    if (text.isNotEmpty && !RegExp(r'[.!?]$').hasMatch(text)) {
      if (text.length < maxChars) {
        text = '$text.';
      }
    }
    return text;
  }

  String _sanitizeCityName(String input, int maxChars) {
    var text = input.trim();
    text = text.replaceAll(RegExp(r'```.*?```', dotAll: true), '').trim();
    if (text.startsWith('"') && text.endsWith('"') && text.length > 1) {
      text = text.substring(1, text.length - 1).trim();
    }
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    text = text.replaceAll(RegExp(r'[.!?]+$'), '').trim();
    if (text.length > maxChars) {
      text = text.substring(0, maxChars).trimRight();
    }
    return text;
  }

  Future<void> _runTourStream(
    _TourStreamSession session, {
    required String city,
    required String key,
    required int placesCount,
    required int maxCityChars,
    required int maxPlaceChars,
  }) async {
    final prompt = _buildTourPrompt(
      city: city,
      placesCount: placesCount,
      maxCityChars: maxCityChars,
      maxPlaceChars: maxPlaceChars,
    );
    try {
      await for (final chunk in _client.generateTextStream(prompt)) {
        if (session.cancelled) break;
        session.buffer.write(chunk);
        if (!session.controller.isClosed) {
          session.controller.add(chunk);
        }
      }
      if (!session.cancelled) {
        final bundle = _parseTourBundle(
          session.buffer.toString(),
          maxCityChars: maxCityChars,
          maxPlaceChars: maxPlaceChars,
        );
        if (bundle != null) {
          session.bundle = bundle;
          _tourBundleCache[key] = bundle;
        }
      }
    } catch (e) {
      debugPrint('🎧 OnboardingAudioGuide: tour stream failed: $e');
      session.error = e;
    } finally {
      session.completed = true;
      if (!session.controller.isClosed) {
        await session.controller.close();
      }
    }
  }

  OnboardingTourBundle? _parseTourBundle(
    String fullText, {
    required int maxCityChars,
    required int maxPlaceChars,
  }) {
    final markerIndex = fullText.indexOf('JSON_START');
    if (markerIndex == -1) return null;
    final jsonText = fullText.substring(markerIndex + 'JSON_START'.length);
    final extracted = _extractJsonBlock(jsonText);
    if (extracted == null) return null;
    try {
      final data = jsonDecode(extracted) as Map<String, dynamic>;
      final cityNameRaw = data['cityName']?.toString() ?? '';
      final cityName = _sanitizeCityName(cityNameRaw, maxCityChars);
      final cityIntroRaw = data['cityIntro']?.toString() ?? '';
      final cityIntro = _sanitize(cityIntroRaw, maxCityChars);
      final placesRaw = data['places'] as List<dynamic>? ?? const [];
      final places = <OnboardingPlaceIntro>[];
      for (final item in placesRaw) {
        if (item is! Map) continue;
        final name = item['name']?.toString().trim() ?? '';
        final introRaw = item['intro']?.toString() ?? '';
        final intro = _sanitize(introRaw, maxPlaceChars);
        if (name.isEmpty || intro.isEmpty) continue;
        places.add(OnboardingPlaceIntro(name: name, intro: intro));
      }
      if (cityIntro.isEmpty || places.isEmpty) return null;
      return OnboardingTourBundle(
        cityName: cityName,
        cityIntro: cityIntro,
        places: places,
      );
    } catch (_) {
      return null;
    }
  }

  String? _extractJsonBlock(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  void stopTourStream(String city) {
    final key = _normalizeCityKey(city);
    final session = _tourSessions[key];
    if (session == null) return;
    session.cancelled = true;
    if (!session.controller.isClosed) {
      session.controller.close();
    }
  }
}

class OnboardingTourBundle {
  final String cityName;
  final String cityIntro;
  final List<OnboardingPlaceIntro> places;

  const OnboardingTourBundle({
    required this.cityName,
    required this.cityIntro,
    required this.places,
  });
}

class OnboardingPlaceIntro {
  final String name;
  final String intro;

  const OnboardingPlaceIntro({
    required this.name,
    required this.intro,
  });
}

class _TourStreamSession {
  final StreamController<String> controller;
  final StringBuffer buffer = StringBuffer();
  OnboardingTourBundle? bundle;
  Object? error;
  bool completed = false;
  bool cancelled = false;

  _TourStreamSession(this.controller);
}
