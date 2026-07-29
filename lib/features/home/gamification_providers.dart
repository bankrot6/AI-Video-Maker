import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/gamification_model.dart';
import 'home_providers.dart';

/// Провайдер для данных геймификации текущего пользователя
final gamificationProvider =
    StateNotifierProvider<GamificationNotifier, GamificationModel?>((ref) {
  return GamificationNotifier(ref);
});

/// Нотификатор для управления состоянием геймификации
class GamificationNotifier extends StateNotifier<GamificationModel?> {
  final Ref _ref;

  GamificationNotifier(this._ref) : super(null) {
    _loadGamificationData();
  }

  /// Загружает данные геймификации для текущего пользователя
  Future<void> _loadGamificationData() async {
    try {
      final userRepository = _ref.read(userRepositoryProvider);
      final currentUser = await userRepository.getCurrentUser();

      if (currentUser != null) {
        // Загружаем данные геймификации из хранилища
        final gamificationData = await _loadFromStorage(currentUser.id);
        state = gamificationData;

        // ВАЖНО: пересчитываем фактические данные из репозитория приемов пищи,
        // чтобы не зависеть от временных инкрементов и отсутствия персиста
        await _recomputeFromRepository(DateTime.now());
      }
    } catch (e) {
      // В случае ошибки создаем пустую модель
      state = GamificationModel(
        lastUpdated: DateTime.now(),
        installDate: DateTime.now(),
      );
    }
  }

  /// Обновляет прогресс при добавлении нового приема пищи
  Future<void> onMealAdded() async {
    if (state == null) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastUpdateDate = DateTime(
      state!.lastUpdated.year,
      state!.lastUpdated.month,
      state!.lastUpdated.day,
    );

    // Если это новый день, сбрасываем дневной счетчик
    int newDailyMeals = state!.currentDailyMeals;
    int newWeeklyProgress = state!.currentWeeklyProgress;
    int newWeeklyMeals = state!.currentWeeklyMeals;

    if (today.isAfter(lastUpdateDate)) {
      // Проверяем, была ли достигнута цель вчера
      if (state!.isDailyGoalCompleted) {
        // Обновляем недельный прогресс
        if (_isStartOfNewWeek(today, state!.installDate)) {
          // Начало новой недели - сброс недельного счетчика
          newWeeklyProgress = 1;
          newWeeklyMeals = 1; // Сброс счетчика приемов пищи за неделю
        } else {
          newWeeklyProgress = state!.currentWeeklyProgress + 1;
          newWeeklyMeals = state!.currentWeeklyMeals + 1;
        }
      } else {
        // Цель не была достигнута
        if (_isStartOfNewWeek(today, state!.installDate)) {
          newWeeklyProgress = 0;
          newWeeklyMeals = 1; // Сброс и первый прием пищи новой недели
        } else {
          newWeeklyMeals = state!.currentWeeklyMeals + 1;
        }
      }

      newDailyMeals = 1; // Первый прием пищи за новый день
    } else {
      // Тот же день - просто увеличиваем счетчики
      newDailyMeals = state!.currentDailyMeals + 1;
      newWeeklyMeals = state!.currentWeeklyMeals + 1;
    }

    // Проверяем, нужно ли разблокировать AI чат
    final shouldUnlock = newWeeklyMeals >= 21;

    final updatedState = state!.copyWith(
      currentDailyMeals: newDailyMeals,
      currentWeeklyProgress: newWeeklyProgress,
      currentWeeklyMeals: newWeeklyMeals,
      isAiChatUnlocked: shouldUnlock,
      lastMealTime: now,
      lastUpdated: now,
    );

    state = updatedState;

    // Сохраняем данные
    await _saveToStorage(updatedState);

    // Дополнительно синхронизируемся с репозиторием, чтобы недельный счетчик
    // отражал реальное количество приемов пищи за неделю
    await _recomputeFromRepository(DateTime.now());
  }

  /// Сбрасывает данные геймификации
  Future<void> reset() async {
    state = GamificationModel(
      lastUpdated: DateTime.now(),
      installDate: DateTime.now(),
    );
    await _saveToStorage(state!);
  }

