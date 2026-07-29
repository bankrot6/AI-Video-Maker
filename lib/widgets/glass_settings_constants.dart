import 'package:flutter/material.dart';
import 'liquid_glass_stub.dart';

/// Константы для оптимизированных настроек эффекта жидкого стекла
/// Все параметры агрессивно снижены для достижения 2,000-3,000 GPU операций/кадр
///
/// Цель оптимизации: максимальная производительность при сохранении визуальной привлекательности
class GlassSettingsConstants {
  GlassSettingsConstants._(); // Приватный конструктор

  /// УЛЬТРА оптимизированные настройки для навигации
  /// Использование: нижняя навигация, важные UI элементы
  /// GPU нагрузка: ~300-500 операций на элемент
  static const LiquidGlassSettings ultraOptimized = LiquidGlassSettings(
    thickness: 3,
    glassColor: Color(0x33FFFFFF), // 20% прозрачность
    lightIntensity: 1.0,
    ambientStrength: 0.25,
    saturation: 1.0,
  );

  /// ЭКСТРЕМАЛЬНО оптимизированные настройки для карточек
  /// Использование: карточки упражнений, списки (много элементов)
  /// GPU нагрузка: ~200-300 операций на элемент
  static const LiquidGlassSettings extremeOptimized = LiquidGlassSettings(
    thickness: 2,
    glassColor: Color(0x30FFFFFF), // 18% прозрачность
    lightIntensity: 0.8,
    ambientStrength: 0.2,
    saturation: 0.95,
  );

  /// Дополнительный матовый пресет для списков
  /// Использование: карточки упражнений, когда требуется более матовый вид
  /// Балансирует матовость и производительность для 5-8 элементов на экране
  static const LiquidGlassSettings matteList = LiquidGlassSettings(
    thickness: 3,
    glassColor: Color(0x40FFFFFF), // ~25% белого тумана (матовее)
    lightIntensity: 0.9, // чуть меньше блика
    ambientStrength: 0.3, // больше рассеянного света
    saturation: 0.95,
  );

  /// Матовый чёрный пресет для небольших чипов (sets/reps/weight)
  static const LiquidGlassSettings blackMatteChip = LiquidGlassSettings(
    thickness: 3,
    glassColor: Color(0x33FFFFFF), // более светлое матовое стекло
    lightIntensity: 0.9,
    ambientStrength: 0.3,
    saturation: 0.95,
  );

  /// Минимальные настройки для декоративных элементов
  /// Использование: заголовки, бейджи, малозначимые элементы
  /// GPU нагрузка: ~150-200 операций на элемент
  static const LiquidGlassSettings minimal = LiquidGlassSettings(
    thickness: 2,
    glassColor: Color(0x28FFFFFF), // 15% прозрачность
    lightIntensity: 0.8,
    ambientStrength: 0.2,
    saturation: 0.95,
  );

  /// Настройки для темного фона
  /// Использование: элементы на темных экранах
  /// GPU нагрузка: ~300-400 операций на элемент
  static const LiquidGlassSettings darkBackground = LiquidGlassSettings(
    thickness: 3,
    glassColor: Color(0x28FFFFFF), // Меньше прозрачности для темного фона
    lightIntensity: 1.0,
    ambientStrength: 0.25,
    saturation: 1.0,
  );

  /// Настройки для кнопок
  /// Использование: интерактивные кнопки, важные действия
  /// GPU нагрузка: ~300-400 операций на элемент
  static const LiquidGlassSettings button = LiquidGlassSettings(
    thickness: 3,
    glassColor: Color(0x44FFFFFF), // Немного ярче для видимости
    lightIntensity: 1.0,
    ambientStrength: 0.25,
    saturation: 1.0,
  );

  /// СУПЕР-минимальные настройки для энергосбережения
  /// Использование: слабые устройства, перегрев/автоблокировка яркости, большие списки
  /// GPU нагрузка: ~100-150 операций на элемент
  static const LiquidGlassSettings superMinimal = LiquidGlassSettings(
    thickness: 1,
    glassColor: Color(0x18FFFFFF), // 9% прозрачность
    lightIntensity: 0.7,
    ambientStrength: 0.1,
    saturation: 0.9,
  );

  /// Пресеты для СВЕТЛОГО фона (например, #D5D9DC)
  /// Повышенная непрозрачность и насыщенность для лучшего контраста
  static const LiquidGlassSettings onLightMinimal = LiquidGlassSettings(
    thickness: 4,
    glassColor: Color(0x66FFFFFF), // ~40% белого тумана (матовее и контрастнее)
    lightIntensity: 1.0,
    ambientStrength: 0.35,
    saturation: 1.02,
  );

  static const LiquidGlassSettings onLightBlue = LiquidGlassSettings(
    thickness: 5,
    glassColor: Color(0xCC2196F3), // ярче и более матовый синий (~80%)
    lightIntensity: 0.95,
    ambientStrength: 0.5,
    saturation: 1.08,
  );

  static const LiquidGlassSettings onLightGreen = LiquidGlassSettings(
    thickness: 5,
    glassColor: Color(0xCC4CAF50), // ярче и более матовый зелёный
    lightIntensity: 0.95,
    ambientStrength: 0.5,
    saturation: 1.08,
  );

