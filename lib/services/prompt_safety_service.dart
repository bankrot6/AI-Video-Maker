import 'package:flutter/foundation.dart';

import 'nutrition_analysis/deepseek/deepseek_client.dart';
import 'prompt_length_guard.dart';

/// Приводит промпт к формулировкам, которые не отвергает фильтр Responsible AI
/// у видеомодели. Замысел пользователя сохраняется — меняются только
/// двусмысленные места.
/// Правка добавляет возрасты и описания взамен имён, поэтому текст растёт —
/// [maxLength] задаёт потолок, в который обязан уложиться результат.
abstract class PromptSafetyService {
  /// Профилактическая нормализация перед первой отправкой в модель.
  Future<String?> normalize(String prompt, {required int maxLength});

  /// Более консервативная переформулировка после отказа модерации.
  Future<String?> relax(String prompt, {required int maxLength});
}

class DeepSeekPromptSafetyService implements PromptSafetyService {
  DeepSeekPromptSafetyService({DeepSeekClient? client})
      : _client = client ??
            DeepSeekClient.fromEnvironment(
              enableCaching: false,
              fastMode: true,
            );

  final DeepSeekClient _client;

  static const _tag = '🛡 PROMPT_SAFETY';

  /// Возраст людей — главный триггер фильтра: «девушка», «парень», «модель»
  /// без возраста читаются как возможные несовершеннолетние.
  static const String _normalizeInstruction = '''
Ты — редактор промптов для генеративной видеомодели Google Veo. Твоя задача — минимально переписать промпт пользователя так, чтобы его не отклонил фильтр безопасности, полностью сохранив замысел, стиль и все визуальные детали.

ЧТО ИСПРАВЛЯТЬ:
- Людям без указанного возраста добавь явный взрослый возраст: «девушка» → «молодая женщина, около 25 лет», «парень» → «молодой мужчина, около 30 лет». Возраст указывай всегда, даже если человек упомянут мимоходом.
- Имена реальных людей, знаменитостей и публичных персон заменяй нейтральным описанием внешности похожего типажа.
- Названия брендов, логотипы и защищённые персонажи заменяй нейтральными аналогами.
- Ракурсы, которые читаются как скрытая съёмка («вид сзади», «подглядывает», «незаметно»), переписывай как операторский приём: «камера следует за героиней в три четверти сзади».
- Формулировки об одежде и теле делай сдержанными и нейтральными, без акцента на обнажённости.
- Насилие, кровь, оружие в действии, травмы заменяй бескровными и безопасными эквивалентами.

ЧТО НЕЛЬЗЯ ДЕЛАТЬ:
- Не меняй сюжет, объекты, окружение, движение камеры, свет, палитру и звук.
- Не добавляй и не удаляй сцены и персонажей.
- Не сокращай промпт и не убирай технические детали.
- Текст в кавычках (надписи и реплики) переноси символ в символ.
- Не добавляй пояснений, заголовков и кавычек вокруг ответа.
- Если менять нечего — верни промпт без изменений.

Ответ: только готовый промпт на языке оригинала.''';

  static const String _relaxInstruction = '''
Ты — редактор промптов для генеративной видеомодели Google Veo. Предыдущая версия промпта была отклонена фильтром безопасности. Перепиши её заметно консервативнее, сохранив главную идею и визуальную привлекательность сцены.

ПРАВИЛА:
- Оставь ту же сцену, локацию, действие, свет и настроение.
- Всех людей описывай как взрослых с явным возрастом, в закрытой повседневной одежде, без акцента на теле и лице.
- Убери любые ракурсы, которые можно прочитать как съёмку без согласия.
- Убери любые упоминания реальных людей, брендов, насилия, оружия, откровенности и опасных действий.
- Если рискованный элемент нельзя переписать безопасно — замени его нейтральным визуальным аналогом, не выбрасывая сцену целиком.
- Текст в кавычках переноси символ в символ.
- Не добавляй пояснений и кавычек вокруг ответа.

Ответ: только готовый промпт на языке оригинала.''';

  @override
  Future<String?> normalize(String prompt, {required int maxLength}) =>
      _rewrite(prompt, _normalizeInstruction, 'нормализация', maxLength);

  @override
  Future<String?> relax(String prompt, {required int maxLength}) =>
      _rewrite(prompt, _relaxInstruction, 'смягчение', maxLength);

  Future<String?> _rewrite(
    String prompt,
    String instruction,
    String stage,
    int maxLength,
  ) async {
    final source = prompt.trim();
    if (source.isEmpty) return null;

    try {
      final response = await _client.generateText(
        '$instruction\n${PromptLengthGuard.instruction(maxLength)}'
        '\n\nПромпт:\n$source',
      );
      final cleaned = _stripWrappers(response.trim());
      if (cleaned.isEmpty) return null;
      // Модель иногда отвечает отказом вместо переписанного текста — такой
      // ответ отправлять в видеомодель нельзя.
      if (_looksLikeRefusal(cleaned)) {
        debugPrint('$_tag $stage: модель отказалась переписывать промпт');
        return null;
      }
      if (cleaned == source) return null;
      debugPrint('$_tag $stage: промпт переписан '
          '(${source.length} → ${cleaned.length} символов)');
      return PromptLengthGuard.enforce(
        cleaned,
        limit: maxLength,
        compress: _compress,
        tag: '$_tag $stage',
      );
    } catch (e) {
      debugPrint('$_tag $stage не удалась: $e');
      return null;
    }
  }

  /// Сжатие идёт той же моделью: она уже видела правила и не выкинет
  /// возрасты и нейтральные формулировки, ради которых промпт переписывался.
  Future<String?> _compress(String text, int limit) async {
    final response = await _client.generateText(
      '${PromptLengthGuard.compressionInstruction(limit)}\n'
      'Сохрани указанные возрасты людей и нейтральные формулировки — '
      'они нужны фильтру безопасности.\n\n$text',
    );
    return _stripWrappers(response.trim());
  }

  static const Set<String> _refusalMarkers = {
    'не могу',
    'не могу помочь',
    'извините',
    'i cannot',
    'i can\'t',
  };

  static bool _looksLikeRefusal(String value) {
    if (value.length > 200) return false;
    final lower = value.toLowerCase();
    return _refusalMarkers.any(lower.startsWith);
  }

  static String _stripWrappers(String value) {
    var text = value.trim();
    for (final prefix in const ['Промпт:', 'Prompt:', 'Вот промпт:']) {
      if (text.toLowerCase().startsWith(prefix.toLowerCase())) {
        text = text.substring(prefix.length).trim();
        break;
      }
    }
    const openQuotes = ['"', "'", '«'];
    const closeQuotes = ['"', "'", '»'];
    for (var i = 0; i < openQuotes.length; i++) {
      if (text.length > 1 &&
          text.startsWith(openQuotes[i]) &&
          text.endsWith(closeQuotes[i])) {
        text = text.substring(1, text.length - 1).trim();
      }
    }
    return text;
  }
}
