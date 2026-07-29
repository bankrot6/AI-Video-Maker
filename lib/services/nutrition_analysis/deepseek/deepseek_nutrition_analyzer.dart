import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../nutrition_analysis/nutrition_analyzer.dart';
import '../../../models/nutrition_info.dart';
import '../../../models/ingredient.dart';
import 'deepseek_client.dart';
import '../../../services/localization/app_localization_service.dart';
import 'deepseek_streaming_parser.dart';

/// Реализация анализатора питательной ценности на основе DeepSeek API
class DeepSeekNutritionAnalyzer implements NutritionAnalyzer {
  final DeepSeekClient _client;
  final bool _fastMode; // kept for compatibility
  // Кэш для хранения последних результатов анализа
  final Map<String, NutritionInfo> _analysisCache = {};
  // Максимальный размер кэша
  // final int _maxCacheSize = 20; // disabled in streaming impl

  /// Создает экземпляр анализатора DeepSeek
  DeepSeekNutritionAnalyzer({DeepSeekClient? client, bool fastMode = false})
      : _client = client ??
            DeepSeekClient.fromEnvironment(
              returnEmptyOnError: true,
              fastMode: fastMode,
            ),
        _fastMode = fastMode;

  /// Генерирует ключ кэша для текстового запроса
  // String _generateCacheKey(String dishName) => 'dish:${dishName.hashCode}';

  /// Добавляет результат в кэш
  // void _addToCache(String key, NutritionInfo info) { /* disabled in streaming impl */ }

  /// Анализирует блюдо по имени
  @override
  Future<NutritionInfo> analyzeDishByName(String dishName,
      {BuildContext? context}) async {
    debugPrint('📋 DEEPSEEK_ANALYZER: ===== НАЧАЛО АНАЛИЗА ТЕКСТА =====');
    debugPrint('📋 DEEPSEEK_ANALYZER: Получен ТЕКСТОВЫЙ запрос: "$dishName"');
    debugPrint('📋 DEEPSEEK_ANALYZER: НЕ обрабатываем изображения напрямую!');

    try {
      debugPrint('📋 DEEPSEEK_ANALYZER: ===== ФОРМИРОВАНИЕ ПРОМПТА =====');
      debugPrint('📋 DEEPSEEK_ANALYZER: Анализ блюда по названию "$dishName"');

      // Определяем язык интерфейса
      final language = _determineLanguage(context);

      // Создаем промпт с поддержкой языка
      final prompt = _buildDishAnalysisPrompt(dishName, language);

      debugPrint(
          '📋 DEEPSEEK_ANALYZER: ===== ОТПРАВКА ЗАПРОСА К DEEPSEEK API =====');
      debugPrint(
          '📋 DEEPSEEK_ANALYZER: Отправляем ТОЛЬКО ТЕКСТ к DeepSeek API');

      // Отправляем запрос к DeepSeek
      final response = await _client.generateText(prompt);

      debugPrint(
          '📋 DEEPSEEK_ANALYZER: ===== ПОЛУЧЕН ОТВЕТ ОТ DEEPSEEK API =====');
      debugPrint('✅ DEEPSEEK_ANALYZER: Получен ответ от DeepSeek API');

      // Парсим ответ
      final nutritionInfo = _parseNutritionResponse(response, context);

      debugPrint('📋 DEEPSEEK_ANALYZER: ===== АНАЛИЗ ТЕКСТА ЗАВЕРШЕН =====');
      debugPrint('📋 DEEPSEEK_ANALYZER: Результат: ${nutritionInfo.dishName}');

      return nutritionInfo;
    } catch (e) {
      debugPrint('❌ DEEPSEEK_ANALYZER: Ошибка при анализе: $e');
      return NutritionInfo.empty();
    }
  }

  /// Потоковый анализ блюда по имени с постепенным возвратом частичных результатов
  Stream<NutritionInfo> analyzeDishByNameStream(String dishName,
      {BuildContext? context}) async* {
    debugPrint('📋 DEEPSEEK_ANALYZER: Streaming анализ текста: "$dishName"');
    try {
      // Определяем язык интерфейса
      final language = _determineLanguage(context);
      final prompt = _buildDishAnalysisPrompt(dishName, language);

      final parser = NutritionStreamingParser();
      final StringBuffer full = StringBuffer();
      await for (final chunk in _client.generateTextStream(prompt)) {
        full.write(chunk);
        final snapshot = parser.addChunk(chunk);
        if (snapshot != null) {
          yield snapshot;
        }
      }

      // После завершения потока пробуем распарсить финальный ответ полностью
      final accumulated = full.toString();
      var finalSnapshot = parser.current;
      final parsedFull = _parseNutritionResponse(accumulated, context);
      // Если парсинг полного ответа дал больше данных — отдаем его
      final bool parserEmpty = finalSnapshot.dishName.isEmpty &&
          finalSnapshot.calories == 0 &&
          finalSnapshot.proteins == 0 &&
          finalSnapshot.fats == 0 &&
          finalSnapshot.carbs == 0 &&
          finalSnapshot.ingredients.isEmpty;
      if (parserEmpty ||
          parsedFull.dishName.isNotEmpty ||
          parsedFull.calories > 0 ||
          parsedFull.ingredients.isNotEmpty) {
        finalSnapshot = parsedFull;
      }
      yield finalSnapshot;
    } catch (e) {
      debugPrint('❌ DEEPSEEK_ANALYZER: Streaming ошибка: $e');
      // В случае ошибки завершаем пустым
      yield NutritionInfo.empty();
    }
  }

