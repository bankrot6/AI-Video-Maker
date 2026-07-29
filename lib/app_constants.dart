/// Файл с константами приложения
library;

/// Константы для лимитов использования
class UsageLimits {
  /// Максимальное количество использований в день для всех пользователей
  static const int maxTotalUsagesPerDay = 5;

  /// Максимальное количество бесплатных использований в день
  static const int maxFreeUsagesPerDay = 2;
}

/// Константы для анимаций
class AnimationPaths {
  /// Путь к анимации загрузки
  static const String loading = 'assets/animations/loading.json';

  /// Путь к анимации дороги
  static const String road = 'assets/animations/road.json';
}

/// Константы для UI
class UIConstants {
  /// Основной цвет приложения
  static const int primaryColorValue = 0xFF6A44E0;

  /// Радиус скругления углов
  static const double borderRadius = 12.0;

  /// Основной отступ в приложении
  static const double padding = 16.0;
}
