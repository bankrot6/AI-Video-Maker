import 'dart:io';
import 'package:translator/translator.dart';

/// Скрипт приводит все файлы переводов к единому виду.
///
/// 1. Английский файл (`en_strings.dart`) используется как эталон.
/// 2. Для каждого языка из перечисления [AppLanguage] генерируется/обновляется
///    соответствующий файл `<lang>_strings.dart`.
/// 3. Отсутствующие ключи добавляются с плейсхолдером вида `TODO: <english>`.
/// 4. Дублирующиеся ключи удаляются, порядок следования ключей совпадает
///    с английским файлом.
/// 5. **НОВАЯ ФУНКЦИЯ**: Для длинных ключей ищет максимально короткие синонимы.
///
/// Запуск:
/// ```bash
/// dart run scripts/fix_localizations.dart
/// ```
/// Скрипт не зависит от Flutter SDK и может выполняться обычным `dart run`.
void main() async {
  const localizationDir = 'lib/services/localization';
  const enFileName = 'en_strings.dart';
  const enumFileName = 'app_localization_service.dart';

  final enFile = File('$localizationDir/$enFileName');
  if (!await enFile.exists()) {
    stderr.writeln('❌ Не найден английский файл переводов: ${enFile.path}');
    exitCode = 1;
    return;
  }

  final enumFile = File('$localizationDir/$enumFileName');
  if (!await enumFile.exists()) {
    stderr.writeln('❌ Не найден файл с перечислением языков: ${enumFile.path}');
    exitCode = 1;
    return;
  }

  final translator = GoogleTranslator();

  // 1. Считываем английские ключи и значения
  final enContent = await enFile.readAsString();
  final Map<String, String> enMap = _extractTranslations(enContent);
  final List<String> enKeys = enMap.keys.toList();

  stdout.writeln('ℹ️  Найдено ${enKeys.length} ключей в английском файле.');

  // 1.5. Анализируем длинные ключи и ищем короткие синонимы
  final longKeysAnalysis = _analyzeLongKeys(enMap);
  if (longKeysAnalysis.isNotEmpty) {
    stdout.writeln('\n🔍 Анализ длинных ключей:');
    for (final analysis in longKeysAnalysis) {
      stdout.writeln(
          '  • ${analysis['key']}: "${analysis['original']}" → предлагается: ${analysis['suggestions']}');
    }
  }

  // 2. Получаем список языков из enum AppLanguage
  final enumContent = await enumFile.readAsString();
  final List<String> languages = _extractEnumValues(enumContent);

  stdout.writeln(
      'ℹ️  Найдено ${languages.length} языков в перечислении AppLanguage.');

  // 3. Обрабатываем каждый язык
  for (final lang in languages) {
    if (lang == 'en') continue; // английский пропускаем

    final fileName = '${lang}_strings.dart';
    final file = File('$localizationDir/$fileName');

    Map<String, String> existing = {};
    if (await file.exists()) {
      // Считываем существующие переводы
      existing = _extractTranslations(await file.readAsString());
      stdout.writeln(
          '  • $lang: найдено ${existing.length} существующих переводов.');
    } else {
      stdout.writeln('  • $lang: файл не найден, будет создан.');
    }

    // 4. Находим НОВЫЕ ключи, которые отсутствуют в файле. Существующие НЕ трогаем вообще
    final newKeys = enKeys.where((key) => !existing.containsKey(key)).toList();

    if (newKeys.isEmpty) {
      stdout.writeln('  ✅ $lang: нет новых ключей — пропускаем');
      continue;
    }

    stdout
        .writeln('    📝 Найдено ${newKeys.length} новых ключей для перевода');

    // 5. Переводим только отсутствующие ключи и ДОБАВЛЯЕМ их в конец карты
    final List<String> newEntries = [];
    for (final key in newKeys) {
      if (key == 'chat_welcome_message') {
        // Никогда не трогаем приветственное сообщение автопереводом.
        // Его восстановит отдельный скрипт translate_welcome_from_ru.dart
        continue;
      }

      final translatedValue = await _translateOrPlaceholder(
        translator,
        enMap[key]!,
        lang,
        key,
      );
      newEntries.add("  '$key': '$translatedValue',");
    }

    // Если файл существует — вставляем новые пары перед закрывающей '};'
    if (await file.exists()) {
      String content = await file.readAsString();
      final insertPos = content.lastIndexOf('};');
      if (insertPos != -1 && newEntries.isNotEmpty) {
        final insertion =
            (newEntries..removeWhere((e) => e.trim().isEmpty)).join('\n');
        content =
            '${content.substring(0, insertPos)}$insertion\n${content.substring(insertPos)}';
        await file.writeAsString(content);
        stdout.writeln(
            '  ✅ $lang: добавлено новых ключей: ${newEntries.length} (существующие не изменены)');
      } else {
        // Файл имеет неожиданный формат — пересоздадим корректно, но только с существующими + новыми
        final buffer = StringBuffer()
          ..writeln('final Map<String, String> ${lang}Strings = {');

        // Сначала переписываем существующие как есть
        for (final entry in existing.entries) {
          buffer
              .writeln("  '${entry.key}': '${_sanitizeForDart(entry.value)}',");
        }
        // Затем добавляем новые переводы
        for (final line in newEntries) {
          buffer.writeln(line);
        }
        buffer.writeln('};');
        await file.writeAsString(buffer.toString());
        stdout.writeln(
            '  ✅ $lang: файл пересобран (формат был некорректен). Существующие значения сохранены');
      }
    } else {
      // Если файла нет — создаём полный файл по английским ключам, переводя всё
      final buffer = StringBuffer()
        ..writeln('final Map<String, String> ${lang}Strings = {');

      for (final key in enKeys) {
        if (key == 'chat_welcome_message')
          continue; // оставляем скрипту восстановления
        final translatedValue = await _translateOrPlaceholder(
          translator,
          enMap[key]!,
          lang,
          key,
        );
        buffer.writeln("  '$key': '$translatedValue',");
      }

      buffer.writeln('};');
      await file.writeAsString(buffer.toString());
      stdout.writeln(
          '  ✅ $lang: файл создан (${newKeys.length} ключей добавлено).');
    }
  }

  stdout.writeln('\n🎉 Все файлы переводов приведены в порядок.');

  if (longKeysAnalysis.isNotEmpty) {
    stdout.writeln('\n📝 Рекомендации по оптимизации длинных ключей:');
    for (final analysis in longKeysAnalysis) {
      stdout.writeln(
          '  • Рассмотрите замену "${analysis['key']}" на более короткие варианты');
    }
  }
}

