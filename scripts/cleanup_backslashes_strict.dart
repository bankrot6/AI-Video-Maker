import 'dart:io';

/// Жёсткая нормализация обратных слешей в локализациях.
/// Правила:
/// - \\' -> \' (ровно один слеш перед одинарной кавычкой)
/// - \\n -> \n (ровно один слеш перед n)
/// - \\\\ -> \\ (ровно два слеша, если требуется реальный обратный слеш)
/// - любой одиночный слеш перед символом, который не требует экранирования (кроме n, ', \\) — удаляется
/// - последовательности из 2+ слешей вне допустимых мест сводятся к одному слешу
///
/// Запуск: dart run scripts/cleanup_backslashes_strict.dart
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
    final before = content;

    content = content.replaceAllMapped(
      RegExp(r"'([^']+)'\s*:\s*'((?:\\'|[^'])*?)'\s*(,)", multiLine: true),
      (m) {
        final key = m.group(1)!;
        String val = m.group(2)!;
        final comma = m.group(3) ?? ',';

        // 1) Нормализуем экранирование кавычек: \\{2,}' -> \'
        val = val.replaceAll(RegExp(r"\\{2,}'"), "\\'");

        // 2) Нормализуем переносы строк: \\{2,}n -> \n
        val = val.replaceAll(RegExp(r"\\{2,}n"), "\\n");

        // 3) Нормализуем двойной обратный слеш: \\{3,} -> \\ (оставляем два)
        val = val.replaceAllMapped(RegExp(r"\\{3,}"), (mm) => "\\\\");

        // 4) Удаляем одиночный слеш перед символами, которые не требуют экранирования
        val = val.replaceAll(RegExp(r"\\(?=[^n'\\])"), '');

        // 5) Подчищаем редкие остатки: двойной слеш перед символом, который не ' n \\ -> один
        val = val.replaceAllMapped(RegExp(r"\\\\(?=[^n'\\])"), (mm) => "\\");

        return "  '$key': '$val'$comma";
      },
    );

    if (content != before) {
      await file.writeAsString(content);
      stdout.writeln('✅ Жёсткая чистка: ${file.path}');
    } else {
      stdout.writeln('— Без изменений: ${file.path}');
    }
  }

  stdout.writeln('\n🎉 Готово: жёсткая нормализация обратных слешей выполнена.');
}





