import 'dart:io';

/// Скрипт для создания всех языковых файлов с заглушками
void main() async {
  try {
    // Читаем английские ключи как эталон
    final enFile = File('lib/services/localization/en_strings.dart');
    final enContent = await enFile.readAsString();

    // Извлекаем ключи из английского файла
    final enKeys = <String>[];
    final regex = RegExp(r"'([^']+)':");
    for (final match in regex.allMatches(enContent)) {
      enKeys.add(match.group(1)!);
    }

    print('Найдено ${enKeys.length} ключей в английском файле');

    // Языки для создания/обновления
    final languages = {
      'ar': 'arStrings',
      'hi': 'hiStrings',
      'ja': 'jaStrings',
      'ko': 'koStrings',
      'pl': 'plStrings',
      'th': 'thStrings',
      'uk': 'ukStrings',
      'vi': 'viStrings',
      'zh': 'zhStrings',
    };

    for (final entry in languages.entries) {
      final langCode = entry.key;
      final varName = entry.value;
      final file = File('lib/services/localization/${langCode}_strings.dart');

      final buffer = StringBuffer();
      buffer.writeln('final Map<String, String> $varName = {');

      for (final key in enKeys) {
        buffer.writeln("  '$key': 'TODO: $key',");
      }

      buffer.writeln('};');

      await file.writeAsString(buffer.toString());
      print('✅ Создан ${langCode}_strings.dart с ${enKeys.length} ключами');
    }

    print(
        '\n🎉 Все файлы переводов созданы с ${enKeys.length} ключами каждый!');
  } catch (e) {
    print('❌ Ошибка: $e');
  }
}
