import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Виджет для создания контейнера, который будет использоваться для скриншота
/// Оборачивает дочерний виджет в RepaintBoundary с заданным ключом
/// Добавлен белый фон для решения проблемы с черным фоном между виджетами на скриншотах
class ScreenshotContainer extends ConsumerWidget {
  final Widget child;
  final GlobalKey boundaryKey;

  const ScreenshotContainer({
    super.key,
    required this.child,
    required this.boundaryKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Используем прозрачный фон для обычного отображения
    // Белый фон будет добавлен только при создании скриншота в ScreenshotService

    return RepaintBoundary(
      key: boundaryKey,
      child: Container(
        color: Colors.transparent,
        child: child,
      ),
    );
  }
}
