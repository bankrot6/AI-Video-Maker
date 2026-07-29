import 'dart:ui' as ui;

/// Система измерения роста и веса
enum MeasurementSystem {
  /// Метрическая система (см, кг)
  metric,

  /// Имперская система (футы/дюймы, фунты)
  imperial,
}

/// Утилиты для работы с системами измерения
class MeasurementUtils {
  /// Страны, использующие имперскую систему
  static const Set<String> _imperialCountries = {
    'US', // США
    'LR', // Либерия
    'MM', // Мьянма
  };

  /// Определяет систему измерения по умолчанию на основе локали устройства
  static MeasurementSystem getDefaultMeasurementSystem() {
    try {
      final deviceLocale = ui.PlatformDispatcher.instance.locale;
      final countryCode = deviceLocale.countryCode?.toUpperCase();

      if (countryCode != null && _imperialCountries.contains(countryCode)) {
        return MeasurementSystem.imperial;
      }

      return MeasurementSystem.metric;
    } catch (e) {
      // Возвращаем метрическую систему по умолчанию в случае ошибки
      return MeasurementSystem.metric;
    }
  }

  /// Конвертирует сантиметры в футы и дюймы
  static HeightImperial cmToFeetInches(double cm) {
    final totalInches = cm / 2.54;
    final feet = totalInches ~/ 12;
    final inches = (totalInches % 12).round();
    return HeightImperial(feet: feet, inches: inches);
  }

  /// Конвертирует футы и дюймы в сантиметры
  static double feetInchesToCm(int feet, int inches) {
    final totalInches = feet * 12 + inches;
    return totalInches * 2.54;
  }

  /// Конвертирует килограммы в фунты
  static double kgToLbs(double kg) {
    return kg * 2.20462;
  }

  /// Конвертирует фунты в килограммы
  static double lbsToKg(double lbs) {
    return lbs / 2.20462;
  }

  /// Получает диапазон роста для picker'а в зависимости от системы
  static HeightRange getHeightRange(MeasurementSystem system) {
    switch (system) {
      case MeasurementSystem.metric:
        return HeightRange(min: 140, max: 220); // см
      case MeasurementSystem.imperial:
        return HeightRange(min: 4, max: 7); // футы (от 4'7" до 7'2")
    }
  }

  /// Получает диапазон веса для picker'а в зависимости от системы
  static WeightRange getWeightRange(MeasurementSystem system) {
    switch (system) {
      case MeasurementSystem.metric:
        return WeightRange(min: 40, max: 200); // кг
      case MeasurementSystem.imperial:
        return WeightRange(min: 88, max: 441); // фунты (40-200 кг)
    }
  }

  /// Форматирует рост для отображения
  static String formatHeight(double heightCm, MeasurementSystem system) {
    switch (system) {
      case MeasurementSystem.metric:
        return '${heightCm.round()} см';
      case MeasurementSystem.imperial:
        final imperial = cmToFeetInches(heightCm);
        return '${imperial.feet}\'${imperial.inches}"';
    }
  }

  /// Форматирует вес для отображения
  static String formatWeight(double weightKg, MeasurementSystem system) {
    switch (system) {
      case MeasurementSystem.metric:
        return '${weightKg.round()} кг';
      case MeasurementSystem.imperial:
        final lbs = kgToLbs(weightKg);
        return '${lbs.round()} lbs';
    }
  }
}

/// Представление роста в имперской системе
class HeightImperial {
  final int feet;
  final int inches;

  HeightImperial({required this.feet, required this.inches});

  @override
  String toString() => '$feet\'$inches"';
}

/// Диапазон значений роста
class HeightRange {
  final int min;
  final int max;

  HeightRange({required this.min, required this.max});
}

/// Диапазон значений веса
class WeightRange {
  final int min;
  final int max;

  WeightRange({required this.min, required this.max});
}
