import 'package:equatable/equatable.dart';

/// Запись о приёме воды
class WaterEntryModel extends Equatable {
  final String id;
  final int volumeMl;
  final DateTime dateTime;

  const WaterEntryModel({
    required this.id,
    required this.volumeMl,
    required this.dateTime,
  });

  @override
  List<Object?> get props => [id, volumeMl, dateTime];

  factory WaterEntryModel.fromJson(Map<String, dynamic> json) {
    return WaterEntryModel(
      id: json['id'] as String,
      volumeMl: json['volumeMl'] as int,
      dateTime: DateTime.parse(json['dateTime'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'volumeMl': volumeMl,
      'dateTime': dateTime.toIso8601String(),
    };
  }
}
