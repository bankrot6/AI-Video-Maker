import 'dart:io';

/// Скрипт для создания файлов переводов на все языки
/// Использование: dart scripts/create_translations.dart
void main() async {
  final languages = {
    'de': 'deStrings', // Немецкий
    'fr': 'frStrings', // Французский
    'it': 'itStrings', // Итальянский
    'pt': 'ptStrings', // Португальский
    'zh': 'zhStrings', // Китайский
    'ja': 'jaStrings', // Японский
    'ko': 'koStrings', // Корейский
    'ar': 'arStrings', // Арабский
    'hi': 'hiStrings', // Хинди
    'th': 'thStrings', // Тайский
    'vi': 'viStrings', // Вьетнамский
    'tr': 'trStrings', // Турецкий
    'uk': 'ukStrings', // Украинский
    'pl': 'plStrings', // Польский
  };

  // Эталонные ключи и значения из русского файла
  final referenceTranslations =
      await _extractTranslationsFromFile('lib/services/localization/ru_strings.dart');
  final referenceKeys = referenceTranslations.keys.toList();

  print('Найдено ${referenceKeys.length} ключей для перевода');
  print('Создаем файлы переводов...\n');

  for (final entry in languages.entries) {
    final langCode = entry.key;
    final varName = entry.value;

    await _createLanguageFile(langCode, varName, referenceKeys);
    print('✅ Создан файл: ${langCode}_strings.dart');
  }

  print('\n🎉 Все файлы переводов созданы!');
  print('📝 Теперь нужно заполнить переводы в каждом файле');
  print(
      '🔧 Обновите app_localization_service.dart чтобы использовать отдельные файлы');
}

/// Извлекает ключи из существующего файла переводов
Future<List<String>> _extractKeysFromFile(String filePath) async {
  final file = File(filePath);
  final content = await file.readAsString();

  final keys = <String>[];
  final regex = RegExp(r"'([^']+)':");

  for (final match in regex.allMatches(content)) {
    keys.add(match.group(1)!);
  }

  return keys;
}

/// Извлекает переводы из существующего файла
Future<Map<String, String>> _extractTranslationsFromFile(String filePath) async {
  final file = File(filePath);
  final content = await file.readAsString();
  
  final translations = <String, String>{};
  final regex = RegExp(r"'([^']+)':\s*'((?:\\'|[^'])*?)'");
  
  for (final match in regex.allMatches(content)) {
    final key = match.group(1)!;
    final rawValue = match.group(2)!;
    // Восстанавливаем экранированные кавычки
    final value = rawValue.replaceAll("\\'", "'");
    translations[key] = value;
  }
  
  return translations;
}

/// Создает или обновляет файл перевода для указанного языка
Future<void> _createLanguageFile(
    String langCode, String varName, List<String> keys) async {
  final filePath = 'lib/services/localization/${langCode}_strings.dart';
  final file = File(filePath);

  // Получаем существующие переводы, если файл уже есть
  Map<String, String> existingTranslations = {};
  if (await file.exists()) {
    print('⚠️  Файл $filePath уже существует, обновляем...');
    existingTranslations = await _extractTranslationsFromFile(filePath);
  }

  final buffer = StringBuffer();
  buffer.writeln('final Map<String, String> $varName = {');

  // Обрабатываем все ключи по порядку
  final processedKeys = <String>{};
  
  // Группируем ключи по категориям для лучшей читаемости
  _writeSection(
      buffer,
      'Оплата',
      keys.where((k) =>
          k.contains('payment') || k.contains('pay') || k.contains('card')),
      existingTranslations,
      processedKeys);
  _writeSection(buffer, 'Общие тексты UI', keys.where((k) => _isGeneralUI(k)),
      existingTranslations, processedKeys);
  _writeSection(
      buffer, 'Онбординг', keys.where((k) => k.startsWith('onboarding_')),
      existingTranslations, processedKeys);
  _writeSection(buffer, 'Пол и активность',
      keys.where((k) => k.startsWith('gender_') || k.startsWith('activity_')),
      existingTranslations, processedKeys);
  _writeSection(buffer, 'Цели', keys.where((k) => k.startsWith('goal_')),
      existingTranslations, processedKeys);
  _writeSection(
      buffer,
      'План питания',
      keys.where((k) =>
          k.contains('meal_') ||
          k.contains('calories') ||
          k.contains('nutritional')),
      existingTranslations, processedKeys);

  // Добавляем оставшиеся ключи, которые не попали в категории
  final remainingKeys = keys.where((k) => !processedKeys.contains(k));
  if (remainingKeys.isNotEmpty) {
    _writeSection(buffer, 'Прочие', remainingKeys, existingTranslations, processedKeys);
  }

  buffer.writeln('};');

  await file.writeAsString(buffer.toString());
}

/// Записывает секцию переводов
void _writeSection(
    StringBuffer buffer, 
    String sectionName, 
    Iterable<String> keys,
    Map<String, String> existingTranslations,
    Set<String> processedKeys) {
  if (keys.isEmpty) return;

  buffer.writeln('  // $sectionName');
  for (final key in keys) {
    processedKeys.add(key);
    
    if (existingTranslations.containsKey(key)) {
      // Используем существующий перевод
      final value = existingTranslations[key]!;
      final escapedValue = value.replaceAll("'", "\\'");
      buffer.writeln("  '$key': '$escapedValue',");
    } else {
      // Создаем плейсхолдер для нового ключа
      buffer.writeln("  '$key': '[$sectionName] $key', // TODO: Перевести");
    }
  }
  buffer.writeln();
}

/// Проверяет, является ли ключ общим UI элементом
bool _isGeneralUI(String key) {
  const generalKeys = [
    'need_help',
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
    'retry',
    'home',
    'history',
    'analytics',
    'share',
    'subscription'
  ];
  return generalKeys.contains(key);
}
