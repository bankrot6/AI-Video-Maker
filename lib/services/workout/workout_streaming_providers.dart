import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/workout_plan_model.dart';

/// Состояние потоковой генерации одного дня тренировки
class WorkoutDayStreamingState {
  final String? dayTitle;
  final List<ExerciseItem> exercises;
  final bool isActive;

  const WorkoutDayStreamingState({
    this.dayTitle,
    this.exercises = const [],
    this.isActive = false,
  });

  WorkoutDayStreamingState copyWith({
    String? dayTitle,
    List<ExerciseItem>? exercises,
    bool? isActive,
  }) {
    return WorkoutDayStreamingState(
      dayTitle: dayTitle ?? this.dayTitle,
      exercises: exercises ?? this.exercises,
      isActive: isActive ?? this.isActive,
    );
  }
}

class WorkoutDayStreamingNotifier
    extends StateNotifier<WorkoutDayStreamingState> {
  WorkoutDayStreamingNotifier() : super(const WorkoutDayStreamingState());

  /// Очищает состояние перед началом новой генерации
  void reset() {
    if (!mounted) return;
    state = const WorkoutDayStreamingState();
  }

  /// Запускает генерацию с чистого листа
  void start() {
    if (!mounted) return;
    state = const WorkoutDayStreamingState(
        isActive: true, exercises: [], dayTitle: null);
  }

  void setTitle(String title) {
    if (!mounted) return;
    state = state.copyWith(dayTitle: title, isActive: true);
  }

  void addExercise(ExerciseItem ex) {
    if (!mounted) return;

    // КРИТИЧНО: Проверяем дубликаты по имени
    // Если упражнение с таким именем уже есть - обновляем его
    // Если нет - добавляем в конец
    final existingIndex = state.exercises.indexWhere((e) => e.name == ex.name);

    if (existingIndex != -1) {
      // Обновляем существующее упражнение (может измениться вес)
      final List<ExerciseItem> updated =
          List<ExerciseItem>.from(state.exercises);
      updated[existingIndex] = ex;
      state = state.copyWith(exercises: updated, isActive: true);
    } else {
      // Добавляем новое упражнение
      final List<ExerciseItem> next = List<ExerciseItem>.from(state.exercises)
        ..add(ex);
      state = state.copyWith(exercises: next, isActive: true);
    }
  }

  /// Завершает генерацию, НЕ перезаписывая данные
  void complete({WorkoutPlanModel? finalPlan}) {
    if (!mounted) return;
    // Просто отмечаем как неактивный, не перезаписываем данные
    // Данные уже были добавлены через addExercise
    state = state.copyWith(isActive: false);
  }
}

final workoutDayStreamingProvider = StateNotifierProvider.family
    .autoDispose<WorkoutDayStreamingNotifier, WorkoutDayStreamingState, String>(
        (ref, key) {
  return WorkoutDayStreamingNotifier();
});

/// Глобальное состояние фоновой генерации недели
class WeekGenerationState {
  final DateTime? weekStart;
  final int totalDays;
  final int completedDays;
  final bool isGenerating;
  final Set<int>
      generatingDayIndexes; // Индексы дней, которые сейчас генерируются

  const WeekGenerationState({
    this.weekStart,
    this.totalDays = 0,
    this.completedDays = 0,
    this.isGenerating = false,
    this.generatingDayIndexes = const {},
  });

  bool get isComplete => completedDays >= totalDays;

  bool isDayGenerating(int dayIndex) => generatingDayIndexes.contains(dayIndex);

  WeekGenerationState copyWith({
    DateTime? weekStart,
    int? totalDays,
    int? completedDays,
    bool? isGenerating,
    Set<int>? generatingDayIndexes,
  }) {
    return WeekGenerationState(
      weekStart: weekStart ?? this.weekStart,
      totalDays: totalDays ?? this.totalDays,
      completedDays: completedDays ?? this.completedDays,
      isGenerating: isGenerating ?? this.isGenerating,
      generatingDayIndexes: generatingDayIndexes ?? this.generatingDayIndexes,
    );
  }
}

class WeekGenerationNotifier extends StateNotifier<WeekGenerationState> {
  WeekGenerationNotifier() : super(const WeekGenerationState());

  void startWeekGeneration(DateTime weekStart, int totalDays) {
    if (!mounted) return;
    state = WeekGenerationState(
      weekStart: weekStart,
      totalDays: totalDays,
      completedDays: 0,
      isGenerating: true,
      generatingDayIndexes: {},
    );
  }

  void startDayGeneration(int dayIndex) {
    if (!mounted) return;
    final Set<int> updated = Set<int>.from(state.generatingDayIndexes)
      ..add(dayIndex);
    state = state.copyWith(generatingDayIndexes: updated);
  }

  void completeDayGeneration(int dayIndex) {
    if (!mounted) return;
    final Set<int> updated = Set<int>.from(state.generatingDayIndexes)
      ..remove(dayIndex);
    state = state.copyWith(
      completedDays: state.completedDays + 1,
      generatingDayIndexes: updated,
    );
  }

  void completeWeekGeneration() {
    if (!mounted) return;
    state = state.copyWith(
      isGenerating: false,
      generatingDayIndexes: {},
    );
  }

  void reset() {
    if (!mounted) return;
    state = const WeekGenerationState();
  }
}

/// Провайдер для отслеживания глобального состояния генерации недели
final weekGenerationStateProvider =
    StateNotifierProvider<WeekGenerationNotifier, WeekGenerationState>((ref) {
  return WeekGenerationNotifier();
});
