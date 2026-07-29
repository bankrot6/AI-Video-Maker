import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nutrition_info.dart';
import 'nutrition_analysis/vision_deepseek_integrator.dart';
import 'nutrition_service.dart';
import 'providers.dart';
import 'package:flutter/material.dart';
import '../widgets/loading/loading_manager.dart';
import 'image_search/image_search_service.dart';
import 'dart:developer' as developer;

import 'localization/app_localization_service.dart';

/// Абстрактный класс для стратегии анализа (Strategy Pattern)
abstract class AnalysisStrategy {
  /// Выполняет анализ и возвращает информацию о питании
  Future<NutritionInfo> analyze(BuildContext context);

  /// Обновляет интерфейс загрузки соответствующим образом
  void updateLoadingUI(BuildContext context,
      {required double progress,
      required String text,
      required String processingStep});
}

/// Стратегия анализа для текстового ввода
class TextAnalysisStrategy implements AnalysisStrategy {
  final String text;
  final NutritionService nutritionService;
  final ImageSearchService? imageSearchService;

  TextAnalysisStrategy({
    required this.text,
    required this.nutritionService,
    this.imageSearchService,
  });

  @override
  Future<NutritionInfo> analyze(BuildContext context) async {
    debugPrint('🔍 TEXT_ANALYSIS: ===== НАЧАЛО АНАЛИЗА ТЕКСТА =====');
    debugPrint('🔍 TEXT_ANALYSIS: Анализируемый текст: "$text"');

    // Обновляем UI с начальным состоянием загрузки
    updateLoadingUI(context,
        progress: 0.2,
        text: context.tr('analysis_request'),
        processingStep: context.trParams('analyzing_request_detailed', [text]));

    // Задержка для обновления UI
    await Future.delayed(const Duration(milliseconds: 200));

    // Обновляем UI с информацией о процессе
    updateLoadingUI(context,
        progress: 0.6,
        text: context.tr('checking_and_analyzing_request'),
        processingStep:
            context.trParams('checking_request_nutritional_value', [text]));

    // ВАЖНО: Сначала проверяем съедобность через DeepSeek
    debugPrint('🔍 TEXT_ANALYSIS: ===== ОТПРАВКА ЗАПРОСА К DEEPSEEK =====');
    debugPrint(
        '🔍 TEXT_ANALYSIS: Отправка запроса к DeepSeek с названием блюда: "$text"');

    // Анализируем текст с помощью DeepSeek
    final nutritionInfo =
        await nutritionService.analyzeDishByName(text, context: context);

    debugPrint('🔍 TEXT_ANALYSIS: ===== ПОЛУЧЕН ОТВЕТ ОТ DEEPSEEK =====');
    debugPrint(
        '🔍 TEXT_ANALYSIS: Результат DeepSeek: ${nutritionInfo.dishName}');

    // Проверяем, есть ли ошибка в результате (не еда)
    if (nutritionInfo.error != null && nutritionInfo.error!.isNotEmpty) {
      debugPrint(
          '⚠️ TEXT_ANALYSIS: Запрос не относится к еде: ${nutritionInfo.error}');
      debugPrint(
          '🔍 TEXT_ANALYSIS: ===== ЗАВЕРШЕНИЕ: НЕ СЪЕДОБНЫЙ ОБЪЕКТ =====');

      // Обновляем UI с информацией об ошибке
      updateLoadingUI(context,
          progress: 1.0,
          text: context.tr('request_not_food_related'),
          processingStep: context.trParams(
              'request_not_recognized_as_food', [nutritionInfo.error!]));

      // Задержка для показа сообщения
      await Future.delayed(const Duration(seconds: 2));

      // 🔧 ИСПРАВЛЕНИЕ: НЕ ИЩЕМ ИЗОБРАЖЕНИЯ ДЛЯ ТЕКСТОВОГО АНАЛИЗА!
      // Если текстовый анализ не дал результата - просто возвращаем пустой результат
      if (nutritionInfo.dishName.isEmpty ||
          (nutritionInfo.error != null && nutritionInfo.error!.isNotEmpty)) {
        debugPrint(
            '🔍 TEXT_ANALYSIS: ===== ТЕКСТОВЫЙ АНАЛИЗ НЕ ДАЛ РЕЗУЛЬТАТА =====');
        debugPrint(
            '🔍 TEXT_ANALYSIS: НЕ ЗАПУСКАЕМ поиск изображений для текстового ввода');

        // Обновляем UI с информацией о том, что не удалось распознать еду
        updateLoadingUI(context,
            progress: 1.0,
            text: context.tr('food_not_recognized'),
            processingStep: context.tr('try_different_food_name'));

        // Задержка для показа сообщения
        await Future.delayed(const Duration(milliseconds: 800));

        debugPrint(
            '🔍 TEXT_ANALYSIS: ===== АНАЛИЗ ТЕКСТА ЗАВЕРШЕН БЕЗ РЕЗУЛЬТАТА =====');
        return nutritionInfo; // Возвращаем пустой результат
      }

      // ✅ Успешный анализ текста - возвращаем результат БЕЗ поиска изображений
      debugPrint('🔍 TEXT_ANALYSIS: ===== УСПЕШНЫЙ АНАЛИЗ ТЕКСТА =====');
      debugPrint(
          '🔍 TEXT_ANALYSIS: НЕ запускаем поиск изображений для текстового ввода');

      // Обновляем UI с информацией об успешном анализе
      updateLoadingUI(context,
          progress: 1.0,
          text: context.tr('analysis_successfully_completed'),
          processingStep:
              context.trParams('dish_info_received', [nutritionInfo.dishName]));

      // Задержка для показа сообщения
      await Future.delayed(const Duration(milliseconds: 800));

      debugPrint(
          '🔍 TEXT_ANALYSIS: ===== АНАЛИЗ ТЕКСТА ЗАВЕРШЕН БЕЗ ИЗОБРАЖЕНИЯ =====');
      return nutritionInfo;
    }

    debugPrint(
        '🔍 TEXT_ANALYSIS: ===== АНАЛИЗ DEEPSEEK ЗАВЕРШЕН УСПЕШНО =====');
    debugPrint(
        '🔍 TEXT_ANALYSIS: Блюдо распознано: "${nutritionInfo.dishName}"');

    // 🔧 ИСПРАВЛЕНИЕ: НЕ ИЩЕМ ИЗОБРАЖЕНИЯ ДЛЯ ТЕКСТОВОГО АНАЛИЗА!
    // Если текстовый анализ не дал результата - просто возвращаем пустой результат
    if (nutritionInfo.dishName.isEmpty ||
        (nutritionInfo.error != null && nutritionInfo.error!.isNotEmpty)) {
      debugPrint(
          '🔍 TEXT_ANALYSIS: ===== ТЕКСТОВЫЙ АНАЛИЗ НЕ ДАЛ РЕЗУЛЬТАТА =====');
      debugPrint(
          '🔍 TEXT_ANALYSIS: НЕ ЗАПУСКАЕМ поиск изображений для текстового ввода');

      // Обновляем UI с информацией о том, что не удалось распознать еду
      updateLoadingUI(context,
          progress: 1.0,
          text: context.tr('food_not_recognized'),
          processingStep: context.tr('try_different_food_name'));

      // Задержка для показа сообщения
      await Future.delayed(const Duration(milliseconds: 800));

      debugPrint(
          '🔍 TEXT_ANALYSIS: ===== АНАЛИЗ ТЕКСТА ЗАВЕРШЕН БЕЗ РЕЗУЛЬТАТА =====');
      return nutritionInfo; // Возвращаем пустой результат
    }

    // ✅ Успешный анализ текста - возвращаем результат БЕЗ поиска изображений
    debugPrint('🔍 TEXT_ANALYSIS: ===== УСПЕШНЫЙ АНАЛИЗ ТЕКСТА =====');
    debugPrint(
        '🔍 TEXT_ANALYSIS: НЕ запускаем поиск изображений для текстового ввода');

    // Обновляем UI с информацией об успешном анализе
    updateLoadingUI(context,
        progress: 1.0,
        text: context.tr('analysis_successfully_completed'),
        processingStep:
            context.trParams('dish_info_received', [nutritionInfo.dishName]));

    // Задержка для показа сообщения
    await Future.delayed(const Duration(milliseconds: 800));

    debugPrint(
        '🔍 TEXT_ANALYSIS: ===== АНАЛИЗ ТЕКСТА ЗАВЕРШЕН БЕЗ ИЗОБРАЖЕНИЯ =====');
    return nutritionInfo;
  }

