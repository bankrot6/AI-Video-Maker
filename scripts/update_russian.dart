import 'dart:io';

/// Скрипт для обновления русского файла до полного набора ключей
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

    // Читаем существующие русские переводы
    final ruFile = File('lib/services/localization/ru_strings.dart');
    final ruContent = await ruFile.readAsString();

    final existingRu = <String, String>{};
    for (final match
        in RegExp(r"'([^']+)':\s*'([^']*)'").allMatches(ruContent)) {
      final key = match.group(1)!;
      final value = match.group(2)!;
      existingRu[key] = value;
    }

    print('Найдено ${existingRu.length} существующих русских переводов');

    // Создаем полный русский файл
    final buffer = StringBuffer();
    buffer.writeln('final Map<String, String> ruStrings = {');

    for (final key in enKeys) {
      if (existingRu.containsKey(key)) {
        // Используем существующий перевод
        final value = existingRu[key]!.replaceAll("'", "\\'");
        buffer.writeln("  '$key': '$value',");
      } else {
        // Добавляем заглушку
        buffer.writeln("  '$key': 'TODO: $key',");
      }
    }

    buffer.writeln('};');

    await ruFile.writeAsString(buffer.toString());
    print('✅ Обновлен ru_strings.dart до ${enKeys.length} ключей');
  } catch (e) {
    print('❌ Ошибка: $e');
  }
}
