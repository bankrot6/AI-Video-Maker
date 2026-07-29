import 'package:equatable/equatable.dart';

/// Модель записи изменения веса пользователя
class WeightEntryModel extends Equatable {
  /// Уникальный идентификатор записи
  final String id;

  /// Вес пользователя в килограммах
  final double weight;

  /// Дата и время, когда был зафиксирован вес
  final DateTime dateTime;

  /// Комментарий к замеру
  final String? comment;

  const WeightEntryModel({
    required this.id,
    required this.weight,
    required this.dateTime,
    this.comment,
  });

  @override
  List<Object?> get props => [id, weight, dateTime, comment];

  factory WeightEntryModel.fromJson(Map<String, dynamic> json) {
    return WeightEntryModel(
      id: json['id'] as String,
      weight: (json['weight'] as num).toDouble(),
      dateTime: DateTime.parse(json['dateTime'] as String),
      comment: json['comment'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'weight': weight,
      'dateTime': dateTime.toIso8601String(),
      if (comment != null) 'comment': comment,
    };
  }
}
