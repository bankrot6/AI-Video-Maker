import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';

import 'image_search_service.dart';
import '../../config/ai_proxy_config.dart';

/// Реализация сервиса поиска изображений с использованием Google Custom Search API
class GoogleImageSearchService implements ImageSearchService {
  /// API ключ для Google Custom Search
  final String? _apiKey;

  /// ID поисковой системы
  final String? _searchEngineId;

  /// Базовый URL для Google Custom Search API
  static const String _baseUrl =
      'https://customsearch.googleapis.com/customsearch/v1';

  // NOTE: кэширование отключено

  // NOTE: Таймаут задаём локально в вызовах http и не держим как поле

  // NOTE: валидация размеров отключена

  /// Создает экземпляр сервиса поиска изображений Google
  ///
  /// Можно указать API ключ и ID поисковой системы вручную, иначе они будут загружены из .env файла
  GoogleImageSearchService({String? apiKey, String? searchEngineId})
      : _apiKey = apiKey ?? dotenv.env['GOOGLE_CSE_API_KEY'],
        _searchEngineId = searchEngineId ?? dotenv.env['GOOGLE_CSE_ID'] {
    // Проверяем наличие ключей при инициализации
    if (_apiKey == null || _apiKey.isEmpty) {
      debugPrint('⚠️ GoogleImageSearchService: API ключ не задан');
    }
    if (_searchEngineId == null || _searchEngineId.isEmpty) {
      debugPrint('⚠️ GoogleImageSearchService: ID поисковой системы не задан');
    }
  }

  @override
  Future<String?> searchImageUrl(String query) async {
    try {
      debugPrint(
          '🔍 GoogleImageSearchService: ==========================================');
      debugPrint(
          '🔍 GoogleImageSearchService: Начало searchImageUrl для: "$query"');

      if (_apiKey == null ||
          _apiKey.isEmpty ||
          _searchEngineId == null ||
          _searchEngineId.isEmpty) {
        debugPrint('❌ GoogleImageSearchService: ⚠️ API ключи не настроены!');
        debugPrint(
            '❌ GoogleImageSearchService: _apiKey is null/empty: ${_apiKey == null || _apiKey.isEmpty}');
        debugPrint(
            '❌ GoogleImageSearchService: _searchEngineId is null/empty: ${_searchEngineId == null || _searchEngineId.isEmpty}');
        debugPrint(
            '🔍 GoogleImageSearchService: ==========================================');
        return null;
      }

      debugPrint('🔍 GoogleImageSearchService: Поиск изображения для "$query"');
      final results = await searchImageUrls(query, count: 3);

      if (results.isEmpty) {
        debugPrint(
            '❌ GoogleImageSearchService: ❌ Результаты поиска пусты для запроса "$query"');
        debugPrint(
            '🔍 GoogleImageSearchService: ==========================================');
        return null;
      }

      debugPrint(
          '✅ GoogleImageSearchService: ✅ Найдено ${results.length} результатов, возвращаем первый: ${results.first}');
      debugPrint(
          '🔍 GoogleImageSearchService: ==========================================');

      return results.first;
    } catch (e, stackTrace) {
      debugPrint(
          '❌ GoogleImageSearchService: ==========================================');
      debugPrint(
          '❌ GoogleImageSearchService: ❌ ОШИБКА при поиске изображения: $e');
      debugPrint('❌ GoogleImageSearchService: StackTrace: $stackTrace');
      debugPrint(
          '❌ GoogleImageSearchService: ==========================================');
      return null;
    }
  }

  /// Проверяет, является ли изображение по URL валидным для использования
  /// Возвращает true, если изображение доступно, имеет подходящий размер и формат
  // удалено: _isValidImage (не используется)

  /// Проверяет, являются ли байты действительно изображением по сигнатуре
  // NOTE: сигнатурная проверка отключена