  /// Формирует промпт для анализа блюда по названию
  String _buildDishAnalysisPrompt(String dishName, String language) {
    return '''
You are a nutritional analysis expert. Analyze the food item: "$dishName"

CRITICAL: You MUST ALWAYS return ONLY a valid JSON object in this exact format, no additional text:

If it's food:
{
  "isFood": true,
  "dishName": "название блюда",
  "calories": количество_калорий_число,
  "proteins": количество_белков_число,
  "fats": количество_жиров_число,
  "carbs": количество_углеводов_число,
  "healthiness": число_от_0_до_5, // оценка полезности блюда (0=вредно, 5=очень полезно)
  "ingredients": [
    {"name": "ингредиент1", "weight": вес_числом},
    {"name": "ингредиент2", "weight": вес_числом}
  ]
}

If it's NOT food or unknown:
{
  "isFood": false,
  "message": "Not food"
}

Rules:
- Return ONLY JSON, no explanations, no markdown formatting
- All numeric values must be numbers (not strings)
- The field "healthiness" MUST be a number between 0 and 5 (inclusive)
- For portions: estimate standard serving size
- If unsure about exact values, provide reasonable estimates
- NEVER return empty response
- IMPORTANT: Provide all text fields (dishName, ingredient names, message) in the user's interface language: $language

Please respond with all text content in the language code: $language''';
  }

  /// Создает сокращенный промпт для быстрого режима
  // String _buildFastPrompt(String dishName, BuildContext? context) { return ''; }

  /// Парсит ответ DeepSeek
  NutritionInfo _parseNutritionResponse(
      String response, BuildContext? context) {
    try {
      debugPrint('🔍 DEEPSEEK_ANALYZER: Парсинг ответа DeepSeek...');
      debugPrint('🔍 DEEPSEEK_ANALYZER: Полный ответ от DeepSeek: $response');

      // Проверяем, не пустой ли ответ
      if (response.trim().isEmpty) {
        debugPrint('⚠️ DEEPSEEK_ANALYZER: Получен пустой ответ от DeepSeek');
        return NutritionInfo.empty();
      }

      String? jsonString;

      // Попытка 1: Найти JSON блок с ```json (наиболее распространенный)
      final codeBlockRegex =
          RegExp(r'```json\s*([\s\S]*?)\s*```', multiLine: true, dotAll: true);
      final codeBlockMatch = codeBlockRegex.firstMatch(response);

      if (codeBlockMatch != null && codeBlockMatch.groupCount > 0) {
        jsonString = codeBlockMatch.group(1)?.trim();
        debugPrint(
            '🔍 DEEPSEEK_ANALYZER: Найден JSON в блоке кода: $jsonString');
      }

      // Попытка 2: Если не нашли в блоке кода, ищем обычный JSON
      if (jsonString == null || jsonString.isEmpty) {
        // Улучшенный регулярное выражение для поиска JSON объектов
        final jsonRegex = RegExp(r'\{(?:[^{}]|(?:\{[^{}]*\})*)*\}',
            multiLine: true, dotAll: true);
        final jsonMatch = jsonRegex.firstMatch(response);

        if (jsonMatch != null) {
          jsonString = jsonMatch.group(0)?.trim();
          debugPrint('🔍 DEEPSEEK_ANALYZER: Найден обычный JSON: $jsonString');
        }
      }

      // Попытка 3: Если всё ещё не нашли, попробуем найти по открывающей и закрывающей скобкам
      if (jsonString == null || jsonString.isEmpty) {
        final startIndex = response.indexOf('{');
        final lastIndex = response.lastIndexOf('}');
        if (startIndex != -1 && lastIndex != -1 && lastIndex > startIndex) {
          jsonString = response.substring(startIndex, lastIndex + 1).trim();
          debugPrint(
              '🔍 DEEPSEEK_ANALYZER: Извлечен JSON по скобкам: $jsonString');
        }
      }

      if (jsonString == null || jsonString.isEmpty) {
        debugPrint(
            '⚠️ DEEPSEEK_ANALYZER: Не удалось найти JSON в ответе DeepSeek');
        debugPrint(
            '⚠️ DEEPSEEK_ANALYZER: Попробуем парсинг как обычный текст...');
        return _parseTextualResponse(response, context);
      }

      return _parseJsonString(jsonString, context);
    } catch (e) {
      debugPrint(
          '❌ DEEPSEEK_ANALYZER: Ошибка при парсинге ответа DeepSeek: ${e.toString()}');
      debugPrint(
          '❌ DEEPSEEK_ANALYZER: Стек ошибки: ${e is Error ? e.stackTrace : ""}');
      return NutritionInfo.empty();
    }
  }

