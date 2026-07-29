import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/nutrition_info.dart';
import 'nutrition_analysis/nutrition_analyzer.dart';
import 'nutrition_analysis/deepseek/deepseek_nutrition_analyzer.dart';

/// Сервис для анализа питательной ценности блюд.
/// По умолчанию использует DeepSeekNutritionAnalyzer с быстрым режимом
class NutritionService {
  final NutritionAnalyzer analyzer;

  NutritionService({NutritionAnalyzer? analyzer})
      : analyzer = analyzer ?? DeepSeekNutritionAnalyzer(fastMode: true);

  /// Создает сервис с быстрым режимом для ускоренного анализа
  factory NutritionService.fastMode() {
    return NutritionService(
      analyzer: DeepSeekNutritionAnalyzer(fastMode: true),
    );
  }

  /// Анализирует блюдо по имени
  ///
  /// Возвращает информацию о питательной ценности блюда
  Future<NutritionInfo> analyzeDishByName(String dishName,
      {BuildContext? context}) async {
    try {
      debugPrint(
          '🍴 NutritionService: Анализ блюда по ТЕКСТУ: "$dishName" - быстрый режим включен');
      final info = await analyzer.analyzeDishByName(dishName, context: context);
      return info;
    } catch (e) {
      debugPrint('❌ NutritionService: Ошибка при анализе блюда по имени: $e');
      return NutritionInfo.empty();
    }
  }

  /// Потоковый анализ блюда по имени. Возвращает части NutritionInfo по мере появления.
  Stream<NutritionInfo> analyzeDishByNameStream(String dishName,
      {BuildContext? context}) {
    // Доступен только если анализатор поддерживает соответствующий метод
    if (analyzer is DeepSeekNutritionAnalyzer) {
      return (analyzer as DeepSeekNutritionAnalyzer)
          .analyzeDishByNameStream(dishName, context: context);
    }
    // Фоллбек: одиночное событие с финальным результатом
    return Stream.fromFuture(
        analyzer.analyzeDishByName(dishName, context: context));
  }

  /// Анализирует изображение блюда
  ///
  /// [imageFile] - файл изображения
  ///
  /// Возвращает информацию о питательной ценности блюда
  Future<NutritionInfo> analyzeDishByImage(File imageFile,
      {BuildContext? context}) async {
    try {
      debugPrint(
          '🍴 NutritionService: Анализ блюда по ИЗОБРАЖЕНИЮ: ${imageFile.path}');
      final info =
          await analyzer.analyzeImageNutrition(imageFile, context: context);
      return info;
    } catch (e) {
      debugPrint(
          '🍴 NutritionService: Ошибка при анализе блюда по изображению: ${e.toString()}');
      return NutritionInfo.empty();
    }
  }

  /// Анализирует байты изображения блюда
  ///
  /// [imageBytes] - байты изображения
  ///
  /// Возвращает информацию о питательной ценности блюда
  Future<NutritionInfo> analyzeDishByImageBytes(Uint8List imageBytes,
      {BuildContext? context}) async {
    try {
      debugPrint('🍴 NutritionService: Анализ блюда по БАЙТАМ ИЗОБРАЖЕНИЯ');
      final info = await analyzer.analyzeImageBytesNutrition(imageBytes,
          context: context);
      return info;
    } catch (e) {
      debugPrint(
          '🍴 NutritionService: Ошибка при анализе блюда по байтам изображения: ${e.toString()}');
      return NutritionInfo.empty();
    }
  }

  /// Проверяет, является ли объект съедобным
  ///
  /// Возвращает true, если объект съедобный (без ошибок в NutritionInfo)
  /// Возвращает false, если объект несъедобный или произошла ошибка
  bool isEdible(NutritionInfo info) {
    return info.error == null || info.error!.isEmpty;
  }
}