  Uri _cseRequestUri(String apiBase, String normalizedQuery, int validCount) {
    return Uri.parse(apiBase).replace(
      queryParameters: <String, String>{
        'key': _apiKey!,
        'cx': _searchEngineId!,
        'q': normalizedQuery,
        'searchType': 'image',
        'num': '$validCount',
        'imgType': 'photo',
        'safe': 'active',
      },
    );
  }

  @override
  Future<List<String>> searchImageUrls(String query, {int count = 5}) async {
    debugPrint(
        '🔍 GoogleImageSearchService: ------------------------------------------');
    debugPrint(
        '🔍 GoogleImageSearchService: searchImageUrls вызван для: "$query"');
    debugPrint('🔍 GoogleImageSearchService: count=$count');

    if (query.isEmpty) {
      debugPrint('⚠️ GoogleImageSearchService: ❌ Пустой поисковый запрос');
      debugPrint(
          '🔍 GoogleImageSearchService: ------------------------------------------');
      return [];
    }

    final validCount = min(count, 10);

    if (_apiKey == null || _apiKey.isEmpty) {
      debugPrint('❌ GoogleImageSearchService: ❌ API ключ не задан');
      debugPrint(
          '🔍 GoogleImageSearchService: ------------------------------------------');
      return [];
    }

    if (_searchEngineId == null || _searchEngineId.isEmpty) {
      debugPrint('❌ GoogleImageSearchService: ❌ ID поисковой системы не задан');
      debugPrint(
          '🔍 GoogleImageSearchService: ------------------------------------------');
      return [];
    }

    final normalizedQuery = query.trim();

    debugPrint(
        '🔍 GoogleImageSearchService: Нормализованный запрос: "$normalizedQuery"');

    try {
      final relayBase = AiProxyConfig.googleCustomSearchV1Url();
      final apiBase = relayBase ?? _baseUrl;
      var uri = _cseRequestUri(apiBase, normalizedQuery, validCount);

      debugPrint(
          '🔍 GoogleImageSearchService: Отправка запроса к Google CSE API...');
      debugPrint(
          '🔍 GoogleImageSearchService: URL (без ключа): $apiBase?cx=$_searchEngineId&q=$normalizedQuery&searchType=image&num=$validCount');

      var response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint(
              '❌ GoogleImageSearchService: ⏱️ Таймаут запроса (10 секунд)');
          throw Exception('Timeout');
        },
      );

