import 'dart:io';
import 'dart:math';
// Убираем зависимость от ML Kit
//import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../models/meal_model.dart';
import 'image_analysis_service.dart';
import '../../utils/food_nutrients_database.dart';
import 'image_recognition_service.dart';
import 'image_recognition_factory.dart';

/// Константа для неизвестных блюд
const String UNKNOWN_DISH = 'unknown_dish';

class MLKitImageAnalysisService implements ImageAnalysisService {
  // Убираем ML Kit объекты
  //final ImageLabeler _imageLabeler;
  final FoodNutrientsDatabase _nutrientsDatabase;
  final Random _random = Random();
  final ImageRecognitionService _recognitionService;
  final bool _useRealImageRecognition;

  MLKitImageAnalysisService({
    FoodNutrientsDatabase? nutrientsDatabase,
    ImageRecognitionService? recognitionService,
    bool useRealImageRecognition = true,
  })  : _nutrientsDatabase = nutrientsDatabase ?? FoodNutrientsDatabase(),
        _recognitionService =
            recognitionService ?? ImageRecognitionFactory.createService(),
        _useRealImageRecognition = useRealImageRecognition;
  // Удаляем инициализацию ML Kit
  //_imageLabeler = ImageLabeler(
  //  options: ImageLabelerOptions(confidenceThreshold: 0.6),
  //);

  @override
  Future<ImageAnalysisResult> analyzeFood(File imageFile) async {
    try {
      // Список распознанных объектов
      List<String> labelTexts = [];
      String? foodName;

      if (_useRealImageRecognition) {
        // Используем реальное распознавание изображений через API
        final recognizedObjects =
            await _recognitionService.recognizeObjects(imageFile);

        // Преобразуем объекты в список строк для дальнейшей обработки
        labelTexts =
            recognizedObjects.map((obj) => obj.label.toLowerCase()).toList();

        // Определяем название блюда
        foodName =
            await _recognitionService.identifyFoodName(recognizedObjects);

        // Если foodName равен null, значит в изображении не обнаружена еда
        if (foodName == null) {
          debugPrint('⚠️ Не обнаружена еда на изображении');
          return ImageAnalysisResult(
            detectedLabels: labelTexts,
            inferredIngredients: [],
            estimatedNutrients:
                MealNutrientsModel(calories: 0, proteins: 0, fats: 0, carbs: 0),
            foodName:
                null, // Явно указываем null, чтобы показать, что еда не распознана
          );
        }
      } else {
        // Используем тестовые данные (для отладки или если API недоступен)
        await Future.delayed(Duration(seconds: 2));

        // Получение случайных "распознанных" продуктов из базы данных
        final availableFoods = [
          'apple',
          'banana',
          'chicken',
          'rice',
          'bread',
          'egg',
          'milk',
          'carrot'
        ];

        // Выбираем 1-3 случайных продукта
        final foodCount = _random.nextInt(3) + 1;
        for (var i = 0; i < foodCount; i++) {
          final foodIndex = _random.nextInt(availableFoods.length);
          final food = availableFoods[foodIndex];
          if (!labelTexts.contains(food)) {
            labelTexts.add(food);
          }
        }

        // Определяем возможное название блюда
        foodName = labelTexts.isNotEmpty ? labelTexts.first : null;
      }

      // Фильтруем распознанные объекты, оставляя только те, что есть в базе данных
      final List<String> validFoodItems = [];
      for (final label in labelTexts) {
        if (_nutrientsDatabase.isFoodItem(label)) {
          validFoodItems.add(label);
        }
      }

      // Если не нашли ни одного продукта в нашей базе, используем стандартные
      if (validFoodItems.isEmpty &&
          _useRealImageRecognition &&
          foodName != null) {
        // В реальном приложении здесь можно логировать отсутствие продуктов в базе
        // и предлагать пользователю выбрать продукт вручную
        validFoodItems
            .add('apple'); // Добавляем хотя бы один продукт по умолчанию
      }

      // Создание ингредиентов на основе распознанных объектов
      final ingredients = _createIngredientsFromLabelTexts(
          validFoodItems.isEmpty ? labelTexts : validFoodItems);

      // Оценка питательной ценности на основе ингредиентов
      final nutrients = await _estimateNutrients(ingredients);

      return ImageAnalysisResult(
        detectedLabels: labelTexts,
        inferredIngredients: ingredients,
        estimatedNutrients: nutrients,
        foodName: foodName ?? UNKNOWN_DISH,
      );
    } catch (e) {
      debugPrint('Ошибка анализа изображения: $e');
      // Возвращаем пустой результат в случае ошибки
      return ImageAnalysisResult(
          detectedLabels: [],
          inferredIngredients: [],
          estimatedNutrients:
              MealNutrientsModel(calories: 0, proteins: 0, fats: 0, carbs: 0),
          foodName: UNKNOWN_DISH);
    }
  }

  /// Создание моделей ингредиентов на основе распознанных текстовых меток
  List<IngredientModel> _createIngredientsFromLabelTexts(
      List<String> labelTexts) {
    return labelTexts.map((labelText) {
      // Для упрощения предполагаем, что порция каждого ингредиента 100г
      // В реальном приложении здесь может быть более сложная логика определения порций
      return IngredientModel(
        name: labelText,
        quantity: 100,
        unit: IngredientUnits.GRAMS,
      );
    }).toList();
  }

  /// Оценка питательной ценности на основе ингредиентов
  Future<MealNutrientsModel> _estimateNutrients(
      List<IngredientModel> ingredients) async {
    int totalCalories = 0;
    double totalProteins = 0;
    double totalFats = 0;
    double totalCarbs = 0;

    for (final ingredient in ingredients) {
      final nutritionData =
          await _nutrientsDatabase.getNutritionData(ingredient.name);

      if (nutritionData != null) {
        // Умножаем на фактор порции (ingredient.quantity / 100)
        final portionFactor = ingredient.quantity / 100.0;

        totalCalories += (nutritionData.calories * portionFactor).round();
        totalProteins += nutritionData.proteins * portionFactor;
        totalFats += nutritionData.fats * portionFactor;
        totalCarbs += nutritionData.carbs * portionFactor;
      }
    }

    return MealNutrientsModel(
      calories: totalCalories,
      proteins: totalProteins,
      fats: totalFats,
      carbs: totalCarbs,
    );
  }
}
