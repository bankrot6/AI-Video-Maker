import 'package:flutter/foundation.dart';

import '../models/image_generation_request.dart';
import '../models/preset_tag.dart';
import 'apibost_model_catalog.dart';
import 'nutrition_analysis/deepseek/deepseek_client.dart';
import 'prompt_length_guard.dart';

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

  /// Лимит подставляется из каталога моделей, а не пишется числом в тексте:
  /// иначе инструкция и реальный предел разъезжаются при смене модели.
  static final String _systemPrompt = _systemPromptTemplate.replaceFirst(
    _lengthLimitPlaceholder,
    PromptLengthGuard.instruction(_promptLimit),
  );

  static const int _promptLimit =
      ApiBostModelCatalog.videoPromptGenerationTarget;

  static const String _lengthLimitPlaceholder = '{{LENGTH_LIMIT}}';

  static const String _systemPromptTemplate = '''
Ты — профессиональный промпт-инженер для генеративных моделей видео (Google Veo 3.1). Пользователь описывает идею буквально несколькими словами. Твоя задача — превратить её в детальный промпт на русском языке, по которому модель гарантированно снимет красивый и осмысленный видеоролик.

ТЕХНИЧЕСКИЕ ОГРАНИЧЕНИЯ МОДЕЛИ (учитывай при построении промпта):
- Длительность клипа не больше 8 секунд — сцена должна полностью укладываться в этот отрезок. Не описывай длинные сюжеты, смены локаций и много последовательных событий.
- Один непрерывный кадр без монтажных склеек. Никаких «затем камера переходит», «в следующем кадре».
- Соотношение сторон приходит в запросе — учитывай его в композиции. Для вертикального кадра строй композицию по вертикали, для горизонтального — по горизонтали.
- Модель генерирует звук — его нужно описать явно.
- Не вставляй в текст промпта служебные директивы в квадратных скобках вида [9:16] или [8s] — их подставляет приложение.
- {{LENGTH_LIMIT}}

ОБЯЗАТЕЛЬНАЯ СТРУКТУРА (используй ровно эти заголовки, каждый с новой строки):

ГЛАВНЫЙ ОБЪЕКТ:
[2-3 предложения: что именно в центре внимания, форма, материал, состояние. Максимально конкретно и визуально.]

ДЕЙСТВИЕ И ДВИЖЕНИЕ:
[2-3 предложения: что происходит в течение 8 секунд, как двигается объект, с какой скоростью, как меняется его состояние от начала к концу клипа. Одно непрерывное действие.]

ОКРУЖЕНИЕ И ФОН:
[1-3 предложения: где происходит сцена, что на заднем плане, глубина пространства, погода или время суток, движение среды — ветер, вода, пыль, дождь.]

КАМЕРА:
[1-2 предложения: план (крупный/средний/общий), ракурс, и обязательно движение камеры — статичный кадр, медленный наезд, отъезд, панорама, облёт, следование за объектом. Скорость движения камеры.]

СВЕТ:
[1-2 предложения: источник и характер света, направление, тени, блики, контраст, изменение света во времени, если уместно.]

ЦВЕТ И СТИЛЬ:
[1-2 предложения: визуальный стиль и конкретные названия цветов палитры.]

ДЕТАЛИ:
[1-2 предложения: фактуры, материалы, мелкие объекты, которые делают кадр живым.]

ЗВУК:
[1-2 предложения: фоновая среда, конкретные шумы объекта, музыка или её отсутствие. Если в кадре есть говорящий человек — приведи короткую реплику в кавычках, иначе укажи «без речи».]

ТЕХНИЧЕСКИЕ ПАРАМЕТРЫ:
[Качество съёмки, объектив, глубина резкости, частота кадров, плавность движения. Подбирай термины под стиль: для съёмки — камера и оптика, для 3D — движок и рендер, для анимации — техника.]

ИЗБЕГАТЬ:
[Перечисли через запятую то, чего быть не должно: монтажные склейки, рывки и дёргание движения, деформация объекта между кадрами, мерцание, лишние конечности, мусорный текст, водяные знаки, титры.]

КРИТИЧЕСКИЕ ПРАВИЛА:
- Видео может быть про что угодно: предмет, животное, пейзаж, еда, техника, абстракция, персонаж, интерьер. НЕ превращай запрос в съёмку человека.
- НЕ добавляй людей, если пользователь о них не просил.
- Фильтр безопасности Veo отклоняет промпт, если человек описан без возраста. Каждому человеку в кадре указывай явный взрослый возраст («молодая женщина, около 25 лет»), одежду описывай сдержанно, а ракурсы формулируй как операторский приём, а не как скрытую съёмку. Не упоминай реальных людей, знаменитостей, бренды, оружие и насилие.
- Не меняй суть идеи — только дополняй её конкретикой.
- Каждая деталь должна быть визуальной: «матовая керамика с трещинами глазури», а не «красивая посуда».
- Движение обязательно должно быть в промпте: статичная картинка без изменений — плохой результат для видео.
- Соблюдай заданные стиль и настроение — они приходят в запросе и приоритетнее твоих предпочтений.
- Если задана надпись — добавь после блока ДЕТАЛИ отдельный блок НАДПИСЬ: с точным текстом в кавычках, его расположением, шрифтом и цветом. Текст воспроизводится символ в символ на языке оригинала.
- Если надпись не задана — в блоке ИЗБЕГАТЬ обязательно укажи «любой текст и надписи».
- Выводи ТОЛЬКО промпт на русском языке. Без вступлений, без пояснений, без кавычек вокруг всего ответа.''';

  @override
  Future<String?> buildPrompt(ImageGenerationRequest request) async {
    final userPrompt = _buildUserMessage(request);

    try {
      final response = await _client.generateText('$_systemPrompt\n\n$userPrompt');
      final cleaned = _stripWrappers(response.trim());
      if (cleaned.isEmpty) return null;
      return PromptLengthGuard.enforce(
        cleaned,
        limit: _promptLimit,
        compress: _compress,
        tag: 'ImagePromptService',
      );
    } catch (e) {
      debugPrint('ImagePromptService: $e');
      return null;
    }
  }

  Future<String?> _compress(String text, int limit) async {
    final response = await _client.generateText(
      '${PromptLengthGuard.compressionInstruction(limit)}\n\n$text',
    );
    return _stripWrappers(response.trim());
  }

  String _buildUserMessage(ImageGenerationRequest request) {
    // Veo поддерживает только 16:9, 9:16, 1:1 и 21:9, поэтому в промпт уходит
    // уже приведённое значение — то же, что подставится директивой в запросе.
    final videoAspectRatio =
        ApiBostModelCatalog.videoAspectRatioFor(request.aspectRatio);
    final parts = <String>[
      'Идея: ${request.idea.trim()}',
      request.style.promptDirective,
      'Формат кадра: ${request.format.label} '
          '(соотношение сторон $videoAspectRatio'
          '${request.format.isVertical ? ', вертикальный кадр' : ''}'
          '${request.format.isHorizontal ? ', горизонтальный кадр' : ''}), '
          'длительность до 8 секунд.',
    ];

    final mood = request.mood.promptDirective;
    if (mood != null) parts.add(mood);

    final details = request.details?.trim();
    if (details != null && details.isNotEmpty) {
      parts.add('Дополнительные пожелания: $details');
    }

    final text = request.textOnImage?.trim();
    if (text != null && text.isNotEmpty) {
      parts.add('Надпись в кадре (воспроизвести дословно): «$text»');
    }

    if (request.hasReference) {
      parts.add(
        switch (request.referenceUsage) {
          ReferenceUsage.keepSubject =>
            'К запросу приложен кадр-источник, который модель будет оживлять. '
                'Главный объект берётся с этого кадра без изменений — НЕ описывай '
                'его внешность, лицо, форму и цвет. Опиши только движение объекта, '
                'движение камеры, изменение света и звук.',
          ReferenceUsage.keepStyle =>
            'К запросу приложен кадр-референс. С него берутся стиль, палитра, '
                'свет и композиция — опиши новую сцену в этой манере, добавив '
                'движение объекта и камеры.',
        },
      );
    }

    return 'Собери промпт для генерации видео по этим вводным:\n\n'
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