/// Извлекает пары `key -> value` из содержимого файла переводов.
Map<String, String> _extractTranslations(String content) {
  final Map<String, String> result = {};
  // Захватываем значение, допускающее экранированные одиночные кавычки \' внутри строки
  final regExp = RegExp(r"'([^']+)':\s*'((?:\\'|[^'])*?)'", multiLine: true);
  for (final match in regExp.allMatches(content)) {
    final key = match.group(1)!;
    final rawValue = match.group(2)!;
    // Восстанавливаем оригинальную строку без экранирования
    final value = rawValue.replaceAll("\\'", "'");
    result.putIfAbsent(key, () => value);
  }
  return result;
}

/// Извлекает имена значений из перечисления `AppLanguage`.
List<String> _extractEnumValues(String content) {
  final enumStart = content.indexOf('enum AppLanguage');
  if (enumStart == -1) return [];

  // Находим тело перечисления (между первой '{' и соответствующей '}')
  final braceStart = content.indexOf('{', enumStart);
  if (braceStart == -1) return [];

  int braceCounter = 1;
  int index = braceStart + 1;
  while (index < content.length && braceCounter > 0) {
    if (content[index] == '{') braceCounter++;
    if (content[index] == '}') braceCounter--;
    index++;
  }

  final braceEnd = index - 1;
  if (braceCounter != 0) return [];

  final enumBody = content.substring(braceStart + 1, braceEnd);

  // Используем RegExp, который находит строки вида `identifier,` игнорируя пробелы
  final regExp = RegExp(r'^\s*(\w+)\s*,', multiLine: true);
  return [for (final m in regExp.allMatches(enumBody)) m.group(1)!];
}

