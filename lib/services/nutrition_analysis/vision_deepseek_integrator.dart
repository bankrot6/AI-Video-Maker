import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/nutrition_info.dart';
import '../image_analysis/image_analysis_service.dart';
import '../nutrition_service.dart';
import '../../models/meal_model.dart';
import '../../services/localization/app_localization_service.dart';

// Константы для локализации
// TODO: Заменить на использование правильной локализации, когда будет исправлена
const String _NOT_FOOD = "Не еда";
const String _NO_FOOD_DETECTED =
    "На изображении не обнаружены пищевые продукты";
const String _DISH_ON_PHOTO = "Блюдо на фотографии";
const String _UNKNOWN_DISH = "Неопознанное блюдо";
const String _NOT_RELATED_TO_FOOD =
    "Запрос не относится к еде или продуктам питания";
const String _ANALYZE_NUTRITIONAL_VALUE =
    "Проанализируй питательную ценность блюда '{0}'";
const String _DETECTED_OBJECTS = "Распознаны следующие объекты: {0}";
const String _PRELIMINARY_ASSESSMENT =
    "Предварительная оценка питательной ценности:";
const String _CALORIES_VALUE = "калории: {0} ккал";
const String _PROTEINS_VALUE = "белки: {0} г";
const String _FATS_VALUE = "жиры: {0} г";
const String _CARBS_VALUE = "углеводы: {0} г";
const String _DETERMINE_DISH_DETAILS =
    "Определи точное название блюда и его нутриционную ценность, используя все предоставленные данные. Верни название блюда, калории (ккал), белки (г), жиры (г), углеводы (г) и список основных ингредиентов с весом в граммах.";
const String _DISH_ANALYSIS_REGION_RU =
    "Учти особенности русской кухни и порций.";
const String _DISH_ANALYSIS_REGION_EN =
    "Consider specifics of international cuisine and portion sizes.";
const String _ANALYZE_SIMPLE =
    "Проанализируй питательную ценность блюда '{0}'. Определи калории, белки, жиры, углеводы и основные ингредиенты.";
const String _DETERMINE_NUTRITIONAL_VALUE = "Определи питательную ценность:";

/// Вспомогательная функция для замены параметров в строке
String _replaceParams(String text, dynamic param) {
  if (param is String) {
    return text.replaceAll('{0}', param);
  } else if (param is num) {
    return text.replaceAll('{0}', param.toString());
  }
  return text;
}

/// Класс для хранения запросов в процессе выполнения
class _RequestTracker {
  final Map<String, Future<NutritionInfo>> _requests = {};

  /// Генерирует уникальный ключ для запроса на основе путь файла или хэша байтов
  String _generateKey(dynamic input) {
    if (input is File) {
      return 'file:${input.path}';
    } else if (input is Uint8List) {
      return 'bytes:${input.length}:${input.hashCode}';
    }
    return 'unknown:${input.hashCode}';
  }

  /// Проверяет, выполняется ли уже такой запрос
  Future<NutritionInfo>? checkOngoingRequest(dynamic input) {
    final key = _generateKey(input);
    return _requests[key];
  }

  /// Добавляет запрос в список выполняющихся
  Future<NutritionInfo> trackRequest(
      dynamic input, Future<NutritionInfo> future) {
    final key = _generateKey(input);
    _requests[key] = future;
    future.whenComplete(() => _requests.remove(key));
    return future;
  }
}

/// Интегратор сервисов Google Vision и DeepSeek для анализа изображений
class VisionDeepSeekIntegrator {
  final NutritionService _nutritionService;
  final ImageAnalysisService? _imageAnalysisService;
  final bool _useVision;
  final _RequestTracker _requestTracker = _RequestTracker();

  VisionDeepSeekIntegrator({
    required NutritionService nutritionService,
    ImageAnalysisService? imageAnalysisService,
    bool useVision = true,
  })  : _nutritionService = nutritionService,
        _imageAnalysisService = imageAnalysisService,
        _useVision = useVision;

  /// Создает интегратор, который будет использовать только DeepSeek
  /// без предварительной обработки через Google Cloud Vision
  factory VisionDeepSeekIntegrator.deepSeekOnly({
    required NutritionService nutritionService,
  }) {
    return VisionDeepSeekIntegrator._internal(
      nutritionService: nutritionService,
      useVision: false,
    );
  }

