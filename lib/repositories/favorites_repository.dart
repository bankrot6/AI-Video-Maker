import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/favorite_meal_model.dart';

/// Интерфейс репозитория избранных блюд
abstract class FavoritesRepository {
  Future<List<FavoriteMealModel>> getAllFavorites();
  Future<void> addFavorite(FavoriteMealModel meal);
  Future<void> removeFavorite(String id);
  Future<bool> isFavorite(String id);
}

/// Реализация на SharedPreferences
class SharedPrefsFavoritesRepository implements FavoritesRepository {
  static const String _favoritesKey = 'favorites_list_v1';

  final SharedPreferences _prefs;

  SharedPrefsFavoritesRepository(this._prefs);

  @override
  Future<List<FavoriteMealModel>> getAllFavorites() async {
    final jsonString = _prefs.getString(_favoritesKey);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final list = (json.decode(jsonString) as List<dynamic>)
          .map((e) => FavoriteMealModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<FavoriteMealModel> items) async {
    final data = json.encode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_favoritesKey, data);
  }

  @override
  Future<void> addFavorite(FavoriteMealModel meal) async {
    final all = await getAllFavorites();
    if (all.any((m) => m.id == meal.id)) return;
    all.insert(0, meal);
    await _saveAll(all);
  }

  @override
  Future<void> removeFavorite(String id) async {
    final all = await getAllFavorites();
    all.removeWhere((m) => m.id == id);
    await _saveAll(all);
  }

  @override
  Future<bool> isFavorite(String id) async {
    final all = await getAllFavorites();
    return all.any((m) => m.id == id);
  }
}
