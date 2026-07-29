import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../models/nutrition_info.dart';
import '../../models/ingredient.dart';
import '../../models/meal_model.dart';
import '../../services/providers.dart' as services;
// analysis_service is accessed via providers in services/providers.dart
import 'analysis_providers.dart' as analysis;
import '../../features/home/home_providers.dart' as home;
import '../analytics/analytics_providers.dart' as analytics;
import 'dart:ui';
import '../../widgets/loading/loading_manager.dart';
import '../../widgets/edit_text/text_editing_bottom_sheet.dart';
// import '../../widgets/edit_text/ingredient_editing_bottom_sheet.dart';
import '../../widgets/edit_text/ingredient_list_editing_bottom_sheet.dart';
// import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../utils/usage_limit_util.dart';
import '../../services/localization/app_localization_service.dart';
import '../../utils/file_utils.dart';
import 'package:shimmer/shimmer.dart';
import 'package:bottom_picker/bottom_picker.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import '../../models/meal_action_result.dart';
import '../../widgets/date_selector_header.dart' as date_selector;
import '../../widgets/rtl_wrapper.dart';
import '../favorites/favorites_providers.dart';
import '../../services/widgets/home_widgets_service.dart';

// Тип редактируемого нутриента (вне класса согласно правилам Dart)
enum _NutrientField { calories, proteins, fats, carbs }

/// Экран анализа питательной ценности блюда
class FoodAnalysisScreen extends ConsumerStatefulWidget {
  /// Создает экран анализа питательной ценности блюда
  ///
  /// [isVoiceInput] - флаг, указывающий, что ввод произведен с помощью голоса
  /// [isTextInput] - флаг, указывающий, что ввод произведен с помощью текста
  const FoodAnalysisScreen(
      {super.key, this.isVoiceInput = false, this.isTextInput = false});

  /// Флаг, указывающий, что ввод произведен с помощью голоса
  final bool isVoiceInput;

  /// Флаг, указывающий, что ввод произведен с помощью текста
  final bool isTextInput;

  @override
  ConsumerState<FoodAnalysisScreen> createState() => _FoodAnalysisScreenState();
}

