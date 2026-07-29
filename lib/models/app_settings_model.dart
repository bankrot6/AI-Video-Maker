import 'package:json_annotation/json_annotation.dart';

part 'app_settings_model.g.dart';

@JsonSerializable()
class AppSettingsModel {
  /// Флаг, определяющий использование Google Cloud Vision для предварительного анализа изображений
  final bool useGoogleVision;

  /// Флаг, определяющий загрузку изображений блюд из интернета
  final bool loadDishImages;

  /// Флаг, определяющий отправку напоминаний о продлении подписки
  final bool enableRenewalReminders;

  /// Конструктор модели настроек
  const AppSettingsModel({
    this.useGoogleVision = true,
    this.loadDishImages = true,
    this.enableRenewalReminders = true,
  });

  /// Создает пустую модель настроек с значениями по умолчанию
  factory AppSettingsModel.defaults() => const AppSettingsModel();

  /// Создает копию модели с возможностью обновления полей
  AppSettingsModel copyWith({
    bool? useGoogleVision,
    bool? loadDishImages,
    bool? enableRenewalReminders,
  }) {
    return AppSettingsModel(
      useGoogleVision: useGoogleVision ?? this.useGoogleVision,
      loadDishImages: loadDishImages ?? this.loadDishImages,
      enableRenewalReminders:
          enableRenewalReminders ?? this.enableRenewalReminders,
    );
  }

  /// Конвертирует модель в JSON
  Map<String, dynamic> toJson() => _$AppSettingsModelToJson(this);

  /// Создает модель из JSON
  factory AppSettingsModel.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsModelFromJson(json);
}
