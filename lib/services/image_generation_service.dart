import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:convert';

/// Абстрактный интерфейс для сервисов генерации изображений
abstract class ImageGenerationService {
  /// Генерирует изображение для блюда по названию
  Future<File?> generateImageForDish(String dishName);

  /// Проверяет доступность сервиса
  Future<bool> isAvailable();
}

/// Реализация сервиса генерации изображений с использованием Google Custom Search API
class GoogleImageGenerationService implements ImageGenerationService {
  final String? apiKey;
  final String? cseId;

  GoogleImageGenerationService({this.apiKey, this.cseId});

  @override
  Future<bool> isAvailable() async {
    final available = apiKey != null &&
        apiKey!.isNotEmpty &&
        cseId != null &&
        cseId!.isNotEmpty;

    debugPrint(
        '🔍 GOOGLE_IMAGE_SERVICE: Проверка доступности: apiKey=${apiKey != null && apiKey!.isNotEmpty}, cseId=${cseId != null && cseId!.isNotEmpty}, итог=$available');

    return available;
  }

  @override
  Future<File?> generateImageForDish(String dishName) async {
    try {
      debugPrint(
          '🔍 GOOGLE_IMAGE_SERVICE: Запрос изображения для блюда: $dishName');

      if (!await isAvailable()) {
        debugPrint(
            '🔍 GOOGLE_IMAGE_SERVICE: API ключ или CSE ID отсутствуют. apiKey=${apiKey != null}, cseId=${cseId != null}');
        return null;
      }

      final searchQuery = Uri.encodeComponent('$dishName еда блюдо dish food');
      final url =
          'https://www.googleapis.com/customsearch/v1?key=$apiKey&cx=$cseId&q=$searchQuery&searchType=image&imgSize=large&imgType=photo&num=1';

      debugPrint(
          '🔍 GOOGLE_IMAGE_SERVICE: Отправка запроса на URL: ${url.substring(0, url.length < 100 ? url.length : 100)}...');
      final response = await http.get(Uri.parse(url));

      debugPrint(
          '🔍 GOOGLE_IMAGE_SERVICE: Получен ответ со статусом: ${response.statusCode}');

      if (response.statusCode == 200) {
        // Добавляем логирование тела ответа (только начало для безопасности)
        final responsePreview = response.body.substring(
            0, response.body.length < 200 ? response.body.length : 200);
        debugPrint(
            '🔍 GOOGLE_IMAGE_SERVICE: Предварительный ответ: $responsePreview...');

        // Парсим JSON ответ, используя jsonDecode вместо compute
        final jsonResponse = jsonDecode(response.body) as Map<String, dynamic>;

        // Проверяем, есть ли результаты поиска
        if (jsonResponse.containsKey('items') &&
            jsonResponse['items'] is List &&
            (jsonResponse['items'] as List).isNotEmpty) {
          final items = jsonResponse['items'] as List;
          final imageUrl = items[0]['link'] as String;

          debugPrint(
              '🔍 GOOGLE_IMAGE_SERVICE: Найдено изображение для блюда: $imageUrl');

          // Скачиваем изображение
          final imageResponse = await http.get(Uri.parse(imageUrl));

          if (imageResponse.statusCode == 200) {
            debugPrint(
                '🔍 GOOGLE_IMAGE_SERVICE: Изображение успешно скачано, размер: ${imageResponse.bodyBytes.length} байт');

            // Создаем временный файл для сохранения изображения
            final directory = await getApplicationDocumentsDirectory();
            final String sanitizedName = dishName
                .toLowerCase()
                .replaceAll(RegExp(r'[^а-яёa-z0-9]'), '_')
                .replaceAll(RegExp(r'_+'), '_');
            final fileName =
                'google_${sanitizedName}_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final filePath = path.join(directory.path, fileName);

            // Сохраняем изображение в файл
            final file = File(filePath);
            await file.writeAsBytes(imageResponse.bodyBytes);

            debugPrint(
                '🔍 GOOGLE_IMAGE_SERVICE: Изображение сохранено: $filePath');
            return file;
          } else {
            debugPrint(
                '🔍 GOOGLE_IMAGE_SERVICE: Ошибка при скачивании изображения, статус: ${imageResponse.statusCode}');
          }
        } else {
          debugPrint(
              '🔍 GOOGLE_IMAGE_SERVICE: В ответе отсутствуют элементы "items" или список пуст');
          if (jsonResponse.containsKey('error')) {
            debugPrint(
                '🔍 GOOGLE_IMAGE_SERVICE: Ошибка API: ${jsonResponse['error']}');
          }
        }
      } else {
        debugPrint(
            '🔍 GOOGLE_IMAGE_SERVICE: Неудачный статус ответа: ${response.statusCode}');
        debugPrint('🔍 GOOGLE_IMAGE_SERVICE: Тело ошибки: ${response.body}');
      }

      debugPrint(
          '🔍 GOOGLE_IMAGE_SERVICE: Не удалось найти изображение через Google API, статус код: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('🔍 GOOGLE_IMAGE_SERVICE: Ошибка при поиске изображения: $e');
      return null;
    }
  }
}

/// Реализация сервиса генерации программных изображений
class ProgrammaticImageGenerationService implements ImageGenerationService {
  @override
  Future<bool> isAvailable() async {
    return true; // Всегда доступен, так как создает программное изображение
  }

