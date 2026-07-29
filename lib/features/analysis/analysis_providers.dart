import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/nutrition_info.dart';
import '../../services/providers.dart';
import '../../widgets/loading/loading_manager.dart';

import '../../services/image_analysis/image_analysis_service.dart';
import '../../services/image_analysis/ml_kit_image_analysis_service.dart';
import '../../data/meal_repository.dart';
import '../../utils/food_nutrients_database.dart';
// import '../../services/analysis_service.dart';
import '../../models/meal_model.dart';
import '../../models/meal_action_result.dart';

/// Провайдер для хранения выбранного изображения
final selectedImageProvider = StateProvider<File?>((ref) => null);

/// Провайдер для сервиса анализа изображений
final imageAnalysisServiceProvider = Provider<ImageAnalysisService>((ref) {
  // Создаем экземпляр базы данных питательных веществ
  final nutrientsDatabase = FoodNutrientsDatabase();

  // Создаем и возвращаем сервис анализа изображений с ML Kit
  return MLKitImageAnalysisService(nutrientsDatabase: nutrientsDatabase);
});

/// Провайдер для результатов анализа изображения
final imageAnalysisResultProvider =
    StateNotifierProvider<ImageAnalysisResultNotifier, ImageAnalysisResult?>(
  (ref) => ImageAnalysisResultNotifier(),
);

/// Провайдер для репозитория приемов пищи
final mealRepositoryProvider = Provider<MealRepository>((ref) {
  // В реальном приложении здесь должна быть логика создания или получения
  // существующего экземпляра репозитория
  // Для простоты создаем новый экземпляр каждый раз
  // В продакшене лучше использовать синглтон или внедрять через DI
  throw UnimplementedError(
    'Репозиторий должен быть предоставлен через ProviderScope.overrides',
  );
});

/// StateNotifier для управления состоянием результатов анализа
class ImageAnalysisResultNotifier extends StateNotifier<ImageAnalysisResult?> {
  ImageAnalysisResultNotifier() : super(null);

  void setResult(ImageAnalysisResult result) {
    state = result;
  }

  /// Частичное обновление результата анализа изображения (для совместимости)
  void mergePartial({
    String? foodName,
    MealNutrientsModel? estimatedNutrients,
    List<String>? detectedLabels,
    List<IngredientModel>? inferredIngredients,
  }) {
    final current = state;
    if (current == null) return;
    state = ImageAnalysisResult(
      detectedLabels: detectedLabels ?? current.detectedLabels,
      inferredIngredients: inferredIngredients ?? current.inferredIngredients,
      estimatedNutrients: estimatedNutrients ?? current.estimatedNutrients,
      foodName: foodName ?? current.foodName,
    );
  }

  void clear() {
    state = null;
  }
}

/// Провайдер для состояния анализа питательной ценности
final nutritionAnalysisStateProvider =
    StateProvider<AsyncValue<NutritionInfo>>((ref) {
  return AsyncValue.data(NutritionInfo.empty());
});

/// Модель для хранения результатов анализа и связанной информации
class AnalysisResults {
  final NutritionInfo info;
  final DateTime timestamp;

  const AnalysisResults({
    required this.info,
    required this.timestamp,
  });
}

/// Провайдер для хранения последних результатов анализа
final lastAnalysisResultsProvider =
    StateProvider<AnalysisResults?>((ref) => null);

/// Провайдер для отслеживания режима просмотра истории
/// Используется для определения, был ли экран анализа открыт из истории приемов пищи
final isHistoryViewProvider = StateProvider<bool>((ref) => false);

/// Текущий выбранный прием пищи при просмотре из истории
final selectedHistoryMealProvider = StateProvider<MealModel?>((ref) => null);

/// Результат действия с приемом пищи после просмотра из истории
final mealActionResultProvider =
    StateProvider<MealActionResult?>((ref) => null);

/// Провайдер для хранения текста ручного ввода (включая голосовой ввод)
final manualFoodInputProvider = StateProvider<String>((ref) => '');

/// Провайдер для сброса состояния анализа и связанных данных
final resetAnalysisStateProvider = Provider<void Function()>((ref) {
  return () {
    try {
      // Сбрасываем результаты анализа в пустое значение
      ref.read(nutritionAnalysisStateProvider.notifier).state =
          AsyncValue.data(NutritionInfo.empty());

      // Очищаем выбранное изображение
      ref.read(selectedImageProvider.notifier).state = null;

      // Очищаем последние результаты анализа
      ref.read(lastAnalysisResultsProvider.notifier).state = null;

      // Сбрасываем флаг просмотра истории
      ref.read(isHistoryViewProvider.notifier).state = false;

      // Очищаем поле ручного ввода
      ref.read(manualFoodInputProvider.notifier).state = '';

      debugPrint('🔄 Состояние анализа сброшено');
    } catch (e) {
      // Если произошла ошибка при сбросе состояния, логируем её
      debugPrint('⚠️ Ошибка при сбросе состояния анализа: $e');
    }
  };
});

