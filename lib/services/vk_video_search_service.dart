import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Модель данных VK видео
class VkVideoData {
  final String ownerId;
  final String videoId;
  final String? title;
  final int? views;

  const VkVideoData({
    required this.ownerId,
    required this.videoId,
    this.title,
    this.views,
  });

  /// Создает embed URL
  String get embedUrl =>
      'https://vk.com/video_ext.php?oid=$ownerId&id=$videoId&hd=2&autoplay=0';
}

/// Сервис для поиска видео на VK
class VkVideoSearchService {
  /// Поиск видео на VK по запросу
  /// Использует веб-скрейпинг для поиска популярных видео
  Future<VkVideoData?> searchVideo(String exerciseName) async {
    try {
      debugPrint('🎥 VK_VIDEO_SEARCH: Поиск видео для: $exerciseName');

      // Создаем несколько вариантов поисковых запросов для лучших результатов
      final searchQueries = _generateSearchQueries(exerciseName);

      // Пробуем каждый запрос по очереди
      for (final query in searchQueries) {
        debugPrint('🔍 VK_VIDEO_SEARCH: Пробуем запрос: "$query"');

        final videoData = await _searchViaWeb(query);

        if (videoData != null) {
          debugPrint(
              '✅ VK_VIDEO_SEARCH: Найдено видео: oid=${videoData.ownerId}, id=${videoData.videoId}');
          debugPrint('   Название: ${videoData.title}');
          debugPrint('   Просмотров: ${videoData.views}');
          return videoData;
        }

        // Небольшая задержка между запросами
        await Future.delayed(const Duration(milliseconds: 500));
      }

      debugPrint('❌ VK_VIDEO_SEARCH: Видео не найдено для: $exerciseName');
      return null;
    } catch (e) {
      debugPrint('❌ VK_VIDEO_SEARCH: Ошибка поиска: $e');
      return null;
    }
  }

  /// Генерирует несколько вариантов поисковых запросов
  /// для лучшего нахождения релевантных видео
  List<String> _generateSearchQueries(String exerciseName) {
    final queries = <String>[];

    // 1. Техника выполнения (самый релевантный запрос)
    queries.add('$exerciseName техника выполнения');

    // 2. Как правильно делать
    queries.add('как правильно делать $exerciseName');

    // 3. Упражнение + техника
    queries.add('$exerciseName упражнение техника');

    // 4. Просто название упражнения
    queries.add(exerciseName);

    return queries;
  }

  /// Поиск через веб-интерфейс VK (без API токена)
  Future<VkVideoData?> _searchViaWeb(String query) async {
    try {
      // Поиск через VK используя публичный поиск
      final encodedQuery = Uri.encodeComponent(query);
      final searchUrl = 'https://vk.com/video?q=$encodedQuery&section=search';

      debugPrint('🔍 VK_VIDEO_SEARCH: Запрос к веб-поиску: $searchUrl');

      final response = await http.get(
        Uri.parse(searchUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
          'Accept-Encoding': 'gzip, deflate, br',
          'Connection': 'keep-alive',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
            '❌ VK_VIDEO_SEARCH: Ошибка веб-поиска: ${response.statusCode}');
        return null;
      }

      // Парсим HTML для поиска видео
      final html = response.body;

      // VK использует формат: video-OWNER_ID_VIDEO_ID
      // Ищем все совпадения и выбираем первое (самое популярное)
      final videoPattern = RegExp(r'video(-?\d+)_(\d+)');
      final matches = videoPattern.allMatches(html).toList();

      if (matches.isEmpty) {
        debugPrint('⚠️ VK_VIDEO_SEARCH: Видео не найдены в HTML');
        return null;
      }

      // Берем первое видео (обычно самое популярное/релевантное)
      final match = matches.first;
      final ownerId = match.group(1)!;
      final videoId = match.group(2)!;

      debugPrint(
          '📹 VK_VIDEO_SEARCH: Найдено видео: owner=$ownerId, id=$videoId');

      // Пытаемся извлечь название и просмотры (опционально)
      String? title;
      int? views;

      try {
        // Ищем название видео (находится после video ID в data-title или title атрибуте)
        final titlePattern = RegExp(
          r'video' +
              ownerId +
              r'_' +
              videoId +
              r'[^>]*(?:data-title|title)="([^"]+)"',
          caseSensitive: false,
        );
        final titleMatch = titlePattern.firstMatch(html);
        if (titleMatch != null) {
          title = titleMatch.group(1);
        }

        // Ищем количество просмотров
        final viewsPattern = RegExp(
          r'video' + ownerId + r'_' + videoId + r'.*?views_count["\s>:]+(\d+)',
          caseSensitive: false,
        );
        final viewsMatch = viewsPattern.firstMatch(html);
        if (viewsMatch != null) {
          views = int.tryParse(viewsMatch.group(1)!);
        }
      } catch (e) {
        debugPrint('⚠️ VK_VIDEO_SEARCH: Не удалось извлечь метаданные: $e');
      }

      return VkVideoData(
        ownerId: ownerId,
        videoId: videoId,
        title: title,
        views: views,
      );
    } catch (e) {
      debugPrint('❌ VK_VIDEO_SEARCH: Ошибка веб-поиска: $e');
      return null;
    }
  }

  /// Создает embed URL из обычного URL VK видео
  String? createEmbedUrl(String videoUrl) {
    try {
      // Формат: https://vk.com/video{owner_id}_{video_id}
      final videoPattern = RegExp(r'video(-?\d+)_(\d+)');
      final match = videoPattern.firstMatch(videoUrl);

      if (match != null) {
        final ownerId = match.group(1)!;
        final videoId = match.group(2)!;
        return 'https://vk.com/video_ext.php?oid=$ownerId&id=$videoId&hd=2&autoplay=0';
      }

      return null;
    } catch (e) {
      debugPrint('❌ VK_VIDEO_SEARCH: Ошибка создания embed URL: $e');
      return null;
    }
  }
}