  /// Внутренний конструктор для создания интегратора с опциональным использованием Vision
  VisionDeepSeekIntegrator._internal({
    required NutritionService nutritionService,
    bool useVision = true,
  })  : _imageAnalysisService = null,
        _nutritionService = nutritionService,
        _useVision = useVision;

  /// Анализирует изображение с помощью Google Vision и DeepSeek
  Future<NutritionInfo> analyzeImageWithVisionAndDeepSeek(
      File imageFile, BuildContext context) async {
    try {
      debugPrint(
          '🔄 VISION_INTEGRATOR: ===== НАЧАЛО ИНТЕГРАЦИИ VISION + DEEPSEEK =====');
      debugPrint('🔄 VISION_INTEGRATOR: Изображение: ${imageFile.path}');

      // Если Vision отключен, используем только DeepSeek для текстового анализа
      if (!_useVision) {
        debugPrint(
            '📡 VISION_INTEGRATOR: Vision отключен, используем анализ через текст');
        // Возвращаем пустой результат, так как мы не можем определить название блюда
        return NutritionInfo.empty();
      }

      debugPrint('🔄 VISION_INTEGRATOR: ===== ЭТАП 1: GOOGLE VISION API =====');
      debugPrint(
          '🔄 VISION_INTEGRATOR: Отправляем изображение в Google Vision для распознавания объектов');

      // Шаг 1: Распознаем объекты на изображении с помощью Google Vision
      final visionResult = await _imageAnalysisService!.analyzeFood(imageFile);

      if (visionResult.detectedLabels.isEmpty) {
        debugPrint(
            '⚠️ VISION_INTEGRATOR: Не удалось распознать объекты на изображении');
        return NutritionInfo.empty();
      }

      debugPrint(
          '✅ VISION_INTEGRATOR: Google Vision распознал объекты: ${visionResult.detectedLabels.join(", ")}');

      // Проводим базовую фильтрацию очевидно не пищевых объектов
      List<String> filteredLabels =
          _filterFoodLabels(visionResult.detectedLabels);
      // Уберем возможные дубликаты за счет синонимов
      filteredLabels = _mergeSynonymousLabels(filteredLabels);

      if (filteredLabels.isEmpty) {
        debugPrint(
            '⚠️ VISION_INTEGRATOR: На изображении не обнаружены пищевые продукты');
        // Возвращаем объект с ошибкой "не еда"
        return NutritionInfo(
          dishName: context.tr('not_food'),
          calories: 0,
          proteins: 0,
          fats: 0,
          carbs: 0,
          ingredients: [],
          error: context.tr('no_food_detected_on_image'),
        );
      }

      debugPrint(
          '✅ VISION_INTEGRATOR: Отфильтрованы пищевые продукты: ${filteredLabels.join(", ")}');

      // Определяем язык интерфейса для DeepSeek
      final container = ProviderScope.containerOf(context);
      final localizationService =
          container.read(appLocalizationServiceProvider);
      final appLocale = localizationService.getCurrentLanguage();
      final language = appLocale.name;
      debugPrint('✅ VISION_INTEGRATOR: Определен язык интерфейса: $language');

      // Формируем промпт для DeepSeek с инструкцией проверить на еду
      String prompt =
          "${context.tr('analyze_if_food')}: ${filteredLabels.join(", ")}";

      // Если имя блюда известно из Vision, добавляем его в промпт
      if (visionResult.foodName != null && visionResult.foodName!.isNotEmpty) {
        prompt +=
            ". ${context.tr('possible_dish_name')}: ${visionResult.foodName!}";
      }

      // Добавляем инструкцию учитывать несколько блюд на тарелке и не терять гарниры/соусы
      prompt +=
          ". The photo can contain multiple distinct dishes on one plate (e.g., main + side). Identify ALL food items you infer from labels, combine them into a single dishName using short form like 'котлета + картофельное пюре' in the user's language, and calculate nutrition for the WHOLE plate. In the ingredients list include components for each item with reasonable gram weights. Do not omit side dishes or sauces even if they are small. If multiple labels are synonyms or regional names of the same dish (e.g., skordalia vs mashed potatoes vs puree), MERGE them into one item and do not duplicate in the name or ingredients.";

      // Добавляем универсальную инструкцию о языке ответа
      prompt +=
          " Please provide all text fields (dishName, ingredient names, message) in the user's interface language: $language";
      debugPrint(
          '✅ VISION_INTEGRATOR: Добавлено указание предоставить ответ на языке интерфейса: $language');

      debugPrint('🔄 VISION_INTEGRATOR: ===== ЭТАП 2: DEEPSEEK API =====');
      debugPrint(
          '🔄 VISION_INTEGRATOR: НЕ ОТПРАВЛЯЕМ ИЗОБРАЖЕНИЕ! Отправляем только ТЕКСТ от Vision');
      debugPrint(
          '🔄 VISION_INTEGRATOR: Текстовый промпт для DeepSeek: "$prompt"');

      // Отправляем запрос в DeepSeek через NutritionService
      final nutritionInfo =
          await _nutritionService.analyzeDishByName(prompt, context: context);

      // Проверяем результат на несъедобность
      if (nutritionInfo.error != null && nutritionInfo.error!.isNotEmpty) {
        debugPrint(
            '⚠️ VISION_INTEGRATOR: Определен несъедобный объект: ${nutritionInfo.error}');
        return nutritionInfo;
      }

      debugPrint('✅ VISION_INTEGRATOR: ===== ПОЛУЧЕН ОТВЕТ ОТ DEEPSEEK =====');
      debugPrint(
          '✅ VISION_INTEGRATOR: Результат DeepSeek: ${nutritionInfo.dishName}');

      // Сохраняем путь к изображению в результатах
      final updatedInfo = nutritionInfo.copyWith(imagePath: imageFile.path);

      debugPrint(
          '✅ VISION_INTEGRATOR: ===== ИНТЕГРАЦИЯ ЗАВЕРШЕНА УСПЕШНО =====');
      debugPrint(
          '✅ VISION_INTEGRATOR: Финальный результат: ${updatedInfo.dishName}');

      return updatedInfo;
    } catch (e) {
      debugPrint('❌ VISION_INTEGRATOR: Ошибка при анализе: $e');
      return NutritionInfo.empty();
    }
  }

