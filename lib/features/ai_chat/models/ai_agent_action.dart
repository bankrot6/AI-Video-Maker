import 'package:equatable/equatable.dart';
import '../../../models/workout_plan_model.dart';

/// Типы действий, которые может предложить AI-агент
enum AiAgentActionType {
  addExercise,      // Добавить упражнение в тренировку
  replaceExercise,  // Заменить упражнение
  modifyExercise,   // Изменить параметры упражнения
  createWorkoutPlan, // Создать план тренировок
}

/// Базовый класс для действий AI-агента
abstract class AiAgentAction extends Equatable {
  final String id;
  final AiAgentActionType type;
  final String description;

  const AiAgentAction({
    required this.id,
    required this.type,
    required this.description,
  });

  @override
  List<Object?> get props => [id, type, description];
}

/// Действие: добавить упражнение в тренировку
class AddExerciseAction extends AiAgentAction {
  final ExerciseItem exercise;
  final int? targetDayIndex; // Индекс дня (null = текущий день)
  final String? targetDayTitle; // Название дня

  const AddExerciseAction({
    required super.id,
    required super.description,
    required this.exercise,
    this.targetDayIndex,
    this.targetDayTitle,
  }) : super(type: AiAgentActionType.addExercise);

  @override
  List<Object?> get props => [...super.props, exercise, targetDayIndex, targetDayTitle];

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'addExercise',
    'description': description,
    'exercise': exercise.toJson(),
    'targetDayIndex': targetDayIndex,
    'targetDayTitle': targetDayTitle,
  };

  factory AddExerciseAction.fromJson(Map<String, dynamic> json) {
    return AddExerciseAction(
      id: json['id'] as String,
      description: json['description'] as String,
      exercise: ExerciseItem.fromJson(json['exercise'] as Map<String, dynamic>),
      targetDayIndex: json['targetDayIndex'] as int?,
      targetDayTitle: json['targetDayTitle'] as String?,
    );
  }
}

/// Действие: заменить упражнение
class ReplaceExerciseAction extends AiAgentAction {
  final String originalExerciseName;
  final ExerciseItem newExercise;
  final int? targetDayIndex;

  const ReplaceExerciseAction({
    required super.id,
    required super.description,
    required this.originalExerciseName,
    required this.newExercise,
    this.targetDayIndex,
  }) : super(type: AiAgentActionType.replaceExercise);

  @override
  List<Object?> get props => [...super.props, originalExerciseName, newExercise, targetDayIndex];
}

/// Действие: изменить параметры упражнения
class ModifyExerciseAction extends AiAgentAction {
  final String exerciseName;
  final int? newSets;
  final int? newReps;
  final double? newWeight;
  final int? targetDayIndex;

  const ModifyExerciseAction({
    required super.id,
    required super.description,
    required this.exerciseName,
    this.newSets,
    this.newReps,
    this.newWeight,
    this.targetDayIndex,
  }) : super(type: AiAgentActionType.modifyExercise);

  @override
  List<Object?> get props => [...super.props, exerciseName, newSets, newReps, newWeight, targetDayIndex];
}

/// Предложение упражнения от AI
class ExerciseSuggestion extends Equatable {
  final String id;
  final ExerciseItem exercise;
  final String reasoning; // Почему AI предлагает это упражнение
  final int? targetDayIndex;
  final String? targetDayTitle;

  const ExerciseSuggestion({
    required this.id,
    required this.exercise,
    required this.reasoning,
    this.targetDayIndex,
    this.targetDayTitle,
  });

  @override
  List<Object?> get props => [id, exercise, reasoning, targetDayIndex, targetDayTitle];

  Map<String, dynamic> toJson() => {
    'id': id,
    'exercise': exercise.toJson(),
    'reasoning': reasoning,
    'targetDayIndex': targetDayIndex,
    'targetDayTitle': targetDayTitle,
  };

  factory ExerciseSuggestion.fromJson(Map<String, dynamic> json) {
    return ExerciseSuggestion(
      id: json['id'] as String,
      exercise: ExerciseItem.fromJson(json['exercise'] as Map<String, dynamic>),
      reasoning: json['reasoning'] as String? ?? '',
      targetDayIndex: json['targetDayIndex'] as int?,
      targetDayTitle: json['targetDayTitle'] as String?,
    );
  }
}











