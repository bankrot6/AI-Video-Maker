import 'package:flutter/foundation.dart';
import '../../../models/nutrition_info.dart';
import '../../../models/ingredient.dart';

/// Lightweight incremental parser for streaming DeepSeek JSON responses.
/// Extracts fields as soon as they appear in the partial text stream.
class NutritionStreamingParser {
  String _buffer = '';
  NutritionInfo _current = NutritionInfo.empty();

  /// Adds a new text chunk. Returns a new NutritionInfo when something changed, otherwise null.
  NutritionInfo? addChunk(String chunk) {
    _buffer += chunk;
    bool changed = false;

    // dishName
    final dishNameMatch =
        RegExp(r'"dishName"\s*:\s*"([^"]+)').firstMatch(_buffer);
    if (dishNameMatch != null) {
      final newDishName = dishNameMatch.group(1)!.trim();
      if (newDishName.isNotEmpty && newDishName != _current.dishName) {
        _current = _current.copyWith(dishName: newDishName);
        changed = true;
      }
    }

    // numbers: calories, proteins, fats, carbs, healthiness
    double? num(String key) {
      final m =
          RegExp('"$key"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)').firstMatch(_buffer);
      if (m != null) {
        return double.tryParse(m.group(1)!);
      }
      return null;
    }

    final cal = num('calories');
    if (cal != null && cal != _current.calories) {
      _current = _current.copyWith(calories: cal);
      changed = true;
    }

    final prot = num('proteins');
    if (prot != null && prot != _current.proteins) {
      _current = _current.copyWith(proteins: prot);
      changed = true;
    }

    final fats = num('fats');
    if (fats != null && fats != _current.fats) {
      _current = _current.copyWith(fats: fats);
      changed = true;
    }

    final carbs = num('carbs');
    if (carbs != null && carbs != _current.carbs) {
      _current = _current.copyWith(carbs: carbs);
      changed = true;
    }

    final health = num('healthiness');
    if (health != null && health != _current.healthiness) {
      // гарантируем диапазон 0..5
      final clamped = health.clamp(0, 5).toDouble();
      _current = _current.copyWith(healthiness: clamped);
      changed = true;
    }

    // ingredients list: try to parse when closing bracket present
    final ingredientsBlock =
        RegExp(r'"ingredients"\s*:\s*\[(.*?)\]', multiLine: true, dotAll: true)
            .firstMatch(_buffer);
    if (ingredientsBlock != null) {
      final block = ingredientsBlock.group(1)!;
      final itemRegex = RegExp(r'\{([^}]*)\}');
      final nameRegex = RegExp(r'"name"\s*:\s*"([^"]+)"');
      final weightRegex = RegExp(r'"weight"\s*:\s*(-?\d+(?:\.\d+)?)');
      final List<Ingredient> parsed = [];
      for (final m in itemRegex.allMatches(block)) {
        final item = m.group(1)!;
        final n = nameRegex.firstMatch(item);
        final w = weightRegex.firstMatch(item);
        if (n != null && w != null) {
          final name = n.group(1)!.trim();
          final weight = double.tryParse(w.group(1)!) ?? 0;
          if (name.isNotEmpty) {
            parsed.add(Ingredient(name: name, weight: weight));
          }
        }
      }
      if (parsed.isNotEmpty &&
          listEquals(parsed, _current.ingredients) == false) {
        _current = _current.copyWith(ingredients: parsed);
        changed = true;
      }
    }

    return changed ? _current : null;
  }

  /// Returns the last known snapshot.
  NutritionInfo get current => _current;
}
