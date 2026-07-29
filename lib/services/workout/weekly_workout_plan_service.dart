import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_model.dart';
import '../../models/workout_plan_model.dart';
import '../../models/weekly_workout_plan_model.dart';
import '../../features/onboarding/services/workout_plan_generation_service.dart';
import '../../repositories/workout_plan_repository.dart';
import '../localization/app_localization_service.dart';

/// Сервис оркестрации генерации недельного плана
class WeeklyWorkoutPlanService {
  final WorkoutPlanRepository _repository;
  final WorkoutPlanGenerationService _dayGenerator;
  final Map<int, Future<void>> _inflightPreloads = {};
  final Map<String, Future<void>> _inflightStreams = {};
  final Set<int> _replicatedWeeks = {};

  WeeklyWorkoutPlanService({
    required WorkoutPlanRepository repository,
    WorkoutPlanGenerationService? dayGenerator,
  })  : _repository = repository,
        _dayGenerator = dayGenerator ?? WorkoutPlanGenerationService();

  /// Возвращает план из кеша, если он есть
  Future<WeeklyWorkoutPlanModel?> getCachedWeekPlan(DateTime date) {
    return _repository.getPlanForWeek(date);
  }

  /// Если недели нет в кэше — создать копией ближайшей доступной (или пустой структурой)
  Future<WeeklyWorkoutPlanModel> getOrReplicateWeek({
    required DateTime baseDate,
    WeeklyWorkoutPlanModel? template,
  }) async {
    final weekStartDate = startOfWeek(baseDate);
    final cached = await _repository.getPlanForWeek(weekStartDate);
    if (cached != null) return cached;
    final WeeklyWorkoutPlanModel plan = WeeklyWorkoutPlanModel(
      weekStart: weekStartDate,
      workoutsPerWeek: template?.workoutsPerWeek ?? 3,
      days: List<WorkoutPlanModel>.from(template?.days ?? const []),
    );
    await _repository.savePlanForWeek(plan);
    return plan;
  }

  /// Реплицировать уже существующую неделю вперёд на N недель
  Future<void> replicateWeeksForward({
    required DateTime fromWeekStart,
    required int weeks,
  }) async {
    final template = await _repository.getPlanForWeek(fromWeekStart);
    if (template == null) return;
    for (int i = 1; i <= weeks; i++) {
      final DateTime nextWeek = fromWeekStart.add(Duration(days: 7 * i));
      final existing = await _repository.getPlanForWeek(nextWeek);
      if (existing != null) continue;
      final copy = WeeklyWorkoutPlanModel(
        weekStart: startOfWeek(nextWeek),
        workoutsPerWeek: template.workoutsPerWeek,
        days: List<WorkoutPlanModel>.from(template.days),
      );
      await _repository.savePlanForWeek(copy);
    }
  }

  /// Возвращает план недели для даты. Если плана нет — находит ближайшую прошлую
  /// неделю и реплицирует её вперёд вплоть до целевой недели (включительно).
  /// Если и прошлых недель нет — создаёт пустую структуру недели, чтобы UI мог
  /// начать потоковую генерацию дня.
  Future<WeeklyWorkoutPlanModel> getOrReplicateWeekFromHistory({
    required DateTime baseDate,
    int lookbackWeeks = 52,
  }) async {
    final DateTime targetWeek = startOfWeek(baseDate);
    final cached = await _repository.getPlanForWeek(targetWeek);
    if (cached != null) return cached;

    // Ищем ближайшую прошлую неделю как шаблон
    WeeklyWorkoutPlanModel? template;
    for (int i = 1; i <= lookbackWeeks; i++) {
      final candidate = targetWeek.subtract(Duration(days: 7 * i));
      final prev = await _repository.getPlanForWeek(candidate);
      if (prev != null && prev.days.isNotEmpty) {
        template = prev;
        break;
      }
    }

    // Если нашли шаблон — реплицируем все пропущенные недели до целевой
    if (template != null) {
      DateTime cursor = template.weekStart.add(const Duration(days: 7));
      while (!isSameWeek(cursor, targetWeek)) {
        final exists = await _repository.getPlanForWeek(cursor);
        if (exists == null) {
          final copyMid = WeeklyWorkoutPlanModel(
            weekStart: startOfWeek(cursor),
            workoutsPerWeek: template.workoutsPerWeek,
            days: List<WorkoutPlanModel>.from(template.days),
          );
          await _repository.savePlanForWeek(copyMid);
        }
        cursor = cursor.add(const Duration(days: 7));
      }
      // Создаём целевую неделю, если её всё ещё нет
      final finalExists = await _repository.getPlanForWeek(targetWeek);
      if (finalExists == null) {
        final copyTarget = WeeklyWorkoutPlanModel(
          weekStart: targetWeek,
          workoutsPerWeek: template.workoutsPerWeek,
          days: List<WorkoutPlanModel>.from(template.days),
        );
        await _repository.savePlanForWeek(copyTarget);
        return copyTarget;
      }
      return finalExists;
    }

    // Шаблон не найден — создаём пустую неделю с дефолтным количеством
    final empty = WeeklyWorkoutPlanModel(
      weekStart: targetWeek,
      workoutsPerWeek: 3,
      days: const <WorkoutPlanModel>[],
    );
    await _repository.savePlanForWeek(empty);
    return empty;
  }

