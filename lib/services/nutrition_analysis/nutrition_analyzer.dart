import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/nutrition_info.dart';

/// Абстрактный класс для анализа питательной ценности блюд
abstract class NutritionAnalyzer {
  /// Анализирует питательную ценность блюда по его названию
  Future<NutritionInfo> analyzeDishByName(String dishName,
      {BuildContext? context});

  /// Анализирует питательную ценность блюда по изображению
  ///
  /// Примечание: Этот метод не отправляет изображение напрямую в DeepSeek,
  /// а использует текстовые данные, извлеченные из изображения с помощью Google Vision
  Future<NutritionInfo> analyzeImageNutrition(File imageFile,
      {BuildContext? context}) {
    // Возвращаем пустой результат, так как мы не можем
    // напрямую определить название блюда без Vision API
    return Future.value(NutritionInfo.empty());
  }

  /// Анализирует питательную ценность блюда по байтам изображения
  ///
  /// Примечание: Этот метод не отправляет изображение напрямую в DeepSeek,
  /// а использует текстовые данные, извлеченные из изображения с помощью Google Vision
  Future<NutritionInfo> analyzeImageBytesNutrition(Uint8List imageBytes,
      {BuildContext? context}) {
    // Возвращаем пустой результат, так как мы не можем
    // напрямую определить название блюда без Vision API
    return Future.value(NutritionInfo.empty());
  }
}