/// Возвращает код языка для Google Translate
String? _langCodeFor(String lang) {
  switch (lang) {
    case 'ru':
      return 'ru';
    case 'es':
    case 'esMX':
      return 'es';
    case 'ar':
      return 'ar';
    case 'fr':
    case 'frCA':
      return 'fr';
    case 'fil':
      return 'tl';
    case 'ja':
      return 'ja';
    case 'it':
      return 'it';
    case 'ko':
      return 'ko';
    case 'pt':
    case 'ptBR':
      return 'pt';
    case 'zh':
      return 'zh-cn';
    case 'zhTW':
      return 'zh-tw';
    case 'uk':
      return 'uk';
    case 'th':
      return 'th';
    case 'el':
      return 'el';
    case 'tr':
      return 'tr';
    case 'vi':
      return 'vi';
    case 'hi':
      return 'hi';
    case 'de':
      return 'de';
    case 'hu':
      return 'hu';
    case 'da':
      return 'da';
    case 'he':
      // GoogleTranslator в некоторых версиях ожидает устаревший код 'iw'
      return 'iw';
    case 'id':
      return 'id';
    case 'ca':
      return 'ca';
    case 'ms':
      return 'ms';
    case 'nl':
      return 'nl';
    case 'no':
      return 'no';
    case 'pl':
      return 'pl';
    case 'ro':
      return 'ro';
    case 'sk':
      return 'sk';
    case 'fi':
      return 'fi';
    case 'hr':
      return 'hr';
    case 'cs':
      return 'cs';
    case 'sv':
      return 'sv';
    default:
      return null;
  }
}

Future<String> _translateOrPlaceholder(
    GoogleTranslator translator, String text, String lang, String key) async {
  final targetCode = _langCodeFor(lang);
  if (targetCode == null) {
    return 'TODO: ${_sanitizeForDart(text)}';
  }

  // Сначала проверяем, есть ли короткий вариант для этого ключа
  final shortTranslations = _getShortTranslations(lang);
  if (shortTranslations.containsKey(key)) {
    return _sanitizeForDart(shortTranslations[key]!);
  }

  // Несколько попыток перевода с экспоненциальной задержкой
  const int maxAttempts = 4;
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      // Защита форматирования для длинных сообщений (например, приветствия)
      const nl2 = '__AI_NL2__';
      const nl1 = '__AI_NL__';
      const bold = '__AI_BOLD__';
      final protected = text
          .replaceAll('**', bold)
          .replaceAll('\n\n', nl2)
          .replaceAll('\n', nl1);

      final translation =
          await translator.translate(protected, from: 'en', to: targetCode);

      // Если сервис вернул исходный английский текст (иногда бывает при сбоях)
      if (targetCode != 'en' && translation.text.trim() == protected.trim()) {
        if (attempt < maxAttempts) {
          stderr.writeln(
              '    ⚠️ Похоже, перевод не выполнен (получен исходный текст). Повторная попытка $attempt/$maxAttempts...');
          await Future.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }
      }

      // Если получили длинный перевод для проблемного ключа, возвращаем короткий вариант
      if (_isProblematicKey(key) && translation.text.length > 4) {
        final shortOption = shortTranslations[key];
        if (shortOption != null) {
          stdout.writeln(
              '    🔄 Автосокращение "$key": "${translation.text}" → "$shortOption"');
          return _sanitizeForDart(shortOption);
        }
      }

      // Специальная замена для русского перевода "tap" → "клик" (не "кран")
      String result = translation.text
          .replaceAll(nl2, '\n\n')
          .replaceAll(nl1, '\n')
          .replaceAll(bold, '**');
      if (lang == 'ru' && key == 'easy_to_cancel') {
        result = result
            .replaceAll('крана', 'клика')
            .replaceAll('тапа', 'клика')
            .replaceAll('нажатия', 'клика');
      }

      return _sanitizeForDart(result);
    } catch (e) {
      if (attempt < maxAttempts) {
        stderr.writeln(
            '    ⚠️ Ошибка перевода "$key" на "$lang" (попытка $attempt/$maxAttempts): $e');
        await Future.delayed(Duration(milliseconds: 600 * attempt));
        continue;
      }
    }
  }
  return 'TODO: ${_sanitizeForDart(text)}';
}

String _sanitizeForDart(String value) {
  return value
      .replaceAll('\\', r'\\') // сначала экранируем обратный слэш
      .replaceAll("'", r"\'") // затем одинарные кавычки
      .replaceAll("\r", '')
      .replaceAll("\n", r"\n"); // перевод строки в литерал
}

/// Анализирует длинные ключи и предлагает короткие синонимы
List<Map<String, dynamic>> _analyzeLongKeys(Map<String, String> enMap) {
  final List<Map<String, dynamic>> longKeys = [];

  for (final entry in enMap.entries) {
    final key = entry.key;
    final value = entry.value;

    // Определяем критерии "длинного" ключа (более 6 символов или содержит определенные слова)
    if (value.length > 6 || _isProblematicKey(key)) {
      final suggestions = _getSynonymSuggestions(key, value);
      if (suggestions.isNotEmpty) {
        longKeys.add({
          'key': key,
          'original': value,
          'suggestions': suggestions,
        });
      }
    }
  }

  return longKeys;
}