  @override
  void updateLoadingUI(BuildContext context,
      {required double progress,
      required String text,
      required String processingStep}) {
    LoadingManager().updateProcessingInfo(
      context,
      newText: text,
      newProcessingStep: processingStep,
      newProgressValue: progress,
      animationPath: 'assets/animations/road.json',
      animationHeight: MediaQuery.of(context).size.height * 0.4,
    );
  }
}

/// Стратегия анализа для голосового ввода (расширена для получения изображений)
class VoiceAnalysisStrategy implements AnalysisStrategy {
  final String recognizedText;
  final NutritionService nutritionService;
  final ImageSearchService imageSearchService;

  VoiceAnalysisStrategy({
    required this.recognizedText,
    required this.nutritionService,
    required this.imageSearchService,
  });

  @override
  Future<NutritionInfo> analyze(BuildContext context) async {
    debugPrint(
        '🔍 VOICE_ANALYSIS: Начало анализа голосового запроса: "$recognizedText"');

    // Голосовой ввод после распознавания - это тот же текстовый ввод
    // Используем композицию для делегирования работы (принцип DRY)
    final textStrategy = TextAnalysisStrategy(
      text: recognizedText,
      nutritionService: nutritionService,
      imageSearchService: imageSearchService,
    );

    // Получаем информацию о блюде через текстовую стратегию
    final nutritionInfo = await textStrategy.analyze(context);

    debugPrint('🔍 VOICE_ANALYSIS: ===== ГОЛОСОВОЙ АНАЛИЗ ЗАВЕРШЕН =====');
    debugPrint('🔍 VOICE_ANALYSIS: НЕ ИЩЕМ изображения для голосового ввода');
    debugPrint('🔍 VOICE_ANALYSIS: Результат: ${nutritionInfo.dishName}');

    return nutritionInfo;
  }

