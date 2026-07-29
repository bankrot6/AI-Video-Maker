import 'package:equatable/equatable.dart';

class StepEntry extends Equatable {
  final DateTime date;
  final int steps;
  final double distanceKm;
  final double caloriesBurned;
  final int activeMinutes;
  final int goal;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StepEntry({
    required this.date,
    required this.steps,
    this.distanceKm = 0,
    this.caloriesBurned = 0,
    this.activeMinutes = 0,
    this.goal = 10000,
    required this.createdAt,
    required this.updatedAt,
  });

  double get progressPercent => goal > 0 ? (steps / goal).clamp(0.0, 1.0) : 0.0;
  
  bool get isGoalReached => steps >= goal;

  String get dateKey => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  StepEntry copyWith({
    DateTime? date,
    int? steps,
    double? distanceKm,
    double? caloriesBurned,
    int? activeMinutes,
    int? goal,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StepEntry(
      date: date ?? this.date,
      steps: steps ?? this.steps,
      distanceKm: distanceKm ?? this.distanceKm,
      caloriesBurned: caloriesBurned ?? this.caloriesBurned,
      activeMinutes: activeMinutes ?? this.activeMinutes,
      goal: goal ?? this.goal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'steps': steps,
      'distanceKm': distanceKm,
      'caloriesBurned': caloriesBurned,
      'activeMinutes': activeMinutes,
      'goal': goal,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory StepEntry.fromJson(Map<String, dynamic> json) {
    return StepEntry(
      date: DateTime.parse(json['date'] as String),
      steps: json['steps'] as int? ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      caloriesBurned: (json['caloriesBurned'] as num?)?.toDouble() ?? 0,
      activeMinutes: json['activeMinutes'] as int? ?? 0,
      goal: json['goal'] as int? ?? 10000,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  factory StepEntry.empty(DateTime date, {int goal = 10000}) {
    final now = DateTime.now();
    return StepEntry(
      date: DateTime(date.year, date.month, date.day),
      steps: 0,
      distanceKm: 0,
      caloriesBurned: 0,
      activeMinutes: 0,
      goal: goal,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  List<Object?> get props => [
        date,
        steps,
        distanceKm,
        caloriesBurned,
        activeMinutes,
        goal,
        createdAt,
        updatedAt,
      ];
}

class StepStats extends Equatable {
  final int totalSteps;
  final double totalDistanceKm;
  final double totalCaloriesBurned;
  final int totalActiveMinutes;
  final double averageStepsPerDay;
  final int daysWithGoalReached;
  final int totalDays;
  final int bestDay;
  final DateTime? bestDayDate;
  final List<StepEntry> entries;

  const StepStats({
    required this.totalSteps,
    required this.totalDistanceKm,
    required this.totalCaloriesBurned,
    required this.totalActiveMinutes,
    required this.averageStepsPerDay,
    required this.daysWithGoalReached,
    required this.totalDays,
    required this.bestDay,
    this.bestDayDate,
    required this.entries,
  });

  factory StepStats.fromEntries(List<StepEntry> entries) {
    if (entries.isEmpty) {
      return const StepStats(
        totalSteps: 0,
        totalDistanceKm: 0,
        totalCaloriesBurned: 0,
        totalActiveMinutes: 0,
        averageStepsPerDay: 0,
        daysWithGoalReached: 0,
        totalDays: 0,
        bestDay: 0,
        bestDayDate: null,
        entries: [],
      );
    }

    int totalSteps = 0;
    double totalDistance = 0;
    double totalCalories = 0;
    int totalActiveMinutes = 0;
    int daysWithGoal = 0;
    int bestDay = 0;
    DateTime? bestDayDate;

    for (final entry in entries) {
      totalSteps += entry.steps;
      totalDistance += entry.distanceKm;
      totalCalories += entry.caloriesBurned;
      totalActiveMinutes += entry.activeMinutes;
      if (entry.isGoalReached) daysWithGoal++;
      if (entry.steps > bestDay) {
        bestDay = entry.steps;
        bestDayDate = entry.date;
      }
    }

    return StepStats(
      totalSteps: totalSteps,
      totalDistanceKm: totalDistance,
      totalCaloriesBurned: totalCalories,
      totalActiveMinutes: totalActiveMinutes,
      averageStepsPerDay: entries.isNotEmpty ? totalSteps / entries.length : 0,
      daysWithGoalReached: daysWithGoal,
      totalDays: entries.length,
      bestDay: bestDay,
      bestDayDate: bestDayDate,
      entries: entries,
    );
  }

  @override
  List<Object?> get props => [
        totalSteps,
        totalDistanceKm,
        totalCaloriesBurned,
        totalActiveMinutes,
        averageStepsPerDay,
        daysWithGoalReached,
        totalDays,
        bestDay,
        bestDayDate,
        entries,
      ];
}

enum StepPeriod {
  day,
  week,
  month,
}