  /// Парсит JSON строку
  NutritionInfo _parseJsonString(String jsonString, BuildContext? context) {
    try {
      debugPrint('🔍 DEEPSEEK_ANALYZER: Парсинг JSON строки: $jsonString');

      // Проверяем и исправляем наиболее распространенные ошибки в JSON
      final sanitizedJson = _sanitizeJson(jsonString);
      debugPrint('🔍 DEEPSEEK_ANALYZER: Очищенный JSON: $sanitizedJson');

      final Map<String, dynamic> data = jsonDecode(sanitizedJson);
      debugPrint('🔍 DEEPSEEK_ANALYZER: Успешно распарсили JSON: $data');

      return _processJsonData(data, context);
    } catch (e) {
      debugPrint(
          '❌ DEEPSEEK_ANALYZER: Ошибка при парсинге JSON строки: ${e.toString()}');
      return NutritionInfo.empty();
    }
  }

  /// Обрабатывает распарсенные JSON данные
  NutritionInfo _processJsonData(
      Map<String, dynamic> data, BuildContext? context) {
    // Проверяем наличие ключевых полей, типичных для пищевых продуктов
    // Если есть хотя бы одно поле с ненулевым значением, вероятно это пищевой продукт
    bool isLikelyFood = false;

    if (data.containsKey('calories') &&
        data['calories'] != null &&
        data['calories'] is num &&
        data['calories'] > 0) {
      isLikelyFood = true;
    }

    if (data.containsKey('proteins') &&
        data['proteins'] != null &&
        data['proteins'] is num &&
        data['proteins'] > 0) {
      isLikelyFood = true;
    }

    if (data.containsKey('dishName') &&
        data['dishName'] != null &&
        data['dishName'].toString().isNotEmpty) {
      isLikelyFood = true;
    }

    if (data.containsKey('ingredients') &&
        data['ingredients'] is List &&
        (data['ingredients'] as List).isNotEmpty) {
      isLikelyFood = true;
    }

    // Если явно указано isFood=false, но у нас есть признаки пищи, перезаписываем
    if (data.containsKey('isFood') && data['isFood'] == false && isLikelyFood) {
      debugPrint(
          '⚠️ DEEPSEEK_ANALYZER: Модель вернула isFood=false, но обнаружены признаки пищи. Игнорируем ошибку');
      // Удаляем сообщение об ошибке, чтобы оно не помешало обработке
      data.remove('message');
    } else if (data.containsKey('isFood') && data['isFood'] == false) {
      debugPrint('⚠️ DEEPSEEK_ANALYZER: Запрос не относится к еде');
      // Создаем специальный объект с сообщением об ошибке
      return NutritionInfo(
        dishName: context != null ? context.tr('not_food') : "Не еда",
        calories: 0,
        proteins: 0,
        fats: 0,
        carbs: 0,
        ingredients: [],
        error: data['message'] ??
            (context != null
                ? context.tr('request_not_related_to_food')
                : "Запрос не относится к еде или продуктам питания"),
      );
    }

    // Проверяем только если есть сообщение с явным указанием на несъедобность
    // и при этом нет явных признаков пищевого продукта
    if (!isLikelyFood &&
        data.containsKey('message') &&
        data['message'] != null &&
        data['dishName'] == null && // Убедимся, что нет названия блюда
        (data['message']
                .toString()
                .toLowerCase()
                .contains('не является едой') ||
            data['message']
                .toString()
                .toLowerCase()
                .contains('не относится к еде') ||
            data['message']
                .toString()
                .toLowerCase()
                .contains('не пищевой продукт') ||
            data['message']
                .toString()
                .toLowerCase()
                .contains('не продукт питания'))) {
      debugPrint(
          '⚠️ DEEPSEEK_ANALYZER: Запрос явно не относится к еде (из сообщения)');
      return NutritionInfo(
        dishName: context != null ? context.tr('not_food') : "Не еда",
        calories: 0,
        proteins: 0,
        fats: 0,
        carbs: 0,
        ingredients: [],
        error: data['message'] ??
            (context != null
                ? context.tr('request_not_related_to_food')
                : "Запрос не относится к еде или продуктам питания"),
      );
    }

    // Преобразуем данные в объект NutritionInfo
    List<Ingredient> ingredients = [];
    if (data.containsKey('ingredients') && data['ingredients'] is List) {
      final ingredientsList = data['ingredients'] as List;
      for (final item in ingredientsList) {
        if (item is Map<String, dynamic>) {
          ingredients.add(Ingredient.fromJson(item));
        }
      }
    }

    return NutritionInfo(
      dishName: data['dishName'] ?? '',
      calories: (data['calories'] as num?)?.toDouble() ?? 0,
      proteins: (data['proteins'] as num?)?.toDouble() ?? 0,
      fats: (data['fats'] as num?)?.toDouble() ?? 0,
      carbs: (data['carbs'] as num?)?.toDouble() ?? 0,
      healthiness: ((data['healthiness'] as num?)?.toDouble() ?? 0)
          .clamp(0, 5)
          .toDouble(),
      ingredients: ingredients,
    );
  }

