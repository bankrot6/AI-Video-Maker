import 'dart:io';

/// Скрипт нормализует лишние запятые после значений в картах переводов
/// Превращает ',,' в ',' только в местах вида: 'key': 'value',,
/// чтобы не задеть текст внутри строк.
///
/// Запуск: dart run scripts/cleanup_commas.dart
Future<void> main() async {
  const dirPath = 'lib/services/localization';
  final dir = Directory(dirPath);
  final files = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('_strings.dart'))
      .cast<File>()
      .toList();

  final pattern = RegExp(r"('(?:\\'|[^'])*?'\s*:\s*'(?:\\'|[^'])*?'\s*,)\s*,+",
      multiLine: true);

  for (final file in files) {
    String content = await file.readAsString();
    final before = content;
    content = content.replaceAllMapped(pattern, (m) => m.group(1)!);

    if (content != before) {
      await file.writeAsString(content);
      stdout.writeln('✅ Исправлены лишние запятые: ${file.path}');
    } else {
      stdout.writeln('— Без изменений: ${file.path}');
    }
  }

  stdout.writeln('\n🎉 Готово: лишние запятые устранены.');
}



