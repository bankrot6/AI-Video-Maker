import 'package:flutter/material.dart';
import '../services/performance/device_performance_service.dart';
import 'liquid_glass_card.dart';

/// Адаптивная карточка упражнения, которая автоматически выбирает
/// оптимальную версию в зависимости от производительности устройства
class AdaptiveExerciseCard extends StatelessWidget {
  final String title;
  final String sets;
  final String reps;
  final String weight;
  final VoidCallback? onTap;

  const AdaptiveExerciseCard({
    super.key,
    required this.title,
    required this.sets,
    required this.reps,
    required this.weight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PerformanceLevel>(
      future: DevicePerformanceService.instance.getPerformanceLevel(),
      builder: (context, snapshot) {
        // Пока определяем производительность, показываем облегченную версию
        if (!snapshot.hasData) {
          return LiquidGlassExerciseCardLight(
            title: title,
            sets: sets,
            reps: reps,
            weight: weight,
            onTap: onTap,
          );
        }

        final level = snapshot.data!;

        switch (level) {
          case PerformanceLevel.high:
            // Высокая производительность - используем полный эффект
            // (уже оптимизированный с thickness: 5)
            return LiquidGlassExerciseCardLight(
              title: title,
              sets: sets,
              reps: reps,
              weight: weight,
              onTap: onTap,
            );

          case PerformanceLevel.medium:
            // Средняя производительность - используем облегченную версию
            // (с thickness: 3)
            return LiquidGlassExerciseCardLight(
              title: title,
              sets: sets,
              reps: reps,
              weight: weight,
              onTap: onTap,
            );

          case PerformanceLevel.low:
            // Низкая производительность - используем версию без эффекта
            return LiquidGlassExerciseCardUltraLight(
              title: title,
              sets: sets,
              reps: reps,
              weight: weight,
              onTap: onTap,
            );
        }
      },
    );
  }
}

/// Провайдер для кэширования уровня производительности
/// Позволяет избежать повторных вычислений
class PerformanceLevelProvider extends InheritedWidget {
  final PerformanceLevel level;

  const PerformanceLevelProvider({
    super.key,
    required this.level,
    required super.child,
  });

  static PerformanceLevel? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PerformanceLevelProvider>()
        ?.level;
  }

  @override
  bool updateShouldNotify(PerformanceLevelProvider oldWidget) {
    return level != oldWidget.level;
  }
}

/// Оптимизированная версия адаптивной карточки с использованием провайдера
/// Использует кэшированное значение производительности из дерева виджетов
class AdaptiveExerciseCardOptimized extends StatelessWidget {
  final String title;
  final String sets;
  final String reps;
  final String weight;
  final VoidCallback? onTap;

  const AdaptiveExerciseCardOptimized({
    super.key,
    required this.title,
    required this.sets,
    required this.reps,
    required this.weight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Пытаемся получить кэшированное значение из провайдера
    final cachedLevel = PerformanceLevelProvider.of(context);

    if (cachedLevel != null) {
      return _buildCardForLevel(cachedLevel);
    }

    // Если провайдера нет, используем обычную версию с FutureBuilder
    return FutureBuilder<PerformanceLevel>(
      future: DevicePerformanceService.instance.getPerformanceLevel(),
      builder: (context, snapshot) {
        final level = snapshot.data ?? PerformanceLevel.medium;
        return _buildCardForLevel(level);
      },
    );
  }

  Widget _buildCardForLevel(PerformanceLevel level) {
    switch (level) {
      case PerformanceLevel.high:
      case PerformanceLevel.medium:
        return LiquidGlassExerciseCardLight(
          title: title,
          sets: sets,
          reps: reps,
          weight: weight,
          onTap: onTap,
        );

      case PerformanceLevel.low:
        return LiquidGlassExerciseCardUltraLight(
          title: title,
          sets: sets,
          reps: reps,
          weight: weight,
          onTap: onTap,
        );
    }
  }
}
