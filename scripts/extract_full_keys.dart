import 'dart:io';

/// Скрипт для извлечения полного набора UI ключей из оригинального коммита
/// и создания полных файлов переводов
void main() async {
  try {
    // Читаем UI ключи из временного файла
    final uiKeysFile = File('/tmp/ui_keys_only.txt');
    final lines = await uiKeysFile.readAsLines();

    print('Найдено ${lines.length} UI ключей');

    // Парсим ключи и создаем полный английский файл
    final enStrings = <String, String>{};
    for (final line in lines) {
      final match = RegExp(r"'([^']+)':\s*'([^']*)'").firstMatch(line);
      if (match != null) {
        final key = match.group(1)!;
        final value = match.group(2)!;
        enStrings[key] = value;
      }
    }

    print('Парсированo ${enStrings.length} ключей');

    // Создаем полный en_strings.dart
    await _createFullEnglishFile(enStrings);

    // Создаем базовые файлы для других языков
    await _createBasicLanguageFiles(enStrings.keys.toList());

    print(
        '✅ Создан полный набор файлов переводов с ${enStrings.length} ключами каждый');
  } catch (e) {
    print('❌ Ошибка: $e');
  }
}

Future<void> _createFullEnglishFile(Map<String, String> enStrings) async {
  final file = File('lib/services/localization/en_strings.dart');
  final buffer = StringBuffer();

  buffer.writeln('final Map<String, String> enStrings = {');

  // Группируем по категориям
  _writeCategory(buffer, '// Общие тексты', enStrings, [
    'need_help',
    'terms_of_service',
    'restore_purchase',
    'settings',
    'yes',
    'no',
    'cancel',
    'ok',
    'save',
    'delete',
    'error',
    'warning',
    'success',
    'loading',
    'app_name',
    'change_language',
    'close',
    'reload',
    'retry'
  ]);

  _writeCategory(buffer, '// Языки', enStrings, [
    'russian',
    'english',
    'spanish',
    'arabic',
    'french',
    'french_canadian',
    'filipino',
    'japanese',
    'italian',
    'korean',
    'portuguese_brazilian',
    'portuguese',
    'chinese',
    'ukrainian',
    'thai',
    'greek',
    'turkish',
    'vietnamese',
    'hindi',
    'german'
  ]);

  _writeCategory(buffer, '// Основные разделы', enStrings,
      ['home', 'history', 'analytics', 'share', 'subscription']);

  _writeCategory(buffer, '// Ошибки', enStrings, [
    'camera_not_available',
    'error_occurred',
    'no_data_to_display',
    'subscription_activated',
    'data_loading_error'
  ]);

  _writeCategory(buffer, '// Онбординг', enStrings, [
    'onboarding_gender_title',
    'onboarding_age_title',
    'onboarding_height_title',
    'onboarding_weight_title',
    'onboarding_activity_title',
    'onboarding_goal_title',
    'onboarding_data_description',
    'onboarding_next',
    'onboarding_finish'
  ]);

  // Добавляем все остальные ключи
  final usedKeys = <String>{};
  final allUsedKeys = buffer
      .toString()
      .split('\n')
      .where((line) => line.contains("'") && line.contains(':'))
      .map((line) => RegExp(r"'([^']+)':").firstMatch(line)?.group(1))
      .where((key) => key != null)
      .cast<String>()
      .toSet();

  final remainingKeys =
      enStrings.keys.where((key) => !allUsedKeys.contains(key)).toList();

  if (remainingKeys.isNotEmpty) {
    buffer.writeln('  // Остальные ключи');
    for (final key in remainingKeys) {
      final value = enStrings[key]!.replaceAll("'", "\\'");
      buffer.writeln("  '$key': '$value',");
    }
  }

  buffer.writeln('};');

  await file.writeAsString(buffer.toString());
  print('✅ Создан полный en_strings.dart с ${enStrings.length} ключами');
}

void _writeCategory(StringBuffer buffer, String categoryName,
    Map<String, String> strings, List<String> keys) {
  final foundKeys = keys.where((key) => strings.containsKey(key)).toList();
  if (foundKeys.isEmpty) return;

  buffer.writeln('  $categoryName');
  for (final key in foundKeys) {
    final value = strings[key]!.replaceAll("'", "\\'");
    buffer.writeln("  '$key': '$value',");
  }
  buffer.writeln();
}

Future<void> _createBasicLanguageFiles(List<String> keys) async {
  final languages = {
    'de': 'deStrings',
    'fr': 'frStrings',
    'it': 'itStrings',
    'pt': 'ptStrings',
    'tr': 'trStrings',
  };

  for (final entry in languages.entries) {
    final langCode = entry.key;
    final varName = entry.value;
    final file = File('lib/services/localization/${langCode}_strings.dart');

    final buffer = StringBuffer();
    buffer.writeln('final Map<String, String> $varName = {');

    for (final key in keys) {
      buffer.writeln("  '$key': 'TODO: $key',");
    }

    buffer.writeln('};');

    await file.writeAsString(buffer.toString());
    print('✅ Создан ${langCode}_strings.dart с ${keys.length} ключами');
  }
}
