import 'package:flutter/foundation.dart';

/// Модель для хранения информации о лимитах использования функций приложения
class UsageLimitModel {
  /// Дата, для которой сохранены данные об использовании
  final DateTime date;

  /// Общее количество использований за день для всех пользователей
  final int totalUsagesCount;

  /// Количество использований для бесплатных пользователей
  final int freeUsagesCount;

  /// Максимально допустимое количество использований в день для всех пользователей
  final int maxTotalUsages;

  /// Максимально допустимое количество использований в день для бесплатных пользователей
  final int maxFreeUsages;

  /// Проверка, исчерпан ли лимит для всех пользователей
  bool get isTotalLimitReached => totalUsagesCount >= maxTotalUsages;

  /// Проверка, исчерпан ли лимит для бесплатных пользователей
  bool get isFreeUserLimitReached => freeUsagesCount >= maxFreeUsages;

  /// Количество оставшихся использований для всех пользователей
  int get remainingTotalUsages => maxTotalUsages - totalUsagesCount;

  /// Количество оставшихся использований для бесплатных пользователей
  int get remainingFreeUsages => maxFreeUsages - freeUsagesCount;

  const UsageLimitModel({
    required this.date,
    required this.totalUsagesCount,
    required this.freeUsagesCount,
    required this.maxTotalUsages,
    required this.maxFreeUsages,
  });

  /// Создание новой модели ограничений с нулевым количеством использований
  factory UsageLimitModel.createNew() {
    return UsageLimitModel(
      date: DateTime.now(),
      totalUsagesCount: 0,
      freeUsagesCount: 0,
      maxTotalUsages:
          10, // Ограничение для всех пользователей - 10 использований в день
      maxFreeUsages:
          2, // Ограничение для бесплатных пользователей - 2 использования в день
    );
  }

  /// Создает копию модели с обновленными параметрами
  UsageLimitModel copyWith({
    DateTime? date,
    int? totalUsagesCount,
    int? freeUsagesCount,
    int? maxTotalUsages,
    int? maxFreeUsages,
  }) {
    return UsageLimitModel(
      date: date ?? this.date,
      totalUsagesCount: totalUsagesCount ?? this.totalUsagesCount,
      freeUsagesCount: freeUsagesCount ?? this.freeUsagesCount,
      maxTotalUsages: maxTotalUsages ?? this.maxTotalUsages,
      maxFreeUsages: maxFreeUsages ?? this.maxFreeUsages,
    );
  }
}
