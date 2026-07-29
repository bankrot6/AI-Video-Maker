class SpeechChunker {
  static const Set<String> _abbreviations = {
    'г',
    'ул',
    'пр',
    'просп',
    'пер',
    'д',
    'стр',
    'рис',
    'таб',
    'т.д',
    'т.п',
    'т.к',
    'т.е',
    'и.д',
    'и.п',
    'см',
    'им',
    'др',
    'напр',
    'тяж',
    'лег',
  };

  static String normalize(String text) {
    final s =
        text.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static ({List<String> chunks, String remainder}) extractFromBuffer(
    String buffer, {
    required bool flush,
    int minChunkChars = 80,
    int maxChunkChars = 320,
    int softLookAheadChars = 120,
  }) {
    var s = buffer.replaceAll('\u00A0', ' ');
    if (s.isEmpty) return (chunks: const <String>[], remainder: '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trimLeft();
    if (s.isEmpty) return (chunks: const <String>[], remainder: '');

    final chunks = <String>[];

    while (s.length >= minChunkChars) {
      final targetEnd = s.length < maxChunkChars ? s.length : maxChunkChars;

      final strong = _lastStrongBoundary(s, targetEnd);
      if (strong != null && strong >= minChunkChars) {
        final chunk = s.substring(0, strong).trim();
        if (chunk.isNotEmpty) chunks.add(chunk);
        s = s.substring(strong).trimLeft();
        continue;
      }

      final shouldForceSplit =
          flush || s.length > (maxChunkChars + softLookAheadChars);
      if (!shouldForceSplit) break;

      final weak = _lastWeakBoundary(s, targetEnd);
      if (weak != null && weak >= minChunkChars) {
        final chunk = s.substring(0, weak).trim();
        if (chunk.isNotEmpty) chunks.add(chunk);
        s = s.substring(weak).trimLeft();
        continue;
      }

      final space = _lastWhitespace(s, targetEnd);
      final splitAt =
          (space != null && space >= minChunkChars) ? space : targetEnd;
      final chunk = s.substring(0, splitAt).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      s = s.substring(splitAt).trimLeft();
    }

    if (flush) {
      final tail = s.trim();
      if (tail.isNotEmpty) {
        chunks.add(tail);
        s = '';
      }
    }

    return (chunks: chunks, remainder: s);
  }

  static int? _lastWhitespace(String s, int maxExclusive) {
    final end = maxExclusive.clamp(0, s.length);
    for (var i = end - 1; i >= 0; i--) {
      final c = s.codeUnitAt(i);
      if (c == 32 || c == 9) return i;
    }
    return null;
  }

  static int? _lastWeakBoundary(String s, int maxExclusive) {
    final end = maxExclusive.clamp(0, s.length);
    for (var i = end - 1; i >= 0; i--) {
      final ch = s[i];
      if (ch == ',' || ch == ';' || ch == ':' || ch == '—' || ch == '-') {
        final next = i + 1;
        if (next < s.length && s[next] == ' ') return next;
        return i + 1;
      }
    }
    return null;
  }

  static int? _lastStrongBoundary(String s, int maxExclusive) {
    final end = maxExclusive.clamp(0, s.length);
    for (var i = end - 1; i >= 0; i--) {
      final ch = s[i];
      if (ch != '.' && ch != '!' && ch != '?' && ch != '…') continue;

      if (ch == '.' && _isLikelyAbbreviationDot(s, i)) continue;

      var j = i + 1;
      while (j < s.length) {
        final cj = s[j];
        if (cj == '"' ||
            cj == '\'' ||
            cj == '»' ||
            cj == '”' ||
            cj == ')' ||
            cj == ']') {
          j++;
          continue;
        }
        break;
      }

      if (j >= s.length) return j;
      if (s[j] == ' ') return j + 1;
      return j;
    }
    return null;
  }

  static bool _isLikelyAbbreviationDot(String s, int dotIndex) {
    if (dotIndex <= 0) return false;

    var i = dotIndex - 1;
    while (i >= 0 && s[i] == ' ') {
      i--;
    }
    if (i < 0) return false;

    var end = i + 1;
    while (i >= 0) {
      final ch = s[i];
      if (ch == ' ' ||
          ch == ',' ||
          ch == ';' ||
          ch == ':' ||
          ch == '—' ||
          ch == '-' ||
          ch == '(') {
        break;
      }
      i--;
    }
    final start = i + 1;
    final token = s.substring(start, end).toLowerCase();
    if (token.length <= 3 && _abbreviations.contains(token)) return true;
    return false;
  }
}
