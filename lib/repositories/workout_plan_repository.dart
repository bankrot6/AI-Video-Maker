import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/weekly_workout_plan_model.dart';
import '../models/workout_plan_model.dart';

/// Репозиторий недельных планов тренировок
abstract class WorkoutPlanRepository {
  Future<WeeklyWorkoutPlanModel?> getPlanForWeek(DateTime anyDateInWeek);
  Future<void> savePlanForWeek(WeeklyWorkoutPlanModel plan);
  Future<void> appendDay(
    DateTime anyDateInWeek,
    WorkoutPlanModel dayPlan,
    int workoutsPerWeek,
  );
  Future<void> saveDayAtIndex(
    DateTime anyDateInWeek,
    WorkoutPlanModel dayPlan,
    int dayIndex,
    int workoutsPerWeek,
  );
}

class SharedPrefsWorkoutPlanRepository implements WorkoutPlanRepository {
  final SharedPreferences _prefs;
  SharedPrefsWorkoutPlanRepository(this._prefs);

  String _keyFor(DateTime anyDateInWeek) {
    final weekStart = startOfWeek(anyDateInWeek);
    final y = weekStart.year;
    final m = weekStart.month.toString().padLeft(2, '0');
    final d = weekStart.day.toString().padLeft(2, '0');
    return 'weekly_workout_plan_$y-$m-$d';
  }

  @override
  Future<WeeklyWorkoutPlanModel?> getPlanForWeek(DateTime anyDateInWeek) async {
    final key = _keyFor(anyDateInWeek);
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      print('📦 REPO: План для недели $anyDateInWeek НЕ НАЙДЕН (key: $key)');
      return null;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final plan = WeeklyWorkoutPlanModel.fromJson(map);
      print(
          '📦 REPO: Загружен план для недели ${plan.weekStart}: ${plan.days.length} дней (key: $key)');
      return plan;
    } catch (e) {
      print('📦 REPO: Ошибка парсинга плана для недели $anyDateInWeek: $e');
      return null;
    }
  }

  @override
  Future<void> savePlanForWeek(WeeklyWorkoutPlanModel plan) async {
    final key = _keyFor(plan.weekStart);
    final raw = jsonEncode(plan.toJson());
    await _prefs.setString(key, raw);
    print(
        '📦 REPO: Сохранен план для недели ${plan.weekStart}: ${plan.days.length} дней (key: $key)');
  }

  @override
  Future<void> appendDay(
    DateTime anyDateInWeek,
    WorkoutPlanModel dayPlan,
    int workoutsPerWeek,
  ) async {
    final existing = await getPlanForWeek(anyDateInWeek);
    if (existing == null) {
      final plan = WeeklyWorkoutPlanModel(
        weekStart: startOfWeek(anyDateInWeek),
        workoutsPerWeek: workoutsPerWeek,
        days: [dayPlan],
      );
      await savePlanForWeek(plan);
      return;
    }
    final updatedDays = List<WorkoutPlanModel>.from(existing.days)
      ..add(dayPlan);
    final updated = existing.copyWith(
      workoutsPerWeek: workoutsPerWeek,
      days: updatedDays,
    );
    await savePlanForWeek(updated);
  }

  @override
  Future<void> saveDayAtIndex(
    DateTime anyDateInWeek,
    WorkoutPlanModel dayPlan,
    int dayIndex,
    int workoutsPerWeek,
  ) async {
    final existing = await getPlanForWeek(anyDateInWeek);

    // Создаем список нужного размера, заполненный null-объектами (placeholder)
    final List<WorkoutPlanModel?> updatedDays =
        List<WorkoutPlanModel?>.filled(workoutsPerWeek, null);

    // Копируем существующие дни
    if (existing != null) {
      for (int i = 0; i < existing.days.length && i < workoutsPerWeek; i++) {
        updatedDays[i] = existing.days[i];
      }
    }

    // Вставляем новый день по индексу
    if (dayIndex >= 0 && dayIndex < workoutsPerWeek) {
      updatedDays[dayIndex] = dayPlan;
    }

    // Фильтруем null-значения для финального списка
    final nonNullDays = updatedDays.whereType<WorkoutPlanModel>().toList();

    final updated = WeeklyWorkoutPlanModel(
      weekStart: startOfWeek(anyDateInWeek),
      workoutsPerWeek: workoutsPerWeek,
      days: nonNullDays,
    );

    await savePlanForWeek(updated);
    print(
        '📦 REPO: Сохранен день $dayIndex по индексу, всего дней: ${nonNullDays.length}/$workoutsPerWeek');
  }
}
