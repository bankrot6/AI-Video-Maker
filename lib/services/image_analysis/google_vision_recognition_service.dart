import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as math;

import 'image_recognition_service.dart';

/// Реализация сервиса распознавания изображений с использованием Google Cloud Vision API
class GoogleVisionRecognitionService implements ImageRecognitionService {
  /// API ключ для Google Cloud Vision
  final String apiKey;

  /// Базовый URL для Google Cloud Vision API
  final String baseUrl;

  /// Список категорий для фильтрации результатов поиска
  final List<String> foodCategories;

  /// Максимальное число регионов для углубленного анализа (кропов)
  final int maxRegionCrops;

  GoogleVisionRecognitionService({
    String? apiKey,
    String? baseUrl,
    List<String>? foodCategories,
    int maxRegionCrops = 1,
  })  : apiKey = apiKey ?? dotenv.env['GOOGLE_CLOUD_VISION_API_KEY'] ?? '',
        baseUrl = baseUrl ?? 'https://vision.googleapis.com/v1/images:annotate',
        foodCategories = foodCategories ??
            [
              'Food',
              'Cuisine',
              'Dish',
              'Meal',
              'Ingredient',
              'Fruit',
              'Vegetable',
              'Meat',
              'Dessert',
              'Baked good',
              'Breakfast'
            ],
        maxRegionCrops = maxRegionCrops;

  @override
  Future<List<RecognizedObject>> recognizeObjects(File imageFile) async {
    try {
      // Проверка API ключа
      if (apiKey.isEmpty) {
        throw Exception('Google Cloud Vision API key is not provided');
      }

      // Конвертация изображения в base64
      final List<int> imageBytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      // Формирование первичного запроса: общие лейблы + локализация объектов
      final response = await http.post(
        Uri.parse('$baseUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'requests': [
            {
              'image': {'content': base64Image},
              'features': [
                {'type': 'LABEL_DETECTION', 'maxResults': 15},
                {'type': 'OBJECT_LOCALIZATION', 'maxResults': 10}
              ],
            }
          ]
        }),
      );

      // Обработка ответа
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        // Парсим первичный ответ
        final initialObjects = _parseGoogleVisionResponse(data);

        // Попробуем углубленный анализ по регионам (если есть локализованные области)
        final List<Map<String, dynamic>> localizedObjects =
            _extractLocalizedObjects(data);

        if (localizedObjects.isNotEmpty) {
          final regionObjects = await _analyzeRegions(
            imageFile,
            localizedObjects,
          );
          // Объединяем результаты
          initialObjects.addAll(regionObjects);
        }