  /// Потоково анализирует изображение: сперва Vision, затем текстовый DeepSeek с потоковой отдачей
  Stream<NutritionInfo> analyzeImageWithVisionAndDeepSeekStream(
      File imageFile, BuildContext context) async* {
    try {
      if (!_useVision) {
        yield NutritionInfo.empty();
        return;
      }

      // Step 1: Vision
      final visionResult = await _imageAnalysisService!.analyzeFood(imageFile);

      if (visionResult.detectedLabels.isEmpty) {
        yield NutritionInfo(
          dishName: context.tr('not_food'),
          calories: 0,
          proteins: 0,
          fats: 0,
          carbs: 0,
          ingredients: const [],
          error: context.tr('no_food_detected_on_image'),
        );
        return;
      }

      var filteredLabels = _filterFoodLabels(visionResult.detectedLabels);
      filteredLabels = _mergeSynonymousLabels(filteredLabels);
      if (filteredLabels.isEmpty) {
        yield NutritionInfo(
          dishName: context.tr('not_food'),
          calories: 0,
          proteins: 0,
          fats: 0,
          carbs: 0,
          ingredients: const [],
          error: context.tr('no_food_detected_on_image'),
        );
        return;
      }

      // Do not emit interim Vision data. Show only real DeepSeek stream later.

      // Step 2: DeepSeek streaming
      // Build prompt similar to non-stream method
      String prompt =
          "${context.tr('analyze_if_food')}: ${filteredLabels.join(", ")}";
      if (visionResult.foodName != null && visionResult.foodName!.isNotEmpty) {
        prompt +=
            ". ${context.tr('possible_dish_name')}: ${visionResult.foodName!}";
      }

      final container = ProviderScope.containerOf(context);
      final localizationService =
          container.read(appLocalizationServiceProvider);
      final language = localizationService.getCurrentLanguage().name;
      prompt +=
          ". The photo can contain multiple distinct dishes on one plate (e.g., main + side). Identify ALL food items you infer from labels, combine them into a single dishName using short form like 'котлета + картофельное пюре' in the user's language, and calculate nutrition for the WHOLE plate. In the ingredients list include components for each item with reasonable gram weights. Do not omit side dishes or sauces even if they are small. If multiple labels are synonyms or regional names of the same dish (e.g., skordalia vs mashed potatoes vs puree), MERGE them into one item and do not duplicate in the name or ingredients. Please provide all text fields (dishName, ingredient names, message) in the user's interface language: $language";

      // Delegate to nutrition service streaming
      // We don't have direct reference here, so reuse _nutritionService streaming via fast path
      // Use NutritionService API (DeepSeekNutritionAnalyzer under the hood)
      await for (final partial in _nutritionService
          .analyzeDishByNameStream(prompt, context: context)) {
        // Ensure image path is attached
        yield partial.copyWith(imagePath: imageFile.path);
      }
    } catch (e) {
      debugPrint('❌ VISION_INTEGRATOR: Streaming error: $e');
      yield NutritionInfo.empty();
    }
  }

