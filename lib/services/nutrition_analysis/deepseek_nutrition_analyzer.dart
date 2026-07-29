import 'package:flutter/foundation.dart';
import '../../models/nutrition_info.dart';

class DeepSeekNutritionAnalyzer {
  Future<NutritionInfo> analyzeDishByName(String dishName) async {
    debugPrint(
        'DeepSeekNutritionAnalyzer: Начало анализа блюда по названию: "$dishName"');

    try {
      // Здесь должен быть существующий код анализа блюда
      // Поскольку мы не знаем, что тут было, возвращаем пустой объект
      return NutritionInfo.empty();
    } catch (e) {
      debugPrint(
          'DeepSeekNutritionAnalyzer: Ошибка при анализе блюда по названию: $e');
      rethrow;
    } finally {
      debugPrint(
          'DeepSeekNutritionAnalyzer: Завершение анализа блюда по названию: "$dishName"');
    }
  }
}
