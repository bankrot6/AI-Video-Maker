import 'package:flutter/material.dart';

/// Утилитный класс для форматирования markdown-текста в rich text
class TextFormatter {
  /// Конвертирует markdown-подобный текст в список TextSpan
  static List<TextSpan> parseMarkdownText(
    String text, {
    required TextStyle baseStyle,
    Color? linkColor,
  }) {
    final List<TextSpan> spans = [];
    final lines = text.split('\n');

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Добавляем отступ между строками, кроме первой
      if (i > 0) {
        spans.add(const TextSpan(text: '\n'));
      }

      // Обрабатываем заголовки
      if (line.trim().startsWith('**') && line.trim().endsWith('**')) {
        spans.add(_parseHeaderLine(line, baseStyle));
      }
      // Обрабатываем списки
      else if (line.trim().startsWith('•') || line.trim().startsWith('-')) {
        spans.addAll(_parseListItem(line, baseStyle));
      }
      // Обрабатываем обычный текст с возможным форматированием
      else {
        spans.addAll(_parseInlineText(line, baseStyle, linkColor));
      }
    }

    return spans;
  }

  /// Обрабатывает заголовки (текст в **скобках**)
  static TextSpan _parseHeaderLine(String line, TextStyle baseStyle) {
    String headerText = line.trim();

    // Улучшенная обработка заголовков
    final headerMatch = RegExp(r'^\*\*(.+?)\*\*').firstMatch(headerText);
    if (headerMatch != null) {
      headerText = headerMatch.group(1)?.trim() ?? headerText;
    } else if (headerText.startsWith('**')) {
      // Если заголовок начинается с **, но не заканчивается корректно
      headerText = headerText.substring(2).trim();
      if (headerText.endsWith('**')) {
        headerText = headerText.substring(0, headerText.length - 2).trim();
      }
    }

    return TextSpan(
      text: headerText,
      style: baseStyle.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: (baseStyle.fontSize ?? 16) + 2,
      ),
    );
  }

  /// Обрабатывает элементы списка
  static List<TextSpan> _parseListItem(String line, TextStyle baseStyle) {
    final spans = <TextSpan>[];
    String itemText = line.trim();

    // Удаляем маркер списка
    if (itemText.startsWith('•')) {
      itemText = itemText.substring(1).trim();
    } else if (itemText.startsWith('-')) {
      itemText = itemText.substring(1).trim();
    }

    // Добавляем отступ и маркер
    spans.add(TextSpan(
      text: '  • ',
      style: baseStyle.copyWith(
        fontWeight: FontWeight.bold,
        color: baseStyle.color?.withOpacity(0.8),
      ),
    ));

    // Парсим текст элемента списка
    spans.addAll(_parseInlineText(itemText, baseStyle, null));

    return spans;
  }

  /// Обрабатывает встроенное форматирование в тексте
  static List<TextSpan> _parseInlineText(
    String text,
    TextStyle baseStyle,
    Color? linkColor,
  ) {
    final spans = <TextSpan>[];
    final RegExp boldPattern = RegExp(r'\*\*((?:[^*]|\*(?!\*))+?)\*\*');
    final RegExp emojiPattern = RegExp(
        r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]',
        unicode: true);

    int lastEnd = 0;
    final matches = boldPattern.allMatches(text).toList();

    // Если нет жирного текста, обрабатываем как обычный
    if (matches.isEmpty) {
      spans.addAll(_addTextWithEmojis(text, baseStyle, emojiPattern));
      return spans;
    }

    // Обрабатываем жирный текст
    for (final match in matches) {
      // Добавляем текст до совпадения
      if (match.start > lastEnd) {
        final beforeText = text.substring(lastEnd, match.start);
        spans.addAll(_addTextWithEmojis(beforeText, baseStyle, emojiPattern));
      }

      // Добавляем жирный текст
      final boldText = match.group(1)?.trim() ?? '';
      if (boldText.isNotEmpty) {
        spans.add(TextSpan(
          text: boldText,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      }

      lastEnd = match.end;
    }

    // Добавляем оставшийся текст
    if (lastEnd < text.length) {
      final remainingText = text.substring(lastEnd);
      spans.addAll(_addTextWithEmojis(remainingText, baseStyle, emojiPattern));
    }

    return spans;
  }

  /// Добавляет текст с выделением эмодзи
  static List<TextSpan> _addTextWithEmojis(
    String text,
    TextStyle baseStyle,
    RegExp emojiPattern,
  ) {
    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final match in emojiPattern.allMatches(text)) {
      // Добавляем текст до эмодзи
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: baseStyle,
        ));
      }

      // Добавляем эмодзи с увеличенным размером
      spans.add(TextSpan(
        text: match.group(0) ?? '',
        style: baseStyle.copyWith(
          fontSize: (baseStyle.fontSize ?? 16) + 2,
        ),
      ));

      lastEnd = match.end;
    }

    // Добавляем оставшийся текст
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: baseStyle,
      ));
    }

    return spans;
  }

  /// Создает RichText виджет из markdown-текста
  static Widget buildRichText(
    String text, {
    required TextStyle baseStyle,
    Color? linkColor,
    TextAlign textAlign = TextAlign.start,
  }) {
    final spans = parseMarkdownText(
      text,
      baseStyle: baseStyle,
      linkColor: linkColor,
    );

    return RichText(
      textAlign: textAlign,
      text: TextSpan(
        style: baseStyle,
        children: spans,
      ),
    );
  }

  /// Очищает текст от лишних символов и форматирует структуру
  static String cleanAndFormatText(String text) {
    if (text.trim().isEmpty) return text;

    // Разбиваем на строки для точечной обработки
    final lines = text.split('\n');
    final processedLines = <String>[];

    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      // Сохраняем пустые строки для структуры
      if (line.trim().isEmpty) {
        processedLines.add('');
        continue;
      }

      // Обрабатываем заголовки: **Текст** или **Текст** с лишними символами
      if (line.trim().startsWith('**') && line.contains('**')) {
        line = _cleanHeaderLine(line);
      }
      // Обрабатываем списки: конвертируем * в •
      else if (RegExp(r'^\s*\*\s+').hasMatch(line) && !line.contains('**')) {
        line = line.replaceFirst(RegExp(r'^\s*\*\s+'), '• ');
      }
      // Удаляем лишние восклицательные знаки в конце строк
      else if (line.trim().endsWith('!') && line.trim().length > 1) {
        // Оставляем ! только если это не одиночный символ
        final withoutExclamation =
            line.trim().substring(0, line.trim().length - 1);
        if (withoutExclamation.trim().isNotEmpty) {
          line = withoutExclamation;
        }
      }

      // Убираем лишние пробелы внутри строки, но сохраняем отступы
      final leadingSpaces = RegExp(r'^(\s*)').firstMatch(line)?.group(1) ?? '';
      final trimmedContent = line.trim().replaceAll(RegExp(r'\s+'), ' ');
      line = leadingSpaces + trimmedContent;

      processedLines.add(line);
    }

    // Убираем лишние пустые строки в начале и конце, но сохраняем внутренние
    while (processedLines.isNotEmpty && processedLines.first.trim().isEmpty) {
      processedLines.removeAt(0);
    }
    while (processedLines.isNotEmpty && processedLines.last.trim().isEmpty) {
      processedLines.removeLast();
    }

    return processedLines.join('\n');
  }

  /// Очищает строку заголовка от лишних символов
  static String _cleanHeaderLine(String line) {
    String cleaned = line.trim();

    // Убираем лишние символы в конце заголовка
    cleaned = cleaned.replaceAll(RegExp(r'[*!]+\s*$'), '**');

    // Исправляем неправильное закрытие заголовка
    if (cleaned.startsWith('**') && !cleaned.endsWith('**')) {
      cleaned = '$cleaned**';
    }

    // Убираем лишние звездочки внутри заголовка
    cleaned = cleaned.replaceAll(RegExp(r'\*{3,}'), '**');

    return cleaned;
  }
}