class _FoodAnalysisScreenState extends ConsumerState<FoodAnalysisScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isSaving = false;
  bool _isAnalysisInProgress = false;
  bool _isLoading = false;
  bool _analysisCompleted = false;
  bool _isMockService = false;
  bool _imageGenerated = false;
  String? _errorMessage;
  bool _shouldCancelAnalysis = false;
  File? _imageFile;
  final List<Ingredient> _progressiveIngredients = [];
  final Set<String> _ingredientNameSet = <String>{};
  int _ingredientsVersion = 0;
  String? _currentDishName;
  bool _imageFetchStarted = false;
  // Дополнительные контроллеры
  final TextEditingController _dishNameController = TextEditingController();
  final TextEditingController _caloriesController = TextEditingController();
  final TextEditingController _proteinsController = TextEditingController();
  final TextEditingController _fatsController = TextEditingController();
  final TextEditingController _carbsController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  DateTime _mealDateTime = DateTime.now();
  // Несохраненные изменения при просмотре из истории
  bool _hasUnsavedHistoryChanges = false;

  Future<String?> _showNumberInputSheet({
    required String title,
    required String hintText,
    required String initialText,
    required bool allowDecimal,
  }) async {
    final controller = TextEditingController(text: initialText);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: hintText,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      autofocus: true,
                      keyboardType: TextInputType.numberWithOptions(
                        signed: false,
                        decimal: allowDecimal,
                      ),
                      textDirection: context.textDirection,
                      textAlign:
                          context.isRTL ? TextAlign.right : TextAlign.left,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          context.tr('cancel'),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context, controller.text.trim());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          context.tr('done'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Открыть числовой редактор для нутриента и применить изменения
  void _editNutrient(_NutrientField field) {
    final isHistoryView = ref.read(analysis.isHistoryViewProvider);
    final analysisState = ref.read(analysis.nutritionAnalysisStateProvider);
    NutritionInfo currentInfo = NutritionInfo.empty();
    if (analysisState is AsyncData<NutritionInfo>) {
      currentInfo = analysisState.value;
    }

    // Определяем текущие значения и параметры ввода
    String title = '';
    String initial = '';
    switch (field) {
      case _NutrientField.calories:
        title = context.tr('calories');
        initial = currentInfo.calories > 0
            ? currentInfo.calories.round().toString()
            : '';
        break;
      case _NutrientField.proteins:
        title = context.tr('proteins');
        initial = currentInfo.proteins > 0
            ? currentInfo.proteins.toStringAsFixed(1)
            : '';
        break;
      case _NutrientField.fats:
        title = context.tr('fats');
        initial =
            currentInfo.fats > 0 ? currentInfo.fats.toStringAsFixed(1) : '';
        break;
      case _NutrientField.carbs:
        title = context.tr('carbs');
        initial =
            currentInfo.carbs > 0 ? currentInfo.carbs.toStringAsFixed(1) : '';
        break;
    }

    final String hint = field == _NutrientField.calories
        ? '${context.tr('dish_example').split(':').first}: 250 ${context.tr('calories_suffix')}'
        : '${context.tr('dish_example').split(':').first}: 23.5 ${context.tr('grams_suffix')}';

    _showNumberInputSheet(
      title: title,
      hintText: hint,
      initialText: initial,
      allowDecimal: field != _NutrientField.calories,
    ).then((text) async {
      if (text == null) return;
      // Нормализуем ввод (поддержка запятой)
      final normalized = text.replaceAll(',', '.');
      if (normalized.isEmpty) return;

      double? parsed = double.tryParse(normalized);
      if (parsed == null) return;

      // Ограничения и приведение типов
      parsed = parsed.clamp(0, 100000).toDouble();

      double newCalories = currentInfo.calories;
      double newProteins = currentInfo.proteins;
      double newFats = currentInfo.fats;
      double newCarbs = currentInfo.carbs;

      switch (field) {
        case _NutrientField.calories:
          newCalories = parsed.floorToDouble();
          break;
        case _NutrientField.proteins:
          newProteins = parsed;
          break;
        case _NutrientField.fats:
          newFats = parsed;
          break;
        case _NutrientField.carbs:
          newCarbs = parsed;
          break;
      }

      // Обновляем состояние анализа для UI
      final updatedInfo = currentInfo.copyWith(
        calories: newCalories,
        proteins: newProteins,
        fats: newFats,
        carbs: newCarbs,
      );
      ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
          AsyncValue.data(updatedInfo);
      ref.read(analysis.lastAnalysisResultsProvider.notifier).state =
          analysis.AnalysisResults(
              info: updatedInfo, timestamp: DateTime.now());

      if (isHistoryView) {
        // В истории теперь помечаем как несохранённые, сохраняем кнопкой внизу
        setState(() {
          _hasUnsavedHistoryChanges = true;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();

    // Инициализируем контроллеры для текстовых полей
    _weightController.text = '100';

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      debugPrint('🚀 FoodAnalysisScreen инициализирован');

      // Проверяем, открыт ли экран для голосового ввода
      if (widget.isVoiceInput) {
        debugPrint('🎤 Обнаружен голосовой ввод');
        final voiceText = ref.read(analysis.manualFoodInputProvider);
        if (voiceText.isNotEmpty) {
          // Устанавливаем текст в контроллер
          _dishNameController.text = voiceText;

          // Запускаем анализ по голосовому запросу с использованием унифицированного сервиса
          // Без полноэкранного лоадера: сразу показываем экран с шиммерами
          await _analyzeImage(
              recognizedVoice: voiceText, skipLoadingScreen: false);

          // 🔒 КРИТИЧНАЯ ЗАЩИТА: Для голосового ввода НЕ анализируем изображения!
          debugPrint(
              '🔒 ЗАЩИТА: Голосовой ввод завершен, пропускаем анализ изображений');
          return;
        }
      }

      // Проверяем, открыт ли экран для текстового ввода
      if (widget.isTextInput) {
        debugPrint('📝 Обнаружен текстовый ввод');
        final textInput = ref.read(analysis.manualFoodInputProvider);
        if (textInput.isNotEmpty) {
          // Устанавливаем текст в контроллер
          _dishNameController.text = textInput;

          // Загружаем существующий результат анализа, если он уже есть
          final analysisState =
              ref.read(analysis.nutritionAnalysisStateProvider);
          if (analysisState is AsyncData<NutritionInfo> &&
              !analysisState.hasError) {
            debugPrint(
                '📝 Найдены существующие результаты анализа для текстового ввода');
            // У нас уже есть результаты, просто обновляем UI
            setState(() {
              _analysisCompleted = true;
            });
          } else {
            // Запускаем анализ по текстовому запросу, если нет существующих результатов
            debugPrint('📝 Запуск анализа для текстового ввода: $textInput');
            // Без полноэкранного лоадера: сразу показываем экран с шиммерами
            await _analyzeImage(
                recognizedVoice: textInput, skipLoadingScreen: false);
          }

          // 🔒 КРИТИЧНАЯ ЗАЩИТА: Для текстового ввода НЕ анализируем изображения!
          debugPrint(
              '🔒 ЗАЩИТА: Текстовый ввод завершен, пропускаем анализ изображений');
          return;
        }
      }

      // Получаем изображение, выбранное на предыдущем экране
      final selectedImage = ref.read(analysis.selectedImageProvider);
      if (selectedImage != null) {
        setState(() {
          _imageFile = selectedImage;
        });
        debugPrint(
            '🖼️ Изображение получено из провайдера: ${selectedImage.path}');
      } else {
        debugPrint('⚠️ Изображение отсутствует в провайдере.');
      }

      // Проверяем, есть ли сохраненные результаты анализа
      final savedResults = ref.read(analysis.lastAnalysisResultsProvider);

      if (savedResults != null && savedResults.info.dishName.isNotEmpty) {
        // Устанавливаем последнее известное имя блюда в контроллер
        setState(() {
          _dishNameController.text = savedResults.info.dishName;
        });
        debugPrint(
            '💾 Загружены сохраненные результаты для блюда: ${savedResults.info.dishName}');

        // Если изображение отсутствует, но у нас есть результаты анализа,
        // создаем программное изображение на основе результатов
        if (_imageFile == null && savedResults.info.dishName.isNotEmpty) {
          debugPrint(
              '🎨 Создаем программное изображение для: ${savedResults.info.dishName}');
          await _generateImageForDish(savedResults.info);
          // Не запускаем анализ, так как у нас уже есть результаты
          return;
        }
      }

      // ИСПРАВЛЕНИЕ: Проверяем состояние анализа в провайдере
      final currentAnalysisState =
          ref.read(analysis.nutritionAnalysisStateProvider);

      // Если у нас уже есть действительные результаты анализа (не пустые), не запускаем повторный анализ
      if (currentAnalysisState is AsyncData<NutritionInfo>) {
        final info = currentAnalysisState.value;
        if (info.dishName.isNotEmpty && info.calories > 0) {
          debugPrint(
              '✅ Уже есть действительные результаты анализа: "${info.dishName}", пропускаем повторный анализ');
          setState(() {
            _dishNameController.text = info.dishName;
            _analysisCompleted = true;
          });
          return;
        }
      }

      // ДОПОЛНИТЕЛЬНАЯ ЗАЩИТА: Если есть сохраненные результаты для текущего изображения, не анализируем заново
      if (_imageFile != null && savedResults != null) {
        final imagePath = _imageFile!.path;
        final lastImagePath = savedResults.info.imagePath;

        if (lastImagePath != null &&
            lastImagePath == imagePath &&
            savedResults.info.dishName.isNotEmpty &&
            savedResults.info.calories > 0) {
          debugPrint(
              '🔒 ЗАЩИТА: Уже есть результаты анализа для этого изображения: "${savedResults.info.dishName}", пропускаем повторный анализ');
          setState(() {
            _dishNameController.text = savedResults.info.dishName;
            _analysisCompleted = true;
          });
          return;
        }
      }

      // Проверяем, нужен ли новый анализ
      final needsNewAnalysis = _isNewAnalysisSession();

      if (needsNewAnalysis && _imageFile != null) {
        debugPrint('🔄 Запуск нового анализа изображения');
        await _analyzeImage(imageFile: _imageFile);
      } else {
        debugPrint(
            '⏸️ Нет необходимости в новом анализе: needsNewAnalysis=$needsNewAnalysis, изображение=${_imageFile != null}');
      }
    });
  }

  /// Добавляет ингредиенты постепенно, имитируя потоковое поступление
  void _appendIngredientsGradually(List<Ingredient> incoming) {
    // Версия на случай смены блюда/запроса в процессе
    _ingredientsVersion++;
    final int versionAtStart = _ingredientsVersion;

    // Фильтрация по имени (регистронезависимо) и пошаговое добавление
    int step = 0;
    for (final ing in incoming) {
      final key = ing.name.trim().toLowerCase();
      if (_ingredientNameSet.contains(key)) {
        // Если ингредиент уже есть — обновляем вес, если он изменился
        final idx = _progressiveIngredients.indexWhere(
            (existing) => existing.name.trim().toLowerCase() == key);
        if (idx >= 0) {
          final existing = _progressiveIngredients[idx];
          if ((existing.weight - ing.weight).abs() > 0.01 ||
              existing.verified != ing.verified) {
            final delayMs = 40 * (step % 5);
            step++;
            Future.delayed(Duration(milliseconds: delayMs), () {
              if (!mounted) return;
              if (_ingredientsVersion != versionAtStart) return;
              if (idx >= 0 && idx < _progressiveIngredients.length) {
                setState(() {
                  _progressiveIngredients[idx] = Ingredient(
                    name: existing.name,
                    weight: ing.weight,
                    verified: ing.verified,
                  );
                });
              }
            });
          }
        }
        continue;
      }
      final delayMs = 50 * (step % 6);
      step++;
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        if (_ingredientsVersion != versionAtStart)
          return; // отмена при смене сеанса
        if (_ingredientNameSet.contains(key)) return;
        setState(() {
          _progressiveIngredients.add(ing);
          _ingredientNameSet.add(key);
        });
      });
    }
  }

  @override
  void dispose() {
    _shouldCancelAnalysis = true;
    _dishNameController.dispose();
    _caloriesController.dispose();
    _proteinsController.dispose();
    _fatsController.dispose();
    _carbsController.dispose();
    _weightController.dispose();

    // Скрываем экран загрузки при уничтожении экрана, если он был показан
    try {
      // Используем безопасное скрытие экрана загрузки даже если виджет уже размонтирован
      LoadingManager().hideLoadingScreen();
    } catch (e) {
      debugPrint('🎤 Ошибка при скрытии экрана загрузки в dispose: $e');
    }

    // Не обращаемся к ref в dispose: сброс состояния выполняется в onWillPop/Back

    super.dispose();
  }

  void _checkApiKey() {
    setState(() {
      _isMockService = false;
    });
  }

  Future<void> _takePicture() async {
    try {
      debugPrint('📷 Запуск камеры для съемки...');
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);

      if (image != null) {
        debugPrint('📷 Получено изображение с камеры: ${image.path}');

        // Сбрасываем предыдущие результаты анализа перед установкой нового изображения
        ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
            const AsyncValue.loading();

        // Обновляем состояние с новым изображением
        setState(() {
          _imageFile = File(image.path);
        });

        debugPrint(
            '📷 Состояние приложения обновлено с новым изображением: ${_imageFile!.path}');

        // Запускаем анализ с полноэкранным лоадером и пошаговыми статусами
        await _analyzeImage(imageFile: _imageFile, skipLoadingScreen: false);
      } else {
        debugPrint('📷 Выбор изображения с камеры отменен');
      }
    } catch (e) {
      debugPrint('📷 Ошибка при работе с камерой: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('camera_error'))),
        );
      }
    }
  }

  /// Анализирует изображение в фоновом режиме и заполняет completer результатом
  void _analyzeImageInBackground(File imageFile, dynamic integrator,
      Completer<NutritionInfo> completer) async {
    try {
      debugPrint('🔄 Запуск анализа в фоновом режиме...');
      final nutritionInfo = await integrator.analyzeImageWithVisionAndDeepSeek(
          imageFile, context);
      debugPrint('🔄 Получен результат анализа: ${nutritionInfo.dishName}');
      completer.complete(nutritionInfo);
    } catch (e) {
      debugPrint('🔄 Ошибка при фоновом анализе: $e');
      completer.completeError(e);
    }
  }

  Future<void> _pickImage() async {
    // Получаем изображение из галереи
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );

    if (image != null) {
      // Сбрасываем предыдущие результаты анализа перед установкой нового изображения
      ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
          const AsyncValue.loading();

      // Обновляем состояние с новым изображением
      setState(() {
        _imageFile = File(image.path);
      });

      // Запускаем анализ с полноэкранным лоадером и пошаговыми статусами
      await _analyzeImage(skipLoadingScreen: false);
    }
  }

  Future<void> _saveMeal() async {
    // Получаем текущую информацию о питании из состояния
    final analysisState = ref.read(analysis.nutritionAnalysisStateProvider);

    // Проверяем, есть ли данные
    if (analysisState is! AsyncData<NutritionInfo>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('no_data_to_save'))),
      );
      return;
    }

    // Получаем информацию о питании
    final nutritionInfo = analysisState.value;

    // Показываем экран загрузки с полным размером анимации и начальным этапом
    LoadingManager().showLoadingScreen(
      context,
      text: context.tr('saving_meal'),
      animationPath: 'assets/animations/road.json',
      animationHeight: MediaQuery.of(context).size.height * 0.4,
      backgroundColor: Colors.white,
      processingStepText: context.tr('preparing_image'),
      progressValue: 0.1,
    );

    setState(() {
      _isSaving = true;
    });

    try {
      // Если в контроллере есть текст, используем его как название блюда
      final dishName = _dishNameController.text.isNotEmpty
          ? _dishNameController.text
          : nutritionInfo.dishName;

      // Преобразуем ингредиенты из модели NutritionInfo в IngredientModel
      final ingredients = nutritionInfo.ingredients
          .map((ingredient) => IngredientModel(
                name: ingredient.name,
                quantity: ingredient.weight,
              ))
          .toList();

      // Обновляем информацию о процессе сохранения
      LoadingManager().updateProcessingInfo(
        context,
        newText: context.tr('processing_image'),
        newProcessingStep: context.tr('processing_step_vision'),
        newProgressValue: 0.25,
        animationPath: 'assets/animations/road.json',
        animationHeight: MediaQuery.of(context).size.height * 0.4,
      );

      // Создаем объект питательных веществ
      final nutrients = MealNutrientsModel(
        calories: nutritionInfo.calories.round(),
        proteins: nutritionInfo.proteins,
        fats: nutritionInfo.fats,
        carbs: nutritionInfo.carbs,
      );

      // Создаем объект приема пищи
      final meal = MealModel(
        id: const Uuid().v4(),
        name: dishName,
        dateTime: _mealDateTime,
        imagePath: _imageFile!.path,
        ingredients: ingredients,
        nutrients: nutrients,
        healthiness: nutritionInfo.healthiness.clamp(0, 5).toDouble(),
      );

      // Обновляем информацию о процессе сохранения
      LoadingManager().updateProcessingInfo(
        context,
        newText: context.tr('saving_meal'),
        newProcessingStep: context.tr('saving_image'),
        newProgressValue: 0.5,
        animationPath: 'assets/animations/road.json',
        animationHeight: MediaQuery.of(context).size.height * 0.4,
      );

      // Сохраняем прием пищи в репозиторий
      final mealRepository = ref.read(home.mealRepositoryProvider);
      await mealRepository.saveMeal(meal);

      // Добавляем прием пищи в список дневных приемов пищи
      ref.read(home.dailyMealsProvider.notifier).addMeal(meal);

      // Обновляем информацию о процессе сохранения
      LoadingManager().updateProcessingInfo(
        context,
        newText: context.tr('analysis_completed'),
        newProcessingStep: context
            .tr('analyzed_dish')
            .replaceAll('{0}', dishName)
            .replaceAll('{1}', nutrients.calories.toString())
            .replaceAll('{2}', context.tr('calories_suffix')),
        newProgressValue: 0.75,
        animationPath: 'assets/animations/road.json',
        animationHeight: MediaQuery.of(context).size.height * 0.4,
      );

      // Обновляем суммарные нутриенты за день
      final dailyNutrients = ref.read(home.dailyNutrientsProvider);
      if (dailyNutrients != null) {
        final updatedNutrients = MealNutrientsModel(
          calories: dailyNutrients.calories + nutrients.calories,
          proteins: dailyNutrients.proteins + nutrients.proteins,
          fats: dailyNutrients.fats + nutrients.fats,
          carbs: dailyNutrients.carbs + nutrients.carbs,
        );
        ref
            .read(home.dailyNutrientsProvider.notifier)
            .setNutrients(updatedNutrients);
      }

      // Обновляем домашний виджет «Прогресс дня»
      await HomeWidgetsService.updateDailyProgressFromRepo(ref);

      // 🔄 ВАЖНО: Принудительно обновляем провайдеры аналитики после сохранения еды
      // Это гарантирует, что аналитика покажет свежие данные без перезапуска приложения
      debugPrint('🔄 Обновляем провайдеры аналитики после сохранения еды');
      ref.invalidate(analytics.weeklyNutrientsProvider);
      ref.invalidate(analytics.dailyNutrientsForDateProvider(DateTime.now()));
      // Обновляем нутриенты для домашнего экрана на выбранную дату
      final today = DateTime.now();
      ref.invalidate(home.nutrientsForDateProvider(today));

      // Регистрируем использование после успешного сохранения
      final usageResult = await UsageLimitUtil.registerUsage(context, ref,
          showRemainingUsagesWarning: false);

      // Получаем информацию о лимитах использования
      final subscriptionService =
          ref.read(services.subscriptionServiceProvider);
      final hasPaidSubscription =
          await subscriptionService.hasPaidSubscription();
      final remainingUsages = await subscriptionService.getRemainingRequests();

      // Логируем информацию о результате использования и оставшихся попытках
      debugPrint(
          '✅ Результат регистрации использования: isSuccess=${usageResult.$1}, remainingUsages=${usageResult.$2}');
      debugPrint(
          '✅ Получено из сервиса подписки: hasPaidSubscription=$hasPaidSubscription, remainingUsages=$remainingUsages');

      // Формируем сообщение с учетом типа подписки и оставшихся использований
      String usageMessage = "";
      if (!hasPaidSubscription) {
        if (remainingUsages > 0) {
          usageMessage =
              " ${context.tr('usages_left_message').replaceAll('{0}', remainingUsages.toString()).replaceAll('{1}', context.tr(_getUsageKey(remainingUsages))).replaceAll('{2}', '')}";
        } else {
          usageMessage = " ${context.tr('free_user_daily_limit')}";
        }
      }

      final message = '${context.tr('meal_saved')}$usageMessage';
      debugPrint('✅ Итоговое сообщение для пользователя: "$message"');

      // Обновляем информацию о процессе сохранения
      LoadingManager().updateProcessingInfo(
        context,
        newText: context.tr('meal_saved'),
        newProcessingStep: context
            .tr('analyzed_dish')
            .replaceAll('{0}', dishName)
            .replaceAll('{1}', nutrients.calories.toString())
            .replaceAll('{2}', context.tr('calories_suffix')),
        newProgressValue: 0.9,
        animationPath: 'assets/animations/road.json',
        animationHeight: MediaQuery.of(context).size.height * 0.4,
      );

      // Подготовка перехода на домашний экран - используем специальный метод для перехода
      LoadingManager().showTransitionScreen(
        context,
        text: context.tr('loading'),
        processingStepText: context.tr('almost_done'),
      );

      // После успешного сохранения сбрасываем состояние анализа
      if (mounted) {
        // Сбрасываем состояние анализа ПЕРЕД навигацией
        ref.read(analysis.resetAnalysisStateProvider)();

        // Небольшая задержка для визуальной обратной связи
        debugPrint('✅ Ожидание короткой задержки с показом экрана перехода');
        await Future.delayed(const Duration(milliseconds: 300));

        // Выполняем безопасную навигацию на домашний экран, сохраняя экран загрузки активным
        debugPrint('✅ Выполняем навигацию с активным экраном загрузки');
        if (!mounted) return;

        // Сообщение о сохранении теперь будет показано на главном экране

        // Переключаем календарь на сегодняшний день перед переходом на домашний экран
        final today = DateTime.now();
        print(
            '🔄 FoodAnalysisScreen: Переключение на сегодня: ${today.day}.${today.month}.${today.year}');
        ref.read(date_selector.selectedDateProvider.notifier).state = today;
        print('✅ FoodAnalysisScreen: Провайдер selectedDateProvider обновлен');

        // Всегда переходим на домашний экран независимо от источника ввода
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (route) => false, arguments: {
          // Передадим сообщение, чтобы показать его уже на главном экране
          'post_home_snack': message,
        });
        debugPrint(
            '✅ Выполнена навигация на домашний экран, прерываем метод _saveMeal');
        return; // Важно: немедленно прерываем выполнение метода
      }
    } catch (e) {
      // Обновляем информацию о процессе при ошибке
      if (mounted) {
        LoadingManager().updateProcessingInfo(
          context,
          newText: context.tr('saving_error').replaceAll('{0}', ''),
          newProcessingStep:
              context.tr('error_occurred').replaceAll('{0}', e.toString()),
          newProgressValue: 1.0,
          animationPath: 'assets/animations/road.json',
          animationHeight: MediaQuery.of(context).size.height * 0.4,
        );

        // Задержка перед скрытием экрана загрузки
        await Future.delayed(const Duration(seconds: 2));
        LoadingManager().hideLoadingScreen();

        // Показываем сообщение об ошибке
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  context.tr('saving_error').replaceAll('{0}', e.toString()))),
        );
      }
    } finally {
      // Завершение операции и обновление состояния
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// Получение ключа для правильной формы слова "использование" в зависимости от числа
  String _getUsageKey(int count) {
    if (count % 10 == 1 && count % 100 != 11) {
      return 'usage_singular';
    } else if (count % 10 >= 2 &&
        count % 10 <= 4 &&
        (count % 100 < 10 || count % 100 >= 20)) {
      return 'usage_few';
    } else {
      return 'usage_many';
    }
  }

  /// Проверяет, является ли изображение новым для существующих результатов
  bool _isNewAnalysisSession() {
    // Проверяем, является ли просмотр просмотром истории
    final isHistoryView = ref.read(analysis.isHistoryViewProvider);
    if (isHistoryView) {
      debugPrint('🔍 Обнаружен просмотр истории, пропускаем анализ');
      return false;
    }

    // Получаем текущее изображение
    final selectedImage = _imageFile;

    // Если нет выбранного изображения, новый анализ не требуется
    if (selectedImage == null) {
      return false;
    }

    // Получаем текущее состояние анализа
    final analysisState = ref.read(analysis.nutritionAnalysisStateProvider);

    // Проверяем, используем ли мы изображение с префиксом food_home_
    // Это изображения, полученные из галереи или камеры - для них всегда делаем новый анализ
    if (selectedImage.path.contains('food_home_')) {
      // Проверяем, было ли последнее изображение из того же источника
      final selectedImageProvider = ref.read(analysis.selectedImageProvider);
      final lastAnalysisResults =
          ref.read(analysis.lastAnalysisResultsProvider);

      // Если есть предыдущие результаты анализа и они совпадают с текущим изображением
      if (lastAnalysisResults != null &&
          selectedImageProvider != null &&
          selectedImageProvider.path == selectedImage.path) {
        // Если это то же самое изображение, не делаем повторный анализ
        debugPrint(
            '🔍 Обнаружено то же изображение, что было проанализировано ранее: ${lastAnalysisResults.info.dishName}');
        return false;
      }

      // Для нового изображения с префиксом food_home_ всегда делаем новый анализ
      debugPrint(
          '🔍 Обнаружено новое изображение из домашнего экрана, запускаем новый анализ');
      return true;
    }

    // Проверяем, есть ли у нас действительные результаты анализа
    if (analysisState is AsyncData<NutritionInfo>) {
      bool hasValidResults = analysisState.value.dishName.isNotEmpty &&
          analysisState.value.calories > 0 &&
          (analysisState.value.proteins > 0 ||
              analysisState.value.fats > 0 ||
              analysisState.value.carbs > 0);

      // Если это программно созданное изображение (dish_), не запускаем повторный анализ
      if (selectedImage.path.contains('dish_') && hasValidResults) {
        debugPrint(
            '🔍 Обнаружено программное изображение, пропускаем повторный анализ');
        return false;
      }
    }

    // По умолчанию считаем, что нужен новый анализ
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Получаем состояние анализа питательной ценности
    final analysisState = ref.watch(analysis.nutritionAnalysisStateProvider);

    // Используем WillPopScope для контроля выхода с экрана
    return WillPopScope(
      // Предотвращаем черный экран при возврате
      onWillPop: () async {
        _shouldCancelAnalysis = true;

        // Если экран открыт из истории — просто возвращаемся назад на историю
        final isHistoryView = ref.read(analysis.isHistoryViewProvider);
        if (isHistoryView) {
          if (mounted) {
            Navigator.of(context).pop();
          }
          return false; // мы обработали навигацию
        }

        // Иначе (обычный поток) показываем переход и уходим на домашний экран
        LoadingManager().showTransitionScreen(
          context,
          text: context.tr('food_screen_home_return'),
          processingStepText: context.tr('food_screen_preparing_transition'),
        );

        // Сбрасываем состояние анализа ПЕРЕД навигацией
        ref.read(analysis.resetAnalysisStateProvider)();

        // Короткая задержка для отрисовки экрана перехода, затем сразу скрываем
        await Future.delayed(const Duration(milliseconds: 80));
        try {
          LoadingManager().hideLoadingScreen();
        } catch (_) {}

        if (mounted) {
          final today = DateTime.now();
          print(
              '🔄 FoodAnalysisScreen (onWillPop): Переключение на сегодня: ${today.day}.${today.month}.${today.year}');
          ref.read(date_selector.selectedDateProvider.notifier).state = today;
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/home', (route) => false);
          debugPrint('🧭 Навигация: возврат на /home из onWillPop');
        }

        return false; // навигация уже выполнена
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(0), // Скрываем AppBar полностью
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
        body: Stack(
          children: [
            // Основной контент с нижней панелью
            Column(
              children: [
                // Основной контент в Expanded с SingleChildScrollView
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Область изображения
                        _buildImageSection(),

                        // Информация о еде
                        analysisState.when(
                          data: (nutritionInfo) {
                            // Если блюдо успешно проанализировано, показываем информацию о нём
                            return _buildAnalysisResults(nutritionInfo);
                          },
                          // Вместо спиннера показываем скелетон с шиммерами, чтобы контент появлялся плавно
                          loading: () => Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16.0, vertical: 8.0),
                            child: _buildAnalysisResults(NutritionInfo.empty()),
                          ),
                          error: (e, _) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    context
                                        .tr('food_analysis_error')
                                        .replaceAll('{0}', e.toString()),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () =>
                                        _analyzeImage(imageFile: _imageFile),
                                    child: Text(context.tr('retry')),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Добавляем выбор времени и отступ внизу для кнопок
                        // Показываем строку времени для обоих режимов (новый анализ и история)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: InkWell(
                            onTap: () async {
                              final isHistoryView =
                                  ref.read(analysis.isHistoryViewProvider);
                              if (isHistoryView) {
                                final meal = ref
                                    .read(analysis.selectedHistoryMealProvider);
                                if (meal != null) {
                                  await _changeMealDateTime(meal);
                                }
                                return;
                              }
                              await Future<void>.delayed(
                                  const Duration(milliseconds: 1));
                              final double submitButtonWidth =
                                  MediaQuery.of(context).size.width - 32;
                              BottomPicker.dateTime(
                                onSubmit: (date) async {
                                  setState(() {
                                    _mealDateTime = date;
                                  });
                                },
                                initialDateTime: _mealDateTime,
                                minDateTime: DateTime.now()
                                    .subtract(const Duration(days: 365)),
                                maxDateTime: DateTime.now(),
                                buttonContent: Center(
                                  child: Text(
                                    context.tr('select'),
                                    style: const TextStyle(
                                        fontSize: 16, color: Colors.white),
                                  ),
                                ),
                                buttonWidth: submitButtonWidth,
                                buttonPadding: 12,
                                use24hFormat: true,
                                buttonSingleColor: Colors.blue,
                              ).show(context);
                            },
                            child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    Expanded(
                                        child:
                                            Text(context.tr('time_of_adding'))),
                                    Builder(builder: (_) {
                                      final isHistoryView = ref.watch(
                                          analysis.isHistoryViewProvider);
                                      if (isHistoryView) {
                                        final meal = ref.watch(analysis
                                            .selectedHistoryMealProvider);
                                        final time =
                                            meal?.dateTime ?? DateTime.now();
                                        return Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                            style: const TextStyle(
                                              color: Colors.blue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        );
                                      }
                                      return Align(
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          '${_mealDateTime.hour.toString().padLeft(2, '0')}:${_mealDateTime.minute.toString().padLeft(2, '0')}',
                                          style: const TextStyle(
                                            color: Colors.blue,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                )),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

                // Нижняя панель с кнопками
                // Если открыто из истории — показываем панель действий истории,
                // иначе — стандартные кнопки сохранения/правки
                Builder(builder: (context) {
                  final isHistoryView =
                      ref.watch(analysis.isHistoryViewProvider);
                  if (isHistoryView) {
                    return _buildHistoryActionsPanel();
                  }
                  return _buildBottomButtonsPanel();
                }),
              ],
            ),

            // Кнопка назад поверх всего контента
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: (_isAnalysisInProgress ||
                          (ref.read(analysis.nutritionAnalysisStateProvider)
                              is AsyncLoading))
                      ? null
                      : () {
                          _shouldCancelAnalysis = true;
                          final isHistoryView =
                              ref.read(analysis.isHistoryViewProvider);
                          if (isHistoryView) {
                            Navigator.of(context).pop();
                            return;
                          }

                          // Показываем специальный экран перехода перед навигацией
                          LoadingManager().showTransitionScreen(
                            context,
                            text: context.tr('food_screen_home_return'),
                            processingStepText:
                                context.tr('food_screen_preparing_transition'),
                          );

                          // Сбрасываем состояние анализа ПЕРЕД навигацией
                          ref.read(analysis.resetAnalysisStateProvider)();

                          // Скрываем оверлей и уходим на /home
                          try {
                            LoadingManager().hideLoadingScreen();
                          } catch (_) {}

                          final today = DateTime.now();
                          print(
                              '🔄 FoodAnalysisScreen (BackButton): Переключение на сегодня: ${today.day}.${today.month}.${today.year}');
                          ref
                              .read(date_selector.selectedDateProvider.notifier)
                              .state = today;

                          Navigator.of(context).pushNamedAndRemoveUntil(
                              '/home', (route) => false);
                          return;
                        },
                ),
              ),
            ),
            // Кнопка избранного справа сверху
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: Consumer(builder: (context, ref, _) {
                final analysisState =
                    ref.watch(analysis.nutritionAnalysisStateProvider);
                final info = analysisState is AsyncData<NutritionInfo>
                    ? analysisState.value
                    : NutritionInfo.empty();
                final id = (info.dishName).trim().toLowerCase();
                final isFav = id.isNotEmpty &&
                    ref.watch(favoritesProvider).any((e) => e.id == id);
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      isFav ? Icons.star : Icons.star_border,
                      color: Colors.white,
                    ),
                    onPressed: (info.dishName.isEmpty ||
                            _isAnalysisInProgress ||
                            analysisState is AsyncLoading)
                        ? null
                        : () async {
                            await ref
                                .read(favoritesProvider.notifier)
                                .toggleFromNutritionInfo(info,
                                    imageFile: _imageFile);
                          },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // Метод для отображения BottomSheet для редактирования результата
  void _showEditResultBottomSheet() {
    final analysisState = ref.read(analysis.nutritionAnalysisStateProvider);

    if (analysisState is! AsyncData<NutritionInfo>) return;

    final nutritionInfo = analysisState.value;

    TextEditingBottomSheet.show(
      context: context,
      initialText: nutritionInfo.dishName,
      title: context.tr('enter_food_name'),
      hintText: context.tr('dish_example'),
      onSave: (newName) async {
        if (newName.isEmpty) return;

        // Если название изменилось, проводим новый анализ
        if (newName != nutritionInfo.dishName) {
          // Обновляем текстовый контроллер
          setState(() {
            _dishNameController.text = newName;
          });

          // Запускаем новый анализ блюда по названию
          if (mounted) {
            // Показываем экран загрузки
            LoadingManager().showLoadingScreen(
              context,
              text: context.tr('analyzing_request').replaceAll('{0}', newName),
              animationPath: 'assets/animations/road.json',
              animationHeight: MediaQuery.of(context).size.height * 0.4,
              backgroundColor: Colors.white,
              processingStepText: context.tr('processing_step_vision'),
              progressValue: 0.1,
            );

            // Небольшая задержка для обновления UI
            await Future.delayed(const Duration(milliseconds: 200));

            // Проводим анализ по новому названию
            try {
              debugPrint(
                  '🔄 Запуск нового анализа после изменения названия: $newName');

              // Получаем сервис DeepSeek
              final nutritionService =
                  ref.read(services.deepSeekNutritionServiceProvider);

              // Обновляем информацию о процессе
              LoadingManager().updateProcessingInfo(
                context,
                newText: context.tr('nutritional_analysis'),
                newProcessingStep:
                    context.tr('deepseek_request').replaceAll('{0}', newName),
                newProgressValue: 0.4,
                animationPath: 'assets/animations/road.json',
                animationHeight: MediaQuery.of(context).size.height * 0.4,
              );

              // Устанавливаем флаг анализа в процессе, чтобы предотвратить повторный анализ
              setState(() {
                _isAnalysisInProgress = true;
              });

              // Отправляем запрос к DeepSeek для анализа
              final updatedInfo = await nutritionService
                  .analyzeDishByName(newName, context: context);

              debugPrint('✅ Новый анализ завершен после изменения названия');
              debugPrint('✅ Результат: ${updatedInfo.dishName}');

              // Обновляем состояние с результатами
              ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
                  AsyncValue.data(updatedInfo);

              // Сохраняем результаты для восстановления при необходимости
              ref.read(analysis.lastAnalysisResultsProvider.notifier).state =
                  analysis.AnalysisResults(
                info: updatedInfo,
                timestamp: DateTime.now(),
              );
              // Обновляем информацию о процессе
              LoadingManager().updateProcessingInfo(
                context,
                newText: context.tr('analysis_completed'),
                newProcessingStep: context.tr('food_analysis_updated'),
                newProgressValue: 1.0,
                animationPath: 'assets/animations/road.json',
                animationHeight: MediaQuery.of(context).size.height * 0.4,
              );

              // Короткая задержка перед скрытием экрана загрузки
              await Future.delayed(const Duration(seconds: 1));

              // Скрываем экран загрузки
              if (mounted) {
                try {
                  LoadingManager().hideLoadingScreen();
                  debugPrint(
                      '📷 Загрузочный экран скрыт после успешного анализа');
                } catch (e) {
                  debugPrint(
                      '❌ Ошибка при скрытии экрана загрузки после успешного анализа: $e');
                }
              }
            } catch (error) {
              debugPrint(
                  '❌ Ошибка при анализе после изменения названия: $error');

              // Показываем сообщение об ошибке в экране загрузки
              LoadingManager().updateProcessingInfo(
                context,
                newText:
                    context.tr('food_analysis_error').replaceAll('{0}', ''),
                newProcessingStep: context
                    .tr('error_occurred')
                    .replaceAll('{0}', error.toString()),
                newProgressValue: 1.0,
                animationPath: 'assets/animations/road.json',
                animationHeight: MediaQuery.of(context).size.height * 0.4,
              );

              // Создаем обновленную информацию только с новым названием
              final simpleUpdatedInfo = NutritionInfo.empty()
                  .copyWith(dishName: _dishNameController.text);

              // Обновляем состояние хотя бы с новым названием
              ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
                  AsyncValue.data(simpleUpdatedInfo);

              // Сохраняем результаты
              ref.read(analysis.lastAnalysisResultsProvider.notifier).state =
                  analysis.AnalysisResults(
                info: simpleUpdatedInfo,
                timestamp: DateTime.now(),
              );

              // Задержка перед скрытием экрана загрузки
              await Future.delayed(const Duration(seconds: 2));

              // Скрываем экран загрузки
              if (mounted) {
                try {
                  LoadingManager().hideLoadingScreen();
                  debugPrint('📷 Загрузочный экран скрыт после ошибки');
                } catch (e) {
                  debugPrint(
                      '❌ Ошибка при скрытии экрана загрузки после ошибки: $e');
                }
              }
            } finally {
              // Сбрасываем флаг анализа в процессе
              if (mounted) {
                setState(() {
                  _isAnalysisInProgress = false;
                });
              }
            }
          }
        } else {
          // Если название не изменилось, просто сохраняем текущее состояние
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('name_not_changed'))),
          );
        }
      },
    );
  }

  Widget _buildAnalysisResults(NutritionInfo info) {
    // Во время активного стрима не показываем ошибку, пока нет финальных данных
    final isStreamingEmpty = _isAnalysisInProgress &&
        info.dishName.isEmpty &&
        info.calories == 0 &&
        info.proteins == 0 &&
        info.fats == 0 &&
        info.carbs == 0 &&
        info.ingredients.isEmpty;

    // Проверяем наличие сообщения об ошибке (не еда)
    if (!isStreamingEmpty && info.error != null && info.error!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('food_not_recognized'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      info.error!,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Нулевые значения: если идет стрим — показываем шиммеры вместо ошибки
    bool isEmptyAnalysis = info.calories == 0 &&
        info.proteins == 0 &&
        info.fats == 0 &&
        info.carbs == 0 &&
        info.ingredients.isEmpty;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Название блюда
          if (info.dishName.isEmpty)
            _buildShimmerBox(height: 28, radius: 6)
          else
            Text(
              info.dishName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),

          const SizedBox(height: 12),

          // Всегда показываем основной контейнер результатов, чтобы карточка
          // не «прыгала» по ширине. Если данных пока нет — внутри остаются
          // шиммеры, которые затем плавно исчезают.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isEmptyAnalysis && !isStreamingEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildShimmerBox(height: 18, radius: 6),
                    const SizedBox(height: 8),
                    _buildShimmerBox(height: 14, radius: 6),
                    const SizedBox(height: 6),
                    _buildShimmerBox(height: 14, radius: 6),
                    const SizedBox(height: 12),
                  ],
                ),
              // Нутриционная карточка с закругленными углами
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // КБЖУ: прижимаем "Углеводы" максимально вправо
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _maybeShimmer(
                              visible: info.calories > 0,
                              child: _buildNutrientItem(
                                context.tr('calories'),
                                "${info.calories.toStringAsFixed(1)} ${context.tr('calories_suffix')}",
                                Colors.red,
                                onTap: () =>
                                    _editNutrient(_NutrientField.calories),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.center,
                            child: _maybeShimmer(
                              visible: info.proteins > 0,
                              child: _buildNutrientItem(
                                context.tr('proteins'),
                                "${info.proteins.toStringAsFixed(1)} ${context.tr('grams_suffix')}",
                                Colors.green,
                                onTap: () =>
                                    _editNutrient(_NutrientField.proteins),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.center,
                            child: _maybeShimmer(
                              visible: info.fats > 0,
                              child: _buildNutrientItem(
                                context.tr('fats'),
                                "${info.fats.toStringAsFixed(1)} ${context.tr('grams_suffix')}",
                                Colors.yellow.shade800,
                                onTap: () => _editNutrient(_NutrientField.fats),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _maybeShimmer(
                              visible: info.carbs > 0,
                              child: _buildNutrientItem(
                                context.tr('carbs'),
                                "${info.carbs.toStringAsFixed(1)} ${context.tr('grams_suffix')}",
                                Colors.purple,
                                onTap: () =>
                                    _editNutrient(_NutrientField.carbs),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Индикатор полезности блюда (0..5)
                    if (info.healthiness > 0)
                      _buildHealthinessIndicator(context, info.healthiness),
                    if (_isAnalysisInProgress && info.ingredients.isEmpty) ...[
                      const SizedBox(height: 16),
                      _buildShimmerBox(height: 18, radius: 6),
                      const SizedBox(height: 8),
                      _buildShimmerBox(height: 14, radius: 6),
                      const SizedBox(height: 6),
                      _buildShimmerBox(height: 14, radius: 6),
                      const SizedBox(height: 6),
                      _buildShimmerBox(height: 14, radius: 6),
                    ] else if ((_isAnalysisInProgress &&
                            _progressiveIngredients.isNotEmpty) ||
                        info.ingredients.isNotEmpty) ...[
                      //const Divider(),
                      //const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('recognized_ingredients'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 0),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 24, minHeight: 24),
                              icon: const Icon(Icons.edit, size: 20),
                              tooltip: context.tr('edit'),
                              onPressed: () async {
                                final analysisState = ref.read(
                                    analysis.nutritionAnalysisStateProvider);
                                if (analysisState is! AsyncData<NutritionInfo>)
                                  return;
                                final info = analysisState.value;
                                final updatedList =
                                    await IngredientListEditingBottomSheet.show(
                                  context: context,
                                  ingredients: _isAnalysisInProgress &&
                                          _progressiveIngredients.isNotEmpty
                                      ? _progressiveIngredients
                                      : info.ingredients,
                                );
                                if (updatedList == null) return;

                                final updatedInfo =
                                    info.copyWith(ingredients: updatedList);
                                ref
                                    .read(analysis
                                        .nutritionAnalysisStateProvider
                                        .notifier)
                                    .state = AsyncValue.data(updatedInfo);
                                ref
                                    .read(analysis
                                        .lastAnalysisResultsProvider.notifier)
                                    .state = analysis.AnalysisResults(
                                  info: updatedInfo,
                                  timestamp: DateTime.now(),
                                );
                                // Отмечаем изменения как несохраненные в режиме истории
                                if (ref.read(analysis.isHistoryViewProvider)) {
                                  setState(() {
                                    _hasUnsavedHistoryChanges = true;
                                  });
                                }

                                // В режиме истории не сохраняем немедленно — включаем режим изменений
                                final isHistoryView =
                                    ref.read(analysis.isHistoryViewProvider);
                                if (isHistoryView) {
                                  setState(() {
                                    _hasUnsavedHistoryChanges = true;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      // Небольшой отступ после заголовка
                      //const SizedBox(height: 4),
                      ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _isAnalysisInProgress
                            ? _progressiveIngredients.length
                            : info.ingredients.length,
                        itemBuilder: (context, index) {
                          final ingredient = _isAnalysisInProgress
                              ? _progressiveIngredients[index]
                              : info.ingredients[index];
                          final widget = _isAnalysisInProgress
                              ? _buildTypewriterIngredient(
                                  ingredient.name,
                                  ingredient.weight,
                                  context.tr('grams_suffix'),
                                  Duration(milliseconds: 15 + index * 4),
                                )
                              : _buildIngredientRow(
                                  ingredient.name,
                                  ingredient.weight,
                                  context.tr('grams_suffix'),
                                );
                          return widget;
                        },
                      ),
                    ],
                  ],
                ),
              ),

              // Добавляем больше отступа внизу для удобства
              //const SizedBox(height: 32),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientItem(String label, String value, Color color,
      {VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.pie_chart,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // Индикатор полезности блюда, стилистически ближе к горизонтальным индикаторам
  // Использует 5 сегментов со стилем разделителей как у калорий (иконки/цвета экрана анализа)
  Widget _buildHealthinessIndicator(BuildContext context, double value) {
    final clamped = value.clamp(0, 5).toDouble();
    final int full = clamped.floor();
    final bool hasHalf = (clamped - full) >= 0.5 && full < 5;

    // Дискретные цвета: 1 — красный, 2–3 — жёлтый, 4–5 — зелёный (0 — серый)
    final int score = clamped.round().clamp(0, 5).toInt();
    final Color activeColor = score <= 0
        ? Colors.grey
        : (score == 1
            ? Colors.red
            : (score <= 3 ? Colors.amber : Colors.green));
    final Color inactiveColor = Colors.grey[200]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.tr('healthiness'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${clamped.round()} / 5',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (index) {
              final bool isFull = index < full;
              final bool isHalf = index == full && hasHalf;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 4,
                    right: index == 4 ? 0 : 4,
                  ),
                  child: _buildHealthSegment(
                    color: activeColor,
                    inactiveColor: inactiveColor,
                    filled: isFull,
                    half: isHalf,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // Сегмент индикатора полезности с возможностью половинного заполнения
  Widget _buildHealthSegment({
    required Color color,
    required Color inactiveColor,
    required bool filled,
    required bool half,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 12,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(color: inactiveColor),
            ),
            if (filled || half)
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: half ? 0.5 : 1.0,
                  child: Container(color: color),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Оборачивает child и поверх рисует шиммер, пока данные не готовы.
  // Это сохраняет итоговую разметку и исключает «прыжок» ширины.
  Widget _maybeShimmer({
    required bool visible,
    required Widget child,
    double width = double.infinity,
  }) {
    return SizedBox(
      width: width,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: child,
          ),
          // Серый слой с шиммером поверх, пока контент недоступен
          if (!visible)
            Positioned.fill(
              child: Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShimmerBox({double height = 16, double radius = 8}) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  Widget _buildIngredientRow(String name, double weight, String unitSuffix) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "${weight.toStringAsFixed(1)} $unitSuffix",
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypewriterIngredient(
    String name,
    double weight,
    String unitSuffix,
    Duration speed,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: AnimatedTextKit(
              isRepeatingAnimation: false,
              totalRepeatCount: 1,
              displayFullTextOnTap: true,
              animatedTexts: [
                TypewriterAnimatedText(
                  name,
                  textStyle: const TextStyle(fontSize: 14),
                  speed: speed,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "${weight.toStringAsFixed(1)} $unitSuffix",
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // Метод для отображения изображения блюда
  Widget _buildImageSection() {
    final imageWidget = _imageFile != null
        ? Image.file(
            _imageFile!,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              return _buildImageShimmer();
            },
            errorBuilder: (context, error, stack) {
              return _buildImageShimmer();
            },
          )
        : _buildImageShimmer();

    return Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.height * 0.4,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        child: imageWidget,
      ),
    );
  }

  Widget _buildImageShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        color: Colors.white,
      ),
    );
  }

  /// Создает программный файл-изображение и возвращает его путь
  Future<File> _createProgrammaticImageFile(String dishName) async {
    final info = NutritionInfo.empty().copyWith(dishName: dishName);
    await _generateImageForDish(info);
    return _imageFile!;
  }

  /// Гарантирует изображение по ПОЛНОЙ фразе пользователя (или dishName), затем fallback
  Future<void> _ensureImageForInputOrDish(NutritionInfo info) async {
    try {
      final manualPhrase = ref.read(analysis.manualFoodInputProvider);
      final query = manualPhrase.isNotEmpty ? manualPhrase : info.dishName;
      if (query.isEmpty) return;

      final imageSearchService = ref.read(services.imageSearchServiceProvider);
      File? file = await imageSearchService.findImage(query);
      file ??= await _createProgrammaticImageFile(query);
      if (!mounted) return;
      setState(() {
        _imageFile = file;
        _imageGenerated = true;
      });
      ref.read(analysis.selectedImageProvider.notifier).state = file;
      final currentState = ref.read(analysis.nutritionAnalysisStateProvider);
      if (currentState is AsyncData<NutritionInfo>) {
        final updated = currentState.value.copyWith(imagePath: file.path);
        ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
            AsyncValue.data(updated);
        ref.read(analysis.lastAnalysisResultsProvider.notifier).state =
            analysis.AnalysisResults(
          info: updated,
          timestamp: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('❌ _ensureImageForInputOrDish: $e');
    }
  }

  // Нижняя панель с кнопками "Сохранить" и "Изменить результат"
  Widget _buildBottomButtonsPanel() {
    final analysisState = ref.watch(analysis.nutritionAnalysisStateProvider);
    final isHistoryView = ref.watch(analysis.isHistoryViewProvider);

    // Не показываем панель, если это просмотр из истории
    if (isHistoryView) return const SizedBox.shrink();

    final hasValidResults = analysisState is AsyncData<NutritionInfo> &&
        !analysisState.hasError &&
        analysisState.value.dishName.isNotEmpty;

    final isFullyReady =
        hasValidResults && _imageFile != null && !_isAnalysisInProgress;

    // Проверяем, нет ли сообщения об ошибке "не еда"
    final hasErrorMessage = analysisState is AsyncData<NutritionInfo> &&
        analysisState.value.error != null &&
        analysisState.value.error!.isNotEmpty;

    if (!hasValidResults || hasErrorMessage) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: 8.0 +
            MediaQuery.of(context)
                .padding
                .bottom, // Уменьшили отступ в 2 раза + безопасная зона iPhone
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Кнопка "Изменить результат"
          Expanded(
            flex: 1,
            child: ElevatedButton.icon(
              onPressed: isFullyReady ? _showEditResultBottomSheet : null,
              icon: const Icon(
                Icons.edit,
                color: Colors.white,
              ),
              label: Text(
                context.tr('text_editing_cancel'),
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Кнопка "Сохранить"
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: (_isSaving || !isFullyReady) ? null : _saveMeal,
              icon: const Icon(
                Icons.save,
                color: Colors.white,
              ),
              label: Text(
                _isSaving
                    ? context.tr('loading')
                    : (isFullyReady
                        ? context.tr('save')
                        : context.tr('loading')),
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Панель действий при просмотре из истории: удалить и изменить время
  Widget _buildHistoryActionsPanel() {
    final meal = ref.watch(analysis.selectedHistoryMealProvider);
    if (meal == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: 20.0,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _confirmDelete(meal),
              icon: const Icon(Icons.delete, color: Colors.white),
              label: Text(context.tr('delete'),
                  style: const TextStyle(fontSize: 16, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: !_hasUnsavedHistoryChanges
                  ? null
                  : () async {
                      final selected =
                          ref.read(analysis.selectedHistoryMealProvider);
                      if (selected == null) return;
                      // Сохраняем изменения ингредиентов/КБЖУ для записи истории
                      try {
                        final analysisState =
                            ref.read(analysis.nutritionAnalysisStateProvider);
                        if (analysisState is! AsyncData<NutritionInfo>) return;
                        final info = analysisState.value;
                        final updatedMeal = MealModel(
                          id: selected.id,
                          name: selected.name,
                          dateTime: selected.dateTime,
                          imagePath: selected.imagePath,
                          ingredients: info.ingredients
                              .map((i) => IngredientModel(
                                  name: i.name,
                                  quantity: i.weight,
                                  unit: IngredientUnits.GRAMS))
                              .toList(),
                          nutrients: MealNutrientsModel(
                            calories: info.calories.round(),
                            proteins: info.proteins,
                            fats: info.fats,
                            carbs: info.carbs,
                          ),
                        );

                        final mealRepository =
                            ref.read(home.mealRepositoryProvider);
                        await mealRepository.updateMeal(updatedMeal);

                        final day = DateTime(selected.dateTime.year,
                            selected.dateTime.month, selected.dateTime.day);
                        ref.invalidate(analytics.weeklyNutrientsProvider);
                        ref.invalidate(
                            analytics.dailyNutrientsForDateProvider(day));
                        ref.invalidate(home.mealsForDateProvider(day));
                        ref.invalidate(home.nutrientsForDateProvider(day));
                        ref
                            .read(analysis.selectedHistoryMealProvider.notifier)
                            .state = updatedMeal;
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.tr('meal_saved'))),
                          );
                        }
                        setState(() {
                          _hasUnsavedHistoryChanges = false;
                        });
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(context
                                    .tr('saving_error')
                                    .replaceAll('{0}', e.toString()))),
                          );
                        }
                      }
                    },
              icon: const Icon(Icons.save, color: Colors.white),
              label: Text(
                context.tr('save'),
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(MealModel meal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('confirm_delete_title')),
        content: Text(context.tr('confirm_delete_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final mealRepository = ref.read(home.mealRepositoryProvider);
    await mealRepository.deleteMeal(meal.id);

    // Инвалидируем аналитические провайдеры для соответствующего дня
    ref.invalidate(analytics.weeklyNutrientsProvider);
    ref.invalidate(analytics.dailyNutrientsForDateProvider(DateTime(
      meal.dateTime.year,
      meal.dateTime.month,
      meal.dateTime.day,
    )));

    // Сообщаем результат и закрываем
    ref.read(analysis.mealActionResultProvider.notifier).state =
        MealActionResult.deleted();
    // Немедленно инвалидируем список приемов пищи за текущий день
    final day =
        DateTime(meal.dateTime.year, meal.dateTime.month, meal.dateTime.day);
    ref.invalidate(home.mealsForDateProvider(day));
    if (mounted) {
      ref.read(analysis.resetAnalysisStateProvider)();
      Navigator.of(context).pop();
    }
  }

  Future<void> _changeMealDateTime(MealModel meal) async {
    DateTime initial = meal.dateTime;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final double submitButtonWidth = MediaQuery.of(context).size.width - 32;
    BottomPicker.dateTime(
      onSubmit: (date) async {
        try {
          final updated = MealModel(
            id: meal.id,
            name: meal.name,
            dateTime: date,
            imagePath: meal.imagePath,
            ingredients: meal.ingredients,
            nutrients: meal.nutrients,
          );
          final mealRepository = ref.read(home.mealRepositoryProvider);
          await mealRepository.updateMeal(updated);

          // Инвалидируем аналитику для старого и нового дня
          ref.invalidate(analytics.weeklyNutrientsProvider);
          final oldDate = DateTime(
              meal.dateTime.year, meal.dateTime.month, meal.dateTime.day);
          final newDate = DateTime(date.year, date.month, date.day);
          ref.invalidate(analytics.dailyNutrientsForDateProvider(oldDate));
          ref.invalidate(analytics.dailyNutrientsForDateProvider(newDate));
          // Инвалидируем списки истории для обоих дней, чтобы элемент не мелькал в старом месте
          ref.invalidate(home.mealsForDateProvider(oldDate));
          ref.invalidate(home.mealsForDateProvider(newDate));
          // Результат для обновления истории и возможного перехода на другой день
          ref.read(analysis.mealActionResultProvider.notifier).state =
              MealActionResult.moved(date);
          if (mounted) {
            ref.read(analysis.resetAnalysisStateProvider)();
            Navigator.of(context).pop();
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(context.tr('saving_error').replaceAll('{0}', ''))),
          );
        }
      },
      initialDateTime: initial,
      minDateTime: DateTime.now().subtract(const Duration(days: 365)),
      maxDateTime: DateTime.now(), // Ограничиваем до текущего дня включительно
      // Кастомный контент и размер кнопки подтверждения
      buttonContent: Center(
        child: Text(
          context.tr('select'),
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
      ),
      buttonWidth: submitButtonWidth,
      buttonPadding: 12,
      // 24-часовой формат времени
      use24hFormat: true,
      buttonSingleColor: Colors.blue,
    ).show(context);
  }

  /// Безопасно сбрасывает состояние анализа с проверкой mounted
  void _safeResetAnalysisState() {
    // Проверяем, что виджет все еще смонтирован
    if (!mounted) {
      debugPrint('⚠️ Попытка сбросить состояние анализа после dispose виджета');
      return;
    }

    // Скрываем экран загрузки, если он отображается
    LoadingManager().hideLoadingScreen();

    // Сбрасываем состояние анализа в начальное значение
    ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
        AsyncValue.data(NutritionInfo.empty());

    // Очищаем последние результаты анализа
    ref.read(analysis.lastAnalysisResultsProvider.notifier).state = null;

    debugPrint('🔄 Безопасный сброс состояния анализа выполнен');
  }

  /// Генерирует изображение для блюда на основе его названия и типа
  Future<void> _generateImageForDish(NutritionInfo info) async {
    try {
      debugPrint('🎨 Создание изображения для блюда: ${info.dishName}');

      // Получаем директорию для временных файлов
      final tempDir = await getApplicationDocumentsDirectory();
      final fileName = FileUtils.generateDishImageFileName(info.dishName);
      final filePath = path.join(tempDir.path, fileName);

      // Создаем изображение с градиентным фоном и текстом
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(400, 300);

      // Рисуем градиентный фон
      final rect = Rect.fromLTWH(0, 0, size.width, size.height);
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
          text: info.dishName,
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

      // Получаем изображение из рекордера
      final picture = recorder.endRecording();
      final img =
          await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await img.toByteData(format: ImageByteFormat.png);

      if (byteData == null) {
        debugPrint('❌ Не удалось создать данные изображения');
        return;
      }

      // Записываем созданное изображение в файл
      final imageFile = File(filePath);
      await imageFile.parent.create(recursive: true);
      await imageFile.writeAsBytes(
          byteData.buffer
              .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
          flush: true);

      debugPrint('✅ Создано программное изображение блюда: $filePath');

      // Устанавливаем созданное изображение
      setState(() {
        _imageFile = imageFile;
      });

      // Сохраняем изображение в провайдере
      ref.read(analysis.selectedImageProvider.notifier).state = _imageFile;
    } catch (e) {
      debugPrint('❌ Ошибка при создании изображения для блюда: $e');
    }
  }

  /// Анализирует текущее выбранное изображение
  Future<void> _analyzeImage(
      {File? imageFile,
      String? recognizedVoice,
      bool skipLoadingScreen = false}) async {
    if (imageFile == null && recognizedVoice == null) {
      debugPrint('⚠️ Нет данных для анализа!');
      return;
    }

    // ДОПОЛНИТЕЛЬНАЯ ЗАЩИТА: Проверяем текущее состояние анализа
    if (recognizedVoice == null && imageFile != null) {
      final currentState = ref.read(analysis.nutritionAnalysisStateProvider);
      if (currentState is AsyncData<NutritionInfo>) {
        final info = currentState.value;
        if (info.dishName.isNotEmpty && info.calories > 0) {
          debugPrint(
              '✅ ЗАЩИТА: Уже есть действительные результаты анализа "${info.dishName}", пропускаем анализ изображения');
          return;
        }
      }
    }

    try {
      setState(() {
        _isAnalysisInProgress = true;
        _progressiveIngredients.clear();
        _ingredientNameSet.clear();
        _ingredientsVersion++;
        _currentDishName = null;
      });
      // Получаем унифицированный сервис анализа
      final unifiedAnalysisService =
          ref.read(services.unifiedAnalysisServiceProvider);

      // Показываем экран загрузки для пользователя, если не указано пропустить
      if (!skipLoadingScreen && mounted) {
        setState(() {
          _isLoading = true;
        });

        LoadingManager().showLoadingScreen(
          context,
          text: context.tr('request_analysis'),
          animationPath: 'assets/animations/road.json',
          animationHeight: MediaQuery.of(context).size.height * 0.4,
          backgroundColor: Colors.white,
          processingStepText: _getInitialProcessingText(recognizedVoice),
          progressValue: 0.1,
        );
      }

      // Устанавливаем состояние загрузки для Riverpod
      ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
          const AsyncValue.loading();

      // Плавная оркестрация прогресса и статусов до первого чанка от модели
      bool firstEmitted = false;
      double currentProgress = 0.1;
      String lastStepText = _getInitialProcessingText(recognizedVoice);
      String lastMainText = recognizedVoice == null
          ? context.tr('analyzing_image')
          : context.tr('request_analysis');

      Future<void> animatePhase({
        required String stepText,
        required double from,
        required double to,
        required Duration duration,
        required String mainText,
      }) async {
        final int steps = 12;
        final int stepMs = (duration.inMilliseconds / steps).round();
        for (int i = 0; i < steps; i++) {
          if (_shouldCancelAnalysis ||
              firstEmitted ||
              skipLoadingScreen ||
              !mounted) return;
          final double t = (i + 1) / steps;
          currentProgress = from + (to - from) * t;
          LoadingManager().updateProcessingInfo(
            context,
            newText: mainText,
            newProcessingStep: stepText,
            newProgressValue: currentProgress.clamp(0.0, 0.95),
          );
          await Future.delayed(Duration(milliseconds: stepMs));
          lastStepText = stepText;
          lastMainText = mainText;
        }
      }

      Future<void> progressOrchestrator() async {
        try {
          if (_shouldCancelAnalysis || skipLoadingScreen || !mounted) return;

          if (recognizedVoice == null) {
            // Фото/галерея: Vision -> Распознавание объектов
            await animatePhase(
              stepText: context.tr('processing_step_vision'),
              from: currentProgress,
              to: 0.4,
              duration: const Duration(milliseconds: 1500),
              mainText: context.tr('analyzing_image'),
            );
            if (firstEmitted || !mounted) return;
            await animatePhase(
              stepText: context.tr('recognizing_objects'),
              from: currentProgress,
              to: 0.85,
              duration: const Duration(milliseconds: 1100),
              mainText: context.tr('analyzing_image'),
            );
          } else {
            // Текст/голос: Анализ пит. ценности -> AI запрос
            await animatePhase(
              stepText: context.tr('nutritional_analysis'),
              from: currentProgress,
              to: 0.3,
              duration: const Duration(milliseconds: 700),
              mainText: context.tr('request_analysis'),
            );
            if (firstEmitted || !mounted) return;
            await animatePhase(
              stepText: context.trParams('deepseek_request', [recognizedVoice]),
              from: currentProgress,
              to: 0.85,
              duration: const Duration(milliseconds: 1300),
              mainText: context.tr('nutritional_analysis'),
            );
          }

          // Медленное подрастание до 0.92, если первый чанк ещё не пришёл
          while (!_shouldCancelAnalysis &&
              !firstEmitted &&
              mounted &&
              !skipLoadingScreen &&
              currentProgress < 0.92) {
            currentProgress = (currentProgress + 0.02).clamp(0.0, 0.92);
            LoadingManager().updateProcessingInfo(
              context,
              newText: lastMainText,
              newProcessingStep: lastStepText,
              newProgressValue: currentProgress,
            );
            await Future.delayed(const Duration(milliseconds: 250));
          }
        } catch (_) {}
      }

      // Запускаем прогресс-оркестратор параллельно ожиданию первого чанка
      if (!skipLoadingScreen && mounted) {
        progressOrchestrator();
      }

      // Подписываемся на поток частичных результатов, чтобы обновлять UI по мере поступления
      Stream<NutritionInfo> stream;
      if (recognizedVoice != null) {
        stream = unifiedAnalysisService.analyzeStream(
            context: context, recognizedVoice: recognizedVoice);
      } else if (imageFile != null) {
        stream = unifiedAnalysisService.analyzeStream(
            context: context, imageFile: imageFile);
      } else {
        throw Exception('Нет данных для анализа');
      }

      // Подписка на поток результатов
      // firstEmitted определен выше и используется для остановки анимации
      await for (final nutritionInfo in stream) {
        if (_shouldCancelAnalysis || !mounted) {
          break;
        }
        // На первом элементе — скрываем лоадер, чтобы UI показался сразу
        if (!firstEmitted) {
          firstEmitted = true;
          if (!skipLoadingScreen && mounted) {
            try {
              LoadingManager().updateProcessingInfo(
                context,
                newText: context.tr('analysis_completed'),
                newProcessingStep: context.tr('analysis_completed'),
                newProgressValue: 1.0,
              );
              await Future.delayed(const Duration(milliseconds: 200));
              LoadingManager().hideLoadingScreen();
            } catch (_) {}
          }
        }

        // Обновляем провайдер частичным/полным результатом
        if (!mounted || _shouldCancelAnalysis) break;
        ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
            AsyncValue.data(nutritionInfo);

        // Сохраняем последние результаты
        ref.read(analysis.lastAnalysisResultsProvider.notifier).state =
            analysis.AnalysisResults(
          info: nutritionInfo,
          timestamp: DateTime.now(),
        );

        // Обновляем текстовое поле имени блюда по мере поступления
        if (mounted &&
            !_shouldCancelAnalysis &&
            nutritionInfo.dishName.isNotEmpty) {
          setState(() {
            _dishNameController.text = nutritionInfo.dishName;
            _analysisCompleted = true;

            if (nutritionInfo.imagePath != null &&
                nutritionInfo.imagePath!.isNotEmpty) {
              final imageFromPath = File(nutritionInfo.imagePath!);
              if (imageFromPath.existsSync()) {
                _imageFile = imageFromPath;
                _imageGenerated = true;
              }
            }
            // Если сменилось блюдо — сбрасываем прогрессивный список и версию
            if (_currentDishName != nutritionInfo.dishName) {
              _currentDishName = nutritionInfo.dishName;
              _progressiveIngredients.clear();
              _ingredientNameSet.clear();
              _ingredientsVersion++;
            }
          });

          // Потоковое добавление ингредиентов по мере поступления
          if (nutritionInfo.ingredients.isNotEmpty) {
            _appendIngredientsGradually(nutritionInfo.ingredients);
          }

          // Получение реального изображения выполняем после завершения стрима,
          // чтобы избежать поиска по неполному названию (например, "бор").
        }
      }

      // Добавляем небольшую задержку для отображения результата
      await Future.delayed(const Duration(milliseconds: 300));

      // После завершения стрима пробуем получить реальное изображение через поиск
      if (mounted &&
          !_shouldCancelAnalysis &&
          _imageFile == null &&
          !_imageFetchStarted) {
        try {
          _imageFetchStarted = true;
          // Берем актуальную информацию из провайдера
          final currentState =
              ref.read(analysis.nutritionAnalysisStateProvider);
          if (currentState is AsyncData<NutritionInfo>) {
            final currentInfo = currentState.value;
            if (currentInfo.dishName.isNotEmpty) {
              await _ensureImageForInputOrDish(currentInfo);
            }
          }
        } catch (e) {
          debugPrint('❌ Ошибка при попытке получить реальное изображение: $e');
        }
      }

      // Скрываем экран загрузки
      if (!skipLoadingScreen && mounted) {
        try {
          LoadingManager().hideLoadingScreen();
        } catch (e) {
          debugPrint('❌ Ошибка при скрытии экрана загрузки: $e');
        }
      }

      if (mounted && !_shouldCancelAnalysis) {
        setState(() {
          _isLoading = false;
          _isAnalysisInProgress = false;
          // На всякий случай синхронизируем финальный список ингредиентов
          final state = ref.read(analysis.nutritionAnalysisStateProvider);
          if (state is AsyncData<NutritionInfo>) {
            final finalList = state.value.ingredients;
            if (finalList.length > _progressiveIngredients.length) {
              _progressiveIngredients
                ..clear()
                ..addAll(finalList);
              _ingredientNameSet
                ..clear()
                ..addAll(finalList.map((e) => e.name.toLowerCase()));
            }
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Ошибка при анализе изображения: $e');
      if (mounted) {
        // Обновляем информацию о процессе при ошибке
        if (!skipLoadingScreen) {
          LoadingManager().updateProcessingInfo(
            context,
            newText: context.tr('image_analysis_error').replaceAll('{0}', ''),
            newProcessingStep:
                context.tr('error_occurred').replaceAll('{0}', e.toString()),
            newProgressValue: 1.0,
          );

          // Добавляем небольшую задержку перед скрытием экрана загрузки
          await Future.delayed(const Duration(seconds: 2));

          try {
            LoadingManager().hideLoadingScreen();
          } catch (e) {
            debugPrint('❌ Ошибка при скрытии экрана загрузки: $e');
          }
        }

        // Скрываем экран загрузки если он все еще показан
        try {
          if (mounted) {
            LoadingManager().hideLoadingScreen();
          }
        } catch (e) {
          debugPrint(
              '❌ Ошибка при скрытии экрана загрузки в обработке ошибки: $e');
        }

        // Показываем сообщение об ошибке
        setState(() {
          _isLoading = false;
          _isAnalysisInProgress = false;
          _errorMessage = e.toString();
        });

        // Устанавливаем состояние ошибки
        ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
            AsyncValue.error(e, StackTrace.current);

        // Показываем сообщение об ошибке пользователю
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                context.tr('analysis_error').replaceAll('{0}', e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Получение начального текста для экрана загрузки в зависимости от типа ввода
  String _getInitialProcessingText(String? recognizedText) {
    if (recognizedText != null) {
      return context.trParams('analyzing_request', [recognizedText]);
    } else {
      return context.tr('preparing_image');
    }
  }

  // Показывает диалог, если еда не обнаружена на изображении
  void _showNotFoodDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('food_not_recognized')),
        content: Text(context.tr('food_analysis_error').replaceAll('{0}', '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.tr('close')),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
