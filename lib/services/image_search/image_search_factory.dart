import 'package:flutter/foundation.dart';

import 'image_search_service.dart';
import 'google_image_search_service.dart';

/// Фабрика для создания сервисов поиска изображений
class ImageSearchFactory {
  /// Создает экземпляр сервиса поиска изображений Google
  static ImageSearchService create() {
    debugPrint('🔍 ImageSearchFactory: Используем Google Custom Search API');
    return GoogleImageSearchService();
  }

  /// Создает экземпляр сервиса поиска изображений Google с указанными API ключом и ID поисковой системы
  static ImageSearchService createWithCredentials({
    required String apiKey,
    required String searchEngineId,
  }) {
    debugPrint(
        '🔍 ImageSearchFactory: Используем Google Custom Search API с указанными ключами');
    return GoogleImageSearchService(
      apiKey: apiKey,
      searchEngineId: searchEngineId,
    );
  }
}
