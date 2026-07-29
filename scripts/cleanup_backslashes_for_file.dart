import 'dart:io';

/// Чистит обратные слеши только в указанном файле *_strings.dart
/// Использует те же правила, что и cleanup_backslashes_strict.dart
/// Запуск:
///   dart run scripts/cleanup_backslashes_for_file.dart lib/services/localization/fr_strings.dart
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('❌ Укажите путь к файлу *_strings.dart');
    exit(1);
  }
  final path = args.first;
  final file = File(path);
  if (!await file.exists()) {
    stderr.writeln('❌ Файл не найден: $path');
    exit(1);
  }

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

      // 3) Нормализуем тройные+ обратные слеши: \\{3,} -> \\
      val = val.replaceAllMapped(RegExp(r"\\{3,}"), (mm) => "\\\\");

      // 4) Удаляем одиночный слеш перед символами без необходимости экранирования
      val = val.replaceAll(RegExp(r"\\(?=[^n'\\])"), '');

      // 5) Двойной слеш перед прочими символами -> один
      val = val.replaceAllMapped(RegExp(r"\\\\(?=[^n'\\])"), (mm) => "\\");

      return "  '$key': '$val'$comma";
    },
  );

  if (content != before) {
    await file.writeAsString(content);
    stdout.writeln('✅ Очищено: $path');
  } else {
    stdout.writeln('— Без изменений: $path');
  }
}



