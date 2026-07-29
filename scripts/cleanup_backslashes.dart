import 'dart:io';

/// Скрипт проходит по всем *_strings.dart и нормализует экранирование:
/// - заменяет последовательности вида \\ n, \\ N на \n
/// - убирает избыточные обратные слеши перед небуквенными символами, кроме
///   случаев, когда это необходимо для литерала Dart (одиночная кавычка и обратный слеш)
/// - сохраняет корректные экранирования: \\n, \\', \\\\ (один реальный обратный слеш)
///
/// Запуск:
///   dart run scripts/cleanup_backslashes.dart
///
Future<void> main() async {
  const localizationDir = 'lib/services/localization';
  final dir = Directory(localizationDir);
  final files = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('_strings.dart'))
      .cast<File>()
      .toList();

  for (final file in files) {
    String content = await file.readAsString();
    final original = content;

    // Нормализуем \ n / \ N -> \n внутри строковых значений карт
    content = _normalizeEscapes(content);

    if (content != original) {
      await file.writeAsString(content);
      stdout.writeln('✅ Очищено: ${file.path}');
    } else {
      stdout.writeln('— Без изменений: ${file.path}');
    }
  }

  stdout.writeln('\n🎉 Готово: экранирование нормализовано.');
}

String _normalizeEscapes(String content) {
  // Работаем только внутри значений карты 'key': 'value'
  return content.replaceAllMapped(
    RegExp(r"'([^']+)'\s*:\s*'((?:\\'|[^'])*?)'\s*(,)", multiLine: true),
    (m) {
      final key = m.group(1)!;
      String val = m.group(2)!;
      final comma = m.group(3) ?? ',';

      // 1) \ n, \ N → \n
      val = val.replaceAll('\\ n', '\\n').replaceAll('\\ N', '\\n');

      // 2) Сжимаем избыточные обратные слеши перед буквами/цифрами, но
      // не трогаем допустимые последовательности \\', \\n и \\\\.
      // Сначала временно защищаем合法ные последовательности
      const escQuote = '__ESC_Q__';
      const escSlash = '__ESC_S__';
      const escNl = '__ESC_N__';
      val = val
          .replaceAll("\\'", escQuote)
          .replaceAll('\\\\', escSlash)
          .replaceAll('\\n', escNl);

      // Удаляем одиночные обратные слеши перед алфанумерикой и пробелами
      val = val.replaceAll(RegExp(r"\\(?=[A-Za-zА-Яа-я0-9 ])"), '');

      // Восстанавливаем защищённые последовательности
      val = val
          .replaceAll(escQuote, "\\'")
          .replaceAll(escSlash, '\\\\')
          .replaceAll(escNl, '\\n');

      return "  '$key': '$val'$comma";
    },
  );
}
