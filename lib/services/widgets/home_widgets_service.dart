import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../features/home/home_providers.dart' as home;
import '../../models/user_model.dart';

/// Сервис обновления данных домашних виджетов (home_widget)
/// Отдельные методы обновляют «Прогресс дня» и «Воду»
class HomeWidgetsService {
  static bool _bindingsInitialized = false;

  /// Реактивная инициализация: как только загрузится текущий пользователь,
  /// мгновенно сохраняем цели в HomeWidget storage и обновляем виджеты.
  static void setupBindings(WidgetRef ref) {
    if (_bindingsInitialized) return;
    _bindingsInitialized = true;

    ref.listen<UserModel?>(home.currentUserProvider, (previous, next) async {
      if (next == null) return;
      try {
        await HomeWidget.saveWidgetData(
          'dp_goal_cal',
          next.nutritionGoals.dailyCalories,
        );
        await HomeWidget.saveWidgetData(
          'dp_goal_protein',
          next.nutritionGoals.dailyProtein,
        );
        await HomeWidget.saveWidgetData(
          'dp_goal_fat',
          next.nutritionGoals.dailyFat,
        );
        await HomeWidget.saveWidgetData(
          'dp_goal_carbs',
          next.nutritionGoals.dailyCarbs,
        );
        await HomeWidget.saveWidgetData(
          'water_goal_ml',
          next.nutritionGoals.dailyWaterMl,
        );

        // Инициализируем нулями фактические значения для корректного "0 / goal"
        await HomeWidget.saveWidgetData('dp_cal', 0);
        await HomeWidget.saveWidgetData('dp_protein', 0);
        await HomeWidget.saveWidgetData('dp_fat', 0);
        await HomeWidget.saveWidgetData('dp_carbs', 0);
        await HomeWidget.saveWidgetData('water_total_ml', 0);

        final now = DateTime.now();
        await HomeWidget.saveWidgetData(
          'dp_date',
          DateFormat('yyyy-MM-dd').format(now),
        );

        await HomeWidget.updateWidget(name: 'DailyProgressWidgetProvider');
        await HomeWidget.updateWidget(name: 'WaterWidgetProvider');
      } catch (_) {}
    });
  }

  /// Ранний бутстрап: записывает цели в HomeWidget до runApp,
  /// когда у нас уже есть объект пользователя (без Riverpod).
  static Future<void> bootstrapGoalsFromUser(UserModel user) async {
    try {
      await HomeWidget.saveWidgetData(
        'dp_goal_cal',
        user.nutritionGoals.dailyCalories,
      );
      await HomeWidget.saveWidgetData(
        'dp_goal_protein',
        user.nutritionGoals.dailyProtein,
      );
      await HomeWidget.saveWidgetData(
        'dp_goal_fat',
        user.nutritionGoals.dailyFat,
      );
      await HomeWidget.saveWidgetData(
        'dp_goal_carbs',
        user.nutritionGoals.dailyCarbs,
      );
      await HomeWidget.saveWidgetData(
        'water_goal_ml',
        user.nutritionGoals.dailyWaterMl,
      );

      // Факты нулевые на самом старте
      await HomeWidget.saveWidgetData('dp_cal', 0);
      await HomeWidget.saveWidgetData('dp_protein', 0);
      await HomeWidget.saveWidgetData('dp_fat', 0);
      await HomeWidget.saveWidgetData('dp_carbs', 0);
      await HomeWidget.saveWidgetData('water_total_ml', 0);

      final now = DateTime.now();
      await HomeWidget.saveWidgetData(
        'dp_date',
        DateFormat('yyyy-MM-dd').format(now),
      );

      await HomeWidget.updateWidget(name: 'DailyProgressWidgetProvider');
      await HomeWidget.updateWidget(name: 'WaterWidgetProvider');
      // Явный широковещательный пинг провайдеров Android
      try {
        await HomeWidget.updateWidget(
          name: 'DailyProgressWidgetProvider',
          androidName: 'com.aivideomaker.app.DailyProgressWidgetProvider',
        );
        await HomeWidget.updateWidget(
          name: 'WaterWidgetProvider',
          androidName: 'com.aivideomaker.app.WaterWidgetProvider',
        );
      } catch (_) {}

      // Дополнительные отложенные обновления, чтобы перекрыть гонки с запуском провайдеров
      Future.delayed(const Duration(milliseconds: 500), () async {
        try {
          await HomeWidget.updateWidget(name: 'DailyProgressWidgetProvider');
          await HomeWidget.updateWidget(name: 'WaterWidgetProvider');
        } catch (_) {}
      });
      Future.delayed(const Duration(seconds: 2), () async {
        try {
          await HomeWidget.updateWidget(name: 'DailyProgressWidgetProvider');
          await HomeWidget.updateWidget(name: 'WaterWidgetProvider');
          try {
            await HomeWidget.updateWidget(
              name: 'DailyProgressWidgetProvider',
              androidName: 'com.aivideomaker.app.DailyProgressWidgetProvider',
            );
            await HomeWidget.updateWidget(
              name: 'WaterWidgetProvider',
              androidName: 'com.aivideomaker.app.WaterWidgetProvider',
            );
          } catch (_) {}
        } catch (_) {}
      });
    } catch (_) {}
  }

