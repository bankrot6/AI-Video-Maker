import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/meal_model.dart';
import '../../services/localization/app_localization_service.dart';
import '../home/home_providers.dart' as home;
// import '../analysis/analysis_providers.dart' as analysis;
// import '../../widgets/meal_history_list.dart';
import 'favorites_providers.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(context.tr('favorites')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: favorites.isEmpty
            ? _buildEmpty(context)
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: favorites.length,
                itemBuilder: (context, index) {
                  final fav = favorites[index];
                  return Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                        onTap: () async {
                          // Добавляем блюдо в историю текущего дня
                          final meal = MealModel(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            name: fav.name,
                            dateTime: DateTime.now(),
                            imagePath: fav.imagePath,
                            ingredients: fav.ingredients,
                            nutrients: fav.nutrients,
                            healthiness: fav.healthiness,
                          );
                          final mealRepo =
                              ref.read(home.mealRepositoryProvider);
                          await mealRepo.saveMeal(meal);
                          ref
                              .read(home.dailyMealsProvider.notifier)
                              .addMeal(meal);
                          final today = DateTime.now();
                          ref.invalidate(home.mealsForDateProvider(today));
                          ref.invalidate(home.nutrientsForDateProvider(today));
                          if (context.mounted) {
                            Navigator.of(context)
                                .pushNamedAndRemoveUntil('/home', (r) => false);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Изображение блюда (70x70, скругление 10)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: fav.imagePath != null &&
                                        fav.imagePath!.isNotEmpty
                                    ? Image.file(
                                        File(fav.imagePath!),
                                        width: 70,
                                        height: 70,
                                        fit: BoxFit.cover,
                                      )
                                    : Container(
                                        width: 70,
                                        height: 70,
                                        color: Colors.grey[200],
                                        child: const Icon(
                                          Icons.restaurant,
                                          color: Colors.grey,
                                          size: 30,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),
                              // Данные о блюде
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Название
                                    Text(
                                      fav.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
                                          '${fav.nutrients.calories} ${context.tr('calories_suffix')}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                Theme.of(context).primaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Макронутриенты — такие же бейджи
                                    Row(
                                      children: [
                                        _buildBadge(
                                            context.tr('protein_short'),
                                            fav.nutrients.proteins.round(),
                                            Colors.blue),
                                        const SizedBox(width: 8),
                                        _buildBadge(
                                            context.tr('fat_short'),
                                            fav.nutrients.fats.round(),
                                            Colors.red),
                                        const SizedBox(width: 8),
                                        _buildBadge(
                                            context.tr('carbs_short'),
                                            fav.nutrients.carbs.round(),
                                            Colors.green),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // Кнопка удалить избранное
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.grey),
                                onPressed: () async {
                                  await ref
                                      .read(favoritesProvider.notifier)
                                      .removeById(fav.id);
                                },
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              context.tr('favorites_empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('favorites_howto'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

  String _buildNutrientsLine(BuildContext context, MealNutrientsModel n) {
    return '${n.calories} ${context.tr('calories_suffix')} · '
        '${context.tr('protein_short')}: ${n.proteins.toStringAsFixed(1)} · '
        '${context.tr('fat_short')}: ${n.fats.toStringAsFixed(1)} · '
        '${context.tr('carbs_short')}: ${n.carbs.toStringAsFixed(1)}';
  }

  Widget _buildImage(String? path) {
    if (path == null || path.isEmpty) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.restaurant, color: Colors.grey),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path),
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.image_not_supported, color: Colors.grey),
        ),
      ),
    );
  }
}