        // Возвращаем объединенный список
        return initialObjects;
      } else {
        throw Exception('Failed to recognize objects: ${response.body}');
      }
    } catch (e) {
      // Логирование ошибки
      debugPrint('Error in recognizeObjects: $e');
      // Возвращаем пустой список в случае ошибки
      return [];
    }
  }

  /// Парсит ответ от Google Cloud Vision API и преобразует его в список объектов RecognizedObject
  List<RecognizedObject> _parseGoogleVisionResponse(Map<String, dynamic> data) {
    final List<RecognizedObject> objects = [];

    // Проверяем наличие результатов
    if (data.containsKey('responses') && data['responses'].isNotEmpty) {
      final Map<String, dynamic> response = data['responses'][0];

      // Обработка лейблов
      if (response.containsKey('labelAnnotations')) {
        final List<dynamic> labels = response['labelAnnotations'];
        for (final label in labels) {
          objects.add(RecognizedObject(
            label: label['description'],
            confidence: label['score'].toDouble(),
            metadata: {'type': 'label'},
          ));
        }
      }

      // Обработка объектов локализации
      if (response.containsKey('localizedObjectAnnotations')) {
        final List<dynamic> localizedObjects =
            response['localizedObjectAnnotations'];
        for (final object in localizedObjects) {
          objects.add(RecognizedObject(
            label: object['name'],
            confidence: object['score'].toDouble(),
            metadata: {
              'type': 'object',
              'boundingPoly': object['boundingPoly'],
            },
          ));
        }
      }
    }

    // Сортируем по убыванию уверенности распознавания
    objects.sort((a, b) => b.confidence.compareTo(a.confidence));

    return objects;
  }

  /// Извлекает локализованные объекты из ответа Vision
  List<Map<String, dynamic>> _extractLocalizedObjects(
      Map<String, dynamic> data) {
    if (!data.containsKey('responses') || data['responses'].isEmpty) {
      return [];
    }
    final Map<String, dynamic> response = data['responses'][0];
    if (!response.containsKey('localizedObjectAnnotations')) {
      return [];
    }
    final List<dynamic> raw = response['localizedObjectAnnotations'];
    return raw.cast<Map<String, dynamic>>();
  }

  /// Выполняет повторный LABEL_DETECTION для верхних N регионов (по bounding box)
  Future<List<RecognizedObject>> _analyzeRegions(
    File imageFile,
    List<Map<String, dynamic>> localizedObjects,
  ) async {
    try {
      // Декодируем изображение один раз
      final bytes = await imageFile.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return [];
      }

      final int width = decoded.width;
      final int height = decoded.height;

      // Отсортируем по score и отфильтруем пересекающиеся боксы
      final sorted = [...localizedObjects]
        ..sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));

      final List<Map<String, dynamic>> selected = [];
      Rect? lastRect;
      for (final obj in sorted) {
        final rect = _polyToRect(obj['boundingPoly'], width, height);
        if (rect == null) continue;
        // Отбрасываем слишком маленькие области (<5% площади)
        final areaRatio = (rect.w * rect.h) / (width * height);
        if (areaRatio < 0.05) continue;
        // Избегаем сильного перекрытия (>0.6 IoU) с уже выбранной областью
        if (lastRect != null && _iou(rect, lastRect) > 0.6) {
          continue;
        }
        selected.add(obj);
        lastRect = rect;
        // Ограничиваем количество регионов согласно настройке
        if (selected.length >= maxRegionCrops) break;
      }

      if (selected.isEmpty) return [];

      // Готовим кропы и батчим запросы к Vision для LABEL_DETECTION
      final List<String> cropsBase64 = [];
      for (final obj in selected) {
        final rect = _polyToRect(obj['boundingPoly'], width, height);
        if (rect == null) continue;
        // Небольшое расширение рамки на 5%
        final int x = math.max(0, rect.x - (rect.w * 0.05).round());
        final int y = math.max(0, rect.y - (rect.h * 0.05).round());
        final int w = math.min(width - x, (rect.w * 1.1).round());
        final int h = math.min(height - y, (rect.h * 1.1).round());

        final img.Image crop =
            img.copyCrop(decoded, x: x, y: y, width: w, height: h);
        final List<int> jpg = img.encodeJpg(crop, quality: 90);
        cropsBase64.add(base64Encode(jpg));
      }

      if (cropsBase64.isEmpty) return [];

      final request = {
        'requests': cropsBase64
            .map((b64) => {
                  'image': {'content': b64},
                  'features': [
                    {'type': 'LABEL_DETECTION', 'maxResults': 10}
                  ],
                })
            .toList(),
      };

      final regionResponse = await http.post(
        Uri.parse('$baseUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request),
      );

      if (regionResponse.statusCode != 200) {
        debugPrint(
            'Error in region analysis: ${regionResponse.statusCode} ${regionResponse.body}');
        return [];
      }

      final Map<String, dynamic> resp = jsonDecode(regionResponse.body);
      final List<RecognizedObject> regionObjects = [];
      if (resp.containsKey('responses')) {
        final List<dynamic> responses = resp['responses'];
        for (int i = 0; i < responses.length; i++) {
          final r = responses[i] as Map<String, dynamic>;
          if (!r.containsKey('labelAnnotations')) continue;
          final List<dynamic> labels = r['labelAnnotations'];
          for (final label in labels) {
            regionObjects.add(RecognizedObject(
              label: label['description'],
              confidence: (label['score'] as num).toDouble(),
              metadata: {
                'type': 'region_label',
                'regionIndex': i,
              },
            ));
          }
        }
      }

      // Отсортируем по уверенности
      regionObjects.sort((a, b) => b.confidence.compareTo(a.confidence));
      return regionObjects;
    } catch (e) {
      debugPrint('Error in _analyzeRegions: $e');
      return [];
    }
  }

  /// Преобразует boundingPoly (normalizedVertices/vertices) в прямоугольник
  Rect? _polyToRect(Map<String, dynamic>? poly, int width, int height) {
    if (poly == null) return null;
    List<dynamic>? verts = poly['normalizedVertices'] ?? poly['vertices'];
    if (verts == null || verts.isEmpty) return null;
    double minX = double.infinity,
        minY = double.infinity,
        maxX = double.negativeInfinity,
        maxY = double.negativeInfinity;
    for (final v in verts) {
      final double x = (v['x'] is num)
          ? (poly['normalizedVertices'] != null
              ? (v['x'] as num).toDouble() * width
              : (v['x'] as num).toDouble())
          : 0.0;
      final double y = (v['y'] is num)
          ? (poly['normalizedVertices'] != null
              ? (v['y'] as num).toDouble() * height
              : (v['y'] as num).toDouble())
          : 0.0;
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    final int x = math.max(0, minX.round());
    final int y = math.max(0, minY.round());
    final int w = math.max(1, (maxX - minX).round());
    final int h = math.max(1, (maxY - minY).round());
    return Rect(x, y, w, h);
  }

  double _iou(Rect a, Rect b) {
    final int x1 = math.max(a.x, b.x);
    final int y1 = math.max(a.y, b.y);
    final int x2 = math.min(a.x + a.w, b.x + b.w);
    final int y2 = math.min(a.y + a.h, b.y + b.h);
    final int interW = math.max(0, x2 - x1);
    final int interH = math.max(0, y2 - y1);
    final int inter = interW * interH;
    final int union = a.w * a.h + b.w * b.h - inter;
    if (union == 0) return 0.0;
    return inter / union;
  }

  @override
  Future<String?> identifyFoodName(List<RecognizedObject> objects) async {
    if (objects.isEmpty) {
      return null;
    }
    final List<RecognizedObject> foodObjects = objects
        .where((obj) => obj.confidence > 0.7 && _isFoodRelated(obj.label))
        .toList();

    if (foodObjects.isEmpty) {
      debugPrint('🍽️ Еда не распознана в изображении');
      return null;
    }
    return foodObjects.first.label;
  }

  bool _isFoodRelated(String label) {
    final lowerLabel = label.toLowerCase();
    return foodCategories
        .any((category) => lowerLabel.contains(category.toLowerCase()));
  }
}

class Rect {
  final int x;
  final int y;
  final int w;
  final int h;
  Rect(this.x, this.y, this.w, this.h);
}