  /// Обновляет данные виджета «Прогресс дня» на основе репозиториев
  static Future<void> updateDailyProgressFromRepo(WidgetRef ref) async {
    try {
      final mealRepo = ref.read(home.mealRepositoryProvider);
      final userRepo = ref.read(home.userRepositoryProvider);
      final waterRepo = ref.read(home.waterRepositoryProvider);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final total = await mealRepo.getDailyNutrientsTotal(today);
      final user = await userRepo.getCurrentUser();
      if (user == null) return;

      await HomeWidget.saveWidgetData(
        'dp_date',
        DateFormat('yyyy-MM-dd').format(now),
      );
      await HomeWidget.saveWidgetData('dp_cal', total.calories);
      await HomeWidget.saveWidgetData('dp_protein', total.proteins.round());
      await HomeWidget.saveWidgetData('dp_fat', total.fats.round());
      await HomeWidget.saveWidgetData('dp_carbs', total.carbs.round());

      await HomeWidget.saveWidgetData(
        'dp_goal_cal',
        user.nutritionGoals.dailyCalories,
      );
      await HomeWidget.saveWidgetData(
        'dp_goal_protein',
        user.nutritionGoals.dailyProtein,
      );
      await HomeWidget.saveWidgetData(
        'dp_goal_fat',
        user.nutritionGoals.dailyFat,
      );
      await HomeWidget.saveWidgetData(
        'dp_goal_carbs',
        user.nutritionGoals.dailyCarbs,
      );

      // Обновляем показатели воды вместе с прогрессом дня для надёжности
      final totalWaterMl = await waterRepo.getTotalForDate(today);
      await HomeWidget.saveWidgetData('water_total_ml', totalWaterMl);
      await HomeWidget.saveWidgetData(
        'water_goal_ml',
        user.nutritionGoals.dailyWaterMl,
      );

      await HomeWidget.updateWidget(name: 'DailyProgressWidgetProvider');
    } catch (_) {
      // Игнорируем, чтобы не ломать UX при фоновых ошибках
    }
  }

  /// Обновляет данные виджета «Вода» на основе репозиториев
  static Future<void> updateWaterFromRepo(WidgetRef ref) async {
    try {
      final waterRepo = ref.read(home.waterRepositoryProvider);
      final userRepo = ref.read(home.userRepositoryProvider);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final totalMl = await waterRepo.getTotalForDate(today);
      final user = await userRepo.getCurrentUser();
      if (user == null) return;

      await HomeWidget.saveWidgetData(
        'water_date',
        DateFormat('yyyy-MM-dd').format(now),
      );
      await HomeWidget.saveWidgetData('water_total_ml', totalMl);
      await HomeWidget.saveWidgetData(
        'water_goal_ml',
        user.nutritionGoals.dailyWaterMl,
      );

      // Обновляем оба: отдельный виджет воды и общий daily-progress, где тоже есть вода
      await HomeWidget.updateWidget(name: 'WaterWidgetProvider');
      await HomeWidget.updateWidget(name: 'DailyProgressWidgetProvider');
    } catch (_) {
      // Игнорируем, чтобы не ломать UX при фоновых ошибках
    }
  }

  /// Вызывать при старте приложения, чтобы вода сразу показала остаток/цель
  static Future<void> primeWaterOnStartup(WidgetRef ref) async {
    try {
      final waterRepo = ref.read(home.waterRepositoryProvider);
      final userRepo = ref.read(home.userRepositoryProvider);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final totalMl = await waterRepo.getTotalForDate(today);
      final user = await userRepo.getCurrentUser();
      if (user == null) return;

      await HomeWidget.saveWidgetData('water_total_ml', totalMl);
      await HomeWidget.saveWidgetData(
        'water_goal_ml',
        user.nutritionGoals.dailyWaterMl,
      );
      await HomeWidget.updateWidget(name: 'DailyProgressWidgetProvider');
    } catch (_) {}
  }
}
