import 'package:equatable/equatable.dart';

class ExerciseItem extends Equatable {
  final String name;
  final int sets;
  final int reps;
  final double weightKg;

  const ExerciseItem({
    required this.name,
    required this.sets,
    required this.reps,
    required this.weightKg,
  });

  factory ExerciseItem.fromJson(Map<String, dynamic> json) {
    final dynamic weightRaw = json['weightKg'];
    final double parsedWeight = weightRaw is num
        ? weightRaw.toDouble()
        : double.tryParse('${weightRaw ?? 0}') ?? 0.0;
    return ExerciseItem(
      name: (json['name'] ?? '').toString(),
      sets: (json['sets'] is num)
          ? (json['sets'] as num).toInt()
          : int.tryParse('${json['sets'] ?? 0}') ?? 0,
      reps: (json['reps'] is num)
          ? (json['reps'] as num).toInt()
          : int.tryParse('${json['reps'] ?? 0}') ?? 0,
      weightKg: parsedWeight,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'sets': sets,
        'reps': reps,
        'weightKg': weightKg,
      };

  @override
  List<Object?> get props => [name, sets, reps, weightKg];
}

class WorkoutPlanModel extends Equatable {
  final String dayTitle;
  final List<ExerciseItem> exercises;

  const WorkoutPlanModel({
    required this.dayTitle,
    required this.exercises,
  });

  factory WorkoutPlanModel.fromJson(Map<String, dynamic> json) {
    final List<ExerciseItem> items = (json['exercises'] is List)
        ? (json['exercises'] as List)
            .whereType<Map<String, dynamic>>()
            .map(ExerciseItem.fromJson)
            .toList()
        : <ExerciseItem>[];
    return WorkoutPlanModel(
      dayTitle: (json['dayTitle'] ?? '').toString().isEmpty
          ? 'Тренировка'
          : (json['dayTitle'] ?? '').toString(),
      exercises: items,
    );
  }

  Map<String, dynamic> toJson() => {
        'dayTitle': dayTitle,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  @override
  List<Object?> get props => [dayTitle, exercises];
}
