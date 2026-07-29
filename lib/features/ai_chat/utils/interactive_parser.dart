/// Утилита для парсинга интерактивных элементов из ответов AI
class InteractiveParser {
  /// Извлекает варианты ответов из текста AI
  /// Ищет паттерны типа:
  /// 🔹 Вариант 1
  /// 🔹 Вариант 2
  /// или
  /// • Вариант 1
  /// • Вариант 2
  static List<String> extractOptions(String content) {
    final options = <String>[];

    // Паттерны для поиска вариантов ответов
    final patterns = [
      RegExp(r'🔹\s*(.+)', multiLine: true),
      RegExp(r'▫️\s*(.+)', multiLine: true),
      RegExp(r'◽\s*(.+)', multiLine: true),
      RegExp(r'•\s*(.+)(?=\n|$)', multiLine: true),
      RegExp(r'→\s*(.+)', multiLine: true),
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(content);
      if (matches.length >= 2 && matches.length <= 6) {
        options.clear(); // Очищаем предыдущие найденные варианты
        for (final match in matches) {
          final option = match.group(1)?.trim();
          if (option != null && option.isNotEmpty) {
            // Убираем лишние символы и ограничиваем длину
            final cleanOption = _cleanOption(option);
            if (cleanOption.length <= 50 && !cleanOption.contains('?')) {
              options.add(cleanOption);
            }
          }
        }
        if (options.length >= 2) {
          break; // Если нашли подходящие варианты, прекращаем поиск
        }
      }
    }

    return options.take(5).toList(); // Максимум 5 вариантов
  }

  /// Проверяет содержит ли текст вопрос требующий ответа
  static bool containsQuestion(String content) {
    // Простые эвристики для определения вопросов
    final questionPatterns = [
      RegExp(r'\?[^?]*$', multiLine: true), // Заканчивается вопросом
      RegExp(r'(что выберете|что предпочитаете|сколько|какой|какие|как часто)',
          caseSensitive: false),
      RegExp(r'(расскажите|выберите|укажите|определите)', caseSensitive: false),
      RegExp(r'(вопрос к вам|выберите вариант)', caseSensitive: false),
    ];

    // Проверяем наличие вопросительных паттернов И наличие потенциальных вариантов ответов
    final hasQuestionPattern =
        questionPatterns.any((pattern) => pattern.hasMatch(content));
    final hasOptionsMarkers = RegExp(r'🔹|▫️|◽').hasMatch(content);

    // Простая проверка на наличие списков без полного парсинга (избегаем рекурсию)
    final hasListItems =
        RegExp(r'(\n|^)\s*[•\-\*]\s+[\p{L}\p{N}]+', unicode: true).allMatches(content).length >= 2;

    return hasQuestionPattern && (hasOptionsMarkers || hasListItems);
  }

  /// Очищает вариант ответа от лишних символов
  static String _cleanOption(String option) {
    return option
        // Убираем только специальные символы в начале (оставляем буквы/цифры любого языка)
        .replaceAll(RegExp(r'^[^\p{L}\p{N}]*', unicode: true), '')
        // Убираем только специальные символы в конце (оставляем буквы/цифры любого языка)
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s.,!"-]+$', unicode: true), '')
        .trim();
  }

  /// Генерирует автоматические варианты ответов для распространенных типов вопросов
  static List<String> generateAutomaticOptions(String content) {
    final lowerContent = content.toLowerCase();

    // Вопросы о количестве воды
    if (lowerContent.contains('вод') &&
        (lowerContent.contains('сколько') || lowerContent.contains('литр'))) {
      return [
        'Меньше 1 литра в день',
        '1-2 литра в день',
        '2-3 литра в день',
        'Больше 3 литров в день',
        'Не слежу за этим'
      ];
    }

    // Вопросы о питании
    if (lowerContent.contains('питан') ||
        lowerContent.contains('еда') ||
        lowerContent.contains('пища')) {
      return [
        'Регулярно, 3-4 раза в день',
        'Нерегулярно, когда получается',
        'Часто перекусываю',
        'Пропускаю приемы пищи'
      ];
    }

    // Вопросы о тренировках
    if (lowerContent.contains('тренир') ||
        lowerContent.contains('спорт') ||
        lowerContent.contains('актив')) {
      return [
        'Каждый день',
        '3-4 раза в неделю',
        '1-2 раза в неделю',
        'Редко занимаюсь',
        'Не занимаюсь спортом'
      ];
    }

    // Вопросы о предпочтениях
    if (lowerContent.contains('предпочит') ||
        lowerContent.contains('нравит') ||
        lowerContent.contains('любит')) {
      return ['Да, нравится', 'Иногда', 'Нет, не очень', 'Совсем не нравится'];
    }

    // Общие вопросы да/нет
    if (lowerContent.contains('?') &&
        (lowerContent.contains('ли ') ||
            lowerContent.contains('хотите') ||
            lowerContent.contains('согласны'))) {
      return ['Да', 'Нет', 'Не уверен(а)', 'Нужно подумать'];
    }

    return [];
  }
}
