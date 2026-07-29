import 'dart:io';

/// Скрипт для создания полного ru_strings.dart из оригинального файла
void main() async {
  try {
    // Читаем русские ключи
    final russianKeysFile = File('/tmp/russian_keys.txt');
    final lines = await russianKeysFile.readAsLines();

    print('Найдено ${lines.length} русских UI ключей');

    // Парсим ключи
    final ruStrings = <String, String>{};
    for (final line in lines) {
      final match = RegExp(r"'([^']+)':\s*'([^']*)'").firstMatch(line);
      if (match != null) {
        final key = match.group(1)!;
        final value = match.group(2)!;
        ruStrings[key] = value;
      }
    }

    print('Парсировано ${ruStrings.length} ключей');

    // Создаем ru_strings.dart
    final file = File('lib/services/localization/ru_strings.dart');
    final buffer = StringBuffer();

    buffer.writeln('final Map<String, String> ruStrings = {');

    // Записываем все ключи
    for (final entry in ruStrings.entries) {
      final key = entry.key;
      final value = entry.value.replaceAll("'", "\\'");
      buffer.writeln("  '$key': '$value',");
    }

    buffer.writeln('};');

    await file.writeAsString(buffer.toString());
    print('✅ Создан полный ru_strings.dart с ${ruStrings.length} ключами');
  } catch (e) {
    print('❌ Ошибка: $e');
  }
}
