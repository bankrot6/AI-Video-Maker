import 'package:flutter/material.dart';

/// Класс для хранения настроек темы скриншотов
/// Этот класс позволяет настроить внешний вид скриншотов
class ScreenshotTheme {
  /// Цвет фона для скриншотов
  final Color backgroundColor;

  /// Создает новый экземпляр настроек темы скриншотов
  /// По умолчанию используется белый цвет фона
  const ScreenshotTheme({
    this.backgroundColor = Colors.white,
  });
}