  @override
  void updateLoadingUI(BuildContext context,
      {required double progress,
      required String text,
      required String processingStep}) {
    LoadingManager().updateProcessingInfo(
      context,
      newText: text,
      newProcessingStep: processingStep,
      newProgressValue: progress,
      animationPath: 'assets/animations/road.json',
      animationHeight: MediaQuery.of(context).size.height * 0.4,
    );
  }
}

/// Стратегия анализа для изображений
class ImageAnalysisStrategy implements AnalysisStrategy {
  final File imageFile;
  final VisionDeepSeekIntegrator integrator;

  ImageAnalysisStrategy({
    required this.imageFile,
    required this.integrator,
  });

  @override
  Future<NutritionInfo> analyze(BuildContext context) async {
    debugPrint('🔍 IMAGE_ANALYSIS: ===== НАЧАЛО АНАЛИЗА ИЗОБРАЖЕНИЯ =====');
    debugPrint('🔍 IMAGE_ANALYSIS: Путь к изображению: ${imageFile.path}');
    debugPrint(
        '🔍 IMAGE_ANALYSIS: Используем схему: Google Vision → DeepSeek (НЕ прямая отправка к DeepSeek)');

    // Обновляем UI с начальным состоянием загрузки
    updateLoadingUI(context,
        progress: 0.1,
        text: 'Анализ изображения...',
        processingStep: 'Подготовка изображения для анализа');

    // Задержка для обновления UI
    await Future.delayed(const Duration(milliseconds: 200));

    debugPrint('🔍 IMAGE_ANALYSIS: ===== ЭТАП 1: GOOGLE VISION API =====');
    // Обновляем UI с информацией о процессе - Google Vision
    updateLoadingUI(context,
        progress: 0.25,
        text: 'Распознавание объектов на изображении...',
        processingStep:
            'Отправка изображения в Google Vision API для классификации и распознавания объектов');

    // Задержка для обновления UI
    await Future.delayed(const Duration(milliseconds: 200));

    debugPrint(
        '🔍 IMAGE_ANALYSIS: ===== ЭТАП 2: DEEPSEEK API (ТОЛЬКО ТЕКСТ ОТ VISION) =====');
    // Обновляем UI с информацией о процессе - DeepSeek
    updateLoadingUI(context,
        progress: 0.6,
        text: 'Анализ питательной ценности блюда...',
        processingStep:
            'Искусственный интеллект анализирует распознанные объекты и рассчитывает нутриционный состав');

    debugPrint(
        '🔍 IMAGE_ANALYSIS: Вызываем integrator.analyzeImageWithVisionAndDeepSeek()');
    debugPrint(
        '🔍 IMAGE_ANALYSIS: Интегратор сделает: 1) Vision API → 2) DeepSeek API (с текстом от Vision)');

    // Анализируем изображение с использованием Vision и DeepSeek
    final nutritionInfo =
        await integrator.analyzeImageWithVisionAndDeepSeek(imageFile, context);

    debugPrint('🔍 IMAGE_ANALYSIS: ===== АНАЛИЗ ИЗОБРАЖЕНИЯ ЗАВЕРШЕН =====');
    debugPrint('🔍 IMAGE_ANALYSIS: Результат: ${nutritionInfo.dishName}');
    debugPrint(
        '🔍 IMAGE_ANALYSIS: Калории: ${nutritionInfo.calories}, Белки: ${nutritionInfo.proteins}');

    return nutritionInfo;
  }