/// Провайдер для анализа питательной ценности блюда по изображению
/// Используем Vision + DeepSeek интегратор вместо прямого вызова DeepSeek
final analyzeImageProvider =
    Provider.family<Future<NutritionInfo>, (File, BuildContext)>(
        (ref, params) async {
  // Используем Vision для распознавания блюда и DeepSeek для анализа текста
  final imageFile = params.$1;
  final context = params.$2;
  final integrator = ref.watch(visionDeepSeekIntegratorProvider);
  return integrator.analyzeImageWithVisionAndDeepSeek(imageFile, context);
});

/// Провайдер для анализа питательной ценности блюда по изображению с интеграцией Google Vision и DeepSeek
final analyzeImageWithVisionProvider =
    Provider.family<Future<NutritionInfo>, (File, BuildContext)>(
        (ref, params) async {
  final imageFile = params.$1;
  final context = params.$2;
  final integrator = ref.watch(visionDeepSeekIntegratorProvider);
  return integrator.analyzeImageWithVisionAndDeepSeek(imageFile, context);
});

/// Провайдер для анализа питательной ценности блюда по массиву байтов
/// Используем Vision + DeepSeek интегратор вместо прямого вызова DeepSeek
final analyzeImageBytesProvider =
    Provider.family<Future<NutritionInfo>, (Uint8List, BuildContext)>(
        (ref, params) async {
  // Используем Vision для распознавания блюда и DeepSeek для анализа текста
  final imageBytes = params.$1;
  final context = params.$2;
  final integrator = ref.watch(visionDeepSeekIntegratorProvider);
  return integrator.analyzeImageBytesWithVisionAndDeepSeek(imageBytes, context);
});

/// Провайдер для анализа питательной ценности блюда по массиву байтов с интеграцией Google Vision и DeepSeek
final analyzeImageBytesWithVisionProvider =
    Provider.family<Future<NutritionInfo>, (Uint8List, BuildContext)>(
        (ref, params) async {
  final imageBytes = params.$1;
  final context = params.$2;
  final integrator = ref.watch(visionDeepSeekIntegratorProvider);
  return integrator.analyzeImageBytesWithVisionAndDeepSeek(imageBytes, context);
});

/// Провайдер для анализа питательной ценности блюда по названию
final analyzeDishByNameProvider =
    Provider.family<Future<NutritionInfo>, (String, BuildContext)>(
        (ref, params) async {
  // Используем реальный DeepSeek API
  final dishName = params.$1;
  final context = params.$2;
  final nutritionService = ref.watch(deepSeekNutritionServiceProvider);
  return nutritionService.analyzeDishByName(dishName, context: context);
});

/// Провайдер для безопасной навигации с экрана анализа
/// Централизует логику очистки состояния и навигации
final safeNavigationBackProvider = Provider<void Function(BuildContext)>((ref) {
  return (BuildContext context) {
    try {
      debugPrint('🧭 Безопасная навигация назад с экрана анализа');

      // Проверяем, установлен ли контекст
      if (!context.mounted) {
        debugPrint('⚠️ Контекст не установлен (mounted = false)');
        return;
      }

      // Проверяем активный LoadingManager и не скрываем его, если он активен
      // Это позволит сохранить экран загрузки во время перехода между экранами
      final manager = LoadingManager();
      if (!manager.isActive) {
        // Используем специальный метод для плавного перехода между экранами
        manager.showTransitionScreen(
          context,
          text: 'Возвращение на главный экран...',
          processingStepText: 'Подготовка перехода на главный экран',
        );
      }

      // Сбрасываем состояние анализа
      try {
        ref.read(resetAnalysisStateProvider)();
        debugPrint('🧭 Состояние анализа сброшено');
      } catch (e) {
        debugPrint('⚠️ Ошибка при сбросе состояния анализа: $e');
      }

      // Небольшая задержка для гарантированного отображения экрана перехода
      Future.delayed(Duration(milliseconds: 100), () {
        if (!context.mounted) return;

        // Проверяем, есть ли Navigator для pop
        bool canPop = false;
        try {
          canPop = Navigator.canPop(context);
          debugPrint('🧭 Navigator.canPop(context): $canPop');
        } catch (e) {
          debugPrint('⚠️ Ошибка при проверке Navigator.canPop: $e');
        }

        if (canPop) {
          // Используем Navigator.pop если это возможно
          debugPrint('🧭 Выполняем Navigator.pop()');
          Navigator.of(context).pop();
        } else {
          // Если невозможно выполнить pop, пытаемся перейти на домашний экран
          debugPrint(
              '🧭 Невозможно выполнить pop, пробуем pushNamedAndRemoveUntil');
          try {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/home', (route) => false);
            debugPrint('🧭 Выполнен переход на домашний экран');
          } catch (e) {
            debugPrint('⚠️ Ошибка при навигации на домашний экран: $e');

            // Резервный метод - попытка использовать pushReplacementNamed
            try {
              Navigator.of(context).pushReplacementNamed('/home');
              debugPrint('🧭 Выполнен pushReplacementNamed на домашний экран');
            } catch (e2) {
              debugPrint('⚠️ Все попытки навигации завершились неудачей: $e2');
            }
          }
        }
      });
    } catch (e) {
      debugPrint('⚠️ Общая ошибка при навигации: $e');
    }
  };
});
