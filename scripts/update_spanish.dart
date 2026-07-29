import 'dart:io';

/// Скрипт для обновления испанского файла до полного набора ключей
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

    // Читаем существующие испанские переводы
    final esFile = File('lib/services/localization/es_strings.dart');
    final esContent = await esFile.readAsString();

    final existingEs = <String, String>{};
    for (final match
        in RegExp(r"'([^']+)':\s*'([^']*)'").allMatches(esContent)) {
      final key = match.group(1)!;
      final value = match.group(2)!;
      existingEs[key] = value;
    }

    print('Найдено ${existingEs.length} существующих испанских переводов');

    // Создаем полный испанский файл
    final buffer = StringBuffer();
    buffer.writeln('final Map<String, String> esStrings = {');

    for (final key in enKeys) {
      if (existingEs.containsKey(key)) {
        // Используем существующий перевод
        final value = existingEs[key]!.replaceAll("'", "\\'");
        buffer.writeln("  '$key': '$value',");
      } else {
        // Добавляем заглушку
        buffer.writeln("  '$key': 'TODO: $key',");
      }
    }

    buffer.writeln('};');

    await esFile.writeAsString(buffer.toString());
    print('✅ Обновлен es_strings.dart до ${enKeys.length} ключей');
  } catch (e) {
    print('❌ Ошибка: $e');
  }
}