  /// Парсит текстовый ответ (когда JSON не найден)
  NutritionInfo _parseTextualResponse(String response, BuildContext? context) {
    debugPrint('🔍 DEEPSEEK_ANALYZER: Попытка парсинга текстового ответа...');

    // Если ответ содержит явные указания на то, что это не еда
    final notFoodPhrases = [
      'не является едой',
      'не относится к еде',
      'не пищевой продукт',
      'не продукт питания',
      'not food',
      'not a food',
      'not edible',
      'not related to food',
    ];

    final responseLower = response.toLowerCase();
    for (final phrase in notFoodPhrases) {
      if (responseLower.contains(phrase)) {
        debugPrint(
            '⚠️ DEEPSEEK_ANALYZER: Обнаружена фраза о несъедобности: $phrase');
        return NutritionInfo(
          dishName: context != null ? context.tr('not_food') : "Не еда",
          calories: 0,
          proteins: 0,
          fats: 0,
          carbs: 0,
          ingredients: [],
          error: context != null
              ? context.tr('request_not_related_to_food')
              : "Запрос не относится к еде или продуктам питания",
        );
      }
    }

    debugPrint(
        '⚠️ DEEPSEEK_ANALYZER: Не удалось интерпретировать текстовый ответ');
    return NutritionInfo.empty();
  }

  /// Санитизирует JSON строку, исправляя распространенные проблемы
  String _sanitizeJson(String jsonString) {
    // Исправление некорректных экранированных кавычек
    var result = jsonString.replaceAll('\\"', '"');

    // Исправление неэкранированных кавычек в строковых значениях
    final propertyRegex = RegExp(r'"[^"]+"\s*:\s*"([^"]*)');
    final matches = propertyRegex.allMatches(result);

    for (final match in matches) {
      if (match.group(1)?.contains('"') ?? false) {
        final original = match.group(0)!;
        final fixed = original.replaceAll('"', '\\"');
        result = result.replaceFirst(original, fixed);
      }
    }

    return result;
  }

  /// Очищает кэш результатов
  void clearCache() {
    _analysisCache.clear();
    debugPrint('🧹 DEEPSEEK_ANALYZER: Кэш очищен');
  }

  @override
  Future<NutritionInfo> analyzeImageNutrition(File imageFile,
      {BuildContext? context}) async {
    // Метод больше не отправляет изображение напрямую в DeepSeek,
    // а использует текстовые данные, извлеченные из изображения
    debugPrint(
        '📋 DEEPSEEK_ANALYZER: Анализ по изображению не поддерживается напрямую');
    // Возвращаем пустой результат, так как мы не можем определить название блюда без Vision API
    return NutritionInfo.empty();
  }

  @override
  Future<NutritionInfo> analyzeImageBytesNutrition(Uint8List imageBytes,
      {BuildContext? context}) async {
    // Метод больше не отправляет изображение напрямую в DeepSeek,
    // а использует текстовые данные, извлеченные из изображения
    debugPrint(
        '📋 DEEPSEEK_ANALYZER: Анализ по байтам изображения не поддерживается напрямую');
    // Возвращаем пустой результат, так как мы не можем определить название блюда без Vision API
    return NutritionInfo.empty();
  }

  /// Определяет язык интерфейса приложения
  String _determineLanguage(BuildContext? context) {
    if (context == null) return 'en';

    try {
      final container = ProviderScope.containerOf(context);
      final localizationService =
          container.read(appLocalizationServiceProvider);
      final appLocale = localizationService.getCurrentLanguage();
      return appLocale.name;
    } catch (e) {
      debugPrint('📋 DEEPSEEK_ANALYZER: Ошибка определения языка: $e');
      return 'en';
    }
  }
}