  /// Фильтрует метки объектов, оставляя только связанные с едой
  List<String> _filterFoodLabels(List<String> labels) {
    // Простая фильтрация на основе черного списка
    final blacklist = [
      'person',
      'human',
      'man',
      'woman',
      'device',
      'electronic',
      'furniture',
      'building',
      'vehicle',
      'car',
      'airplane',
      'electronic device',
      'computer',
      'table',
      'chair',
      'phone',
      'smartphone',
      'clothing',
      'apparel',
      'outfit',
      'dress',
      'shoe',
      'accessory'
    ];

    // Фильтруем, исключая метки из черного списка
    return labels.where((label) {
      for (final blackWord in blacklist) {
        if (label.toLowerCase().contains(blackWord.toLowerCase())) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Объединяет синонимичные метки (например: mashed potatoes, puree, skordalia)
  /// чтобы избежать двойного учета одного и того же блюда
  List<String> _mergeSynonymousLabels(List<String> labels) {
    // Карта групп синонимов: ключ — каноническое название (на англ., т.к. Vision отдает EN)
    // Значения — набор возможных вариантов
    final Map<String, Set<String>> synonymGroups = {
      'mashed potatoes': {
        'mashed potatoes',
        'mashed potato',
        'potato puree',
        'potato purée',
        'puree',
        'purée',
        'skordalia',
        'instant mashed potatoes',
      },
      // Можно расширять новыми группами при необходимости
    };

    final Set<String> result = <String>{};
    final Set<String> alreadyCovered = <String>{};
    final List<String> lowerLabels =
        labels.map((e) => e.toLowerCase().trim()).toList();

    for (final label in lowerLabels) {
      if (alreadyCovered.contains(label)) continue;
      bool matched = false;
      for (final MapEntry<String, Set<String>> entry in synonymGroups.entries) {
        if (entry.value.contains(label)) {
          // Добавляем только канонический термин группы
          result.add(entry.key);
          alreadyCovered.addAll(entry.value);
          matched = true;
          break;
        }
      }
      if (!matched) {
        result.add(label);
        alreadyCovered.add(label);
      }
    }

    return result.toList();
  }

  /// Проверяет, содержат ли метки пищевые объекты
  bool _containsFoodLabel(List<String> labels) {
    // Список меток, которые могут быть связаны с пищей
    final foodWhiteList = [
      'food',
      'dish',
      'meal',
      'cuisine',
      'breakfast',
      'lunch',
      'dinner',
      'fruit',
      'vegetable',
      'meat',
      'fish',
      'seafood',
      'bread',
      'bun',
      'roll',
      'soup',
      'salad',
      'pizza',
      'pasta',
      'cake',
      'dessert',
      'snack',
      'sweet',
      'egg',
      'cheese',
      'dairy',
      'rice',
      'noodle',
      'sandwich',
      'burger',
      'steak',
      'sushi',
      'ramen',
      'cutlet',
      'potato',
      'tomato',
      'beef',
      'pork',
      'chicken',
      'lamb',
      'shrimp',
      'crab',
      'lobster',
      'apple',
      'banana',
      'orange',
      'berry',
      'grape',
      'melon',
      'cucumber',
      'carrot',
      'onion',
      'pepper',
      'mushroom',
      'corn',
      'bean',
      'nut',
      'seed',
      'oil',
      'sauce',
      'spice',
      'herb',
      'sugar',
      'honey',
      'milk',
      'yogurt',
      'cream',
      'butter',
      'ice cream',
      'cookie',
      'biscuit',
      'chocolate',
      'candy',
      'jam',
      'jelly',
      'juice',
      'drink',
      'beverage',
      'coffee',
      'tea',
      'wine',
      'beer',
      'liquor',
      'alcohol'
    ];

    // Проверяем, содержит ли хоть одна метка хоть одно пищевое слово
    return labels.any((label) => foodWhiteList
        .any((food) => label.toLowerCase().contains(food.toLowerCase())));
  }

  /// Строит промпт для DeepSeek на основе распознанных объектов
  String _buildDeepSeekPrompt(List<String> foodLabels,
      [BuildContext? context]) {
    if (foodLabels.isEmpty) {
      return context != null ? context.tr('dish_on_photo') : _DISH_ON_PHOTO;
    }

    // Расширенный список непищевых меток, которые нужно исключить
    final nonFoodItems = [
      'food',
      'dish',
      'meal',
      'tableware',
      'plate',
      'serveware',
      'dishware',
      'ingredient',
      'bowl',
      'porcelain',
      'teapot',
      'cutlery',
      'silverware',
      'cup',
      'glass',
      'container',
      'plastic',
      'metal',
      'ceramic'
    ];

    // Общие категории еды, которые не являются конкретными блюдами
    final generalFoodCategories = [
      'recipe',
      'cooking',
      'cuisine',
      'comfort food',
      'staple food',
      'finger food',
      'breakfast',
      'lunch',
      'dinner',
      'snack',
      'dessert'
    ];

    // Разделяем метки на конкретные блюда и общие категории
    List<String> specificDishes = [];
    List<String> generalCategories = [];

    for (final label in foodLabels) {
      if (nonFoodItems.contains(label.toLowerCase())) {
        continue; // Пропускаем непищевые метки
      } else if (generalFoodCategories.any(
          (category) => label.toLowerCase().contains(category.toLowerCase()))) {
        generalCategories.add(label);
      } else {
        specificDishes.add(label);
      }
    }

    // Если есть конкретные блюда, отдаем им приоритет
    if (specificDishes.isNotEmpty) {
      // Берем до 3 конкретных блюд
      final dishesString = specificDishes.take(3).join(", ");
      debugPrint(
          '✅ VISION_INTEGRATOR: Отправляем конкретные блюда: $dishesString');
      return dishesString;
    }

    // Если нет конкретных блюд, используем общие категории
    if (generalCategories.isNotEmpty) {
      final categoriesString = generalCategories.take(3).join(", ");
      debugPrint(
          '✅ VISION_INTEGRATOR: Отправляем общие категории еды: $categoriesString');
      return categoriesString;
    }

    // Если после фильтрации не осталось вообще никаких меток, используем общее название
    return context != null
        ? context.tr('deepseek_unknown_dish')
        : _UNKNOWN_DISH;
  }

  /// Анализирует изображение из байтов, используя сначала Google Cloud Vision для получения
  /// предварительных данных о содержимом, а затем DeepSeek для детального анализа текста
  Future<NutritionInfo> analyzeImageBytesWithVisionAndDeepSeek(
      Uint8List imageBytes,
      [BuildContext? context]) async {
    try {
      // Если Vision отключен, возвращаем пустой результат
      if (!_useVision) {
        debugPrint(
            '📡 VISION_INTEGRATOR: Vision отключен, используем анализ через текст');
        return NutritionInfo.empty();
      }

      // Временно сохраняем изображение в файл для Vision API
      final tempDir = await Directory.systemTemp.createTemp('vision_analysis');
      final tempFile = File('${tempDir.path}/temp_image.jpg');

      // Записываем файл
      await tempFile.writeAsBytes(imageBytes);

      debugPrint(
          '✅ VISION_INTEGRATOR: Временное изображение сохранено: ${tempFile.path}');

      // Получаем данные о содержимом изображения от Google Cloud Vision
      debugPrint(
          '📡 VISION_INTEGRATOR: Отправка изображения в Google Vision API...');

      // Получаем результат от Vision API
      final visionResult = await _imageAnalysisService!.analyzeFood(tempFile);

      debugPrint(
          '✅ VISION_INTEGRATOR: Получены данные от Google Vision: ${visionResult.detectedLabels.length} меток');

      // Удаляем временный файл
      await tempFile.delete();
      await tempDir.delete(recursive: true);
      debugPrint('✅ VISION_INTEGRATOR: Временные файлы удалены');

      // Если не удалось распознать объекты, возвращаем пустой результат
      if (visionResult.detectedLabels.isEmpty &&
          (visionResult.foodName == null || visionResult.foodName!.isEmpty)) {
        debugPrint(
            '⚠️ VISION_INTEGRATOR: Google Vision не распознал объекты, возвращаем пустой результат');

        // Возвращаем результат с сообщением об ошибке
        return NutritionInfo(
          dishName: context != null ? context.tr('not_food') : _NOT_FOOD,
          calories: 0,
          proteins: 0,
          fats: 0,
          carbs: 0,
          ingredients: [],
          error: context != null
              ? context.tr('request_not_related_to_food')
              : _NOT_RELATED_TO_FOOD,
        );
      }

      // Проводим базовую фильтрацию очевидно не пищевых объектов
      List<String> filteredLabels =
          _filterFoodLabels(visionResult.detectedLabels);
      String detectedLabels = filteredLabels.join(', ');

      debugPrint('✅ VISION_INTEGRATOR: Отфильтрованные метки: $detectedLabels');

      // Получаем название блюда, если оно доступно
      String? dishName = visionResult.foodName;
      if (dishName != null && dishName.isNotEmpty) {
        debugPrint('✅ VISION_INTEGRATOR: Название блюда из Vision: $dishName');
      }

      // Получаем информацию о предполагаемых нутриентах из анализа Vision
      final EstimatedNutrients nutrients =
          visionResult.estimatedNutrients != null
              ? visionResult.estimatedNutrients as EstimatedNutrients
              : EstimatedNutrients(
                  calories:
                      visionResult.estimatedNutrients.calories.toDouble() ?? 0,
                  proteins: visionResult.estimatedNutrients.proteins ?? 0,
                  fats: visionResult.estimatedNutrients.fats ?? 0,
                  carbs: visionResult.estimatedNutrients.carbs ?? 0,
                );

      // Определяем язык интерфейса для DeepSeek
      String interfaceLanguage = "en";
      if (context != null) {
        // Получаем локализационный сервис через Provider
        final container = ProviderScope.containerOf(context);
        final localizationService =
            container.read(appLocalizationServiceProvider);
        final appLocale = localizationService.getCurrentLanguage();
        interfaceLanguage = appLocale.name;
        debugPrint(
            '✅ VISION_INTEGRATOR: Определен язык интерфейса: $interfaceLanguage');
      }

      // Формируем промпт для DeepSeek с инструкцией определить, является ли что-то едой
      String prompt;
      if (context != null) {
        prompt = "${context.tr('analyze_if_food')}: $detectedLabels";
        if (dishName != null && dishName.isNotEmpty) {
          prompt += ". ${context.tr('possible_dish_name')}: $dishName";
        }

        // Добавляем информацию о нутриентах, если они доступны
        if (nutrients.calories > 0 ||
            nutrients.proteins > 0 ||
            nutrients.fats > 0 ||
            nutrients.carbs > 0) {
          prompt +=
              ". ${context.tr('preliminary_nutritional_value_assessment')}";
        }
      } else {
        prompt = "Определи, является ли что-то из этого едой: $detectedLabels";
        if (dishName != null && dishName.isNotEmpty) {
          prompt += ". Возможное название блюда: $dishName";
        }
      }

      // Добавляем универсальную инструкцию о языке ответа
      prompt +=
          " Please provide all text fields (dishName, ingredient names, message) in the user's interface language: $interfaceLanguage";
      debugPrint(
          '✅ VISION_INTEGRATOR: Добавлено указание предоставить ответ на языке интерфейса: $interfaceLanguage');

      debugPrint(
          '📡 VISION_INTEGRATOR: Отправка всех меток в DeepSeek: $prompt');

      // Получаем результат от DeepSeek через текстовый запрос
      final enrichedResult =
          await _nutritionService.analyzeDishByName(prompt, context: context);

      // Проверяем, нет ли ошибки в результате DeepSeek
      if (enrichedResult.error != null && enrichedResult.error!.isNotEmpty) {
        debugPrint(
            '⚠️ VISION_INTEGRATOR: DeepSeek вернул ошибку: ${enrichedResult.error}');
        return enrichedResult;
      }

      debugPrint('✅ VISION_INTEGRATOR: Получен результат анализа от DeepSeek');
      return enrichedResult;
    } catch (e) {
      debugPrint(
          '❌ VISION_INTEGRATOR: Ошибка при интеграции Vision и DeepSeek: ${e.toString()}');
      // Если произошла ошибка, возвращаем пустой результат
      return NutritionInfo.empty();
    }
  }

  /// Этот метод оставлен для обратной совместимости и может быть удален в будущем
  Future<NutritionInfo> analyzeImageWithEstimatedNutrition(File imageFile,
      double? calories, double? proteins, double? fats, double? carbs,
      [BuildContext? context]) async {
    try {
      // Если есть предварительные оценки питательной ценности, формируем обогащенный промпт
      final imageAnalysisResult =
          await _imageAnalysisService!.analyzeFood(imageFile);

      // Преобразуем результат в VisionResult
      final visionResult =
          VisionResult.fromImageAnalysisResult(imageAnalysisResult);

      // Объединяем метки
      final String detectedLabels = visionResult.detectedLabels.join(', ');

      // Получаем название блюда
      final String? dishName = visionResult.foodName;

      if (dishName == null) {
        debugPrint(
            '⚠️ VISION_INTEGRATOR: Название блюда не определено, возвращаем пустой результат');
        return NutritionInfo.empty();
      }

      // Создаем объект для примерных нутриентов
      final EstimatedNutrients estimatedNutrients = EstimatedNutrients(
        calories: calories ?? 0,
        proteins: proteins ?? 0,
        fats: fats ?? 0,
        carbs: carbs ?? 0,
      );

      // Формируем обогащенный промпт
      final String enrichedPrompt = _buildEnrichedPrompt(
          detectedLabels, dishName, estimatedNutrients, context);

      // Отправляем запрос
      final NutritionInfo enrichedResult = await _nutritionService
          .analyzeDishByName(enrichedPrompt, context: context);

      return enrichedResult;
    } catch (e) {
      debugPrint(
          '❌ VISION_INTEGRATOR: Ошибка при анализе с оценкой: ${e.toString()}');
      return NutritionInfo.empty();
    }
  }

  /// Формирует обогащенный промпт для DeepSeek с учетом данных из Vision API
  String _buildEnrichedPrompt(String detectedLabels, String dishName,
      EstimatedNutrients estimatedNutrients,
      [BuildContext? context]) {
    try {
      // Создаем расширенный запрос с данными из Vision API
      var prompt = context != null
          ? context.trParams('analyze_nutritional_value_of_dish', [dishName])
          : _replaceParams(_ANALYZE_NUTRITIONAL_VALUE, dishName);

      // Добавляем информацию о распознанных объектах
      if (detectedLabels.isNotEmpty) {
        prompt += context != null
            ? context.trParams('detected_following_objects', [detectedLabels])
            : _replaceParams(_DETECTED_OBJECTS, detectedLabels);
      }

      // Добавляем информацию из оценки нутриентов
      if (estimatedNutrients.calories > 0 ||
          estimatedNutrients.proteins > 0 ||
          estimatedNutrients.fats > 0 ||
          estimatedNutrients.carbs > 0) {
        prompt += context != null
            ? context.tr('preliminary_nutritional_value_assessment')
            : _PRELIMINARY_ASSESSMENT;
        if (estimatedNutrients.calories > 0) {
          prompt += context != null
              ? context.trParams(
                  'calories_value', [estimatedNutrients.calories.toString()])
              : _replaceParams(
                  _CALORIES_VALUE, estimatedNutrients.calories.toString());
        }
        if (estimatedNutrients.proteins > 0) {
          prompt += context != null
              ? context.trParams(
                  'proteins_value', [estimatedNutrients.proteins.toString()])
              : _replaceParams(
                  _PROTEINS_VALUE, estimatedNutrients.proteins.toString());
        }
        if (estimatedNutrients.fats > 0) {
          prompt += context != null
              ? context
                  .trParams('fats_value', [estimatedNutrients.fats.toString()])
              : _replaceParams(_FATS_VALUE, estimatedNutrients.fats.toString());
        }
        if (estimatedNutrients.carbs > 0) {
          prompt += context != null
              ? context.trParams(
                  'carbs_value', [estimatedNutrients.carbs.toString()])
              : _replaceParams(
                  _CARBS_VALUE, estimatedNutrients.carbs.toString());
        }
      }

      // Заключительная часть промпта с инструкциями по формату ответа
      prompt += context != null
          ? context.tr('determine_dish_details')
          : _DETERMINE_DISH_DETAILS;

      // Получаем текущий язык интерфейса для указания DeepSeek возвращать данные на соответствующем языке
      if (context != null) {
        // Получаем локализационный сервис через Provider
        final container = ProviderScope.containerOf(context);
        final localizationService =
            container.read(appLocalizationServiceProvider);
        final appLocale = localizationService.getCurrentLanguage();
        final language = appLocale.name;

        // Добавляем региональную подсказку и универсальную инструкцию о языке
        prompt += " $_DISH_ANALYSIS_REGION_EN";
        prompt +=
            " Please provide all text fields (dishName, ingredient names, message) in the user's interface language: $language";
        debugPrint(
            '✅ VISION_INTEGRATOR: Добавлено указание предоставить ответ на языке интерфейса: $language');
      }

      return prompt;
    } catch (e) {
      debugPrint('❌ VISION_INTEGRATOR: Ошибка при создании промпта: $e');
      return context != null
          ? context
              .trParams('analyze_nutritional_value_of_dish_simple', [dishName])
          : _replaceParams(_ANALYZE_SIMPLE, dishName);
    }
  }

  /// Метод для преобразования MealNutrientsModel в EstimatedNutrients
  EstimatedNutrients _convertToEstimatedNutrients(MealNutrientsModel model) {
    return EstimatedNutrients(
      calories: model.calories.toDouble(),
      proteins: model.proteins,
      fats: model.fats,
      carbs: model.carbs,
    );
  }
}

/// Параметры для анализа изображения в изоляте
class _AnalyzeImageParams {
  final ImageAnalysisService imageAnalysisService;
  final File imageFile;

  _AnalyzeImageParams({
    required this.imageAnalysisService,
    required this.imageFile,
  });
}

/// Анализирует изображение в отдельном изоляте
Future<dynamic> _analyzeImageInIsolate(_AnalyzeImageParams params) async {
  return await params.imageAnalysisService.analyzeFood(params.imageFile);
}

/// Параметры для анализа блюда по названию в изоляте
class _AnalyzeDishParams {
  final NutritionService nutritionService;
  final String prompt;

  _AnalyzeDishParams({
    required this.nutritionService,
    required this.prompt,
  });
}

/// Анализирует блюдо по названию в отдельном изоляте
Future<NutritionInfo> _analyzeDishByNameInIsolate(
    _AnalyzeDishParams params) async {
  return await params.nutritionService.analyzeDishByName(params.prompt);
}

/// Параметры для записи файла в изоляте
class _WriteFileParams {
  final Uint8List bytes;
  final String path;

  _WriteFileParams({
    required this.bytes,
    required this.path,
  });
}

/// Записывает файл в отдельном изоляте
Future<void> _writeFileInIsolate(_WriteFileParams params) async {
  final file = File(params.path);
  await file.writeAsBytes(params.bytes);
}

// Результат анализа изображения с Vision API
class VisionResult {
  final List<String> detectedLabels;
  final String? foodName;
  final EstimatedNutrients? estimatedNutrients;

  VisionResult({
    this.detectedLabels = const [],
    this.foodName,
    this.estimatedNutrients,
  });

  // Конвертер из ImageAnalysisResult
  factory VisionResult.fromImageAnalysisResult(ImageAnalysisResult result) {
    return VisionResult(
      detectedLabels: result.detectedLabels,
      foodName: result.foodName,
      estimatedNutrients: result.estimatedNutrients != null
          ? EstimatedNutrients(
              calories: result.estimatedNutrients.calories.toDouble(),
              proteins: result.estimatedNutrients.proteins,
              fats: result.estimatedNutrients.fats,
              carbs: result.estimatedNutrients.carbs,
            )
          : null,
    );
  }
}

// Класс для хранения оценочных значений питательных веществ
class EstimatedNutrients {
  final double calories;
  final double proteins;
  final double fats;
  final double carbs;

  EstimatedNutrients({
    this.calories = 0,
    this.proteins = 0,
    this.fats = 0,
    this.carbs = 0,
  });
}
