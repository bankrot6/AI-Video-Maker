import 'package:equatable/equatable.dart';
import 'workout_plan_model.dart';

/// Модель недельного плана тренировок
class WeeklyWorkoutPlanModel extends Equatable {
  final DateTime weekStart; // начало недели (понедельник, без времени)
  final int workoutsPerWeek;
  final List<WorkoutPlanModel> days; // индекс 0 => День 1 недели

  const WeeklyWorkoutPlanModel({
    required this.weekStart,
    required this.workoutsPerWeek,
    required this.days,
  });

  bool get isComplete => days.length >= workoutsPerWeek;

  WeeklyWorkoutPlanModel copyWith({
    DateTime? weekStart,
    int? workoutsPerWeek,
    List<WorkoutPlanModel>? days,
  }) {
    return WeeklyWorkoutPlanModel(
      weekStart: weekStart ?? this.weekStart,
      workoutsPerWeek: workoutsPerWeek ?? this.workoutsPerWeek,
      days: days ?? this.days,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'weekStart': weekStart.toIso8601String(),
      'workoutsPerWeek': workoutsPerWeek,
      'days': days.map((e) => e.toJson()).toList(),
    };
  }

  factory WeeklyWorkoutPlanModel.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawDays = (json['days'] as List?) ?? <dynamic>[];
    return WeeklyWorkoutPlanModel(
      weekStart: DateTime.parse(
              (json['weekStart'] ?? DateTime.now().toIso8601String()) as String)
          .toLocal(),
      workoutsPerWeek: (json['workoutsPerWeek'] is num)
          ? (json['workoutsPerWeek'] as num).toInt()
          : int.tryParse('${json['workoutsPerWeek'] ?? 3}') ?? 3,
      days: rawDays
          .whereType<Map<String, dynamic>>()
          .map(WorkoutPlanModel.fromJson)
          .toList(),
    );
  }

  @override
  List<Object?> get props =>
      [weekStart.millisecondsSinceEpoch, workoutsPerWeek, days];
}

/// Утилиты для вычисления начала недели (понедельник)
DateTime startOfWeek(DateTime date) {
  final normalized = DateTime(date.year, date.month, date.day);
  // Делаем понедельник первым днем недели: weekday Monday=1, Sunday=7
  final int diff = normalized.weekday - DateTime.monday;
  return normalized.subtract(Duration(days: diff));
}







































