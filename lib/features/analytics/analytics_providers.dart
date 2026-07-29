import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/meal_model.dart';
import '../home/home_providers.dart';
import '../../models/weight_entry_model.dart';
import '../../models/measurement_entry_model.dart';
import '../home/home_providers.dart' as home;

/// Класс кэша для аналитических данных
class AnalyticsCache {
  final Map<String, MealNutrientsModel> _dailyNutrientsCache = {};
  List<MealNutrientsModel> _weeklyNutrients = [];
  DateTime? _weekStartDate;

  /// Получение дневных данных из кэша
  MealNutrientsModel? getDailyNutrients(DateTime date) {
    final key = '${date.year}-${date.month}-${date.day}';
    return _dailyNutrientsCache[key];
  }

  /// Сохранение дневных данных в кэш
  void cacheDailyNutrients(DateTime date, MealNutrientsModel nutrients) {
    final key = '${date.year}-${date.month}-${date.day}';
    _dailyNutrientsCache[key] = nutrients;
  }

  /// Проверка, есть ли недельные данные в кэше
  bool hasWeeklyData(DateTime weekStart) {
    if (_weekStartDate == null) return false;
    return _isSameDate(_weekStartDate!, weekStart) &&
        _weeklyNutrients.isNotEmpty;
  }

  /// Получение недельных данных из кэша
  List<MealNutrientsModel> getWeeklyNutrients() {
    return _weeklyNutrients;
  }

  /// Сохранение недельных данных в кэш
  void cacheWeeklyNutrients(
      DateTime weekStart, List<MealNutrientsModel> nutrients) {
    _weekStartDate = weekStart;
    _weeklyNutrients = nutrients;
  }

  /// Вспомогательный метод для сравнения дат
  bool _isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }
}

/// Провайдер кэша для аналитических данных
final analyticsCacheProvider = Provider<AnalyticsCache>((ref) {
  return AnalyticsCache();
});

/// Провайдер для получения данных о питательной ценности за неделю
final weeklyNutrientsProvider =
    FutureProvider<List<MealNutrientsModel>>((ref) async {
  final mealRepository = ref.read(mealRepositoryProvider);
  final selectedDate = ref.read(selectedDateProvider);

  // Вычисляем первый день недели
  final weekday = selectedDate.weekday;
  final startOfWeek = selectedDate.subtract(Duration(days: weekday - 1));

  print(
      'weeklyNutrientsProvider: запрашиваем данные за неделю с ${startOfWeek.toIso8601String().substring(0, 10)}');

  // Получаем данные за последние 7 дней
  final nutrients = <MealNutrientsModel>[];

  for (var i = 0; i < 7; i++) {
    final date = startOfWeek.add(Duration(days: i));
    print(
        'weeklyNutrientsProvider: получение данных за ${date.toIso8601String().substring(0, 10)}');

    // Всегда запрашиваем свежие данные из репозитория для избежания расхождений
    final dailyNutrients = await mealRepository.getDailyNutrientsTotal(date);

    print(
        'weeklyNutrientsProvider: получены данные: калорий ${dailyNutrients.calories}, дата: ${dailyNutrients.dateTime?.toIso8601String() ?? "отсутствует"}');

    nutrients.add(dailyNutrients);
  }

  // Выводим список всех полученных данных для отладки
  print('weeklyNutrientsProvider: итоговый список данных:');
  for (var i = 0; i < nutrients.length; i++) {
    final date = startOfWeek.add(Duration(days: i));
    final nutrient = nutrients[i];
    print(
        'День ${date.toIso8601String().substring(0, 10)}: калорий ${nutrient.calories}, БЖУ: ${nutrient.proteins}/${nutrient.fats}/${nutrient.carbs}');
  }

  return nutrients;
});

/// Провайдер для всех данных веса пользователя
final weeklyWeightProvider =
    FutureProvider<List<WeightEntryModel>>((ref) async {
  final weightRepository = ref.read(weightRepositoryProvider);

  // Загружаем все записи веса
  final allEntries = await weightRepository.getAllEntries();
  allEntries.sort((a, b) => a.dateTime.compareTo(b.dateTime));

  // Фильтруем только записи с весом > 0
  final validEntries = allEntries.where((e) => e.weight > 0).toList();

  return validEntries;
});

/// Типы замеров тела
enum BodyMeasurementType {
  weight,
  bodyFat,
  neck,
  shoulders,
  chest,
  arm,
  forearm,
  waist,
  abdomen,
  hips,
  thigh,
  calf,
}

/// Провайдер выбранного типа замеров на экране аналитики
final selectedMeasurementTypeProvider =
    StateProvider<BodyMeasurementType>((ref) => BodyMeasurementType.weight);

double? _valueForType(MeasurementEntryModel e, BodyMeasurementType type) {
  switch (type) {
    case BodyMeasurementType.weight:
      return null;
    case BodyMeasurementType.bodyFat:
      return e.bodyFat;
    case BodyMeasurementType.neck:
      return e.neck;
    case BodyMeasurementType.shoulders:
      return e.shoulders;
    case BodyMeasurementType.chest:
      return e.chest;
    case BodyMeasurementType.arm:
      return e.arm;
    case BodyMeasurementType.forearm:
      return e.forearm;
    case BodyMeasurementType.waist:
      return e.waist;
    case BodyMeasurementType.abdomen:
      return e.abdomen;
    case BodyMeasurementType.hips:
      return e.hips;
    case BodyMeasurementType.thigh:
      return e.thigh;
    case BodyMeasurementType.calf:
      return e.calf;
  }
}

/// Провайдер для всех данных замеров (в виде совместимом с WeightLineChart)
final weeklyMeasurementsProvider =
    FutureProvider.family<List<WeightEntryModel>, BodyMeasurementType>(
        (ref, type) async {
  final measurementRepository = ref.read(home.measurementRepositoryProvider);

  // Все записи замеров
  final allEntries = await measurementRepository.getAllEntries();
  allEntries.sort((a, b) => a.dateTime.compareTo(b.dateTime));

  // Фильтруем записи, которые имеют значение для выбранного типа
  final filteredEntries = allEntries.where((entry) {
    final value = _valueForType(entry, type);
    return value != null && value > 0;
  }).toList();

  // Преобразуем в WeightEntryModel для графика
  final result = <WeightEntryModel>[];
  for (var entry in filteredEntries) {
    final value = _valueForType(entry, type);
    if (value != null && value > 0) {
      result.add(WeightEntryModel(
        id: entry.id,
        weight: value,
        dateTime: entry.dateTime,
      ));
    }
  }

  return result;
});

/// Провайдер для выбранной даты на экране аналитики
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// Провайдер для получения данных о питательной ценности за выбранную дату
final dailyNutrientsForDateProvider =
    FutureProvider.family<MealNutrientsModel, DateTime>((ref, date) async {
  final mealRepository = ref.read(mealRepositoryProvider);

  print(
      'dailyNutrientsForDateProvider: запрашиваем данные за ${date.toIso8601String().substring(0, 10)}');

  // Всегда запрашиваем свежие данные для избежания расхождений с главным экраном
  final dailyNutrients = await mealRepository.getDailyNutrientsTotal(date);

  print(
      'dailyNutrientsForDateProvider: получены данные: калорий ${dailyNutrients.calories}, БЖУ: ${dailyNutrients.proteins}/${dailyNutrients.fats}/${dailyNutrients.carbs}');

  return dailyNutrients;
});
