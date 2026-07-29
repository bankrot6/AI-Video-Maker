import 'package:flutter/material.dart';
import '../models/location_overview_info.dart';
import '../../../services/nutrition_analysis/deepseek/deepseek_client.dart';

class LocationOverviewService {
  final DeepSeekClient _client;

  LocationOverviewService({DeepSeekClient? client})
      : _client = client ?? DeepSeekClient.fromEnvironment();

  Future<LocationOverviewInfo> analyzeLocation(
    String locationName, {
    BuildContext? context,
  }) async {
    try {
      final language = _determineLanguage(context);
      final prompt = _buildLocationAnalysisPrompt(locationName, language);
      final response = await _client.generateText(prompt);
      return _parseLocationResponse(
        response,
        locationName,
        null,
        isPartial: false,
      );
    } catch (e) {
      return LocationOverviewInfo.empty().copyWith(
        name: locationName,
        error: e.toString(),
      );
    }
  }

  Stream<LocationOverviewInfo> analyzeLocationStream(
    String locationName, {
    BuildContext? context,
  }) async* {
    debugPrint(
        '🌍 LOCATION_OVERVIEW: ===== НАЧАЛО ПОТОКОВОГО АНАЛИЗА ЛОКАЦИИ =====');
    debugPrint('🌍 LOCATION_OVERVIEW: Локация: "$locationName"');

    try {
      final language = _determineLanguage(context);

      final prompt = _buildLocationAnalysisPrompt(
        locationName,
        language,
      );

      debugPrint(
          '🌍 LOCATION_OVERVIEW: ===== ОТПРАВКА ЗАПРОСА К DEEPSEEK =====');

      String accumulatedResponse = '';

      await for (final chunk in _client.generateTextStream(prompt)) {
        accumulatedResponse += chunk;

        final partialInfo = _parseLocationResponse(
          accumulatedResponse,
          locationName,
          context,
          isPartial: true,
        );

        yield partialInfo;
      }

      debugPrint('🌍 LOCATION_OVERVIEW: ===== АНАЛИЗ ЗАВЕРШЕН =====');
    } catch (e) {
      debugPrint('❌ LOCATION_OVERVIEW: Ошибка при анализе: $e');
      yield LocationOverviewInfo.empty().copyWith(
        name: locationName,
        error: e.toString(),
      );
    }
  }

  String _determineLanguage(BuildContext? context) {
    if (context == null) return 'ru';

    final locale = Localizations.localeOf(context);

    return locale.languageCode;
  }