      if (response.statusCode == 404 && relayBase != null) {
        uri = _cseRequestUri(_baseUrl, normalizedQuery, validCount);
        debugPrint(
            '🔍 GoogleImageSearchService: Повтор напрямую к Google (нет /google-cse/ на NL)');
        response = await http.get(uri).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint(
                '❌ GoogleImageSearchService: ⏱️ Таймаут запроса (10 секунд)');
            throw Exception('Timeout');
          },
        );
      }

      debugPrint(
          '🔍 GoogleImageSearchService: Получен ответ. Статус: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint(
            '🔍 GoogleImageSearchService: ✅ Успешный ответ, парсим JSON...');
        final jsonResponse = json.decode(response.body);

        // Проверяем наличие ошибок в ответе
        if (jsonResponse.containsKey('error')) {
          final error = jsonResponse['error'];
          debugPrint(
              '❌ GoogleImageSearchService: ❌ Ошибка в ответе API: ${error['message']}');
          debugPrint(
              '❌ GoogleImageSearchService: Код ошибки: ${error['code']}');
          debugPrint('❌ GoogleImageSearchService: Детали: ${error['errors']}');
          debugPrint(
              '🔍 GoogleImageSearchService: ------------------------------------------');
          return [];
        }

        final items = jsonResponse['items'] as List<dynamic>?;

        if (items == null || items.isEmpty) {
          debugPrint(
              '⚠️ GoogleImageSearchService: ⚠️ Изображения не найдены для "$normalizedQuery"');
          debugPrint(
              '⚠️ GoogleImageSearchService: JSON ответ содержит: ${jsonResponse.keys}');
          debugPrint(
              '🔍 GoogleImageSearchService: ------------------------------------------');
          return [];
        }

        debugPrint(
            '🔍 GoogleImageSearchService: ✅ Найдено ${items.length} результатов');

        // Извлекаем URL изображений, фильтруя проблемные источники
        final blockedDomains = [
          'lookaside.fbsbx.com',
          'facebook.com',
          'fbcdn.net',
          'instagram.com',
          'cdninstagram.com',
          'pinterest.com',
          'pinimg.com',
        ];

        final imageUrls = items
            .map<String>((item) => item['link'] as String)
            .where((url) {
              final isBlocked =
                  blockedDomains.any((domain) => url.contains(domain));
              if (isBlocked) {
                debugPrint(
                    '🔍 GoogleImageSearchService: ⚠️ Пропускаем заблокированный URL: $url');
              }
              return !isBlocked;
            })
            .take(validCount)
            .toList();

        // Выводим найденные URL для отладки
        for (int i = 0; i < imageUrls.length; i++) {
          debugPrint(
              '🔍 GoogleImageSearchService:   ${i + 1}. ${imageUrls[i]}');
        }

        debugPrint(
            '✅ GoogleImageSearchService: ✅ Возвращаем ${imageUrls.length} URL');
        debugPrint(
            '🔍 GoogleImageSearchService: ------------------------------------------');
        return imageUrls;
      } else {
        debugPrint(
            '❌ GoogleImageSearchService: ❌ Ошибка HTTP ${response.statusCode}');
        debugPrint('❌ GoogleImageSearchService: Тело ответа: ${response.body}');
        debugPrint(
            '🔍 GoogleImageSearchService: ------------------------------------------');
        return [];
      }
    } catch (e, stackTrace) {
      debugPrint('❌ GoogleImageSearchService: ❌ Исключение: $e');
      debugPrint('❌ GoogleImageSearchService: StackTrace: $stackTrace');
      debugPrint(
          '🔍 GoogleImageSearchService: ------------------------------------------');
      return [];
    }
  }

  /// Добавляет результаты в кэш, удаляя старые записи при необходимости
  // удалено: _addToCache (не используется)

  /// Создание заглушки с логотипом приложения, если изображение не найдено
  Future<File> createFallbackImage(String query) async {
    try {
      // Создаем имя файла на основе запроса
      final String sanitizedName = query
          .toLowerCase()
          .replaceAll(RegExp(r'[^а-яёa-z0-9]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Получаем директорию для сохранения
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'image_${sanitizedName}_${timestamp}_fallback.jpg';
      final filePath = path.join(directory.path, fileName);

      // Копируем логотип приложения как заглушку (используем существующие ассеты)
      ByteData data;
      try {
        data = await rootBundle.load('assets/images/robot.png');
      } catch (_) {
        data = await rootBundle.load('assets/images/Icon.png');
      }
      final Uint8List bytes = data.buffer.asUint8List();

      // Создаем файл с логотипом
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      debugPrint(
          '🔍 GoogleImageSearchService: Создана заглушка с логотипом: $filePath');

      return file;
    } catch (e) {
      debugPrint(
          '❌ GoogleImageSearchService: Ошибка при создании заглушки: $e');
      throw Exception('Не удалось создать заглушку для изображения: $e');
    }
  }

  /// Удаляем этот метод, так как теперь используем другую логику
  // удалено: _normalizeQuery (не используется)

  /// Удаляем ненужный метод
  // удалено: _isFoodRelatedQuery (не используется)

  @override
  Future<File?> findImage(String query) async {
    debugPrint(
        '🔍 GOOGLE_IMAGE_SEARCH: ========================================');
    debugPrint('🔍 GOOGLE_IMAGE_SEARCH: ===== НАЧАЛО ПОИСКА ИЗОБРАЖЕНИЯ =====');
    debugPrint(
        '🔍 GOOGLE_IMAGE_SEARCH: Поиск изображения для запроса: "$query"');

    final imageUrls = await searchImageUrls(query, count: 5);

    if (imageUrls.isEmpty) {
      debugPrint('🔍 GOOGLE_IMAGE_SEARCH: ⚠️ URL не найдены для "$query"');
      return _createFallbackAndReturn(query);
    }

    debugPrint(
        '🔍 GOOGLE_IMAGE_SEARCH: Найдено ${imageUrls.length} URL, пробуем загрузить...');

    for (int i = 0; i < imageUrls.length; i++) {
      final imageUrl = imageUrls[i];
      debugPrint(
          '🔍 GOOGLE_IMAGE_SEARCH: Попытка ${i + 1}/${imageUrls.length}: $imageUrl');

      try {
        final response = await http.get(Uri.parse(imageUrl)).timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint('🔍 GOOGLE_IMAGE_SEARCH: ⏱️ Таймаут для URL #${i + 1}');
            throw Exception('Timeout');
          },
        );

        if (response.statusCode != 200) {
          debugPrint(
              '🔍 GOOGLE_IMAGE_SEARCH: ❌ HTTP ${response.statusCode} для URL #${i + 1}');
          continue;
        }

        if (response.bodyBytes.length < 1000) {
          debugPrint(
              '🔍 GOOGLE_IMAGE_SEARCH: ⚠️ Слишком маленький файл (${response.bodyBytes.length} байт)');
          continue;
        }

        debugPrint(
            '🔍 GOOGLE_IMAGE_SEARCH: ✅ Изображение загружено (${response.bodyBytes.length} байт)');

        final String sanitizedName = query
            .toLowerCase()
            .replaceAll(RegExp(r'[^а-яёa-z0-9]'), '_')
            .replaceAll(RegExp(r'_+'), '_');
        final timestamp = DateTime.now().millisecondsSinceEpoch;

        final directory = await getApplicationDocumentsDirectory();
        final fileName = 'image_${sanitizedName}_$timestamp.jpg';
        final filePath = path.join(directory.path, fileName);

        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        debugPrint('🔍 GOOGLE_IMAGE_SEARCH: ✅ УСПЕХ! Сохранено: $filePath');
        debugPrint(
            '🔍 GOOGLE_IMAGE_SEARCH: ========================================');
        return file;
      } catch (e) {
        debugPrint('🔍 GOOGLE_IMAGE_SEARCH: ❌ Ошибка для URL #${i + 1}: $e');
        continue;
      }
    }

    debugPrint(
        '🔍 GOOGLE_IMAGE_SEARCH: ⚠️ Все ${imageUrls.length} URL не сработали');
    return _createFallbackAndReturn(query);
  }

  Future<File?> _createFallbackAndReturn(String query) async {
    debugPrint('🔍 GOOGLE_IMAGE_SEARCH: Создаем FALLBACK изображение...');
    try {
      final fallback = await createFallbackImage(query);
      debugPrint('🔍 GOOGLE_IMAGE_SEARCH: ✅ Fallback создан: ${fallback.path}');
      debugPrint(
          '🔍 GOOGLE_IMAGE_SEARCH: ========================================');
      return fallback;
    } catch (e) {
      debugPrint('🔍 GOOGLE_IMAGE_SEARCH: ❌ Не удалось создать fallback: $e');
      debugPrint(
          '🔍 GOOGLE_IMAGE_SEARCH: ========================================');
      return null;
    }
  }

  Stream<File> streamImages({
    required String baseName,
    required String? cityName,
    required String? countryName,
    required List<String> searchSuffixes,
    int maxImages = 8,
  }) async* {
    debugPrint('🖼️ STREAM_IMAGE: ===== СТРИМИНГ ИЗОБРАЖЕНИЙ =====');
    debugPrint('🖼️ STREAM_IMAGE: Название: "$baseName"');
    debugPrint('🖼️ STREAM_IMAGE: Город: $cityName, Страна: $countryName');

    final Set<String> usedUrls = {};
    int foundCount = 0;

    for (int i = 0; i < searchSuffixes.length && foundCount < maxImages; i++) {
      final suffix = searchSuffixes[i];
      final query = _buildPreciseQuery(baseName, cityName, countryName, suffix);

      debugPrint('🖼️ STREAM_IMAGE: [$i] Запрос: "$query"');

      try {
        final urls = await _searchPreciseImageUrls(query, count: 5);

        for (final url in urls) {
          if (usedUrls.contains(url)) continue;
          if (foundCount >= maxImages) break;

          final file = await _downloadImage(url, baseName, suffix);
          if (file != null) {
            foundCount++;
            usedUrls.add(url);
            debugPrint(
                '🖼️ STREAM_IMAGE: ✅ Отдаём фото $foundCount/$maxImages');
            yield file;
            break;
          }
        }
      } catch (e) {
        debugPrint('🖼️ STREAM_IMAGE: ⚠️ Ошибка категории "$suffix": $e');
      }
    }

    if (foundCount == 0) {
      debugPrint('🖼️ STREAM_IMAGE: ⚠️ Создаём fallback');
      final fallback = await createFallbackImage(baseName);
      yield fallback;
    }

    debugPrint('🖼️ STREAM_IMAGE: ===== ЗАВЕРШЕНО: $foundCount фото =====');
  }

  String _buildPreciseQuery(
    String baseName,
    String? cityName,
    String? countryName,
    String suffix,
  ) {
    final parts = <String>[];

    parts.add('"$baseName"');

    if (cityName != null && cityName.isNotEmpty) {
      parts.add(cityName);
    }
    if (countryName != null && countryName.isNotEmpty) {
      parts.add(countryName);
    }

    if (suffix.isNotEmpty) {
      parts.add(suffix);
    }

    return parts.join(' ');
  }

  Future<List<String>> _searchPreciseImageUrls(String query,
      {int count = 5}) async {
    if (_apiKey == null || _searchEngineId == null) {
      return [];
    }

    try {
      final url = Uri.https('www.googleapis.com', '/customsearch/v1', {
        'key': _apiKey,
        'cx': _searchEngineId,
        'q': query,
        'searchType': 'image',
        'num': count.toString(),
        'imgSize': 'large',
        'imgType': 'photo',
        'safe': 'active',
      });

      final response = await http.get(url).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Timeout'),
          );

      if (response.statusCode != 200) {
        return [];
      }

      final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final items = jsonResponse['items'] as List<dynamic>?;

      if (items == null || items.isEmpty) {
        return [];
      }

      final blockedDomains = [
        'lookaside.fbsbx.com',
        'facebook.com',
        'fbcdn.net',
        'instagram.com',
        'cdninstagram.com',
        'pinterest.com',
        'pinimg.com',
        'shutterstock.com',
        'depositphotos.com',
        'istockphoto.com',
        'gettyimages.com',
        'alamy.com',
        'dreamstime.com',
        '123rf.com',
        'freepik.com',
        'vectorstock.com',
        'stock.adobe.com',
      ];

      return items
          .map<String>((item) => item['link'] as String)
          .where((url) => !blockedDomains.any((d) => url.contains(d)))
          .take(count)
          .toList();
    } catch (e) {
      debugPrint('🖼️ PRECISE_SEARCH: Ошибка: $e');
      return [];
    }
  }

  Future<File?> _downloadImage(
      String url, String baseName, String suffix) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 6),
            onTimeout: () => throw Exception('Timeout'),
          );

      if (response.statusCode != 200 || response.bodyBytes.length < 1000) {
        return null;
      }

      final String sanitizedName = baseName
          .toLowerCase()
          .replaceAll(RegExp(r'[^а-яёa-z0-9]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final String sanitizedSuffix = suffix
          .split(' ')
          .first
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z]'), '');
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'attraction_${sanitizedName}_${sanitizedSuffix}_$timestamp.jpg';
      final filePath = path.join(directory.path, fileName);

      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      return file;
    } catch (e) {
      return null;
    }
  }
}
