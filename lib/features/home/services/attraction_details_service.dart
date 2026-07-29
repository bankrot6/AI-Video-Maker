import 'dart:convert';

import 'package:flutter/material.dart';
import '../models/attraction_info.dart';
import '../models/attraction_place.dart';
import '../../../services/nutrition_analysis/deepseek/deepseek_client.dart';

class AttractionDetailsService {
  final DeepSeekClient _client;

  AttractionDetailsService({DeepSeekClient? client})
      : _client = client ?? DeepSeekClient.fromEnvironment();

  Future<AttractionInfo> analyzeAttraction(
    String attractionName,
    String category, {
    BuildContext? context,
  }) async {
    debugPrint('🏛️ ATTRACTION_ANALYZER: ===== НАЧАЛО АНАЛИЗА МЕСТА =====');
    debugPrint('🏛️ ATTRACTION_ANALYZER: Место: "$attractionName"');
    debugPrint('🏛️ ATTRACTION_ANALYZER: Категория: "$category"');

    try {
      final language = _determineLanguage(context);

      final prompt = _buildAttractionAnalysisPrompt(
        attractionName,
        category,
        language,
      );

      debugPrint(
          '🏛️ ATTRACTION_ANALYZER: ===== ОТПРАВКА ЗАПРОСА К DEEPSEEK =====');
      debugPrint(
          '🏛️ ATTRACTION_ANALYZER: Размер промпта: ${prompt.length} символов');

      final response = await _client.generateText(prompt);

      debugPrint(
          '🏛️ ATTRACTION_ANALYZER: ===== ПОЛУЧЕН ОТВЕТ ОТ DEEPSEEK =====');
      debugPrint(
          '🏛️ ATTRACTION_ANALYZER: Размер ответа: ${response.length} символов');

      final attractionInfo = _parseAttractionResponse(
        response,
        attractionName,
        null,
      );

      debugPrint('🏛️ ATTRACTION_ANALYZER: ===== АНАЛИЗ ЗАВЕРШЕН =====');
      debugPrint('🏛️ ATTRACTION_ANALYZER: Результат: ${attractionInfo.name}');

      return attractionInfo;
    } catch (e) {
      debugPrint('❌ ATTRACTION_ANALYZER: Ошибка при анализе: $e');
      return AttractionInfo.empty().copyWith(
        name: attractionName,
        error: e.toString(),
      );
    }
  }

  Stream<AttractionInfo> analyzeAttractionStream(
    String attractionName,
    String category, {
    BuildContext? context,
  }) async* {
    debugPrint(
        '🏛️ ATTRACTION_ANALYZER_STREAM: ===== НАЧАЛО ПОТОКОВОГО АНАЛИЗА =====');
    debugPrint('🏛️ ATTRACTION_ANALYZER_STREAM: Место: "$attractionName"');

    try {
      final language = _determineLanguage(context);

      final prompt = _buildAttractionAnalysisPrompt(
        attractionName,
        category,
        language,
      );

      debugPrint(
          '🏛️ ATTRACTION_ANALYZER_STREAM: ===== ОТПРАВКА ЗАПРОСА К DEEPSEEK =====');

      String accumulatedResponse = '';

      await for (final chunk in _client.generateTextStream(prompt)) {
        accumulatedResponse += chunk;

        final partialInfo = _parseAttractionResponse(
          accumulatedResponse,
          attractionName,
          context,
          isPartial: true,
        );

        yield partialInfo;
      }

      debugPrint('🏛️ ATTRACTION_ANALYZER_STREAM: ===== АНАЛИЗ ЗАВЕРШЕН =====');
    } catch (e) {
      debugPrint('❌ ATTRACTION_ANALYZER_STREAM: Ошибка при анализе: $e');
      yield AttractionInfo.empty().copyWith(
        name: attractionName,
        error: e.toString(),
      );
    }
  }