  @override
  void updateLoadingUI(BuildContext context,
      {required double progress,
      required String text,
      required String processingStep}) {
    LoadingManager().updateProcessingInfo(
      context,
      newText: text,
      newProcessingStep: processingStep,
      newProgressValue: progress,
      animationPath: 'assets/animations/road.json',
      animationHeight: MediaQuery.of(context).size.height * 0.4,
    );
  }
}

/// Сервис унифицированного анализа пищи (Facade Pattern)
class UnifiedAnalysisService {
  final ProviderRef ref;

  UnifiedAnalysisService(this.ref);

  /// Анализирует ввод с использованием подходящей стратегии
  Future<NutritionInfo> analyze({
    required BuildContext context,
    String? text,
    String? recognizedVoice,
    File? imageFile,
  }) async {
    // Проверяем, был ли предоставлен входной параметр
    if (text == null && recognizedVoice == null && imageFile == null) {
      throw ArgumentError(
          'Для анализа должен быть предоставлен хотя бы один параметр: текст, голос или изображение');
    }

    // Показываем экран загрузки
    LoadingManager().showLoadingScreen(
      context,
      text: 'Начало анализа...',
      animationPath: 'assets/animations/road.json',
      animationHeight: MediaQuery.of(context).size.height * 0.4,
      backgroundColor: Colors.white,
      processingStepText: 'Подготовка к анализу',
      progressValue: 0.05,
    );

    try {
      // Определяем нужную стратегию на основе входных данных
      AnalysisStrategy strategy;

      if (imageFile != null) {
        // Используем стратегию анализа изображения
        final integrator = ref.read(visionDeepSeekIntegratorProvider);
        strategy = ImageAnalysisStrategy(
          imageFile: imageFile,
          integrator: integrator,
        );
      } else if (recognizedVoice != null && recognizedVoice.isNotEmpty) {
        // Используем стратегию голосового ввода
        final nutritionService = ref.read(deepSeekNutritionServiceProvider);
        final imageSearchService = ref.read(imageSearchServiceProvider);
        strategy = VoiceAnalysisStrategy(
          recognizedText: recognizedVoice,
          nutritionService: nutritionService,
          imageSearchService: imageSearchService,
        );
      } else if (text != null && text.isNotEmpty) {
        // Используем стратегию текстового ввода с сервисом поиска изображений
        final nutritionService = ref.read(deepSeekNutritionServiceProvider);
        final imageSearchService = ref.read(imageSearchServiceProvider);
        strategy = TextAnalysisStrategy(
          text: text,
          nutritionService: nutritionService,
          imageSearchService: imageSearchService,
        );
      } else {
        throw ArgumentError('Недостаточно данных для анализа');
      }

      // Выполняем анализ с помощью выбранной стратегии
      final nutritionInfo = await strategy.analyze(context);

      // Проверяем, был ли анализ успешным (не содержит ошибку "не еда")
      bool isSuccessfulAnalysis = true;
      if (nutritionInfo.error != null && nutritionInfo.error!.isNotEmpty) {
        // Если это несъедобный объект или превышен лимит, не регистрируем использование
        if (nutritionInfo.error!.contains('не еда') ||
            nutritionInfo.error!.contains('не распознан') ||
            nutritionInfo.error!.contains('лимит') ||
            nutritionInfo.error!.contains('limit')) {
          isSuccessfulAnalysis = false;
        }
      }

      // Если анализ был успешным, уменьшаем количество доступных запросов
      if (isSuccessfulAnalysis) {
        final subscriptionService = ref.read(subscriptionServiceProvider);
        await subscriptionService.useRequest();
        developer.log(
            'Использован запрос после успешного анализа (стратегия: ${strategy.runtimeType})',
            name: 'UnifiedAnalysisService');
      }

      // Проверяем, есть ли ошибка в результате (не еда)
      // Если это несъедобный объект, сразу возвращаем результат
      if (nutritionInfo.error != null && nutritionInfo.error!.isNotEmpty) {
        // Скрываем экран загрузки
        LoadingManager().hideLoadingScreen();
        return nutritionInfo;
      }

      // Проверяем, не пустой ли результат
      bool isEmpty = nutritionInfo.dishName.isEmpty &&
          nutritionInfo.calories == 0 &&
          nutritionInfo.proteins == 0 &&
          nutritionInfo.fats == 0 &&
          nutritionInfo.carbs == 0;

      if (isEmpty) {
        // Обновляем UI с информацией об ошибке
        LoadingManager().updateProcessingInfo(
          context,
          newText: 'Не удалось распознать блюдо',
          newProcessingStep:
              'К сожалению, не удалось получить информацию о питательной ценности. Попробуйте другой запрос.',
          newProgressValue: 1.0,
          animationPath: 'assets/animations/road.json',
          animationHeight: MediaQuery.of(context).size.height * 0.4,
        );

        // Задержка перед скрытием экрана загрузки
        await Future.delayed(const Duration(seconds: 3));

        return NutritionInfo.empty();
      }

      // Обновляем UI с информацией об успехе
      LoadingManager().updateProcessingInfo(
        context,
        newText: 'Анализ успешно завершен!',
        newProcessingStep:
            'Определена питательная ценность блюда "${nutritionInfo.dishName}"\nКалории: ${nutritionInfo.calories} ккал, Белки: ${nutritionInfo.proteins.toStringAsFixed(1)}г, Жиры: ${nutritionInfo.fats.toStringAsFixed(1)}г, Углеводы: ${nutritionInfo.carbs.toStringAsFixed(1)}г',
        newProgressValue: 1.0,
        animationPath: 'assets/animations/road.json',
        animationHeight: MediaQuery.of(context).size.height * 0.4,
      );

      // Задержка перед скрытием экрана загрузки
      await Future.delayed(const Duration(seconds: 3));

      return nutritionInfo;
    } catch (e) {
      debugPrint('❌ Ошибка в UnifiedAnalysisService: $e');

      // Обновляем UI с информацией об ошибке
      LoadingManager().updateProcessingInfo(
        context,
        newText: 'Ошибка при анализе',
        newProcessingStep:
            'Произошла ошибка при анализе: $e\nПожалуйста, попробуйте еще раз.',
        newProgressValue: 1.0,
        animationPath: 'assets/animations/road.json',
        animationHeight: MediaQuery.of(context).size.height * 0.4,
      );

      // Задержка перед скрытием экрана загрузки
      await Future.delayed(const Duration(seconds: 3));

      rethrow;
    } finally {
      // Скрываем экран загрузки
      LoadingManager().hideLoadingScreen();
    }
  }

