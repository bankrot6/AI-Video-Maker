import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/exercise_video_candidate.dart';

/// Поиск RuTube видео через Google Custom Search API (CSE) с фильтрацией site:rutube.ru
/// Плюсы: устойчиво, не требует отдельного API RuTube, минимальный риск бана
/// Минусы: ограничения квоты CSE. При необходимости можно добавить прямой HTML-поиск RuTube как фолбэк
class RutubeVideoSearchService {
  static const String _baseUrl =
      'https://customsearch.googleapis.com/customsearch/v1';

  final String? _apiKey;
  final String? _searchEngineId;

  RutubeVideoSearchService({String? apiKey, String? searchEngineId})
      : _apiKey = apiKey ?? dotenv.env['GOOGLE_CSE_API_KEY'],
        _searchEngineId = searchEngineId ?? dotenv.env['GOOGLE_CSE_ID'] {
    if (_isBlank(_apiKey)) {
      debugPrint('⚠️ RutubeVideoSearchService: API ключ не задан');
    }
    if (_isBlank(_searchEngineId)) {
      debugPrint('⚠️ RutubeVideoSearchService: ID поисковой системы не задан');
    }
  }

  /// Ищет до 10 кандидатов RuTube видео по названию упражнения (простой запрос)
  Future<List<ExerciseVideoCandidate>> searchVideos(String exerciseName) async {
    final results = <ExerciseVideoCandidate>[];

    try {
      debugPrint('🔍 RUTUBE_VIDEO: Поиск видео для: $exerciseName');

      final queries = _generateQueries(exerciseName);
      for (final q in queries) {
        if (results.length >= 10) break;

        debugPrint('🔎 RUTUBE_VIDEO: Запрос: "$q"');
        final found =
            await _searchOnce(q, exerciseName, siteDomain: 'rutube.ru/video');
        for (final c in found) {
          if (!results.any((e) => e.uniqueKey == c.uniqueKey)) {
            results.add(c);
            if (results.length >= 10) break;
          }
        }

        if (results.length < 10 && q != queries.last) {
          await Future.delayed(const Duration(milliseconds: 250));
        }
      }

      debugPrint('✅ RUTUBE_VIDEO: Найдено ${results.length} видео');
    } catch (e) {
      debugPrint('❌ RUTUBE_VIDEO: Ошибка поиска: $e');
    }

    return results;
  }

  List<String> _generateQueries(String exerciseName) {
    final base = _sanitize(exerciseName);
    // Простой запрос: только название, домен ограничим через siteSearch
    return <String>[base];
  }

  Future<List<ExerciseVideoCandidate>> _searchOnce(
    String query,
    String exerciseName, {
    String? siteDomain,
  }) async {
    final candidates = <ExerciseVideoCandidate>[];

    final String? apiKey = _apiKey;
    final String? cseId = _searchEngineId;
    if (_isBlank(apiKey) || _isBlank(cseId)) {
      return candidates;
    }

    try {
      final String apiKeyStr = apiKey!;
      final String cseIdStr = cseId!;
      final qp = <String, String>{
        'key': apiKeyStr,
        'cx': cseIdStr,
        'q': query,
        'num': '10',
        'hl': 'ru',
        'safe': 'off',
        'gl': 'ru',
        'lr': 'lang_ru',
      };
      if (siteDomain != null && siteDomain.isNotEmpty) {
        qp['siteSearch'] = siteDomain;
        qp['siteSearchFilter'] = 'i';
      }

      final uri = Uri.parse(_baseUrl).replace(queryParameters: qp);
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        debugPrint('❌ RUTUBE_VIDEO: HTTP ${resp.statusCode}');
        return candidates;
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];

      // Логируем сырые ссылки для диагностики
      final rawUrls = <String>[];
      for (final it in items) {
        final link = (it['link'] ?? '').toString();
        final formatted = (it['formattedUrl'] ?? '').toString();
        final url = link.isNotEmpty ? link : formatted;
        if (url.isNotEmpty) rawUrls.add(url);
      }
      if (rawUrls.isNotEmpty) {
        debugPrint(
            '🔗 RUTUBE_VIDEO: RAW URLS (${rawUrls.length}) для "$query":');
        for (final u in rawUrls.take(10)) {
          debugPrint(' • $u');
        }
      }

      // collectTexts не нужен — используем только URL для строгой релевантности

      for (final item in items) {
        if (candidates.length >= 10) break;

        final title = (item['title'] ?? '').toString();
        final link = (item['link'] ?? '').toString();
        final formatted = (item['formattedUrl'] ?? '').toString();
        String? url =
            link.isNotEmpty ? link : (formatted.isNotEmpty ? formatted : null);
        if (url == null || url.isEmpty) continue;
        final text = _normalize(url);

        if (!text.contains('rutube.ru')) continue;

        // Игнорируем встраиваемые/короткие ссылки, берём только страницы /video/

        final m2 = _rutubePageRegex.firstMatch(text);
        if (m2 != null) {
          final id = m2.group(1)!;
          final cand = ExerciseVideoCandidate(
            source: ExerciseVideoSource.rutube,
            videoId: id,
            title: title.isNotEmpty ? title : null,
            playerUrl: 'https://rutube.ru/play/embed/$id?autoplay=0',
          );
          if (!candidates.any((e) => e.uniqueKey == cand.uniqueKey)) {
            candidates.add(cand);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ RUTUBE_VIDEO: Ошибка разбора ответа: $e');
    }

    return candidates;
  }

  String _normalize(String value) {
    try {
      final decoded = Uri.decodeFull(value);
      return decoded
          .replaceAll('\\u0026', '&')
          .replaceAll('&amp;', '&')
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
    } catch (_) {
      return value;
    }
  }

  // _looksLikeUrl больше не используется после перехода на сбор всех текстовых полей

  // Фильтрация по названию отключена: берём топ из выдачи CSE

  bool _isBlank(String? value) => value == null || value.isEmpty;

  String _sanitize(String value) {
    return value
        .replaceAll('"', ' ')
        .replaceAll("'", ' ')
        .replaceAll('(', ' ')
        .replaceAll(')', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static final RegExp _rutubePageRegex =
      RegExp(r'rutube\.ru/+(?:video)/+([A-Za-z0-9\-]{6,})');
}