  String _buildLocationAnalysisPrompt(
    String locationName,
    String language,
  ) {
    return '''
Ты легендарный гид с 30-летним опытом работы, автор книг-путеводителей. Проведи МАКСИМАЛЬНО ПОДРОБНУЮ обзорную экскурсию по месту: "$locationName".

КРИТИЧЕСКИ ВАЖНО: Пиши ТОЛЬКО на языке: $language. Пиши ОЧЕНЬ ПОДРОБНО - это должна быть полноценная обзорная экскурсия на 20-25 минут! Никаких списков - только живой увлекательный рассказ!

Используй ТОЛЬКО эти 5 секций В УКАЗАННОМ ПОРЯДКЕ, пиши в каждой МАКСИМАЛЬНО МНОГО:

GENERAL:
Дай ПОЛНОЕ и ПОДРОБНОЕ общее представление о месте. Опиши географическое положение, климат, размеры территории. Расскажи чем известно это место в мире. Объясни почему туристы сюда приезжают. Опиши общую атмосферу и характер места. Расскажи о населении и местных жителях. Упомяни главные районы и кварталы. Опиши транспортную доступность. Расскажи о лучшем времени для посещения с подробными объяснениями почему. Дай общие впечатления о месте глазами опытного путешественника. Пиши МИНИМУМ 20-25 предложений связным текстом!

HISTORY:
Расскажи ПОЛНУЮ И ДЕТАЛЬНУЮ историю этого места как захватывающий исторический роман. Начни с древних времен: что было на этой территории тысячи лет назад, какие народы здесь жили. Подробно опиши основание города или формирование региона: когда, кем, при каких обстоятельствах. Расскажи о средневековье и более поздних периодах. Опиши все значимые исторические события, которые здесь происходили: войны, революции, смены власти, важные договоры и встречи. Упомяни всех известных исторических личностей, связанных с этим местом. Расскажи как место развивалось через века, как менялся его облик и значение. Опиши роль места в истории страны и мира. Добавь малоизвестные исторические факты и увлекательные исторические анекдоты. Свяжи историю места с мировыми историческими процессами. Пиши МИНИМУМ 40-45 предложений связным увлекательным текстом!

CULTURE:
Проведи ГЛУБОКИЙ культурологический анализ этого места. Подробно опиши культурное наследие и традиции. Расскажи о местной кухне: традиционные блюда, где их попробовать, история местной гастрономии. Опиши праздники и фестивали, которые здесь проводятся. Расскажи о музеях, театрах, концертных залах. Упомяни известных художников, писателей, музыкантов, связанных с этим местом. Опиши архитектурный облик: преобладающие стили, известные здания, уникальные архитектурные черты. Расскажи о местном менталитете и образе жизни. Опиши народные промыслы и ремесла. Упомяни о религиозных традициях и храмах. Расскажи о вкладе этого места в мировую культуру. Опиши современную культурную жизнь. Пиши МИНИМУМ 30-35 предложений связным текстом!

SECRETS:
Поделись ВСЕМИ секретами, легендами и малоизвестными фактами как гид-старожил. Расскажи все городские легенды и мифы этого места. Поведай о мистических историях, привидениях и загадочных событиях. Опиши скрытые места, которые знают только местные жители. Расскажи забавные и курьёзные истории из жизни места. Упомяни о съёмках известных фильмов здесь. Расскажи о необычных традициях и обычаях. Поделись секретными смотровыми площадками с лучшими видами. Опиши тайные места для фотографий. Расскажи о малоизвестных достопримечательностях, которые пропускают туристы. Добавь удивительные факты и рекорды. Упомяни о знаменитых гостях этого места. Пиши МИНИМУМ 25-30 предложений связным текстом!

VISIT:
Дай ИСЧЕРПЫВАЮЩИЕ практические рекомендации для идеального путешествия. Опиши как лучше добраться (самолет, поезд, автомобиль). Расскажи о размещении: какие районы лучше для проживания и почему. Дай советы по бюджету: сколько денег нужно на день. Опиши транспорт: как передвигаться внутри, какие есть варианты. Перечисли ТОП достопримечательностей, которые нельзя пропустить, с кратким описанием каждой. Посоветуй лучшие рестораны и кафе местной кухни. Расскажи о сувенирах: что привезти и где покупать. Дай советы по безопасности. Упомяни о языковом барьере и как с ним справиться. Расскажи о местном этикете и правилах поведения. Опиши идеальный маршрут на 2-3 дня. Заверши эмоциональной личной рекомендацией почему это место обязательно нужно посетить. Пиши МИНИМУМ 25-30 предложений связным текстом!

АБСОЛЮТНО КРИТИЧЕСКИ ВАЖНО:
- Пиши МАКСИМАЛЬНО ПОДРОБНО в каждой секции!
- ТОЛЬКО связный текст, НИКАКИХ списков, буллетов, нумерации!
- Используй яркий, эмоциональный, увлекательный язык настоящего гида!
- Начинай СРАЗУ с GENERAL: без вступлений и приветствий!
''';
  }

  LocationOverviewInfo _parseLocationResponse(
    String response,
    String originalName,
    BuildContext? context, {
    bool isPartial = false,
  }) {
    try {
      final general = _extractSection(response, 'GENERAL:', 'HISTORY:');
      final history = _extractSection(response, 'HISTORY:', 'CULTURE:');
      final culture = _extractSection(response, 'CULTURE:', 'SECRETS:');
      final secrets = _extractSection(response, 'SECRETS:', 'VISIT:');
      final visit = _extractSection(response, 'VISIT:', null);

      if (isPartial &&
          general.isEmpty &&
          history.isEmpty &&
          culture.isEmpty &&
          secrets.isEmpty &&
          visit.isEmpty) {
        return LocationOverviewInfo.empty().copyWith(name: originalName);
      }

      return LocationOverviewInfo(
        name: originalName,
        generalInfo: general,
        history: history,
        culture: culture,
        interestingFacts: secrets,
        practicalInfo: visit,
      );
    } catch (e) {
      debugPrint('❌ LOCATION_OVERVIEW: Ошибка парсинга: $e');
      if (isPartial) {
        return LocationOverviewInfo.empty().copyWith(name: originalName);
      }
      return LocationOverviewInfo.empty().copyWith(
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
          '❌ LOCATION_OVERVIEW: Ошибка извлечения секции $startMarker: $e');
      return '';
    }
  }
}











