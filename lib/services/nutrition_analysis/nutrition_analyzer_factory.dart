import 'nutrition_analyzer.dart';
import 'deepseek/deepseek_nutrition_analyzer.dart';

/// Тип анализатора питательной ценности
enum NutritionAnalyzerType {
  /// DeepSeek AI
  deepSeek,
}

/// Фабрика для создания анализаторов питательной ценности
class NutritionAnalyzerFactory {
  /// Создает анализатор питательной ценности заданного типа
  /// По умолчанию всегда используется быстрый режим для ускорения работы
  static NutritionAnalyzer create(NutritionAnalyzerType type) {
    // Всегда возвращаем реализацию DeepSeek с быстрым режимом
    return DeepSeekNutritionAnalyzer(fastMode: true);
  }

  /// Создает анализатор питательной ценности по умолчанию
  /// Всегда используем DeepSeek с быстрым режимом
  static NutritionAnalyzer createDefault() {
    // Всегда используем DeepSeek с быстрым режимом
    return DeepSeekNutritionAnalyzer(fastMode: true);
  }

  /// Создает анализатор в быстром режиме для тестирования
  static NutritionAnalyzer createFast() {
    return DeepSeekNutritionAnalyzer(fastMode: true);
  }
}
