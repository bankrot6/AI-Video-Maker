import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/meal_model.dart';
import '../../services/image_analysis/image_analysis_service.dart';
import '../../services/localization/app_localization_service.dart';
import 'analysis_providers.dart';
import '../../widgets/rtl_wrapper.dart';
import '../../services/widgets/home_widgets_service.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  final File imageFile;

  const AnalysisScreen({
    super.key,
    required this.imageFile,
  });

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  bool _isSaving = false;
  final TextEditingController _mealNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _analyzeImage();
    });
  }

  @override
  void dispose() {
    _mealNameController.dispose();
    super.dispose();
  }

  Future<void> _analyzeImage() async {
    final imageAnalysisService = ref.read(imageAnalysisServiceProvider);

    try {
      // Запускаем анализ изображения
      final analysisResult =
          await imageAnalysisService.analyzeFood(widget.imageFile);

      // Обновляем состояние через провайдер
      if (!mounted) return;
      ref.read(imageAnalysisResultProvider.notifier).setResult(analysisResult);

      // Устанавливаем имя блюда, если оно было определено
      if (analysisResult.foodName != null) {
        _mealNameController.text = analysisResult.foodName!;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.trParams('image_analysis_error', ['$e']))),
        );
      }
    }
  }

  Future<void> _saveMeal() async {
    if (_mealNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('enter_food_name'))),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final analysisResult = ref.read(imageAnalysisResultProvider);

      if (analysisResult == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('no_data_to_save'))),
        );
        return;
      }

      // Создаем новую модель приема пищи
      final meal = MealModel(
        id: const Uuid().v4(),
        name: _mealNameController.text,
        dateTime: DateTime.now(),
        imagePath: widget.imageFile.path,
        ingredients: analysisResult.inferredIngredients,
        nutrients: analysisResult.estimatedNutrients,
      );

      // Сохраняем прием пищи в репозитории
      final mealRepository = ref.read(mealRepositoryProvider);
      await mealRepository.saveMeal(meal);

      // Обновляем домашний виджет «Прогресс дня»
      await HomeWidgetsService.updateDailyProgressFromRepo(ref);

      if (mounted) {
        // Показываем уведомление об успешном сохранении
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('meal_saved'))),
        );

        // Возвращаемся на главный экран
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.trParams('saving_error', ['$e']))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final analysisResult = ref.watch(imageAnalysisResultProvider);
    final isAnalyzing = analysisResult == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('food_analysis')),
        actions: [
          if (!isAnalyzing && !_isSaving)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveMeal,
            ),
        ],
      ),
      body:
          isAnalyzing ? _buildLoadingView() : _buildResultView(analysisResult),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.file(
            widget.imageFile,
            height: 200,
            width: 200,
            fit: BoxFit.cover,
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(context.tr('analyzing_image')),
        ],
      ),
    );
  }

  Widget _buildResultView(ImageAnalysisResult result) {
    return _isSaving
        ? const Center(
            child: CircularProgressIndicator(),
          )
        : SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Изображение еды
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        widget.imageFile,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Поле ввода названия
                  TextField(
                    controller: _mealNameController,
                    textDirection: context.textDirection,
                    textAlign: context.isRTL ? TextAlign.right : TextAlign.left,
                    decoration: InputDecoration(
                      labelText: context.tr('food_name'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Информация о питательной ценности
                  _buildNutrientsCard(result.estimatedNutrients),
                  const SizedBox(height: 16),

                  // Список распознанных ингредиентов
                  Text(
                    context.tr('recognized_ingredients'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildIngredientslist(result.inferredIngredients),
                  const SizedBox(height: 16),

                  // Метки распознавания
                  Text(
                    context.tr('recognition_labels'),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildLabelChips(result.detectedLabels),
                  const SizedBox(height: 24),

                  // Кнопка сохранения
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _saveMeal,
                      child: Text(context.tr('save_meal')),
                    ),
                  ),
                ],
              ),
            ),
          );
  }

  Widget _buildNutrientsCard(MealNutrientsModel nutrients) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('nutritional_value'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${nutrients.calories} ${context.tr('calories_suffix')}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Прогрессбары для БЖУ
            _buildNutrientProgressBar(
              context.tr('proteins'),
              nutrients.proteins,
              Colors.blue,
              '${nutrients.proteins.toStringAsFixed(1)} ${context.tr('grams_suffix')}',
            ),
            const SizedBox(height: 8),
            _buildNutrientProgressBar(
              context.tr('fats'),
              nutrients.fats,
              Colors.red,
              '${nutrients.fats.toStringAsFixed(1)} ${context.tr('grams_suffix')}',
            ),
            const SizedBox(height: 8),
            _buildNutrientProgressBar(
              context.tr('carbs'),
              nutrients.carbs,
              Colors.green,
              '${nutrients.carbs.toStringAsFixed(1)} ${context.tr('grams_suffix')}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutrientProgressBar(
      String label, double value, Color color, String valueText) {
    // Максимальное значение для прогресс-бара
    // В реальном приложении это может быть относительно дневной нормы
    const double maxValue = 100;
    final double percentage = value / maxValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(valueText),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: percentage.clamp(
              0.01, 1.0), // Гарантируем, что значение в допустимых пределах
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  Widget _buildIngredientslist(List<IngredientModel> ingredients) {
    return Card(
      elevation: 2,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: ingredients.length,
        itemBuilder: (context, index) {
          final ingredient = ingredients[index];
          return ListTile(
            title: Text(ingredient.name),
            trailing: Text(
                '${ingredient.quantity.toStringAsFixed(0)} ${ingredient.unit}'),
          );
        },
      ),
    );
  }

  Widget _buildLabelChips(List<String> labels) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: labels.map((label) {
        return Chip(
          label: Text(label),
          backgroundColor: Colors.grey[200],
        );
      }).toList(),
    );
  }
}
