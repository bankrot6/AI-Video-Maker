import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ExerciseSetExecution {
  final int? reps;
  final double? weight;
  final double? rpe;
  final bool done;

  const ExerciseSetExecution({
    required this.reps,
    required this.weight,
    required this.rpe,
    required this.done,
  });

  ExerciseSetExecution copyWith({
    int? reps,
    double? weight,
    double? rpe,
    bool? done,
  }) {
    return ExerciseSetExecution(
      reps: reps ?? this.reps,
      weight: weight ?? this.weight,
      rpe: rpe ?? this.rpe,
      done: done ?? this.done,
    );
  }

  Map<String, dynamic> toJson() => {
        'reps': reps,
        'weight': weight,
        'rpe': rpe,
        'done': done,
      };

  factory ExerciseSetExecution.fromJson(Map<String, dynamic> json) {
    return ExerciseSetExecution(
      reps: json['reps'] is num ? (json['reps'] as num).toInt() : null,
      weight: json['weight'] is num
          ? (json['weight'] as num).toDouble()
          : (json['weight'] is String
              ? double.tryParse(json['weight'] as String)
              : null),
      rpe: json['rpe'] is num
          ? (json['rpe'] as num).toDouble()
          : (json['rpe'] is String
              ? double.tryParse(json['rpe'] as String)
              : null),
      done: (json['done'] as bool?) ?? false,
    );
  }
}

abstract class WorkoutExecutionRepository {
  Future<List<ExerciseSetExecution>> getSets(
    String exerciseName,
    DateTime date,
    int totalSets,
  );

  Future<void> saveSet(
    String exerciseName,
    DateTime date,
    int setIndex,
    ExerciseSetExecution data,
    int totalSets,
  );
}

class SharedPrefsWorkoutExecutionRepository
    implements WorkoutExecutionRepository {
  final SharedPreferences _prefs;
  SharedPrefsWorkoutExecutionRepository(this._prefs);

  String _keyFor(String exerciseName, DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final safe = exerciseName.replaceAll(' ', '_');
    return 'workout_exec_${safe}_$y-$m-$day';
  }

  @override
  Future<List<ExerciseSetExecution>> getSets(
    String exerciseName,
    DateTime date,
    int totalSets,
  ) async {
    final key = _keyFor(exerciseName, date);
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return List.generate(
        totalSets,
        (_) => const ExerciseSetExecution(
            reps: null, weight: null, rpe: null, done: false),
      );
    }
    try {
      final list = (json.decode(raw) as List<dynamic>).map((e) {
        return ExerciseSetExecution.fromJson(e as Map<String, dynamic>);
      }).toList();
      // Гарантируем размер totalSets
      if (list.length < totalSets) {
        final tail = List.generate(
          totalSets - list.length,
          (_) => const ExerciseSetExecution(
              reps: null, weight: null, rpe: null, done: false),
        );
        return [...list, ...tail];
      } else if (list.length > totalSets) {
        return list.sublist(0, totalSets);
      }
      return list;
    } catch (_) {
      return List.generate(
        totalSets,
        (_) => const ExerciseSetExecution(
            reps: null, weight: null, rpe: null, done: false),
      );
    }
  }

  @override
  Future<void> saveSet(
    String exerciseName,
    DateTime date,
    int setIndex,
    ExerciseSetExecution data,
    int totalSets,
  ) async {
    final key = _keyFor(exerciseName, date);
    final current = await getSets(exerciseName, date, totalSets);
    final index = setIndex.clamp(0, totalSets - 1);
    final updated = List<ExerciseSetExecution>.from(current);
    updated[index] = data.copyWith(done: true);
    final jsonString = json.encode(updated.map((e) => e.toJson()).toList());
    await _prefs.setString(key, jsonString);
  }
}