  bool isSameWeek(DateTime a, DateTime b) {
    final aa = startOfWeek(a);
    final bb = startOfWeek(b);
    return aa.year == bb.year && aa.month == bb.month && aa.day == bb.day;
  }

  /// Сохранить первый день немедленно, чтобы главная могла его отобразить
  Future<void> saveFirstDay({
    required UserModel user,
    required WorkoutPlanModel firstDay,
    DateTime? baseDate,
  }) async {
    final weekStartDate = startOfWeek(baseDate ?? DateTime.now());
    final int n = (user.workoutsPerWeek ?? 3).clamp(1, 7);
    final existing = await _repository.getPlanForWeek(weekStartDate);
    if (existing == null || existing.days.isEmpty) {
      // Заполняем всю неделю копиями первого дня, чтобы UI показал контент мгновенно
      final List<WorkoutPlanModel> days = [firstDay];
      while (days.length < n) {
        days.add(firstDay);
      }
      final plan = WeeklyWorkoutPlanModel(
        weekStart: weekStartDate,
        workoutsPerWeek: n,
        days: days,
      );
      await _repository.savePlanForWeek(plan);
      // Реплицируем месяц вперёд сразу, чтобы обеспечить кэш
      try {
        await replicateWeeksForward(fromWeekStart: weekStartDate, weeks: 4);
        // Отметим, что для этой недели уже была выполнена репликация
        _replicatedWeeks.add(weekStartDate.millisecondsSinceEpoch);
      } catch (_) {}
    }
  }

  /// Принудительно перегенерировать неделю (опционально)
  Future<WeeklyWorkoutPlanModel> regenerateWeek({
    required BuildContext context,
    required UserModel user,
    DateTime? baseDate,
  }) async {
    final weekStartDate = startOfWeek(baseDate ?? DateTime.now());
    final int n = (user.workoutsPerWeek ?? 3).clamp(1, 7);

    final List<WorkoutPlanModel> days = [];
    for (int i = 0; i < n; i++) {
      final plan = await _generateOneDay(
        context: context,
        user: user,
        weekStartDate: weekStartDate,
        dayIndexInWeek: i,
        weekdayNumber: _weekdayPatternFor(n)[i],
      );
      days.add(plan);
      await _repository.savePlanForWeek(WeeklyWorkoutPlanModel(
        weekStart: weekStartDate,
        workoutsPerWeek: n,
        days: List<WorkoutPlanModel>.from(days),
      ));
    }
    return WeeklyWorkoutPlanModel(
      weekStart: weekStartDate,
      workoutsPerWeek: n,
      days: days,
    );
  }