  /// Генерирует изображение для блюда
  Future<File?> generateImageForDish(
      NutritionInfo info, Function(String) createImageCallback) async {
    // Если это несъедобный объект, не генерируем изображение
    if (info.error != null && info.error!.isNotEmpty) {
      debugPrint(
          '⚠️ Объект не съедобный, пропускаем генерацию изображения: ${info.error}');
      return null;
    }

    if (info.dishName.isEmpty) {
      debugPrint('⚠️ Пустое название блюда, пропускаем генерацию изображения');
      return null;
    }

    try {
      debugPrint(
          '🔍 UNIFIED_ANALYSIS: Запрос изображения для блюда: ${info.dishName}');

      // Сначала пробуем получить изображение через сервис поиска изображений
      final imageSearchService = ref.read(imageSearchServiceProvider);
      final imageFile = await imageSearchService.findImage(info.dishName);

      if (imageFile != null) {
        debugPrint(
            '🔍 UNIFIED_ANALYSIS: Найдено изображение через поиск: ${imageFile.path}');
        return imageFile;
      }

      debugPrint(
          '🔍 UNIFIED_ANALYSIS: Изображение не найдено через поиск, генерируем программно');

      // Если не удалось найти через поиск, используем программную генерацию
      return await createImageCallback(info.dishName);
    } catch (e) {
      debugPrint('❌ Ошибка при генерации изображения: $e');
      return null;
    }
  }

