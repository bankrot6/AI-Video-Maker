import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/favorite_meal_model.dart';
import '../../models/meal_model.dart';
import '../../models/nutrition_info.dart';
import '../../services/providers.dart' as services;
import '../../repositories/favorites_repository.dart';

String normalizeFavoriteId(String name) => name.trim().toLowerCase();

class FavoritesNotifier extends StateNotifier<List<FavoriteMealModel>> {
  final FavoritesRepository _repository;

  FavoritesNotifier(this._repository) : super([]) {
    _load();
  }

  Future<void> _load() async {
    final list = await _repository.getAllFavorites();
    state = list;
  }

  Future<void> add(FavoriteMealModel item) async {
    await _repository.addFavorite(item);
    await _load();
  }

  Future<void> removeById(String id) async {
    await _repository.removeFavorite(id);
    await _load();
  }

  bool isFavoriteId(String id) {
    return state.any((e) => e.id == id);
  }

  Future<void> toggleFromNutritionInfo(NutritionInfo info,
      {File? imageFile}) async {
    final id = normalizeFavoriteId(info.dishName);
    if (id.isEmpty) return;

    if (isFavoriteId(id)) {
      await removeById(id);
      return;
    }

    // Конвертация NutritionInfo -> FavoriteMealModel
    final ingredients = info.ingredients
        .map((e) => IngredientModel(name: e.name, quantity: e.weight))
        .toList();
    final nutrients = MealNutrientsModel(
      calories: info.calories.round(),
      proteins: info.proteins,
      fats: info.fats,
      carbs: info.carbs,
    );
    final fav = FavoriteMealModel(
      id: id,
      name: info.dishName,
      imagePath: imageFile?.path ?? info.imagePath,
      ingredients: ingredients,
      nutrients: nutrients,
      healthiness: info.healthiness.clamp(0, 5).toDouble(),
    );
    await add(fav);
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<FavoriteMealModel>>((ref) {
  final repo = ref.watch(services.favoritesRepositoryProvider);
  return FavoritesNotifier(repo);
});
