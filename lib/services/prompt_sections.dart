/// Разбор и сборка структурированного промпта вида «ЗАГОЛОВОК:\nтекст».
///
/// Используется экраном создания, чтобы пользователь мог править отдельные
/// смысловые блоки промпта, не ломая его структуру.
class PromptSections {
  const PromptSections._(this._order, this._values);

  factory PromptSections.parse(String prompt) {
    final order = <String>[];
    final values = <String, String>{};
    final buffer = StringBuffer();
    String? current;

    void flush() {
      final key = current;
      if (key == null) return;
      values[key] = buffer.toString().trim();
      buffer.clear();
    }

    for (final line in prompt.split('\n')) {
      final header = _headerOf(line);
      if (header != null) {
        flush();
        current = header;
        if (!order.contains(header)) order.add(header);
        final inline = line.substring(line.indexOf(':') + 1).trim();
        if (inline.isNotEmpty) buffer.writeln(inline);
        continue;
      }
      if (current != null) {
        buffer.writeln(line);
      } else if (line.trim().isNotEmpty) {
        current = introKey;
        order.add(introKey);
        buffer.writeln(line);
      }
    }
    flush();

    values.removeWhere((_, value) => value.isEmpty);
    order.removeWhere((key) => !values.containsKey(key));

    if (order.isEmpty) {
      return PromptSections._([introKey], {introKey: prompt.trim()});
    }
    return PromptSections._(order, values);
  }

  static const String introKey = 'ОПИСАНИЕ';

  final List<String> _order;
  final Map<String, String> _values;

  List<String> get keys => List.unmodifiable(_order);

  String? operator [](String key) => _values[key];

  PromptSections replace(String key, String content) {
    if (!_values.containsKey(key)) return this;
    return PromptSections._(
      List<String>.from(_order),
      {..._values, key: content.trim()},
    );
  }

  String compose() {
    final buffer = StringBuffer();
    for (final key in _order) {
      final content = _values[key] ?? '';
      if (content.isEmpty) continue;
      buffer.writeln('$key:');
      buffer.writeln(content);
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  /// Человекочитаемый заголовок блока для UI.
  static String displayTitle(String key) {
    final lower = key.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  /// Заголовком считаем строку вида «ТЕКСТ ЗАГЛАВНЫМИ:» — так DeepSeek
  /// размечает блоки промпта.
  static String? _headerOf(String line) {
    final trimmed = line.trim();
    final colon = trimmed.indexOf(':');
    if (colon <= 0 || colon > 40) return null;
    final head = trimmed.substring(0, colon).trim();
    if (head.isEmpty) return null;
    if (head != head.toUpperCase()) return null;
    if (!RegExp(r'^[A-ZА-ЯЁ0-9 ,\-/]+$').hasMatch(head)) return null;
    return head;
  }
}
