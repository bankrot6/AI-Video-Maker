import 'package:equatable/equatable.dart';

/// Модель геймификации для отслеживания прогресса пользователя
class GamificationModel extends Equatable {
  /// Цель приемов пищи в день (по умолчанию 3)
  final int dailyMealsTarget;

  /// Цель дней в неделю с выполненной дневной целью (по умолчанию 5 из 7)
  final int weeklyDaysTarget;

  /// Текущее количество приемов пищи за сегодня
  final int currentDailyMeals;

  /// Количество дней в текущей неделе с выполненной целью
  final int currentWeeklyProgress;

  /// Общее количество приемов пищи за текущую неделю
  final int currentWeeklyMeals;

  /// Количество приемов пищи по каждому дню текущей недели, начиная с понедельника (7 значений)
  /// Индекс 0 — понедельник, 6 — воскресенье
  final List<int> weekDailyMeals;

  /// Разблокирован ли чат с AI диетологом
  final bool isAiChatUnlocked;

  /// Время последнего добавленного приема пищи
  final DateTime? lastMealTime;

  /// Дата последнего обновления данных
  final DateTime lastUpdated;

  /// Дата установки приложения (для подсчета недели)
  final DateTime? installDate;

  const GamificationModel({
    this.dailyMealsTarget = 3,
    this.weeklyDaysTarget = 7,
    this.currentDailyMeals = 0,
    this.currentWeeklyProgress = 0,
    this.currentWeeklyMeals = 0,
    this.weekDailyMeals = const [],
    this.isAiChatUnlocked = false,
    this.lastMealTime,
    required this.lastUpdated,
    this.installDate,
  });

  /// Процент выполнения дневной цели (0.0 - 1.0)
  double get dailyProgress =>
      (currentDailyMeals / dailyMealsTarget).clamp(0.0, 1.0);

  /// Выполнена ли дневная цель
  bool get isDailyGoalCompleted => currentDailyMeals >= dailyMealsTarget;

  /// Процент выполнения недельной цели (0.0 - 1.0)
  double get weeklyProgress =>
      (currentWeeklyProgress / weeklyDaysTarget).clamp(0.0, 1.0);

  /// Выполнена ли недельная цель
  bool get isWeeklyGoalCompleted => currentWeeklyProgress >= weeklyDaysTarget;

  /// Нужно ли разблокировать чат с AI (21 прием пищи за неделю)
  bool get shouldUnlockAiChat => currentWeeklyMeals >= 21;

  @override
  List<Object?> get props => [
        dailyMealsTarget,
        weeklyDaysTarget,
        currentDailyMeals,
        currentWeeklyProgress,
        currentWeeklyMeals,
        weekDailyMeals,
        isAiChatUnlocked,
        lastMealTime,
        lastUpdated,
        installDate,
      ];

  factory GamificationModel.fromJson(Map<String, dynamic> json) {
    return GamificationModel(
      dailyMealsTarget: json['dailyMealsTarget'] as int? ?? 3,
      weeklyDaysTarget: json['weeklyDaysTarget'] as int? ?? 7,
      currentDailyMeals: json['currentDailyMeals'] as int? ?? 0,
      currentWeeklyProgress: json['currentWeeklyProgress'] as int? ?? 0,
      currentWeeklyMeals: json['currentWeeklyMeals'] as int? ?? 0,
      weekDailyMeals: (json['weekDailyMeals'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      isAiChatUnlocked: json['isAiChatUnlocked'] as bool? ?? false,
      lastMealTime: json['lastMealTime'] != null
          ? DateTime.parse(json['lastMealTime'] as String)
          : null,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      installDate: json['installDate'] != null
          ? DateTime.parse(json['installDate'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dailyMealsTarget': dailyMealsTarget,
      'weeklyDaysTarget': weeklyDaysTarget,
      'currentDailyMeals': currentDailyMeals,
      'currentWeeklyProgress': currentWeeklyProgress,
      'currentWeeklyMeals': currentWeeklyMeals,
      'weekDailyMeals': weekDailyMeals,
      'isAiChatUnlocked': isAiChatUnlocked,
      'lastMealTime': lastMealTime?.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'installDate': installDate?.toIso8601String(),
    };
  }

  GamificationModel copyWith({
    int? dailyMealsTarget,
    int? weeklyDaysTarget,
    int? currentDailyMeals,
    int? currentWeeklyProgress,
    int? currentWeeklyMeals,
    List<int>? weekDailyMeals,
    bool? isAiChatUnlocked,
    DateTime? lastMealTime,
    DateTime? lastUpdated,
    DateTime? installDate,
  }) {
    return GamificationModel(
      dailyMealsTarget: dailyMealsTarget ?? this.dailyMealsTarget,
      weeklyDaysTarget: weeklyDaysTarget ?? this.weeklyDaysTarget,
      currentDailyMeals: currentDailyMeals ?? this.currentDailyMeals,
      currentWeeklyProgress:
          currentWeeklyProgress ?? this.currentWeeklyProgress,
      currentWeeklyMeals: currentWeeklyMeals ?? this.currentWeeklyMeals,
      weekDailyMeals: weekDailyMeals ?? this.weekDailyMeals,
      isAiChatUnlocked: isAiChatUnlocked ?? this.isAiChatUnlocked,
      lastMealTime: lastMealTime ?? this.lastMealTime,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      installDate: installDate ?? this.installDate,
    );
  }
}
