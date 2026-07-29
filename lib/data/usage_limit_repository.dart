import 'package:shared_preferences/shared_preferences.dart';
import '../models/usage_limit_model.dart';
import 'dart:convert';
import 'dart:developer' as developer;

/// Репозиторий для работы с ограничениями использования функций приложения
/// Реализует паттерн Repository, для абстрагирования доступа к данным
class UsageLimitRepository {
  static const String _usageLimitKey = 'usage_limit_data';
  final SharedPreferences _prefs;

  /// Конструктор, принимающий экземпляр SharedPreferences
  UsageLimitRepository(this._prefs) {
    // При инициализации ничего не делаем - любые сбросы должны быть явными
  }

  /// Получение данных об использовании на текущий день
  /// Если данные не найдены или относятся к другому дню, создает новые
  Future<UsageLimitModel> getCurrentDayUsage() async {
    final jsonString = _prefs.getString(_usageLimitKey);
    final today = _getDateWithoutTime(DateTime.now());

    if (jsonString == null) {
      // Если данных нет, создаем новую модель с нулевыми значениями
      final newUsage = UsageLimitModel.createNew();
      await saveUsageLimit(newUsage);
      developer.log('Создана новая модель лимитов использования (нет данных)',
          name: 'UsageLimitRepository');
      return newUsage;
    }

    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final storedUsage = _usageLimitFromJson(json);

      // Проверяем, относятся ли данные к текущему дню
      final storedDate = _getDateWithoutTime(storedUsage.date);
      if (storedDate.isAtSameMomentAs(today)) {
        developer.log('Использованы сохраненные данные лимитов на сегодня',
            name: 'UsageLimitRepository');
        return storedUsage;
      } else {
        // Если данные от другого дня, создаем новую модель
        final newUsage = UsageLimitModel.createNew();
        await saveUsageLimit(newUsage);
        developer.log(
            'Создана новая модель лимитов (данные от другого дня: ${storedDate.toString()} vs ${today.toString()})',
            name: 'UsageLimitRepository');
        return newUsage;
      }
    } catch (e) {
      // В случае ошибки декодирования, создаем новую модель
      final newUsage = UsageLimitModel.createNew();
      await saveUsageLimit(newUsage);
      developer.log('Создана новая модель лимитов (ошибка декодирования: $e)',
          name: 'UsageLimitRepository');
      return newUsage;
    }
  }

  /// Сохранение данных об использовании
  Future<void> saveUsageLimit(UsageLimitModel usageLimit) async {
    final json = _usageLimitToJson(usageLimit);
    await _prefs.setString(_usageLimitKey, jsonEncode(json));
  }

  /// Сброс лимитов использования (для тестирования)
  Future<UsageLimitModel> resetUsageLimits() async {
    final newUsage = UsageLimitModel.createNew();
    await saveUsageLimit(newUsage);
    developer.log(
        'Счетчики использований сброшены. Новые лимиты: '
        'макс. для всех=${newUsage.maxTotalUsages}, '
        'макс. для бесплатных=${newUsage.maxFreeUsages}',
        name: 'UsageLimitRepository');
    return newUsage;
  }

  /// Увеличение счетчика использований для всех пользователей
  Future<UsageLimitModel> incrementTotalUsage() async {
    final currentUsage = await getCurrentDayUsage();

    final updatedUsage = currentUsage.copyWith(
      totalUsagesCount: currentUsage.totalUsagesCount + 1,
    );

    await saveUsageLimit(updatedUsage);
    developer.log(
        'Увеличен счетчик для платных пользователей: ${updatedUsage.totalUsagesCount}/${updatedUsage.maxTotalUsages}',
        name: 'UsageLimitRepository');
    return updatedUsage;
  }

  /// Увеличение счетчика использований для бесплатных пользователей
  Future<UsageLimitModel> incrementFreeUsage() async {
    final currentUsage = await getCurrentDayUsage();

    final updatedUsage = currentUsage.copyWith(
      totalUsagesCount: currentUsage.totalUsagesCount + 1,
      freeUsagesCount: currentUsage.freeUsagesCount + 1,
    );

    await saveUsageLimit(updatedUsage);
    developer.log(
        'Увеличен счетчик для бесплатных пользователей: ${updatedUsage.freeUsagesCount}/${updatedUsage.maxFreeUsages}',
        name: 'UsageLimitRepository');
    return updatedUsage;
  }

  /// Проверка, не исчерпан ли лимит использований для всех пользователей
  Future<bool> isTotalLimitReached() async {
    final usage = await getCurrentDayUsage();
    return usage.isTotalLimitReached;
  }

  /// Проверка, не исчерпан ли лимит использований для бесплатных пользователей
  Future<bool> isFreeUserLimitReached() async {
    final usage = await getCurrentDayUsage();
    return usage.isFreeUserLimitReached;
  }

  /// Получение количества оставшихся использований для всех пользователей
  Future<int> getRemainingTotalUsages() async {
    final usage = await getCurrentDayUsage();
    return usage.remainingTotalUsages;
  }

  /// Получение количества оставшихся использований для бесплатных пользователей
  Future<int> getRemainingFreeUsages() async {
    final usage = await getCurrentDayUsage();
    return usage.remainingFreeUsages;
  }

  /// Сериализация модели ограничений в Map
  Map<String, dynamic> _usageLimitToJson(UsageLimitModel usageLimit) {
    return {
      'date': usageLimit.date.millisecondsSinceEpoch,
      'totalUsagesCount': usageLimit.totalUsagesCount,
      'freeUsagesCount': usageLimit.freeUsagesCount,
      'maxTotalUsages': usageLimit.maxTotalUsages,
      'maxFreeUsages': usageLimit.maxFreeUsages,
    };
  }

  /// Десериализация модели ограничений из Map
  UsageLimitModel _usageLimitFromJson(Map<String, dynamic> json) {
    return UsageLimitModel(
      date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
      totalUsagesCount: json['totalUsagesCount'] as int,
      freeUsagesCount: json['freeUsagesCount'] as int,
      maxTotalUsages: json['maxTotalUsages'] as int,
      maxFreeUsages: json['maxFreeUsages'] as int,
    );
  }

  /// Получение даты без времени для корректного сравнения дней
  DateTime _getDateWithoutTime(DateTime dateTime) {
    return DateTime(dateTime.year, dateTime.month, dateTime.day);
  }

  /// Ключ для хранения даты последнего сброса лимитов
  static const String _lastResetDateKey = 'last_reset_date';

  /// Получение строкового представления даты последнего сброса лимитов
  Future<String?> getLastResetDateString() async {
    return _prefs.getString(_lastResetDateKey);
  }

  /// Сохранение строкового представления даты последнего сброса лимитов
  Future<void> saveLastResetDateString(String dateString) async {
    await _prefs.setString(_lastResetDateKey, dateString);
  }
}
