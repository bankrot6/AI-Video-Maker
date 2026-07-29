import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/onboarding/services/workout_plan_generation_service.dart';
import '../../models/user_model.dart';
import '../../models/workout_plan_model.dart';
import '../../features/home/home_providers.dart' as home_providers;
import 'workout_streaming_providers.dart';
import 'weekly_workout_plan_service.dart';

/// Провайдер для сервиса фоновой генерации тренировок
final backgroundWorkoutGenerationServiceProvider = Provider((ref) {
  return BackgroundWorkoutGenerationService(ref);
});

/// Сервис для фоновой генерации остальных дней тренировок с потоковым отображением
/// Используется на главной странице для генерации дней 2, 3, ... N
class BackgroundWorkoutGenerationService {
  final ProviderRef _ref;

  BackgroundWorkoutGenerationService(this._ref);

  /// Запускает фоновую генерацию всех остальных дней (кроме первого)
  /// с потоковым отображением и постепенным сохранением
  Future<void> generateRemainingDaysInBackground({
    required BuildContext context,
    required UserModel user,
    required DateTime weekStart,
    required WorkoutPlanModel firstDay,
    required int totalDays,
  }) async {
    if (totalDays <= 1) {
      debugPrint('✅ Только 1 день - генерация не требуется');
      return;
    }

    debugPrint('🔄 ФОНОВАЯ ГЕНЕРАЦИЯ: Запуск генерации дней 2-$totalDays');

    final repository = _ref.read(weeklyWorkoutPlanRepositoryProvider);
    final weekGenerationState = _ref.read(weekGenerationStateProvider.notifier);

    // Инициализируем состояние генерации недели
    weekGenerationState.startWeekGeneration(weekStart, totalDays);

    try {
      // Генерируем каждый день ПОСЛЕДОВАТЕЛЬНО с потоковым отображением
      for (int dayIndex = 1; dayIndex < totalDays; dayIndex++) {
        try {
          debugPrint('');
          debugPrint('═══════════════════════════════════════════');
          debugPrint(
              '🏋️ ФОНОВАЯ ГЕНЕРАЦИЯ: День ${dayIndex + 1}/$totalDays НАЧАЛО');
          debugPrint('═══════════════════════════════════════════');

          // Отмечаем начало генерации дня
          weekGenerationState.startDayGeneration(dayIndex);

          // Создаем УНИКАЛЬНЫЙ ключ для провайдера стриминга
          final streamingKey =
              'workout_day_${weekStart.millisecondsSinceEpoch}_$dayIndex';
          final streamingProvider = workoutDayStreamingProvider(streamingKey);

          debugPrint('🔑 Ключ провайдера: $streamingKey');

          // ВАЖНО: Очищаем провайдер перед началом
          _ref.read(streamingProvider.notifier).reset();
          debugPrint('🧹 Провайдер очищен');

          // Небольшая задержка для корректной очистки состояния
          await Future.delayed(const Duration(milliseconds: 100));

          // Запускаем стриминг с чистого листа
          _ref.read(streamingProvider.notifier).start();
          debugPrint('▶️ Стриминг запущен');

          // Генерируем день с потоковым обновлением UI
          final dayPlan = await _generateDayWithStreaming(
            context: context,
            user: user,
            dayIndex: dayIndex,
            totalDays: totalDays,
            weekStart: weekStart,
            onTitle: (title) {
              if (context.mounted) {
                _ref.read(streamingProvider.notifier).setTitle(title);
                debugPrint('📝 День ${dayIndex + 1}: Заголовок → "$title"');
              }
            },
            onExercise: (exercise) {
              if (context.mounted) {
                _ref.read(streamingProvider.notifier).addExercise(exercise);
                debugPrint(
                    '➕ День ${dayIndex + 1}: Упражнение → "${exercise.name}"');
              }
            },
          );

          if (!context.mounted) {
            debugPrint('⚠️ Context не смонтирован, прерываем генерацию');
            return;
          }

          // Завершаем стриминг (БЕЗ перезаписи данных)
          _ref.read(streamingProvider.notifier).complete();
          debugPrint('⏹️ Стриминг завершен');

          // Сохраняем день
          await repository.saveDayAtIndex(
            weekStart,
            dayPlan,
            dayIndex,
            totalDays,
          );

          debugPrint(
              '💾 День ${dayIndex + 1}: ${dayPlan.exercises.length} упражнений сохранено');
          debugPrint(
              '✅ ФОНОВАЯ ГЕНЕРАЦИЯ: День ${dayIndex + 1}/$totalDays ЗАВЕРШЕН');
          debugPrint('═══════════════════════════════════════════');

          // Обновляем состояние генерации
          weekGenerationState.completeDayGeneration(dayIndex);

          // Инвалидируем провайдер чтобы UI обновился
          _ref.invalidate(
            home_providers.weeklyWorkoutPlanForDateProvider(weekStart),
          );

          // Задержка между днями для визуального разделения
          if (dayIndex < totalDays - 1) {
            debugPrint('⏸️ Пауза 500мс перед следующим днем...');
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          debugPrint('🔴 ФОНОВАЯ ГЕНЕРАЦИЯ: Ошибка дня ${dayIndex + 1}: $e');
          debugPrint('═══════════════════════════════════════════');
          weekGenerationState.completeDayGeneration(dayIndex);
          // Продолжаем генерацию остальных дней
        }
      }

      debugPrint('✅ ФОНОВАЯ ГЕНЕРАЦИЯ: Все $totalDays дня завершены');
      weekGenerationState.completeWeekGeneration();
    } catch (e) {
      debugPrint('🔴 ФОНОВАЯ ГЕНЕРАЦИЯ: Критическая ошибка: $e');
      weekGenerationState.completeWeekGeneration();
    }
  }

  /// Генерирует один день с потоковым обновлением
  Future<WorkoutPlanModel> _generateDayWithStreaming({
    required BuildContext context,
    required UserModel user,
    required int dayIndex,
    required int totalDays,
    required DateTime weekStart,
    void Function(String title)? onTitle,
    void Function(ExerciseItem exercise)? onExercise,
  }) async {
    final completer = Completer<WorkoutPlanModel>();
    final buffer = StringBuffer();
    final generator = WorkoutPlanGenerationService();

    final weekdayPattern = _getWeekdayPattern(totalDays, weekStart);

    debugPrint('🏋️ Генерация дня $dayIndex с потоковым обновлением');

    // Определяем целевое количество упражнений на основе уровня опыта
    final int targetExercises = getExerciseCountForLevel(user.experienceLevel);

    // Состояние для отслеживания упражнений без дублирования
    String? currentDayTitle;
    final List<ExerciseItem> currentExercises = [];
    // КРИТИЧНО: Отслеживаем какие упражнения мы УЖЕ отправили в UI
    final Set<String> sentExerciseNames = {};

    final sub = generator
        .streamWorkoutText(
      user: user,
      context: context,
      dayIndexInWeek: dayIndex,
      weekdayNumber: weekdayPattern[dayIndex],
      weekStartDate: weekStart,
    )
        .listen((chunk) {
      buffer.write(chunk);

      // КРИТИЧНО: Парсим только если заголовок уже получен (как на онбоардинге)
      // Извлекаем заголовок
      final dayMatch = RegExp(r'DAY:\s*([^\n]+)', multiLine: true)
          .firstMatch(buffer.toString());
      if (dayMatch != null) {
        final title = dayMatch.group(1)?.trim();
        if (title != null && title.isNotEmpty) {
          if (currentDayTitle == null ||
              currentDayTitle!.isEmpty ||
              title.length > currentDayTitle!.length) {
            currentDayTitle = title;
            onTitle?.call(title);
            debugPrint(
                '📝 STREAMING: День ${dayIndex + 1} заголовок: "$title"');
          }
        }
      }

      // Парсим упражнения ТОЛЬКО ЕСЛИ заголовок уже есть (как на онбоардинге)
      if (currentDayTitle != null && currentDayTitle!.isNotEmpty) {
        final exMatches = RegExp(r'EX:\s*([^\n]+)', multiLine: true)
            .allMatches(buffer.toString());

        for (final match in exMatches) {
          final payload = match.group(1)?.trim();
          if (payload != null) {
            final parts = payload.split('|');
            if (parts.length >= 4) {
              final name = parts[0].trim();
              final sets = int.tryParse(parts[1].trim());
              final reps = int.tryParse(parts[2].trim());
              final weight = double.tryParse(parts[3].trim());

              if (name.isNotEmpty && sets != null && reps != null) {
                final ex = ExerciseItem(
                  name: name,
                  sets: sets,
                  reps: reps,
                  weightKg: weight ?? 0.0,
                );

                // КРИТИЧНО: Точно такая же логика как на онбоардинге
                final existingIndex =
                    currentExercises.indexWhere((e) => e.name == ex.name);

                if (existingIndex != -1) {
                  // Обновляем существующее упражнение (может прийти обновленный вес)
                  if (currentExercises[existingIndex].weightKg != ex.weightKg) {
                    debugPrint(
                        '🔄 STREAMING: День ${dayIndex + 1} обновление: $name (${currentExercises[existingIndex].weightKg} → ${ex.weightKg} кг)');
                    currentExercises[existingIndex] = ex;
                    // Вызываем колбек только если вес изменился
                    onExercise?.call(ex);
                  }
                } else if (currentExercises.length < targetExercises &&
                    !sentExerciseNames.contains(name)) {
                  // Добавляем новое упражнение ТОЛЬКО если мы его еще НЕ отправляли
                  debugPrint(
                      '➕ STREAMING: День ${dayIndex + 1} новое: $name (${ex.sets}x${ex.reps}, ${ex.weightKg} кг)');
                  currentExercises.add(ex);
                  sentExerciseNames.add(name); // Помечаем как отправленное
                  onExercise?.call(ex);
                }
              }
            }
          }
        }
      }

      // Если достигли целевого количества упражнений - завершаем
      if (currentExercises.length >= targetExercises &&
          currentDayTitle != null &&
          currentDayTitle!.isNotEmpty &&
          !completer.isCompleted) {
        debugPrint(
            '✅ День ${dayIndex + 1}: Получено ${currentExercises.length} упражнений, завершаем генерацию');
        completer.complete(WorkoutPlanModel(
          dayTitle: currentDayTitle!,
          exercises: List<ExerciseItem>.from(currentExercises),
        ));
      }
    }, onError: (e) {
      if (!completer.isCompleted) {
        debugPrint('🔴 Ошибка генерации дня ${dayIndex + 1}: $e');
        // Если есть промежуточные данные - используем их
        if (currentExercises.isNotEmpty) {
          completer.complete(WorkoutPlanModel(
            dayTitle: currentDayTitle ?? 'Тренировка',
            exercises: List<ExerciseItem>.from(currentExercises),
          ));
        } else {
          completer.completeError(e);
        }
      }
    }, onDone: () {
      if (!completer.isCompleted) {
        // Пытаемся извлечь финальный результат из JSON
        final final_ = generator.tryParseWorkoutFromText(buffer.toString());
        if (final_ != null) {
          debugPrint(
              '✅ День ${dayIndex + 1}: Генерация завершена, ${final_.exercises.length} упражнений');
          completer.complete(final_);
        } else if (currentExercises.isNotEmpty) {
          // Используем то что успели спарсить из текста
          debugPrint(
              '✅ День ${dayIndex + 1}: Используем текстовый результат, ${currentExercises.length} упражнений');
          completer.complete(WorkoutPlanModel(
            dayTitle: currentDayTitle ?? 'Тренировка',
            exercises: List<ExerciseItem>.from(currentExercises),
          ));
        } else {
          debugPrint(
              '🔴 День ${dayIndex + 1}: Не удалось распарсить результат');
          completer.completeError(
              Exception('Failed to parse workout from generated text'));
        }
      }
    });

    try {
      // Ждем завершения с таймаутом
      final result = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          sub.cancel();
          // Пытаемся извлечь что успели сгенерировать
          final partial = generator.tryParseWorkoutFromText(buffer.toString());
          if (partial != null && partial.exercises.isNotEmpty) {
            debugPrint(
                '⚠️ День ${dayIndex + 1}: Таймаут, используем частичный результат');
            return partial;
          }
          throw TimeoutException('Workout generation timeout');
        },
      );

      sub.cancel();
      return result;
    } catch (e) {
      sub.cancel();
      rethrow;
    }
  }

  /// Вычисляет паттерн дней недели для тренировок
  List<int> _getWeekdayPattern(int totalDays, DateTime weekStart) {
    // Распределяем тренировки равномерно по неделе
    // Например, 3 дня: Пн(1), Ср(3), Пт(5)
    // 4 дня: Пн(1), Вт(2), Чт(4), Сб(6)
    // 5 дней: Пн(1), Вт(2), Ср(3), Чт(4), Пт(5)

    if (totalDays >= 7) {
      return List.generate(7, (i) => i + 1); // Все дни недели
    }

    final spacing = (7 / totalDays).floor();
    final pattern = <int>[];
    int currentWeekday = weekStart.weekday; // Начинаем с дня недели старта

    for (int i = 0; i < totalDays; i++) {
      pattern.add(currentWeekday);
      currentWeekday = ((currentWeekday + spacing - 1) % 7) + 1;
    }

    return pattern;
  }

  /// Проверяет нужна ли фоновая генерация для недели
  Future<bool> needsBackgroundGeneration(DateTime weekStart) async {
    final repository = _ref.read(weeklyWorkoutPlanRepositoryProvider);
    final plan = await repository.getPlanForWeek(weekStart);

    if (plan == null) {
      debugPrint('🔍 Нужна фоновая генерация: план отсутствует');
      return true;
    }

    if (!plan.isComplete) {
      debugPrint(
          '🔍 Нужна фоновая генерация: план неполный (${plan.days.length}/${plan.workoutsPerWeek})');
      return true;
    }

    debugPrint('✅ Фоновая генерация не нужна: план полный');
    return false;
  }

  /// Запускает проверку и генерацию при необходимости
  Future<void> ensureWeekIsComplete({
    required BuildContext context,
    required UserModel user,
    required DateTime weekStart,
  }) async {
    final needsGeneration = await needsBackgroundGeneration(weekStart);

    if (!needsGeneration) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    final repository = _ref.read(weeklyWorkoutPlanRepositoryProvider);
    final existingPlan = await repository.getPlanForWeek(weekStart);

    // Если есть первый день - генерируем только остальные
    if (existingPlan != null && existingPlan.days.isNotEmpty) {
      await generateRemainingDaysInBackground(
        context: context,
        user: user,
        weekStart: weekStart,
        firstDay: existingPlan.days.first,
        totalDays: existingPlan.workoutsPerWeek,
      );
    } else {
      debugPrint('⚠️ Нет первого дня для генерации остальных');
    }
  }
}
