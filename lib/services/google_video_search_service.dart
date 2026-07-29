import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/exercise_video_candidate.dart';

/// Поиск VK видео через Google Custom Search API (CSE)
class GoogleVideoSearchService {
  static const String _baseUrl =
      'https://customsearch.googleapis.com/customsearch/v1';

  final String? _apiKey;
  final String? _searchEngineId;

  GoogleVideoSearchService({String? apiKey, String? searchEngineId})
      : _apiKey = apiKey ?? dotenv.env['GOOGLE_CSE_API_KEY'],
        _searchEngineId = searchEngineId ?? dotenv.env['GOOGLE_CSE_ID'] {
    if (_isBlank(_apiKey)) {
      debugPrint('⚠️ GoogleVideoSearchService: API ключ не задан');
    }
    if (_isBlank(_searchEngineId)) {
      debugPrint('⚠️ GoogleVideoSearchService: ID поисковой системы не задан');
    }
  }

  /// Ищет до 10 кандидатов VK видео по названию упражнения
  Future<List<ExerciseVideoCandidate>> searchVideos(String exerciseName) async {
    final results = <ExerciseVideoCandidate>[];

    try {
      debugPrint('🔍 GOOGLE_VIDEO: Поиск видео для: $exerciseName');

      final queries = _generateQueries(exerciseName);
      for (final q in queries) {
        if (results.length >= 10) break;

        debugPrint('🔎 GOOGLE_VIDEO: Запрос: "$q"');
        // Ограничиваем поиск строго разделом с видео на vk.com
        final found = await _searchOnce(
          q,
          exerciseName,
          siteDomain: 'vk.com/video',
        );
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

      debugPrint('✅ GOOGLE_VIDEO: Найдено ${results.length} видео');
    } catch (e) {
      debugPrint('❌ GOOGLE_VIDEO: Ошибка поиска: $e');
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
      // siteSearch больше не используем — логика site: в q

      final uri = Uri.parse(_baseUrl).replace(queryParameters: qp);
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        debugPrint('❌ GOOGLE_VIDEO: HTTP ${resp.statusCode}');
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
            '🔗 GOOGLE_VIDEO: RAW URLS (${rawUrls.length}) для "$query":');
        for (final u in rawUrls.take(10)) {
          debugPrint(' • $u');
        }
      }

      // collectTexts не требуется — используем только URL для строгой релевантности

      // Берём только то, что реально приходит в виде ссылок vk.com/video
      for (final item in items) {
        if (candidates.length >= 10) break;
        final title = (item['title'] ?? '').toString();
        final link = (item['link'] ?? '').toString();
        final formatted = (item['formattedUrl'] ?? '').toString();

        String? url =
            link.isNotEmpty ? link : (formatted.isNotEmpty ? formatted : null);
        if (url == null || url.isEmpty) continue;
        final norm = _normalize(url);

        // Принимаем только ссылки на vk.com/video
        if (!norm.contains('vk.com/video')) continue;

        final m = RegExp(r'video(-?\d+)_(\d+)').firstMatch(norm);
        if (m == null) continue;

        final ownerId = m.group(1)!;
        final videoId = m.group(2)!;
        final cand = ExerciseVideoCandidate(
          source: ExerciseVideoSource.vk,
          ownerId: ownerId,
          videoId: videoId,
          title: title.isNotEmpty ? title : null,
          playerUrl:
              'https://vk.com/video_ext.php?oid=$ownerId&id=$videoId&hd=2&autoplay=0',
        );
        if (!candidates.any((e) => e.uniqueKey == cand.uniqueKey)) {
          candidates.add(cand);
        }
      }
    } catch (e) {
      debugPrint('❌ GOOGLE_VIDEO: Ошибка разбора ответа: $e');
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

  // Фильтрация по названию отключена по требованию: берём топ из выдачи

  String _sanitize(String value) {
    // Убираем кавычки/скобки, чтобы избежать 400 и лишней точности
    return value
        .replaceAll('"', ' ')
        .replaceAll("'", ' ')
        .replaceAll('(', ' ')
        .replaceAll(')', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isBlank(String? value) => value == null || value.isEmpty;
}
