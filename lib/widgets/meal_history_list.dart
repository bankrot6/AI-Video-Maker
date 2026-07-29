import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import '../models/meal_model.dart';
import '../features/analysis/food_analysis_screen.dart';
import '../features/analysis/analysis_providers.dart' as analysis;
import '../models/meal_action_result.dart';
import '../models/nutrition_info.dart';
import '../models/ingredient.dart';
import '../services/localization/app_localization_service.dart';
import '../features/share/share_screen_manager.dart';
import '../features/share/share_provider.dart';
import '../models/water_entry_model.dart';
import '../features/home/home_providers.dart' as home;
import '../services/widgets/home_widgets_service.dart';

/// Виджет для отображения списка приемов пищи
/// Используется на экране истории
class MealHistoryList extends ConsumerWidget {
  /// Список приемов пищи для отображения
  final List<MealModel> meals;

  /// Функция для обновления данных после возврата с экрана анализа
  final VoidCallback? onMealAnalysisComplete;

  /// Показывать ли разделитель по дням
  final bool groupByDate;

  /// Форматтер для даты
  final DateFormat? dateFormat;

  /// Форматтер для времени
  final DateFormat? timeFormat;

  /// Запросить смену выбранной даты в истории
  final ValueChanged<DateTime>? onDateChangeRequested;

  /// Записи воды для отображения в одном блоке с едой
  final List<WaterEntryModel> waterEntries;