  @override
  Future<File?> generateImageForDish(String dishName) async {
    try {
      // Получаем директорию для временных файлов
      final tempDir = await getApplicationDocumentsDirectory();
      final String sanitizedName = dishName
          .toLowerCase()
          .replaceAll(RegExp(r'[^а-яёa-z0-9]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final fileName =
          'programmatic_${sanitizedName}_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = path.join(tempDir.path, fileName);

      // Создаем изображение с градиентным фоном и текстом
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(400, 300);

      // Рисуем градиентный фон
      final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);
      final gradient = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.blue.shade100,
          Colors.green.shade100,
        ],
      );
      final paint = Paint()..shader = gradient.createShader(rect);
      canvas.drawRect(rect, paint);

      // Добавляем декоративный элемент (круг)
      final circlePaint = Paint()
        ..color = Colors.white.withOpacity(0.2)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.2),
          size.width * 0.15, circlePaint);

      // Рисуем текст блюда с тенью
      final textPainter = TextPainter(
        text: TextSpan(
          text: dishName,
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 32,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.3),
                offset: const Offset(2, 2),
                blurRadius: 3,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout(maxWidth: size.width - 40);
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );

      // Добавляем небольшое описание под названием
      final descriptionPainter = TextPainter(
        text: TextSpan(
          text: 'Автоматически созданное изображение',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      descriptionPainter.layout(maxWidth: size.width - 40);
      descriptionPainter.paint(
        canvas,
        Offset(
          (size.width - descriptionPainter.width) / 2,
          (size.height - textPainter.height) / 2 + textPainter.height + 8,
        ),
      );

      // Получаем изображение из рекордера
      final picture = recorder.endRecording();
      final img =
          await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await img.toByteData(format: ImageByteFormat.png);

      if (byteData == null) {
        debugPrint('❌ Не удалось создать данные изображения');
        return null;
      }

      // Записываем созданное изображение в файл
      final imageFile = File(filePath);
      await imageFile.parent.create(recursive: true);
      await imageFile.writeAsBytes(
          byteData.buffer
              .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
          flush: true);

      debugPrint('✅ Создано программное изображение блюда: $filePath');

      // Возвращаем созданный файл
      return imageFile;
    } catch (e) {
      debugPrint('❌ Ошибка при создании программного изображения: $e');
      return null;
    }
  }
}

/// Фабрика для создания сервисов генерации изображений
class ImageGenerationServiceFactory {
  /// Создает сервис Google Custom Search
  static ImageGenerationService createGoogleService(
      {String? apiKey, String? cseId}) {
    return GoogleImageGenerationService(apiKey: apiKey, cseId: cseId);
  }

  /// Создает программный сервис генерации изображений
  static ImageGenerationService createProgrammaticService() {
    return ProgrammaticImageGenerationService();
  }
}

/// Композитный сервис генерации изображений, пытающийся использовать несколько стратегий
class CompositeImageGenerationService implements ImageGenerationService {
  final List<ImageGenerationService> _services;

  CompositeImageGenerationService(this._services) {
    debugPrint(
        '🔍 COMPOSITE_IMAGE_SERVICE: Инициализация с ${_services.length} сервисами:');
    for (int i = 0; i < _services.length; i++) {
      debugPrint(
          '🔍 COMPOSITE_IMAGE_SERVICE: Сервис #$i: ${_services[i].runtimeType}');
    }
  }

  @override
  Future<bool> isAvailable() async {
    for (final service in _services) {
      if (await service.isAvailable()) {
        debugPrint(
            '🔍 COMPOSITE_IMAGE_SERVICE: Найден доступный сервис: ${service.runtimeType}');
        return true;
      }
    }
    debugPrint('🔍 COMPOSITE_IMAGE_SERVICE: Нет доступных сервисов');
    return false;
  }

  @override
  Future<File?> generateImageForDish(String dishName) async {
    debugPrint(
        '🔍 COMPOSITE_IMAGE_SERVICE: Запрос изображения для блюда: $dishName');

    for (final service in _services) {
      debugPrint(
          '🔍 COMPOSITE_IMAGE_SERVICE: Проверка сервиса: ${service.runtimeType}');

      if (await service.isAvailable()) {
        debugPrint(
            '🔍 COMPOSITE_IMAGE_SERVICE: Сервис ${service.runtimeType} доступен, пытаемся получить изображение');

        final result = await service.generateImageForDish(dishName);

        if (result != null) {
          debugPrint(
              '🔍 COMPOSITE_IMAGE_SERVICE: Успешно получено изображение с помощью ${service.runtimeType}: ${result.path}');
          return result;
        } else {
          debugPrint(
              '🔍 COMPOSITE_IMAGE_SERVICE: Сервис ${service.runtimeType} не смог найти изображение, переход к следующему');
        }
      } else {
        debugPrint(
            '🔍 COMPOSITE_IMAGE_SERVICE: Сервис ${service.runtimeType} недоступен, пропускаем');
      }
    }
    debugPrint(
        '🔍 COMPOSITE_IMAGE_SERVICE: Все сервисы проверены, изображение не найдено');
    return null;
  }
}
