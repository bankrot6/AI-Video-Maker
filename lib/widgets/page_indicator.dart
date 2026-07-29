import 'package:flutter/material.dart';
import 'dart:ui';

/// iOS-стиль индикатор страниц с кружочками и полупрозрачным фоном
class PageIndicator extends StatelessWidget {
  /// Общее количество страниц
  final int pageCount;

  /// Текущая активная страница (0-based)
  final int currentPage;

  /// Цвет активной точки
  final Color activeColor;

  /// Цвет неактивной точки
  final Color inactiveColor;

  /// Размер точки
  final double dotSize;

  /// Расстояние между точками
  final double spacing;

  const PageIndicator({
    super.key,
    required this.pageCount,
    required this.currentPage,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x80FFFFFF), // Полупрозрачный белый
    this.dotSize = 10.0,
    this.spacing = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(pageCount, (index) {
          final isActive = index == currentPage;
          return Container(
            margin: EdgeInsets.symmetric(horizontal: spacing / 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
          );
        }),
      ),
    );
  }
}