  /// Выделенные варианты для onLight-кнопок (ещё более заметные)
  static const LiquidGlassSettings onLightGreenSelected = LiquidGlassSettings(
    thickness: 6,
    glassColor: Color(0xE64CAF50), // ~90%
    lightIntensity: 1.0,
    ambientStrength: 0.55,
    saturation: 1.1,
  );

  static const LiquidGlassSettings onLightOrange = LiquidGlassSettings(
    thickness: 5,
    glassColor: Color(0xCCFB8C00), // ярче и более матовый оранжевый
    lightIntensity: 0.95,
    ambientStrength: 0.5,
    saturation: 1.08,
  );

  static const LiquidGlassSettings onLightOrangeSelected = LiquidGlassSettings(
    thickness: 6,
    glassColor: Color(0xE6FB8C00),
    lightIntensity: 1.0,
    ambientStrength: 0.55,
    saturation: 1.1,
  );

  static const LiquidGlassSettings onLightRed = LiquidGlassSettings(
    thickness: 5,
    glassColor: Color(0xCCE53935), // ярче и более матовый красный
    lightIntensity: 0.95,
    ambientStrength: 0.5,
    saturation: 1.08,
  );

  static const LiquidGlassSettings onLightRedSelected = LiquidGlassSettings(
    thickness: 6,
    glassColor: Color(0xE6E53935),
    lightIntensity: 1.0,
    ambientStrength: 0.55,
    saturation: 1.1,
  );

  /// iOS 16/17 style: более матовое стекло с выраженной дисторсией
  /// Рекомендуется для ограниченного числа элементов (оверлеи/кнопки онбординга)
  static const LiquidGlassSettings ios26Overlay = LiquidGlassSettings(
    thickness: 6, // увеличенный радиус размытия
    glassColor: Color(0x4DFFFFFF), // ~30% белого тумана
    lightIntensity: 1.0,
    ambientStrength: 0.35, // больше рассеянного света (матовость)
    saturation: 1.1, // лёгкая вибрантность как на iOS
  );

  /// iOS‑style для кнопок (обычное состояние)
  static const LiquidGlassSettings ios26Button = LiquidGlassSettings(
    thickness: 5,
    glassColor: Color(0x4DFFFFFF), // ~30% туман (матовее)
    lightIntensity: 0.9, // чуть меньше блика
    ambientStrength: 0.4, // больше рассеянного света
    saturation: 1.02, // слегка приглушённая насыщенность
  );

  /// iOS‑style для кнопок (выбранное состояние)
  static const LiquidGlassSettings ios26ButtonSelected = LiquidGlassSettings(
    thickness: 5,
    glassColor: Color(0x66FFFFFF), // ~40% туман (чуть ярче при выделении)
    lightIntensity: 1.0,
    ambientStrength: 0.45,
    saturation: 1.06,
  );

  /// Цветные пресеты для кнопок (для тёмного фона)
  /// Полупрозрачные оттенки, согласованные с минимальной нагрузкой
  static const LiquidGlassSettings blue = LiquidGlassSettings(
    thickness: 3,
    glassColor: Color(0x662196F3), // синий оттенок (ярче)
    lightIntensity: 1.0,
    ambientStrength: 0.25,
    saturation: 1.0,
  );

  static const LiquidGlassSettings green = LiquidGlassSettings(
    thickness: 3,
    glassColor: Color(0x664CAF50), // зелёный оттенок (ярче)
    lightIntensity: 1.0,
    ambientStrength: 0.25,
    saturation: 1.0,
  );

  static const LiquidGlassSettings orange = LiquidGlassSettings(
    thickness: 3,
    glassColor: Color(0x66FB8C00), // оранжевый оттенок (ярче)
    lightIntensity: 1.0,
    ambientStrength: 0.25,
    saturation: 1.0,
  );

  static const LiquidGlassSettings red = LiquidGlassSettings(
    thickness: 3,
    glassColor: Color(0x66E53935), // красный оттенок (ярче)
    lightIntensity: 1.0,
    ambientStrength: 0.25,
    saturation: 1.0,
  );
}

/// Рекомендации по использованию:
/// 
/// ПРИОРИТЕТ 1 - Навигация (2 элемента):
///   - LiquidGlassSettings: ultraOptimized
///   - Нагрузка: ~600-1,000 операций
/// 
/// ПРИОРИТЕТ 2 - Карточки упражнений (6-10 элементов):
///   - LiquidGlassSettings: extremeOptimized
///   - Нагрузка: ~1,200-3,000 операций
/// 
/// ПРИОРИТЕТ 3 - Заголовки/бейджи (1-3 элемента):
///   - LiquidGlassSettings: minimal
///   - Нагрузка: ~150-600 операций
/// 
/// ИТОГО: ~2,000-4,600 операций (цель: 2,000-3,000)
/// 
/// Для достижения цели 2,000-3,000:
/// - Использовать extremeOptimized для всех карточек
/// - Ограничить количество видимых элементов до 8-10
/// - Рассмотреть условное отображение эффекта

