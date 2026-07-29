import 'package:equatable/equatable.dart';

/// Модель записи замеров тела пользователя
class MeasurementEntryModel extends Equatable {
  final String id;
  final DateTime dateTime;

  // Обхваты в сантиметрах
  final double? chest; // грудь
  final double? waist; // талия
  final double? hips; // бёдра
  final double? leg; // нога (бедро/икра по договорённости)
  final double? arm; // рука
  final double? shoulders; // плечи
  final double? abdomen; // живот
  final double? bodyFat; // процент жира
  final double? neck; // шея
  final double? forearm; // предплечье
  final double? calf; // голень
  final double? thigh; // бедро
  final String? comment; // комментарий

  const MeasurementEntryModel({
    required this.id,
    required this.dateTime,
    this.chest,
    this.waist,
    this.hips,
    this.leg,
    this.arm,
    this.shoulders,
    this.abdomen,
    this.bodyFat,
    this.neck,
    this.forearm,
    this.calf,
    this.thigh,
    this.comment,
  });

  MeasurementEntryModel copyWith({
    String? id,
    DateTime? dateTime,
    double? chest,
    double? waist,
    double? hips,
    double? leg,
    double? arm,
    double? shoulders,
    double? abdomen,
    double? bodyFat,
    double? neck,
    double? forearm,
    double? calf,
    double? thigh,
    String? comment,
  }) {
    return MeasurementEntryModel(
      id: id ?? this.id,
      dateTime: dateTime ?? this.dateTime,
      chest: chest ?? this.chest,
      waist: waist ?? this.waist,
      hips: hips ?? this.hips,
      leg: leg ?? this.leg,
      arm: arm ?? this.arm,
      shoulders: shoulders ?? this.shoulders,
      abdomen: abdomen ?? this.abdomen,
      bodyFat: bodyFat ?? this.bodyFat,
      neck: neck ?? this.neck,
      forearm: forearm ?? this.forearm,
      calf: calf ?? this.calf,
      thigh: thigh ?? this.thigh,
      comment: comment ?? this.comment,
    );
  }

  @override
  List<Object?> get props => [
        id,
        dateTime,
        chest,
        waist,
        hips,
        leg,
        arm,
        shoulders,
        abdomen,
        bodyFat,
        neck,
        forearm,
        calf,
        thigh,
        comment,
      ];

  factory MeasurementEntryModel.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic v) => v == null ? null : (v as num).toDouble();
    return MeasurementEntryModel(
      id: json['id'] as String,
      dateTime: DateTime.parse(json['dateTime'] as String),
      chest: toDouble(json['chest']),
      waist: toDouble(json['waist']),
      hips: toDouble(json['hips']),
      leg: toDouble(json['leg']),
      arm: toDouble(json['arm']),
      shoulders: toDouble(json['shoulders']),
      abdomen: toDouble(json['abdomen']),
      bodyFat: toDouble(json['bodyFat']),
      neck: toDouble(json['neck']),
      forearm: toDouble(json['forearm']),
      calf: toDouble(json['calf']),
      thigh: toDouble(json['thigh']),
      comment: json['comment'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dateTime': dateTime.toIso8601String(),
      if (chest != null) 'chest': chest,
      if (waist != null) 'waist': waist,
      if (hips != null) 'hips': hips,
      if (leg != null) 'leg': leg,
      if (arm != null) 'arm': arm,
      if (shoulders != null) 'shoulders': shoulders,
      if (abdomen != null) 'abdomen': abdomen,
      if (bodyFat != null) 'bodyFat': bodyFat,
      if (neck != null) 'neck': neck,
      if (forearm != null) 'forearm': forearm,
      if (calf != null) 'calf': calf,
      if (thigh != null) 'thigh': thigh,
      if (comment != null) 'comment': comment,
    };
  }
}
