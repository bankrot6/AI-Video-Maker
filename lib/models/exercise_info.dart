import 'package:equatable/equatable.dart';

/// Модель с детальной информацией об упражнении
class ExerciseInfo extends Equatable {
  /// Название упражнения
  final String name;

  /// Описание техники выполнения упражнения
  final String description;

  /// Ключевые моменты, на что обратить внимание
  final String keyPoints;

  /// Распространенные ошибки при выполнении
  final String commonMistakes;

  /// Целевые группы мышц
  final String targetMuscles;

  /// Путь к изображению упражнения
  final String? imagePath;

  /// Сообщение об ошибке (если что-то пошло не так)
  final String? error;

  const ExerciseInfo({
    required this.name,
    required this.description,
    required this.keyPoints,
    required this.commonMistakes,
    required this.targetMuscles,
    this.imagePath,
    this.error,
  });

  /// Создает пустую модель ExerciseInfo
  factory ExerciseInfo.empty() {
    return const ExerciseInfo(
      name: '',
      description: '',
      keyPoints: '',
      commonMistakes: '',
      targetMuscles: '',
      imagePath: null,
      error: null,
    );
  }

  /// Создает копию модели с возможностью изменения отдельных полей
  ExerciseInfo copyWith({
    String? name,
    String? description,
    String? keyPoints,
    String? commonMistakes,
    String? targetMuscles,
    String? imagePath,
    String? error,
  }) {
    return ExerciseInfo(
      name: name ?? this.name,
      description: description ?? this.description,
      keyPoints: keyPoints ?? this.keyPoints,
      commonMistakes: commonMistakes ?? this.commonMistakes,
      targetMuscles: targetMuscles ?? this.targetMuscles,
      imagePath: imagePath ?? this.imagePath,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
        name,
        description,
        keyPoints,
        commonMistakes,
        targetMuscles,
        imagePath,
        error,
      ];

  /// Создает модель из JSON
  factory ExerciseInfo.fromJson(Map<String, dynamic> json) {
    return ExerciseInfo(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      keyPoints: json['keyPoints'] as String? ?? '',
      commonMistakes: json['commonMistakes'] as String? ?? '',
      targetMuscles: json['targetMuscles'] as String? ?? '',
      imagePath: json['imagePath'] as String?,
      error: json['error'] as String?,
    );
  }

  /// Преобразует модель в JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'keyPoints': keyPoints,
      'commonMistakes': commonMistakes,
      'targetMuscles': targetMuscles,
      'imagePath': imagePath,
      'error': error,
    };
  }
}