/// Определяет проблемные ключи (для кнопок пола и кнопки "Изменить")
bool _isProblematicKey(String key) {
  const problematicKeys = [
    'gender_male',
    'gender_female',
    'text_editing_cancel', // кнопка "Изменить" на экране анализа еды
    'easy_to_cancel', // фраза под кнопкой покупки на paywall
  ];
  return problematicKeys.contains(key);
}

/// Возвращает true для ключей, которые нужно принудительно перезаписать переводом
// Удалено: логика принудительного перезаписа не используется — существующие ключи не трогаем
// Оставлено для справки: если потребуется, можно вернуть поведенческое перезаписывание
// bool _shouldForceRetranslate(String key) { ... }

/// Возвращает предложения коротких синонимов для ключа
List<String> _getSynonymSuggestions(String key, String value) {
  final suggestions = <String>[];

  switch (key) {
    case 'gender_male':
      suggestions.addAll(['М', 'Муж', '♂']);
      break;
    case 'gender_female':
      suggestions.addAll(['Ж', 'Жен', '♀']);
      break;
    case 'text_editing_cancel':
      suggestions.addAll(['Правка', 'Ред.', '✏️', 'Изм.']);
      break;
    default:
      // Общие правила сокращения
      if (value.length > 10) {
        // Для очень длинных слов предлагаем сокращения
        if (value.contains(' ')) {
          // Если несколько слов, берем первые буквы
          final words = value.split(' ');
          if (words.length > 1) {
            final acronym = words
                .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
                .join('');
            if (acronym.length <= 4) suggestions.add(acronym);
          }
        }
        // Предлагаем укороченную версию (первые 6 символов + "...")
        if (value.length > 8) {
          suggestions.add('${value.substring(0, 6)}...');
        }
      }
  }

  return suggestions;
}

/// Возвращает сокращенный перевод для длинных ключей
// Удалено: логика автосокращения не используется при неизменности существующих значений
// String _getShortenedTranslation(...) { ... }

/// Возвращает карту коротких переводов для каждого языка
Map<String, String> _getShortTranslations(String lang) {
  switch (lang) {
    case 'ru':
      return {
        // Используем полноценные, но компактные синонимы (≤8 символов)
        'gender_male': 'Мужчина', // 7
        'gender_female': 'Женщина', // 8
        'text_editing_cancel': 'Правка',
      };
    case 'en':
      return {
        'gender_male': 'Male',
        'gender_female': 'Female',
        'text_editing_cancel': 'Edit',
      };
    case 'es':
    case 'esMX':
      return {
        'gender_male': 'Hombre',
        'gender_female': 'Mujer',
        'text_editing_cancel': 'Editar',
      };
    case 'fr':
    case 'frCA':
      return {
        'gender_male': 'Homme', // 5
        'gender_female': 'Femme', // 5
        'text_editing_cancel': 'Modifier',
      };
    case 'de':
      return {
        'gender_male': 'Mann', // 4
        'gender_female': 'Frau', // 4
        'text_editing_cancel': 'Ändern',
      };
    case 'it':
      return {
        'gender_male': 'Uomo',
        'gender_female': 'Donna',
        'text_editing_cancel': 'Modifica',
      };
    case 'pt':
    case 'ptBR':
      return {
        'gender_male': 'Homem',
        'gender_female': 'Mulher',
        'text_editing_cancel': 'Editar',
      };
    case 'zh':
    case 'zhTW':
      return {
        'gender_male': '男性',
        'gender_female': '女性',
        'text_editing_cancel': '编辑',
      };
    case 'ja':
      return {
        'gender_male': '男性',
        'gender_female': '女性',
        'text_editing_cancel': '編集',
      };
    case 'ko':
      return {
        'gender_male': '남성',
        'gender_female': '여성',
        'text_editing_cancel': '편집',
      };
    case 'ar':
      return {
        'gender_male': 'ذكر',
        'gender_female': 'أنثى',
        'text_editing_cancel': 'تعديل',
      };
    case 'hi':
      return {
        'gender_male': 'पुरुष',
        'gender_female': 'महिला',
        'text_editing_cancel': 'संपादन',
      };
    case 'th':
      return {
        'gender_male': 'ชาย',
        'gender_female': 'หญิง',
        'text_editing_cancel': 'แก้ไข',
      };
    case 'uk':
      return {
        'gender_male': 'Чоловік', // 7
        'gender_female': 'Жінка', // 5
        'text_editing_cancel': 'Правка',
      };
    default:
      return {};
  }
}