  /// Конструктор
  const MealHistoryList({
    super.key,
    required this.meals,
    this.onMealAnalysisComplete,
    this.groupByDate = false,
    this.dateFormat,
    this.timeFormat,
    this.onDateChangeRequested,
    this.waterEntries = const [],
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (meals.isEmpty && waterEntries.isEmpty) {
      return _buildEmptyMealsView(context);
    }

    if (groupByDate) {
      return _buildGroupedMealsList(context, ref);
    } else {
      return _buildMealsList(context, ref);
    }
  }

  /// Создает представление для случая, когда список пуст
  Widget _buildEmptyMealsView(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.restaurant,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('no_meals'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('meals_history_empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  /// Создает список приемов пищи, сгруппированный по датам
  Widget _buildGroupedMealsList(BuildContext context, WidgetRef ref) {
    // Форматтеры с дефолтными значениями
    final DateFormat df = dateFormat ?? DateFormat('dd.MM.yyyy');
    final DateFormat tf = timeFormat ?? DateFormat('HH:mm');

    // Группируем еду и воду по дате
    final Map<String, List<_HistoryItem>> itemsByDate = {};
    for (final meal in meals) {
      final dateKey = df.format(meal.dateTime);
      itemsByDate.putIfAbsent(dateKey, () => []);
      itemsByDate[dateKey]!.add(_HistoryItem.fromMeal(meal));
    }
    for (final w in waterEntries) {
      final dateKey = df.format(w.dateTime);
      itemsByDate.putIfAbsent(dateKey, () => []);
      itemsByDate[dateKey]!.add(_HistoryItem.fromWater(w));
    }

    // Сортировка дат (от последней к самой ранней)
    final sortedDates = itemsByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedDates.length,
      itemBuilder: (context, index) {
        final dateKey = sortedDates[index];
        final dailyItems = itemsByDate[dateKey]!;
        dailyItems.sort((a, b) => a.dateTime.compareTo(b.dateTime));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                dateKey,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: dailyItems.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, mealIndex) {
                final item = dailyItems[mealIndex];
                return item.isMeal
                    ? _buildMealItem(context, ref, item.meal!, tf)
                    : _buildWaterItem(context, ref, item.water!, tf);
              },
            ),
            const Divider(thickness: 2),
          ],
        );
      },
    );
  }

  /// Создает список приемов пищи без группировки
  Widget _buildMealsList(BuildContext context, WidgetRef ref) {
    // Дефолтный форматтер времени
    final DateFormat tf = timeFormat ?? DateFormat('HH:mm');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 28.0),
                    child: Text(
                      context.tr('journal'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.share, color: Colors.blueGrey),
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 0, minHeight: 0),
                      visualDensity: VisualDensity.compact,
                      tooltip: context.tr('share'),
                      onPressed: () async {
                        try {
                          final shareManager =
                              ref.read(shareScreenManagerProvider);
                          await shareManager
                              .shareScreenshot(ScreenshotType.history);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(context.tr('share_error'))),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: (() {
              final list = [
                ...meals.map(_HistoryItem.fromMeal),
                ...waterEntries.map(_HistoryItem.fromWater),
              ];
              list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
              return list.length;
            })(),
            itemBuilder: (context, index) {
              final items = [
                ...meals.map(_HistoryItem.fromMeal),
                ...waterEntries.map(_HistoryItem.fromWater),
              ]..sort((a, b) => a.dateTime.compareTo(b.dateTime));
              final item = items[index];
              return item.isMeal
                  ? _buildMealItem(context, ref, item.meal!, tf)
                  : _buildWaterItem(context, ref, item.water!, tf);
            },
          ),
        ],
      ),
    );
  }

  /// Создает элемент для отображения одного приема пищи
  Widget _buildMealItem(
      BuildContext context, WidgetRef ref, MealModel meal, DateFormat tf) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openMealDetails(context, ref, meal),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Изображение блюда
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: (() {
                    final path = meal.imagePath;
                    if (path == null || path.isEmpty) {
                      return Container(
                        width: 70,
                        height: 70,
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.restaurant,
                          color: Colors.grey,
                          size: 30,
                        ),
                      );
                    }
                    final isUrl = path.startsWith('http://') ||
                        path.startsWith('https://');
                    if (isUrl) {
                      return Image.network(
                        path,
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                      );
                    }
                    return Image.file(
                      File(path),
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                    );
                  })(),
                ),

                const SizedBox(width: 12),

                // Данные о блюде
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Название и время
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              meal.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  size: 12,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  tf.format(meal.dateTime),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      // Калории
                      Row(
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            size: 16,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${meal.nutrients.calories} ${context.tr('calories_suffix')}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Макронутриенты
                      Row(
                        children: [
                          _buildNutrientBadge(context.tr('protein_short'),
                              meal.nutrients.proteins.round(), Colors.blue),
                          const SizedBox(width: 8),
                          _buildNutrientBadge(context.tr('fat_short'),
                              meal.nutrients.fats.round(), Colors.red),
                          const SizedBox(width: 8),
                          _buildNutrientBadge(context.tr('carbs_short'),
                              meal.nutrients.carbs.round(), Colors.green),
                        ],
                      ),
                    ],
                  ),
                ),

                // Иконка для перехода
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Создает значок для отображения макронутриентов
  Widget _buildNutrientBadge(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Элемент записи воды (компактная плашка в общем списке)
  Widget _buildWaterItem(BuildContext context, WidgetRef ref,
      WaterEntryModel entry, DateFormat tf) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.lightBlue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_drink, color: Colors.lightBlue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${entry.volumeMl} ${context.tr('ml_suffix')}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              tf.format(entry.dateTime),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.lightBlue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Вода',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.lightBlue,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 16,
              height: 16,
              child: IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: Colors.grey, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final repo = ref.read(home.waterRepositoryProvider);
                  await repo.removeEntry(entry.id);
                  final date = DateTime(entry.dateTime.year,
                      entry.dateTime.month, entry.dateTime.day);
                  ref.invalidate(home.waterEntriesForDateProvider(date));
                  ref.invalidate(home.waterTotalForDateProvider(date));
                  // Также инвалидируем все вариации провайдеров на случай различий дат по времени
                  ref.invalidate(home.waterEntriesForDateProvider);
                  ref.invalidate(home.waterTotalForDateProvider);
                  // Обновляем виджеты через updateDailyProgressFromRepo для полной инициализации (как при добавлении еды)
                  await HomeWidgetsService.updateDailyProgressFromRepo(ref);
                },
              ),
            ),
            // Отступ не добавляем, как и у стрелки в карточке еды
          ],
        ),
      ),
    );
  }

  /// Открывает экран с детальной информацией о блюде
  void _openMealDetails(BuildContext context, WidgetRef ref, MealModel meal) {
    // Устанавливаем информацию о питательной ценности в провайдер
    final nutritionInfo = NutritionInfo(
      dishName: meal.name,
      calories: meal.nutrients.calories.toDouble(),
      proteins: meal.nutrients.proteins.toDouble(),
      fats: meal.nutrients.fats.toDouble(),
      carbs: meal.nutrients.carbs.toDouble(),
      healthiness: meal.healthiness,
      // Добавляем ингредиенты, если они доступны
      ingredients: meal.ingredients
          .map((i) => Ingredient(
                name: i.name,
                weight: i.quantity,
                verified: true,
              ))
          .toList(),
    );

    // Если есть изображение, устанавливаем его
    if (meal.imagePath != null) {
      ref.read(analysis.selectedImageProvider.notifier).state =
          File(meal.imagePath!);
    } else {
      ref.read(analysis.selectedImageProvider.notifier).state = null;
    }

    // Устанавливаем информацию о питании
    ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
        AsyncValue.data(nutritionInfo);

    // Сохраняем в lastAnalysisResults, чтобы FoodAnalysisScreen знал,
    // что это существующий элемент и не запускал повторный анализ
    ref.read(analysis.lastAnalysisResultsProvider.notifier).state =
        analysis.AnalysisResults(
      info: nutritionInfo,
      timestamp: DateTime.now(),
    );

    // Устанавливаем флаг для FoodAnalysisScreen, что это просмотр истории
    ref.read(analysis.isHistoryViewProvider.notifier).state = true;

    // Устанавливаем текущий прием пищи для экрана анализа (просмотр истории)
    ref.read(analysis.selectedHistoryMealProvider.notifier).state = meal;

    // Переходим на экран анализа
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => const FoodAnalysisScreen(),
      ),
    )
        .then((_) {
      // После возвращения очищаем данные анализа и флаг просмотра истории
      _clearAnalysisData(ref);
      ref.read(analysis.isHistoryViewProvider.notifier).state = false;

      // Проверяем, есть ли результат действия (перемещение/удаление)
      final MealActionResult? result =
          ref.read(analysis.mealActionResultProvider);
      ref.read(analysis.mealActionResultProvider.notifier).state = null;

      // Если блюдо перенесено на другой день — переключаем выбранную дату
      if (result != null && result.movedTo != null) {
        final movedDate = DateTime(
            result.movedTo!.year, result.movedTo!.month, result.movedTo!.day);
        if (onDateChangeRequested != null) {
          onDateChangeRequested!(movedDate);
        }
      }

      // Вызываем колбэк обновления данных, если он предоставлен
      if (onMealAnalysisComplete != null) {
        onMealAnalysisComplete!();
      }
    });
  }

  /// Очищает данные анализа
  void _clearAnalysisData(WidgetRef ref) {
    // Вызываем метод сброса, который предоставляется провайдером resetAnalysisStateProvider
    final resetFunction = ref.read(analysis.resetAnalysisStateProvider);
    resetFunction();
  }
}

/// Внутренний объединённый элемент истории
class _HistoryItem {
  final MealModel? meal;
  final WaterEntryModel? water;
  final DateTime dateTime;

  bool get isMeal => meal != null;

  _HistoryItem._(this.meal, this.water, this.dateTime);

  static _HistoryItem fromMeal(MealModel m) =>
      _HistoryItem._(m, null, m.dateTime);
  static _HistoryItem fromWater(WaterEntryModel w) =>
      _HistoryItem._(null, w, w.dateTime);
}