  /// Фоновая предзагрузка оставшихся дней: сохраняет частичный прогресс
  Future<void> preloadRemainingDays({
    required BuildContext context,
    required UserModel user,
    WorkoutPlanModel? firstDay,
    bool excludeFirstDay = false,
    DateTime? baseDate,
  }) async {
    final weekStartDate = startOfWeek(baseDate ?? DateTime.now());
    final int key = weekStartDate.millisecondsSinceEpoch;
    // Защита от параллельных/повторных запусков на ту же неделю
    final existing = _inflightPreloads[key];
    if (existing != null) {
      await existing;
      return;
    }

    final future = () async {
      try {
        final int n = (user.workoutsPerWeek ?? 3).clamp(1, 7);

        // Записываем день 1, если передан и ещё не сохранён
        if (firstDay != null) {
          final existing = await _repository.getPlanForWeek(weekStartDate);
          if (existing == null || existing.days.isEmpty) {
            await _repository.savePlanForWeek(WeeklyWorkoutPlanModel(
              weekStart: weekStartDate,
              workoutsPerWeek: n,
              days: [firstDay],
            ));
          }
        }

        WeeklyWorkoutPlanModel? current =
            await _repository.getPlanForWeek(weekStartDate);
        final List<WorkoutPlanModel> days = List.of(current?.days ?? const []);
        final int already = days.length;
        // Генерируем недостающие дни до целевого количества
        final int toGenerate = (n - already).clamp(0, n);
        // Если неделя уже полная — выходим (репликацию мы могли сделать ранее в saveFirstDay)
        if (toGenerate == 0) {
          return;
        }
        for (int i = 0; i < toGenerate; i++) {
          final int dayIndexInWeek = already + i;
          final day = await _generateOneDay(
            context: context,
            user: user,
            weekStartDate: weekStartDate,
            dayIndexInWeek: dayIndexInWeek,
            weekdayNumber: _weekdayPatternFor(n)[dayIndexInWeek],
          );
          // Не сохраняем пустые дни
          if (day.exercises.isEmpty) {
            continue;
          }
          days.add(day);
          await _repository.savePlanForWeek(WeeklyWorkoutPlanModel(
            weekStart: weekStartDate,
            workoutsPerWeek: n,
            days: List<WorkoutPlanModel>.from(days),
          ));
        }
        // Если неделя стала полной — один раз реплицируем месяц вперёд
        final latest = await _repository.getPlanForWeek(weekStartDate);
        if (latest != null && latest.days.length >= latest.workoutsPerWeek) {
          final int keyRep = weekStartDate.millisecondsSinceEpoch;
          if (!_replicatedWeeks.contains(keyRep)) {
            _replicatedWeeks.add(keyRep);
            await replicateWeeksForward(fromWeekStart: weekStartDate, weeks: 4);
          }
        }
      } catch (e) {
        debugPrint('🔴 Weekly preload failed: $e');
      }
    }();

    _inflightPreloads[key] = future;
    try {
      await future;
    } finally {
      _inflightPreloads.remove(key);
    }
  }

  /// Потоковая генерация конкретного дня недели (с прогрессом)
  /// ОПТИМИЗАЦИЯ: останавливается после 6-7 упражнений, не ждёт финального JSON
  /// Если [targetDayIndex] не указан, генерируется следующий недостающий день
  Future<void> streamNextMissingDay({
    required BuildContext context,
    required UserModel user,
    DateTime? baseDate,
    int? targetDayIndex,
    void Function(String title)? onTitle,
    void Function(ExerciseItem ex)? onExercise,
  }) async {
    final DateTime weekStartDate = startOfWeek(baseDate ?? DateTime.now());
    final latest = await _repository.getPlanForWeek(weekStartDate);
    final int n =
        (user.workoutsPerWeek ?? latest?.workoutsPerWeek ?? 3).clamp(1, 7);

    // Определяем индекс дня для генерации
    final int dayIndex = targetDayIndex ?? (latest?.days.length ?? 0);

    // ИСПРАВЛЕНИЕ: Проверяем, существует ли уже день с этим индексом
    if (latest != null && dayIndex < latest.days.length) {
      debugPrint('⚠️ День $dayIndex уже существует в плане, пропускаем');
      return;
    }

    if (dayIndex >= n) return; // индекс за пределами недели

    final String key = '${weekStartDate.millisecondsSinceEpoch}_$dayIndex';
    if (_inflightStreams.containsKey(key)) {
      await _inflightStreams[key];
      return;
    }

    final future = () async {
      final buffer = StringBuffer();
      String? streamedTitle;
      // КРИТИЧНО: Отслеживаем упражнения по ИМЕНИ, а не по индексу!
      final Set<String> sentExerciseNames = <String>{};
      final List<ExerciseItem> interim = [];
      final completer = Completer<WorkoutPlanModel>();

      // ОПТИМИЗАЦИЯ: Останавливаемся после 6-7 упражнений
      const int targetExercises = 6;

      final sub = _dayGenerator
          .streamWorkoutText(
        user: user,
        context: context,
        dayIndexInWeek: dayIndex,
        weekdayNumber: _weekdayPatternFor(n)[dayIndex],
        weekStartDate: weekStartDate,
      )
          .listen((chunk) {
        buffer.write(chunk);

        // Извлекаем заголовок (КАК НА ОНБОАРДИНГЕ)
        final dayMatch = RegExp(r'DAY:\s*([^\n]+)', multiLine: true)
            .firstMatch(buffer.toString());
        if (dayMatch != null) {
          final title = dayMatch.group(1)?.trim();
          if (title != null && title.isNotEmpty) {
            if (streamedTitle == null ||
                streamedTitle!.isEmpty ||
                title.length > streamedTitle!.length) {
              streamedTitle = title;
              if (onTitle != null) onTitle(title);
            }
          }
        }

        // Парсим упражнения ТОЛЬКО ЕСЛИ заголовок уже есть (КАК НА ОНБОАРДИНГЕ)
        if (streamedTitle != null && streamedTitle!.isNotEmpty) {
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
                  // КРИТИЧНО: Проверяем дубликаты ПО ИМЕНИ (как на онбоардинге)
                  final existingIndex =
                      interim.indexWhere((e) => e.name == name);

                  if (existingIndex != -1) {
                    // Обновляем существующее упражнение (может прийти обновленный вес)
                    if (interim[existingIndex].weightKg != weight) {
                      debugPrint(
                          '🔄 FALLBACK STREAMING: День $dayIndex обновление: $name (${interim[existingIndex].weightKg} → ${weight ?? 0.0} кг)');
                      final ex = ExerciseItem(
                          name: name,
                          sets: sets,
                          reps: reps,
                          weightKg: weight ?? 0.0);
                      interim[existingIndex] = ex;
                      if (onExercise != null) onExercise(ex);
                    }
                  } else if (interim.length < targetExercises &&
                      !sentExerciseNames.contains(name)) {
                    // Добавляем новое упражнение ТОЛЬКО если еще НЕ отправляли
                    debugPrint(
                        '➕ FALLBACK STREAMING: День $dayIndex новое: $name (${sets}x$reps, ${weight ?? 0.0} кг)');
                    final ex = ExerciseItem(
                        name: name,
                        sets: sets,
                        reps: reps,
                        weightKg: weight ?? 0.0);
                    interim.add(ex);
                    sentExerciseNames.add(name); // Помечаем как отправленное
                    if (onExercise != null) onExercise(ex);
                  }
                }
              }
            }
          }
        }