  Future<List<AttractionInfo>> analyzeAttractionsBatch(
    List<AttractionPlace> places, {
    BuildContext? context,
  }) async {
    if (places.isEmpty) return const <AttractionInfo>[];

    try {
      final language = _determineLanguage(context);
      final prompt = _buildBatchPrompt(places, language);
      final response = await _client.generateText(prompt);
      final jsonString = _extractFirstJsonValue(response);
      if (jsonString == null) {
        return places
            .map((p) => AttractionInfo.empty().copyWith(
                  name: p.name,
                  error: 'Не удалось извлечь JSON',
                ))
            .toList(growable: false);
      }

      final decoded = jsonDecode(jsonString);
      if (decoded is! List) {
        return places
            .map((p) => AttractionInfo.empty().copyWith(
                  name: p.name,
                  error: 'JSON не является массивом',
                ))
            .toList(growable: false);
      }

      final byKey = <String, AttractionPlace>{};
      for (final p in places) {
        byKey[_nameKey(p.name)] = p;
      }

      final out = <AttractionInfo>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final name = (map['name'] ?? '').toString();
        final key = _nameKey(name);
        if (key.isEmpty) continue;
        final original = byKey[key];
        if (original == null) continue;

        out.add(
          AttractionInfo(
            name: original.name,
            history: (map['history'] ?? '').toString(),
            historicalPeriods: '',
            architecturalDetails: (map['architecture'] ?? '').toString(),
            culturalSignificance: '',
            interestingFacts: (map['secrets'] ?? '').toString(),
            legendsAndStories: '',
            famousPeople: '',
            importantEvents: '',
            evolution: '',
            currentState: '',
            practicalInfo: (map['visit'] ?? '').toString(),
            photographyTips: '',
            bestViewpoints: '',
            nearbyAttractions: '',
            recommendation: '',
            imageUrl: null,
            error: null,
          ),
        );
      }

      // если часть мест не пришла — вернём пустышки, чтобы вызывающий мог fallback’нуть
      final seen = out.map((e) => _nameKey(e.name)).toSet();
      for (final p in places) {
        if (!seen.contains(_nameKey(p.name))) {
          out.add(AttractionInfo.empty().copyWith(
            name: p.name,
            error: 'Нет результата в batch ответе',
          ));
        }
      }

      return out;
    } catch (e) {
      return places
          .map((p) => AttractionInfo.empty().copyWith(
                name: p.name,
                error: e.toString(),
              ))
          .toList(growable: false);
    }
  }

  String _buildBatchPrompt(List<AttractionPlace> places, String language) {
    final items = places.map((p) => '- "${p.name}" (${p.category})').join('\n');

    return '''
Ты легендарный гид. Сгенерируй экскурсионные тексты для нескольких мест.

КРИТИЧЕСКИ ВАЖНО:
- Пиши ТОЛЬКО на языке: $language
- НИКАКИХ списков, буллетов, нумерации внутри текстов секций (только связный текст)
- Верни ТОЛЬКО JSON массив, без пояснений и без Markdown

Места:
$items

Формат JSON (строго):
[
  {
    "name": "точно как в списке мест",
    "visit": "советы для посещения (связный текст)",
    "history": "история (связный текст)",
    "architecture": "архитектура (связный текст)",
    "secrets": "секреты и факты (связный текст)"
  }
]
''';
  }

  static String _nameKey(String value) =>
      value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  String? _extractFirstJsonValue(String text) {
    final codeBlock = RegExp(r'```(?:json)?(.*?)```', dotAll: true);
    final match = codeBlock.firstMatch(text);
    final input = match?.group(1)?.trim() ?? text.trim();

    final startBrace = input.indexOf('{');
    final startBracket = input.indexOf('[');
    final start = _minPositive(startBrace, startBracket);
    if (start == -1) return null;

    final opener = input[start];
    if (opener != '{' && opener != '[') return null;

    final stack = <String>[opener];
    var inString = false;
    var escape = false;

    for (var i = start + 1; i < input.length; i++) {
      final ch = input[i];

      if (inString) {
        if (escape) {
          escape = false;
          continue;
        }
        if (ch == r'\') {
          escape = true;
          continue;
        }
        if (ch == '"') inString = false;
        continue;
      }

      if (ch == '"') {
        inString = true;
        continue;
      }
      if (ch == '{' || ch == '[') {
        stack.add(ch);
        continue;
      }
      if (ch == '}' || ch == ']') {
        if (stack.isEmpty) continue;
        final last = stack.last;
        final isMatch =
            (last == '{' && ch == '}') || (last == '[' && ch == ']');
        if (!isMatch) return null;
        stack.removeLast();
        if (stack.isEmpty) {
          final candidate = input.substring(start, i + 1);
          try {
            jsonDecode(candidate);
            return candidate;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  int _minPositive(int a, int b) {
    if (a == -1) return b;
    if (b == -1) return a;
    return a < b ? a : b;
  }

  String _determineLanguage(BuildContext? context) {
    if (context == null) return 'ru';

    final locale = Localizations.localeOf(context);

    return locale.languageCode;
  }

  String _buildAttractionAnalysisPrompt(
    String attractionName,
    String category,
    String language,
  ) {
    return '''
Ты легендарный гид с 30-летним опытом, автор книг о достопримечательностях. Проведи МАКСИМАЛЬНО ПОДРОБНУЮ экскурсию по месту "$attractionName" ($category).

КРИТИЧЕСКИ ВАЖНО: Пиши ТОЛЬКО на языке: $language. Пиши ОЧЕНЬ ПОДРОБНО - это должна быть полноценная экскурсия на 15-20 минут! Никаких списков - только живой увлекательный рассказ!

Используй ТОЛЬКО эти 4 секции В УКАЗАННОМ ПОРЯДКЕ, пиши в каждой МАКСИМАЛЬНО МНОГО:

VISIT:
Дай ИСЧЕРПЫВАЮЩИЕ практические советы для идеального посещения. Опиши лучшее время года, день недели и время суток для визита с объяснением почему. Расскажи откуда открываются лучшие виды для фотографий. Укажи сколько времени нужно на полноценный осмотр. Перечисли что ОБЯЗАТЕЛЬНО нужно увидеть и сделать. Дай советы по одежде и обуви. Расскажи о ближайших кафе и ресторанах где можно перекусить. Опиши что интересного находится рядом и стоит посетить вместе. Дай советы как избежать толп и очередей. Упомяни о доступности для людей с ограниченными возможностями. Заверши эмоциональной личной рекомендацией почему это место обязательно к посещению. Пиши МИНИМУМ 12-15 предложений связным текстом!

HISTORY:
Расскажи ПОЛНУЮ И ПОДРОБНУЮ историю этого места как захватывающий исторический роман. Начни с предыстории: что было на этом месте до появления достопримечательности, какие события привели к её созданию. Подробно опиши основание: кто именно создал, в каком году, при каких политических и социальных обстоятельствах, кто финансировал, сколько времени заняло строительство. Расскажи о каждом значимом периоде в истории места: как оно развивалось, какие изменения претерпевало, какие исторические события здесь происходили. Упомяни всех известных людей, которые здесь бывали, и что они здесь делали. Опиши, как место пережило войны, революции, смены власти. Расскажи о реставрациях и перестройках. Свяжи историю места с историей города, страны и мировой историей. Добавь малоизвестные исторические факты и анекдоты из прошлого. Пиши МИНИМУМ 35-40 предложений связным увлекательным текстом!

ARCHITECTURE:
Проведи ДЕТАЛЬНЫЙ архитектурный анализ как профессиональный искусствовед. Определи и подробно опиши архитектурный стиль или смешение стилей. Расскажи об архитекторе: его биографию, другие известные работы, почему именно он был выбран. Опиши конструктивные особенности: фундамент, стены, крышу, материалы и технологии строительства. Детально разбери фасад: каждый декоративный элемент, колонны, арки, окна, двери, скульптуры, барельефы. Опиши интерьеры если они доступны. Расскажи о символике архитектурных элементов. Сравни с другими похожими зданиями в мире. Опиши, как здание менялось со временем, какие элементы были добавлены или утрачены. Пиши МИНИМУМ 25-30 предложений связным текстом!

SECRETS:
Поделись ВСЕМИ секретами и малоизвестными фактами как гид-старожил, который знает ВСЁ. Расскажи городские легенды и мифы, связанные с этим местом. Поведай о призраках и мистических историях если такие есть. Опиши скрытые детали, которые 99% туристов не замечают. Расскажи забавные и курьёзные случаи из истории места. Упомяни о съёмках фильмов или музыкальных клипов здесь. Расскажи что знают только местные жители. Поделись интересными числами и рекордами. Опиши тайные проходы, скрытые комнаты, секретные символы если они есть. Добавь удивительные совпадения и необъяснимые факты. Пиши МИНИМУМ 25-35 предложений связным текстом!

АБСОЛЮТНО КРИТИЧЕСКИ ВАЖНО:
- Пиши МАКСИМАЛЬНО ПОДРОБНО в каждой секции!
- ТОЛЬКО связный текст, НИКАКИХ списков, буллетов, нумерации!
- Используй яркий, эмоциональный, увлекательный язык настоящего гида!
- Начинай СРАЗУ с VISIT: без вступлений и приветствий!
''';
  }

  AttractionInfo _parseAttractionResponse(
    String response,
    String originalName,
    BuildContext? context, {
    bool isPartial = false,
  }) {
    try {
      // 4 секции в новом порядке: VISIT -> HISTORY -> ARCHITECTURE -> SECRETS
      final visit = _extractSection(response, 'VISIT:', 'HISTORY:');
      final history = _extractSection(response, 'HISTORY:', 'ARCHITECTURE:');
      final architecture =
          _extractSection(response, 'ARCHITECTURE:', 'SECRETS:');
      final secrets = _extractSection(response, 'SECRETS:', null);

      if (isPartial &&
          history.isEmpty &&
          architecture.isEmpty &&
          secrets.isEmpty &&
          visit.isEmpty) {
        return AttractionInfo.empty().copyWith(name: originalName);
      }

      return AttractionInfo(
        name: originalName,
        history: history,
        historicalPeriods: '',
        architecturalDetails: architecture,
        culturalSignificance: '',
        interestingFacts: secrets,
        legendsAndStories: '',
        famousPeople: '',
        importantEvents: '',
        evolution: '',
        currentState: '',
        practicalInfo: visit,
        photographyTips: '',
        bestViewpoints: '',
        nearbyAttractions: '',
        recommendation: '',
      );
    } catch (e) {
      debugPrint('❌ ATTRACTION_ANALYZER: Ошибка парсинга: $e');
      if (isPartial) {
        return AttractionInfo.empty().copyWith(name: originalName);
      }
      return AttractionInfo.empty().copyWith(
        name: originalName,
        error: e.toString(),
      );
    }
  }

  String _extractSection(String text, String startMarker, String? endMarker) {
    try {
      final startIndex = text.indexOf(startMarker);
      if (startIndex == -1) return '';

      final contentStart = startIndex + startMarker.length;

      int contentEnd;
      if (endMarker != null) {
        contentEnd = text.indexOf(endMarker, contentStart);
        if (contentEnd == -1) {
          contentEnd = text.length;
        }
      } else {
        contentEnd = text.length;
      }

      final content = text.substring(contentStart, contentEnd).trim();
      return content;
    } catch (e) {
      debugPrint(
          '❌ ATTRACTION_ANALYZER: Ошибка извлечения секции $startMarker: $e');
      return '';
    }
  }
}
