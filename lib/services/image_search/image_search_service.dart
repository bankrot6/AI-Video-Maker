import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Интерфейс для сервиса поиска изображений
abstract class ImageSearchService {
  /// Поиск URL изображения по запросу
  ///
  /// Возвращает URL первого найденного изображения или null, если изображение не найдено
  Future<String?> searchImageUrl(String query);

  /// Поиск URLs нескольких изображений по запросу
  ///
  /// [query] - поисковый запрос
  /// [count] - максимальное количество результатов
  ///
  /// Возвращает список URL найденных изображений
  Future<List<String>> searchImageUrls(String query, {int count = 5});

  /// Загружает изображение для запроса и сохраняет его в файловой системе
  ///
  /// [query] - поисковый запрос
  ///
  /// Возвращает файл изображения или null, если изображение не найдено
  Future<File?> findImage(String query) async {
    try {
      debugPrint(
          '🔍 IMAGE_SEARCH_SERVICE: Поиск изображения для запроса: "$query"');

      // Получаем URL изображения
      final imageUrl = await searchImageUrl(query);

      if (imageUrl == null) {
        debugPrint(
            '🔍 IMAGE_SEARCH_SERVICE: URL для запроса "$query" не найден');
        return null;
      }

      debugPrint('🔍 IMAGE_SEARCH_SERVICE: Найден URL: $imageUrl');

      // Загружаем изображение
      final response = await http.get(Uri.parse(imageUrl));

      if (response.statusCode != 200) {
        debugPrint(
            '🔍 IMAGE_SEARCH_SERVICE: Ошибка при загрузке изображения. Статус: ${response.statusCode}');
        return null;
      }

      // Формируем имя файла на основе запроса
      final String sanitizedName = query
          .toLowerCase()
          .replaceAll(RegExp(r'[^а-яёa-z0-9]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Получаем директорию для сохранения
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'image_${sanitizedName}_$timestamp.jpg';
      final filePath = path.join(directory.path, fileName);

      // Сохраняем файл
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      debugPrint(
          '🔍 IMAGE_SEARCH_SERVICE: Изображение сохранено: $filePath (${response.bodyBytes.length} байт)');

      return file;
    } catch (e) {
      debugPrint('🔍 IMAGE_SEARCH_SERVICE: Ошибка при поиске изображения: $e');
      return null;
    }
  }
}