        // ОПТИМИЗАЦИЯ: Как только получили достаточно упражнений - завершаем досрочно
        if (interim.length >= targetExercises &&
            streamedTitle != null &&
            streamedTitle!.isNotEmpty &&
            !completer.isCompleted) {
          debugPrint(
              '⚡ Достигнуто $targetExercises упражнений для дня $dayIndex, завершаем досрочно');
          completer.complete(WorkoutPlanModel(
            dayTitle: streamedTitle!,
            exercises: List<ExerciseItem>.from(interim),
          ));
        }

        // Пробуем распарсить финальный JSON
        final parsed = _dayGenerator.tryParseWorkoutFromText(buffer.toString());
        if (parsed != null && !completer.isCompleted) {
          _dayGenerator
              .normalizeWorkoutLanguage(context: context, plan: parsed)
              .then((normalized) {
            if (!completer.isCompleted) {
              completer.complete(normalized);
            }
          }).catchError((_) {
            if (!completer.isCompleted) {
              completer.complete(parsed);
            }
          });
        }
      }, onError: (e) {
        if (!completer.isCompleted) {
          // Используем промежуточные данные если есть
          if (interim.isNotEmpty) {
            completer.complete(WorkoutPlanModel(
              dayTitle: streamedTitle ?? 'Тренировка',
              exercises: interim,
            ));
          } else {
            completer.complete(WorkoutPlanModel(
              dayTitle: 'Тренировка',
              exercises: const [],
            ));
          }
        }
      }, onDone: () {
        if (!completer.isCompleted) {
          final parsed =
              _dayGenerator.tryParseWorkoutFromText(buffer.toString());
          if (parsed != null) {
            _dayGenerator
                .normalizeWorkoutLanguage(context: context, plan: parsed)
                .then((norm) {
              if (!completer.isCompleted) completer.complete(norm);
            }).catchError((_) {
              if (!completer.isCompleted) completer.complete(parsed);
            });
          } else if (interim.isNotEmpty) {
            completer.complete(WorkoutPlanModel(
              dayTitle: streamedTitle ?? 'Тренировка',
              exercises: interim,
            ));
          } else {
            completer.complete(WorkoutPlanModel(
              dayTitle: 'Тренировка',
              exercises: const [],
            ));
          }
        }
      });

      WorkoutPlanModel finalPlan;
      try {
        finalPlan = await completer.future;
      } finally {
        await sub.cancel();
      }

      // ИСПРАВЛЕНИЕ: Сохраняем день по конкретному индексу
      await _repository.saveDayAtIndex(weekStartDate, finalPlan, dayIndex, n);
      debugPrint('💾 День $dayIndex сохранен по индексу');

      // Если неделя стала полной — реплицируем месяц вперёд один раз
      final latestAfter = await _repository.getPlanForWeek(weekStartDate);
      if (latestAfter != null &&
          latestAfter.days.length >= latestAfter.workoutsPerWeek) {
        final int keyRep = weekStartDate.millisecondsSinceEpoch;
        if (!_replicatedWeeks.contains(keyRep)) {
          _replicatedWeeks.add(keyRep);
          await replicateWeeksForward(fromWeekStart: weekStartDate, weeks: 4);
        }
      }
    }();

    _inflightStreams[key] = future;
    try {
      await future;
    } finally {
      _inflightStreams.remove(key);
    }
  }

  Future<WorkoutPlanModel> _generateOneDay({
    required BuildContext context,
    required UserModel user,
    required DateTime weekStartDate,
    required int dayIndexInWeek,
    required int weekdayNumber,
  }) async {
    // Используем потоковый метод для UX, но здесь нам нужен финальный JSON
    final completer = Completer<WorkoutPlanModel>();
    final StringBuffer buffer = StringBuffer();
    final sub = _dayGenerator
        .streamWorkoutText(
      user: user,
      context: context,
      dayIndexInWeek: dayIndexInWeek,
      weekdayNumber: weekdayNumber,
      weekStartDate: weekStartDate,
    )
        .listen((chunk) {
      buffer.write(chunk);
      final parsed = _dayGenerator.tryParseWorkoutFromText(buffer.toString());
      if (parsed != null && !completer.isCompleted) {
        // Нормализуем язык и завершаем
        _dayGenerator
            .normalizeWorkoutLanguage(context: context, plan: parsed)
            .then((norm) {
          if (!completer.isCompleted) completer.complete(norm);
        }).catchError((_) {
          if (!completer.isCompleted) completer.complete(parsed);
        });
      }
    }, onError: (e) {
      if (!completer.isCompleted) {
        // Фолбэк: пустая тренировка, чтобы не блокироваться
        completer.complete(
            WorkoutPlanModel(dayTitle: 'Тренировка', exercises: const []));
      }
    }, onDone: () {
      if (!completer.isCompleted) {
        final parsed = _dayGenerator.tryParseWorkoutFromText(buffer.toString());
        if (parsed != null) {
          _dayGenerator
              .normalizeWorkoutLanguage(context: context, plan: parsed)
              .then((norm) {
            if (!completer.isCompleted) completer.complete(norm);
          }).catchError((_) {
            if (!completer.isCompleted) completer.complete(parsed);
          });
        } else {
          completer.complete(
              WorkoutPlanModel(dayTitle: 'Тренировка', exercises: const []));
        }
      }
    });
    final plan = await completer.future;
    await sub.cancel();
    return plan;
  }

  List<int> _weekdayPatternFor(int workoutsPerWeek) {
    switch (workoutsPerWeek.clamp(1, 7)) {
      case 1:
        return [DateTime.monday];
      case 2:
        return [DateTime.tuesday, DateTime.friday];
      case 3:
        return [DateTime.monday, DateTime.wednesday, DateTime.friday];
      case 4:
        return [
          DateTime.monday,
          DateTime.tuesday,
          DateTime.thursday,
          DateTime.saturday
        ];
      case 5:
        return [
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.friday,
          DateTime.saturday
        ];
      default:
        return [
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
          DateTime.saturday,
          DateTime.sunday,
        ];
    }
  }
}

/// Провайдеры
final weeklyWorkoutPlanRepositoryProvider =
    Provider<WorkoutPlanRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SharedPrefsWorkoutPlanRepository(prefs);
});

final weeklyWorkoutPlanServiceProvider =
    Provider<WeeklyWorkoutPlanService>((ref) {
  final repo = ref.watch(weeklyWorkoutPlanRepositoryProvider);
  return WeeklyWorkoutPlanService(repository: repo);
});

/// Текущий план недели (из кеша)
final weeklyPlanForCurrentWeekProvider =
    FutureProvider<WeeklyWorkoutPlanModel?>((ref) async {
  final service = ref.watch(weeklyWorkoutPlanServiceProvider);
  return service.getCachedWeekPlan(DateTime.now());
});

/// План недели для произвольной даты (из кеша)
final weeklyPlanForDateProvider =
    FutureProvider.family<WeeklyWorkoutPlanModel?, DateTime>((ref, date) async {
  final service = ref.watch(weeklyWorkoutPlanServiceProvider);
  return service.getCachedWeekPlan(date);
});
