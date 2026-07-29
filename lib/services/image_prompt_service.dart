import 'package:flutter/foundation.dart';

import '../models/image_generation_request.dart';
import '../models/preset_tag.dart';
import 'nutrition_analysis/deepseek/deepseek_client.dart';

/// Превращает короткую идею пользователя в детальный промпт для генератора.
abstract class ImagePromptService {
  Future<String?> buildPrompt(ImageGenerationRequest request);
}

/// Определяет категории галереи по готовому промпту.
abstract class PromptTagExtractor {
  Future<List<String>> extractTags(String prompt);
}

class DeepSeekImagePromptService
    implements ImagePromptService, PromptTagExtractor {
  DeepSeekImagePromptService({DeepSeekClient? client})
      : _client =
            client ?? DeepSeekClient.fromEnvironment(enableCaching: false);

  final DeepSeekClient _client;

  static const String _systemPrompt = '''
Ты — профессиональный промпт-инженер для генеративных моделей изображений (Gemini / Nano Banana). Пользователь описывает идею буквально несколькими словами. Твоя задача — превратить её в детальный промпт на русском языке, по которому модель гарантированно нарисует красивое и осмысленное изображение.

ОБЯЗАТЕЛЬНАЯ СТРУКТУРА (используй ровно эти заголовки, каждый с новой строки):

ГЛАВНЫЙ ОБЪЕКТ:
[2-3 предложения: что именно изображено в центре внимания, его форма, материал, состояние, действие. Максимально конкретно и визуально.]

ОКРУЖЕНИЕ И ФОН:
[1-3 предложения: где происходит сцена, что на заднем плане, глубина пространства, погода или время суток, если уместно.]

КОМПОЗИЦИЯ:
[1-2 предложения: план (крупный/средний/общий), ракурс камеры, точка съёмки, расположение объекта в кадре, что остаётся пустым.]

СВЕТ:
[1-2 предложения: источник и характер света, направление, тени, блики, контраст.]

ЦВЕТ И СТИЛЬ:
[1-2 предложения: художественный стиль и конкретные названия цветов палитры.]

ДЕТАЛИ:
[1-2 предложения: фактуры, материалы, мелкие объекты, которые делают картинку живой.]

ТЕХНИЧЕСКИЕ ПАРАМЕТРЫ:
[Уровень детализации, резкость, качество рендера/съёмки, соотношение сторон. Подбирай термины под стиль: для фото — объектив и диафрагма, для 3D — движок и глобальное освещение, для рисунка — техника и материал.]

ИЗБЕГАТЬ:
[Перечисли через запятую то, чего в кадре быть не должно: артефакты, лишние объекты, кривая анатомия, мусорный текст, водяные знаки.]

КРИТИЧЕСКИЕ ПРАВИЛА:
- Изображение может быть про что угодно: предмет, животное, пейзаж, еда, техника, абстракция, персонаж, интерьер, постер. НЕ превращай запрос в фотосессию человека.
- НЕ добавляй людей, если пользователь о них не просил.
- Не меняй суть идеи — только дополняй её конкретикой.
- Каждая деталь должна быть визуальной: «матовая керамика с трещинами глазури», а не «красивая посуда».
- Соблюдай заданные стиль, формат кадра и настроение — они приходят в запросе и приоритетнее твоих предпочтений.
- Если задана надпись — добавь после блока ДЕТАЛИ отдельный блок НАДПИСЬ: с точным текстом в кавычках, его расположением, шрифтом и цветом. Текст воспроизводится символ в символ на языке оригинала.
- Если надпись не задана — в блоке ИЗБЕГАТЬ обязательно укажи «любой текст и надписи».
- Выводи ТОЛЬКО промпт на русском языке. Без вступлений, без пояснений, без кавычек вокруг всего ответа.''';

  @override
  Future<String?> buildPrompt(ImageGenerationRequest request) async {
    final userPrompt = _buildUserMessage(request);

    try {
      final response = await _client.generateText('$_systemPrompt\n\n$userPrompt');
      final cleaned = _stripWrappers(response.trim());
      return cleaned.isEmpty ? null : cleaned;
    } catch (e) {
      debugPrint('ImagePromptService: $e');
      return null;
    }
  }

  String _buildUserMessage(ImageGenerationRequest request) {
    final parts = <String>[
      'Идея: ${request.idea.trim()}',
      request.style.promptDirective,
      'Формат кадра: ${request.format.label} '
          '(соотношение сторон ${request.aspectRatio}'
          '${request.format.isVertical ? ', вертикальный кадр' : ''}'
          '${request.format.isHorizontal ? ', горизонтальный кадр' : ''}).',
    ];

    final mood = request.mood.promptDirective;
    if (mood != null) parts.add(mood);

    final details = request.details?.trim();
    if (details != null && details.isNotEmpty) {
      parts.add('Дополнительные пожелания: $details');
    }

    final text = request.textOnImage?.trim();
    if (text != null && text.isNotEmpty) {
      parts.add('Надпись на изображении (воспроизвести дословно): «$text»');
    }

    if (request.hasReference) {
      parts.add(
        switch (request.referenceUsage) {
          ReferenceUsage.keepSubject =>
            'К запросу приложено изображение-референс. Главный объект берётся '
                'с этого изображения без изменений — НЕ описывай его внешность, '
                'лицо, форму и цвет, только новое окружение, свет и композицию '
                'вокруг него.',
          ReferenceUsage.keepStyle =>
            'К запросу приложено изображение-референс. С него берутся стиль, '
                'палитра, свет и композиция — опиши новую сцену в этой манере.',
        },
      );
    }

    return 'Собери промпт для генерации изображения по этим вводным:\n\n'
        '${parts.join('\n')}';
  }

  @override
  Future<List<String>> extractTags(String prompt) async {
    final vocabulary = PresetTag.generationTagIds;
    final systemPrompt = '''
Ты классифицируешь сгенерированные изображения по категориям галереи.

Доступные категории: ${vocabulary.join(', ')}

ПРАВИЛА:
- Выбери от 2 до 4 категорий, которые лучше всего описывают изображение по промпту.
- Используй ТОЛЬКО категории из списка.
- Ориентируйся на главный объект, окружение и стиль.
- Ответ строго в формате JSON: {"tags": ["категория1", "категория2"]}
- Без пояснений, только JSON.''';

    try {
      final response = await _client.generateText(
        '$systemPrompt\n\nПромпт изображения:\n\n$prompt',
      );
      final tags = _parseTags(response, vocabulary);
      if (tags.isNotEmpty) return tags;
    } catch (e) {
      debugPrint('ImagePromptService: ошибка извлечения тегов: $e');
    }
    return _fallbackTags(prompt, vocabulary);
  }

  static List<String> _parseTags(String response, List<String> vocabulary) {
    final match =
        RegExp(r'"tags"\s*:\s*\[([^\]]*)\]').firstMatch(response);
    if (match == null) return const [];
    final tags = <String>[];
    for (final quoted in RegExp(r'"([^"]+)"').allMatches(match.group(1) ?? '')) {
      final tag = quoted.group(1)!.toLowerCase().trim();
      if (vocabulary.contains(tag) && !tags.contains(tag)) tags.add(tag);
    }
    return tags.take(4).toList();
  }

  static const Map<String, List<String>> _tagKeywords = {
    'люди': ['человек', 'девушк', 'мужчин', 'женщин', 'ребён', 'ребен', 'персонаж', 'портрет'],
    'портрет': ['портрет', 'лицо', 'крупный план лица'],
    'животные': ['кот', 'кош', 'собак', 'птиц', 'зверь', 'животн', 'лис', 'волк', 'дракон'],
    'природа': ['лес', 'гор', 'море', 'океан', 'закат', 'поле', 'река', 'озеро', 'пейзаж', 'небо'],
    'город': ['город', 'улиц', 'небоскрёб', 'небоскреб', 'мегаполис', 'переулок'],
    'интерьер': ['комнат', 'интерьер', 'кухн', 'гостин', 'офис', 'спальн'],
    'еда': ['еда', 'блюдо', 'десерт', 'кофе', 'торт', 'фрукт', 'бургер', 'напиток'],
    'автомобили': ['автомобил', 'машин', 'спорткар', 'мотоцикл'],
    'техника': ['робот', 'гаджет', 'механизм', 'дрон', 'компьютер', 'техник'],
    'космос': ['космос', 'планет', 'галактик', 'звёзд', 'звезд', 'астронавт', 'орбит'],
    'фэнтези': ['фэнтези', 'магия', 'волшеб', 'эльф', 'замок', 'сказоч'],
    'аниме': ['аниме', 'манга'],
    'арт': ['иллюстрац', 'живопис', 'акварел', 'арт', 'рисунок', 'мазк'],
    '3d': ['3d', 'рендер', 'octane', 'blender'],
    'мода': ['мода', 'одежд', 'платье', 'подиум', 'стиль одежды'],
    'спорт': ['спорт', 'бег', 'футбол', 'тренировк', 'велосипед'],
    'бизнес': ['бизнес', 'офис', 'презентац', 'финанс'],
    'абстракция': ['абстракц', 'геометр', 'фрактал', 'паттерн'],
    'праздник': ['праздник', 'новый год', 'день рожден', 'открытк', 'фейерверк'],
    'цветы': ['цвет', 'букет', 'роз', 'пион', 'флорал'],
    'ретро': ['ретро', 'винтаж', 'плёнк', 'пленк', '80-х', '90-х'],
    'минимализм': ['минимализм', 'минималист', 'простые формы'],
    'логотип': ['логотип', 'иконк', 'эмблем', 'вектор'],
  };

  static List<String> _fallbackTags(String prompt, List<String> vocabulary) {
    final lower = prompt.toLowerCase();
    final found = <String>[];
    for (final entry in _tagKeywords.entries) {
      if (!vocabulary.contains(entry.key)) continue;
      if (entry.value.any(lower.contains)) found.add(entry.key);
      if (found.length == 4) break;
    }
    return found;
  }

  static String _stripWrappers(String value) {
    var text = value.trim();
    for (final quote in ['"', "'", '«']) {
      if (text.startsWith(quote) && text.length > 1) {
        text = text.substring(1).trim();
      }
    }
    for (final quote in ['"', "'", '»']) {
      if (text.endsWith(quote) && text.length > 1) {
        text = text.substring(0, text.length - 1).trim();
      }
    }
    for (final prefix in const ['Промпт:', 'Prompt:', 'Вот промпт:']) {
      if (text.toLowerCase().startsWith(prefix.toLowerCase())) {
        text = text.substring(prefix.length).trim();
        break;
      }
    }
    return text;
  }
}