  /// Проверяет, является ли указанная дата началом новой недели относительно дня установки
  bool _isStartOfNewWeek(DateTime date, DateTime? installDate) {
    if (installDate == null) return false;

    // Вычисляем количество дней с установки
    final daysSinceInstall = date.difference(installDate).inDays;

    // Если прошло кратное 7 дней, то это начало новой недели
    return daysSinceInstall % 7 == 0;
  }

  /// Загружает данные из локального хранилища
  Future<GamificationModel> _loadFromStorage(String userId) async {
    try {
      // TODO: Здесь будет интеграция с SharedPreferences или Hive
      // Возвращаем пустую модель для реальных данных
      return GamificationModel(
        lastUpdated: DateTime.now(),
        installDate: DateTime.now(),
      );
    } catch (e) {
      return GamificationModel(
        lastUpdated: DateTime.now(),
        installDate: DateTime.now(),
      );
    }
  }

  /// Сохраняет данные в локальное хранилище
  Future<void> _saveToStorage(GamificationModel data) async {
    try {
      // TODO: Здесь будет интеграция с SharedPreferences или Hive
      // Пока просто логируем
      print('Gamification data saved: ${data.toJson()}');
    } catch (e) {
      print('Error saving gamification data: $e');
    }
  }

  /// Вычисляет дневной прогресс на основе количества приемов пищи за день
  Future<void> updateDailyProgress(DateTime date) async {
    try {
      final mealRepository = _ref.read(mealRepositoryProvider);
      final meals = await mealRepository.getMealsForDay(date);

      if (state != null) {
        final today = DateTime.now();
        final targetDate = DateTime(date.year, date.month, date.day);
        final todayDate = DateTime(today.year, today.month, today.day);

        // Обновляем только если это сегодняшний день
        if (targetDate.isAtSameMomentAs(todayDate)) {
          state = state!.copyWith(
            currentDailyMeals: meals.length,
            lastUpdated: DateTime.now(),
          );

          // После обновления дневного значения – пересчитываем всю неделю из репозитория
          await _recomputeFromRepository(today);
        }
      }
    } catch (e) {
      print('Error updating daily progress: $e');
    }
  }

  /// Пересчитывает показатели геймификации по данным репозитория за текущую неделю
  Future<void> _recomputeFromRepository(DateTime referenceDate) async {
    try {
      final mealRepository = _ref.read(mealRepositoryProvider);

      final today =
          DateTime(referenceDate.year, referenceDate.month, referenceDate.day);
      // Начало недели (понедельник)
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1));

      int weeklyMeals = 0;
      int weeklyProgressDays = 0;
      final int dailyTarget = state?.dailyMealsTarget ?? 3;
      final List<int> weekDailyMeals = List<int>.filled(7, 0, growable: false);

      for (int i = 0; i < 7; i++) {
        final d = startOfWeek.add(Duration(days: i));
        final dayMeals = await mealRepository.getMealsForDay(d);
        final count = dayMeals.length;
        weekDailyMeals[i] = count;
        if (!d.isAfter(today)) {
          weeklyMeals += count;
          if (count >= dailyTarget) {
            weeklyProgressDays += 1;
          }
        }
      }

      // Текущие приемы пищи за сегодня
      final todayMeals = await mealRepository.getMealsForDay(today);

      final newState = (state ??
              GamificationModel(
                lastUpdated: DateTime.now(),
                installDate: startOfWeek,
              ))
          .copyWith(
        currentDailyMeals: todayMeals.length,
        currentWeeklyMeals: weeklyMeals,
        currentWeeklyProgress: weeklyProgressDays,
        weekDailyMeals: weekDailyMeals,
        lastUpdated: DateTime.now(),
        // Устанавливаем дату установки, если её не было – на начало недели,
        // чтобы корректно работал расчёт «новой недели», если он где-либо используется
        installDate: state?.installDate ?? startOfWeek,
      );

      state = newState;
      await _saveToStorage(newState);
    } catch (e) {
      print('Error recomputing gamification from repository: $e');
    }
  }
}