  /// Выполняет анализ изображения пищи
  Future<NutritionInfo> analyzeImage(
      File imageFile, BuildContext context) async {
    try {
      final subscriptionService = ref.read(subscriptionServiceProvider);
      final visionDeepSeekIntegrator =
          ref.read(visionDeepSeekIntegratorProvider);

      // Анализируем изображение
      final nutritionInfo =
          await visionDeepSeekIntegrator.analyzeImageWithVisionAndDeepSeek(
        imageFile,
        context,
      );

      // Проверяем, был ли анализ успешным (не содержит ошибку "не еда" или "лимит исчерпан")
      bool isSuccessfulAnalysis = true;
      if (nutritionInfo.error != null) {
        // Если у нас ошибка из-за лимита, не уменьшаем счетчик
        if (nutritionInfo.error!.contains('лимит') ||
            nutritionInfo.error!.contains('limit') ||
            nutritionInfo.error!.contains('не еда') ||
            nutritionInfo.error!.contains('не распознан')) {
          isSuccessfulAnalysis = false;
        }
      }

      // Если анализ был успешным, уменьшаем количество доступных запросов
      if (isSuccessfulAnalysis) {
        await subscriptionService.useRequest();
        developer.log('Использован запрос после успешного анализа',
            name: 'AnalysisService');
      }

      return nutritionInfo;
    } catch (e) {
      developer.log('Ошибка при анализе изображения: $e',
          name: 'AnalysisService');
      // В случае ошибки возвращаем пустой объект с информацией об ошибке
      return NutritionInfo.empty().copyWith(
        error: 'Ошибка при анализе изображения: $e',
        imagePath: imageFile.path,
      );
    }
  }

  /// Потоковый анализ для всех типов ввода. Возвращает частичные результаты.
  Stream<NutritionInfo> analyzeStream({
    required BuildContext context,
    String? text,
    String? recognizedVoice,
    File? imageFile,
  }) async* {
    if (imageFile != null) {
      final integrator = ref.read(visionDeepSeekIntegratorProvider);
      yield* integrator.analyzeImageWithVisionAndDeepSeekStream(
          imageFile, context);
      return;
    }

    final nutritionService = ref.read(deepSeekNutritionServiceProvider);
    final query = (recognizedVoice != null && recognizedVoice.isNotEmpty)
        ? recognizedVoice
        : (text ?? '');
    if (query.isEmpty) {
      yield NutritionInfo.empty();
      return;
    }
    yield* nutritionService.analyzeDishByNameStream(query, context: context);
  }
}

/// Провайдер для унифицированного сервиса анализа
final unifiedAnalysisServiceProvider = Provider<UnifiedAnalysisService>((ref) {
  return UnifiedAnalysisService(ref);
});
