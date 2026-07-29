class TextCleaner {
  static String cleanMarkdown(String text) {
    if (text.isEmpty) return text;

    String cleaned = text;

    // Убираем жирный текст (**текст** или __текст__)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\*\*([^\*]+)\*\*'),
      (match) => match.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'__([^_]+)__'),
      (match) => match.group(1) ?? '',
    );

    // Убираем курсив (*текст* или _текст_)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(?<!\*)\*(?!\*)([^\*]+)\*(?!\*)'),
      (match) => match.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(?<!_)_(?!_)([^_]+)_(?!_)'),
      (match) => match.group(1) ?? '',
    );

    // Убираем зачеркнутый текст (~~текст~~)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'~~([^~]+)~~'),
      (match) => match.group(1) ?? '',
    );

    // Убираем заголовки markdown (### Заголовок)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'^#+\s+(.+)$', multiLine: true),
      (match) => '${match.group(1)}',
    );

    // Убираем списки (- элемент, * элемент, + элемент, 1. элемент)
    cleaned = cleaned.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');

    // Убираем ссылки [текст](url)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^\)]+\)'),
      (match) => match.group(1) ?? '',
    );

    // Убираем изображения ![alt](url)
    cleaned = cleaned.replaceAll(RegExp(r'!\[([^\]]*)\]\([^\)]+\)'), '');

    // Убираем инлайн код `код`
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (match) => match.group(1) ?? '',
    );

    // Убираем блоки кода ```код```
    cleaned = cleaned.replaceAll(RegExp(r'```[^`]*```', multiLine: true), '');

    // Убираем горизонтальные линии
    cleaned = cleaned.replaceAll(RegExp(r'^[-*_]{3,}$', multiLine: true), '');

    // Убираем цитаты (> текст)
    cleaned = cleaned.replaceAll(RegExp(r'^>\s+', multiLine: true), '');

    // Убираем HTML теги
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), '');

    // Убираем специальные символы markdown
    cleaned = cleaned.replaceAll(RegExp(r'[`~\[\]]'), '');

    // Убираем экранированные символы (\*)
    cleaned = cleaned.replaceAll(RegExp(r'\\([*_`~\[\]()#+-])'), r'$1');

    // Заменяем множественные переносы строк на пробелы (для отображения)
    cleaned = cleaned.replaceAll(RegExp(r'\n+'), ' ');

    // Убираем множественные пробелы
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    // Убираем пробелы в начале и конце
    cleaned = cleaned.trim();

    return cleaned;
  }

  static String cleanForSpeech(String text) {
    String cleaned = cleanMarkdown(text);

    // Разбиваем на предложения для добавления естественных пауз
    final sentences = cleaned.split(RegExp(r'[.!?]\s+'));

    final parts = <String>[];

    for (var sentence in sentences) {
      if (sentence.trim().isEmpty) continue;

      // Убираем скобки и их содержимое для более естественной речи
      String processed = sentence.replaceAll(RegExp(r'\([^)]*\)'), '');

      // Заменяем цифры на слова для лучшего произношения (опционально)
      // processed = _replaceNumbersWithWords(processed);

      parts.add(processed.trim());
    }

    return '${parts.where((s) => s.isNotEmpty).join('. ')}.';
  }

  static String cleanForDisplay(String text) {
    if (text.isEmpty) return text;

    String cleaned = text;

    // АГРЕССИВНАЯ ОЧИСТКА MARKDOWN В НАЧАЛЕ
    // Убираем ** в начале текста (частая проблема при потоковой загрузке)
    cleaned = cleaned.replaceFirst(RegExp(r'^\*\*+'), '');

    // Убираем жирный текст (**текст** или __текст__)
    cleaned = cleaned.replaceAll(RegExp(r'\*\*([^\*]*)\*\*'), r'$1');
    cleaned = cleaned.replaceAll(RegExp(r'__([^_]*)__'), r'$1');

    // Убираем курсив (*текст* или _текст_) - более точный паттерн
    cleaned =
        cleaned.replaceAll(RegExp(r'(?<!\*)\*(?!\*)([^\*]*?)\*(?!\*)'), r'$1');
    cleaned = cleaned.replaceAll(RegExp(r'(?<!_)_(?!_)([^_]*?)_(?!_)'), r'$1');

    // Убираем зачеркнутый текст
    cleaned = cleaned.replaceAll(RegExp(r'~~([^~]*)~~'), r'$1');

    // Убираем заголовки markdown
    cleaned = cleaned.replaceAll(RegExp(r'^#+\s+', multiLine: true), '');

    // Нормализуем маркеры списков
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'^(\s*[-*+]\s+)(.+)$', multiLine: true),
      (match) => '• ${match.group(2)}',
    );

    // Убираем ссылки [текст](url)
    cleaned = cleaned.replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1');

    // Убираем изображения ![alt](url)
    cleaned = cleaned.replaceAll(RegExp(r'!\[([^\]]*)\]\([^\)]+\)'), '');

    // Убираем инлайн код `код`
    cleaned = cleaned.replaceAll(RegExp(r'`([^`]+)`'), r'$1');

    // Убираем HTML теги
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), '');

    // Убираем экранированные символы
    cleaned = cleaned.replaceAll(RegExp(r'\\([*_`~\[\]()#+-])'), r'$1');

    // Убираем лишние звездочки в начале и конце
    cleaned = cleaned.replaceAll(RegExp(r'^\*+\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*\*+$'), '');

    // Нормализуем пробелы
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    return cleaned.trim();
  }

  static String ensureProperBulletPoints(String text) {
    String cleaned = text;

    // Заменяем все виды маркеров на единый символ •
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'^(\s*)[-*+]\s+', multiLine: true),
      (match) => '${match.group(1) ?? ''}• ',
    );

    return cleaned;
  }

  static String cleanForDisplayPreserveStructure(String text) {
    if (text.isEmpty) return text;

    String cleaned = text;

    // Убираем незакрытые звездочки markdown в начале (при потоковой загрузке)
    cleaned = cleaned.replaceFirst(RegExp(r'^\*\*+'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'\*\*+$'), '');

    // Убираем жирный текст (**текст** или __текст__)
    cleaned = cleaned.replaceAll(RegExp(r'\*\*([^\*]*)\*\*'), r'$1');
    cleaned = cleaned.replaceAll(RegExp(r'__([^_]*)__'), r'$1');

    // Убираем курсив (*текст* или _текст_)
    cleaned =
        cleaned.replaceAll(RegExp(r'(?<!\*)\*(?!\*)([^\*]*?)\*(?!\*)'), r'$1');
    cleaned = cleaned.replaceAll(RegExp(r'(?<!_)_(?!_)([^_]*?)_(?!_)'), r'$1');

    // Убираем зачеркнутый текст
    cleaned = cleaned.replaceAll(RegExp(r'~~([^~]*)~~'), r'$1');

    // Убираем заголовки markdown (### Заголовок -> Заголовок)
    cleaned = cleaned.replaceAll(RegExp(r'^#+\s+', multiLine: true), '');

    // Нормализуем маркеры списков на единый символ •
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'^(\s*)[-*+]\s+', multiLine: true),
      (match) => '• ',
    );

    // Нормализуем нумерованные списки: 1. текст -> • текст
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'^\s*\d+\.\s+', multiLine: true),
      (match) => '• ',
    );

    // Убираем ссылки [текст](url)
    cleaned = cleaned.replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1');

    // Убираем изображения ![alt](url)
    cleaned = cleaned.replaceAll(RegExp(r'!\[([^\]]*)\]\([^\)]+\)'), '');

    // Убираем инлайн код `код`
    cleaned = cleaned.replaceAll(RegExp(r'`([^`]+)`'), r'$1');

    // Убираем HTML теги
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), '');

    // Убираем экранированные символы
    cleaned = cleaned.replaceAll(RegExp(r'\\([*_`~\[\]()#+-])'), r'$1');

    // Убираем оставшиеся одинокие звездочки
    cleaned = cleaned.replaceAll(RegExp(r'(?<!\*)\*(?!\*)'), '');

    // Убираем placeholder'ы в квадратных скобках полностью (типа [Period 1: ...])
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*:\s*[^\]]*\]'), '');

    // Убираем оставшиеся квадратные скобки с содержимым типа [текст]
    cleaned = cleaned.replaceAll(RegExp(r'\[([^\]]+)\]'), r'$1');

    // Убираем символы валют
    cleaned = cleaned.replaceAll(RegExp(r'[\$€£₽¥₴₸]'), '');

    // Нормализуем множественные переносы строк до двух
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // Нормализуем пробелы (но не переносы строк!)
    cleaned = cleaned.replaceAll(RegExp(r'[^\S\n]+'), ' ');

    // Убираем пробелы в начале строк (кроме отступов для списков)
    cleaned = cleaned.split('\n').map((line) => line.trimLeft()).join('\n');

    return cleaned.trim();
  }

  static String cleanForSpeechPreserveContent(String text) {
    if (text.isEmpty) return text;

    String cleaned = cleanForDisplayPreserveStructure(text);

    // Убираем символы валют которые озвучиваются неправильно
    cleaned = cleaned.replaceAll(RegExp(r'[\$€£₽¥₴₸]'), '');

    // Убираем цены и денежные суммы (например "100$", "50 рублей", "€200")
    cleaned = cleaned.replaceAll(RegExp(r'\d+\s*[\$€£₽¥₴₸]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[\$€£₽¥₴₸]\s*\d+'), '');

    // Убираем placeholder'ы в квадратных скобках типа [Period 1: ...]
    cleaned = cleaned.replaceAll(RegExp(r'\[[^\]]*\]'), '');

    // Заменяем bullet points на паузы для речи
    cleaned = cleaned.replaceAll('• ', '. ');

    // Убираем двойные точки
    cleaned = cleaned.replaceAll('..', '.');

    // Заменяем переносы строк на паузы
    cleaned = cleaned.replaceAll('\n', '. ');

    // Нормализуем множественные пробелы
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    // Убираем пробелы перед точками
    cleaned = cleaned.replaceAll(RegExp(r'\s+\.'), '.');

    // Убираем множественные точки
    cleaned = cleaned.replaceAll(RegExp(r'\.{2,}'), '.');

    // Убираем пустые предложения (только точка и пробелы)
    cleaned = cleaned.replaceAll(RegExp(r'\.\s*\.'), '.');

    return cleaned.trim();
  }

  static String removeEmojis(String text) {
    if (text.isEmpty) return text;
    final emojiPattern = RegExp(
      r'[\u{1F600}-\u{1F64F}]'
      r'|[\u{1F300}-\u{1F5FF}]'
      r'|[\u{1F680}-\u{1F6FF}]'
      r'|[\u{1F1E0}-\u{1F1FF}]'
      r'|[\u{2600}-\u{26FF}]'
      r'|[\u{2700}-\u{27BF}]'
      r'|[\u{1F900}-\u{1F9FF}]'
      r'|[\u{1FA70}-\u{1FAFF}]',
      unicode: true,
    );
    String cleaned = text.replaceAll(emojiPattern, '');
    cleaned = cleaned.replaceAll(
      RegExp(r'[\u{FE0F}\u{200D}\u{20E3}]', unicode: true),
      '',
    );
    return cleaned;
  }
}
