// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppSettingsModel _$AppSettingsModelFromJson(Map<String, dynamic> json) =>
    AppSettingsModel(
      useGoogleVision: json['useGoogleVision'] as bool? ?? true,
      loadDishImages: json['loadDishImages'] as bool? ?? true,
      enableRenewalReminders: json['enableRenewalReminders'] as bool? ?? true,
    );

Map<String, dynamic> _$AppSettingsModelToJson(AppSettingsModel instance) =>
    <String, dynamic>{
      'useGoogleVision': instance.useGoogleVision,
      'loadDishImages': instance.loadDishImages,
      'enableRenewalReminders': instance.enableRenewalReminders,
    };
