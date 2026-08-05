import 'package:flutter/foundation.dart';

/// Просит модель сократить текст до [limit] символов, сохранив структуру.
/// Возвращает `null`, если сжать не удалось.
typedef PromptCompressor = Future<String?> Function(String text, int limit);

/// Держит промпт в пределах лимита модели.
///
/// Обрезка на стороне клиента — крайняя мера: она выбрасывает то, за что уже
/// заплачено токенами, и может срезать важную часть замысла. Поэтому лимит
/// сначала объявляется автору текста ([instruction]), затем результат
/// проверяется ([fits]) и при перерасходе пересобирается моделью
/// ([PromptCompressor]). Механическая обрезка остаётся только страховкой на
/// случай, когда и сжатие не помогло.
abstract final class PromptLengthGuard {
  /// Строка для системного промпта генератора. Лимит называется числом, иначе
  /// модель ориентируется на «покороче» и стабильно промахивается.
  static String instruction(int limit) =>
      'Жёсткий лимит длины: весь ответ не длиннее $limit символов вместе с '
      'заголовками и переносами строк. Более длинный текст модель не примет. '
      'Держись нижней границы диапазонов предложений, пиши плотно, '
      'без повторов и общих слов.';

  static String compressionInstruction(int limit) =>
      'Сократи текст ниже до $limit символов или меньше. Сохрани все разделы '
      'и их заголовки, сюжет, движение камеры, свет, звук и стиль. Убирай '
      'только повторы, общие слова и второстепенные уточнения. '
      'Ответ: только сокращённый текст, без пояснений и кавычек.';

  static bool fits(String text, int limit) => text.trim().length <= limit;

  /// Приводит [text] к лимиту: сначала силами модели, и только потом обрезкой.
  static Future<String> enforce(
    String text, {
    required int limit,
    PromptCompressor? compress,
    String tag = '✂️ PROMPT_LIMIT',
  }) async {
    final source = text.trim();
    if (limit <= 0 || source.length <= limit) return source;

    if (compress != null) {
      try {
        final compressed = (await compress(source, limit))?.trim();
        if (compressed != null && compressed.isNotEmpty) {
          if (compressed.length <= limit) {
            debugPrint('$tag сжат моделью: ${source.length} → '
                '${compressed.length} символов (лимит $limit)');
            return compressed;
          }
          debugPrint('$tag сжатие не уложилось в лимит: '
              '${compressed.length} > $limit');
          // Даже неудачное сжатие ближе к лимиту, чем оригинал, — обрезать
          // придётся меньше.
          if (compressed.length < source.length) {
            return trimToBoundary(compressed, limit, tag: tag);
          }
        }
      } catch (e) {
        debugPrint('$tag сжатие не удалось: $e');
      }
    }

    return trimToBoundary(source, limit, tag: tag);
  }

  /// Рез по границе блока или предложения, чтобы модель не получила
  /// оборванную на полуслове фразу.
  static String trimToBoundary(
    String text,
    int limit, {
    String tag = '✂️ PROMPT_LIMIT',
  }) {
    if (limit <= 0) return '';
    final source = text.trim();
    if (source.length <= limit) return source;

    final head = source.substring(0, limit);
    for (final separator in const ['\n\n', '\n', '. ', '.', ' ']) {
      final cut = head.lastIndexOf(separator);
      if (cut > limit ~/ 2) {
        final trimmed = head.substring(0, cut).trimRight();
        if (trimmed.isNotEmpty) {
          debugPrint('$tag обрезан до ${trimmed.length} символов '
              '(исходно ${source.length}, лимит $limit)');
          return trimmed;
        }
      }
    }
    return head.trimRight();
  }
}
