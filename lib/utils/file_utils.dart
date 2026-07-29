import 'package:intl/intl.dart';

/// Утилиты для работы с файлами
class FileUtils {
  /// Генерирует имя файла в формате AI Video Maker_дата_время
  ///
  /// [prefix] - префикс для имени файла (по умолчанию 'AI Video Maker')
  /// [suffix] - суффикс для имени файла (по умолчанию пустой)
  /// [extension] - расширение файла (по умолчанию 'png')
  ///
  /// Возвращает строку вида: AI Video Maker_2024-03-15_14-30-25.png
  static String generateFileName({
    String prefix = 'AI Video Maker',
    String suffix = '',
    String extension = 'png',
  }) {
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd_HH-mm-ss');
    final datePart = formatter.format(now);

    String fileName = '${prefix}_$datePart';
    if (suffix.isNotEmpty) {
      fileName += '_$suffix';
    }
    fileName += '.$extension';

    return fileName;
  }

  /// Генерирует имя файла скриншота
  static String generateScreenshotFileName() {
    return generateFileName(prefix: 'AI Video Maker', extension: 'png');
  }

  /// Генерирует имя файла изображения еды
  static String generateFoodImageFileName({String source = ''}) {
    final suffix = source.isEmpty ? 'food' : 'food_$source';
    return generateFileName(
        prefix: 'AI Video Maker', suffix: suffix, extension: 'jpg');
  }

  /// Генерирует имя файла изображения блюда
  static String generateDishImageFileName(String dishName) {
    // Очищаем название блюда для использования в имени файла
    final sanitizedName = dishName
        .toLowerCase()
        .replaceAll(RegExp(r'[^а-яёa-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), ''); // убираем _ в начале и конце

    final suffix = sanitizedName.isEmpty ? 'dish' : 'dish_$sanitizedName';
    return generateFileName(
        prefix: 'AI Video Maker', suffix: suffix, extension: 'png');
  }
}
