import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../services/nutrition_analysis/deepseek/deepseek_client.dart';
import '../models/attraction_place.dart';
import '../models/attraction_route.dart';

class AttractionAiService {
  final DeepSeekClient _client;
  final DeepSeekClient _fastClient;

  AttractionAiService({DeepSeekClient? client, DeepSeekClient? fastClient})
      : _client = client ??
            DeepSeekClient.fromEnvironment(
              fastMode: false,
              returnEmptyOnError: true,
            ),
        _fastClient = fastClient ??
            DeepSeekClient.fromEnvironment(
              fastMode: true,
              returnEmptyOnError: true,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 30),
            );

  Stream<List<AttractionRoute>> fetchRoutesStream({
    required double latitude,
    required double longitude,
    String? cityHint,
    int routesCount = 3,
    int stopsPerRoute = 6,
    String? interestsHint,
  }) async* {
    const int maxChunks = 6000;
    const int maxPayload = 400000;
    final prompt = _buildRoutesPrompt(
      latitude: latitude,
      longitude: longitude,
      cityHint: cityHint,
      routesCount: routesCount,
      stopsPerRoute: stopsPerRoute,
      interestsHint: interestsHint,
    );

    debugPrint(
        '🗺️ AttractionAiService: Начинаем streaming маршрутов для $cityHint');
    final parser = _StreamingJsonArrayParser();
    final routes = <AttractionRoute>[];
    final seen = <String>{};
    int chunkCount = 0;
    int lastEmittedRoutesCount = 0;

    final stream = _client.generateTextStream(prompt).timeout(
      const Duration(seconds: 90),
      onTimeout: (sink) {
        debugPrint(
            '🛑 AttractionAiService: Таймаут ожидания чанка маршрутов (no-events)');
        sink.close();
      },
    );

    await for (final chunk in stream) {
      chunkCount++;

      if (chunkCount == 1) {
        debugPrint('🗺️ AttractionAiService: Получен первый чанк маршрутов');
      }

      final newObjects = parser.addChunk(chunk);
      if (newObjects.isNotEmpty) {
        for (final obj in newObjects) {
          if (routes.length >= routesCount) break;
          try {
            final route = AttractionRoute.fromJson(obj);
            if (route.stops.isEmpty) continue;
            final key = route.title.toLowerCase().trim();
            if (key.isEmpty) continue;
            if (seen.add(key)) {
              routes.add(route);
            }
          } catch (_) {
            // ignore
          }
        }
      }

      if (routes.length > lastEmittedRoutesCount) {
        lastEmittedRoutesCount = routes.length;
        debugPrint(
            '🗺️ AttractionAiService: Отправлен частичный результат: ${routes.length} маршрутов');
        yield List<AttractionRoute>.unmodifiable(routes);
        if (routes.length >= routesCount) {
          debugPrint(
              '🗺️ AttractionAiService: Получены все маршруты ($routesCount), завершаем streaming');
          return;
        }
      }

      if (chunkCount >= maxChunks || parser.bufferLength >= maxPayload) {
        debugPrint(
            '🛑 AttractionAiService: Прерывание streaming маршрутов (chunkCount=$chunkCount, size=${parser.bufferLength})');
        break;
      }
    }

    debugPrint(
        '🗺️ AttractionAiService: Streaming маршрутов завершен, всего чанков: $chunkCount');
  }

  Stream<List<AttractionPlace>> fetchAttractionsStream({
    required double latitude,
    required double longitude,
    String? cityHint,
    int limit = 8,
    String? interestsHint,
  }) async* {
    const int maxChunks = 6000;
    const int maxPayload = 400000;
    final prompt = _buildPrompt(
      latitude: latitude,
      longitude: longitude,
      cityHint: cityHint,
      limit: limit,
      interestsHint: interestsHint,
    );

    debugPrint(
        '🗺️ AttractionAiService: Начинаем streaming достопримечательностей для $cityHint');
    final parser = _StreamingJsonArrayParser();
    final places = <AttractionPlace>[];
    final seen = <String>{};
    int chunkCount = 0;
    int lastEmittedPlacesCount = 0;

    final stream = _client.generateTextStream(prompt).timeout(
      const Duration(seconds: 90),
      onTimeout: (sink) {
        debugPrint(
            '🛑 AttractionAiService: Таймаут ожидания чанка мест (no-events)');
        sink.close();
      },
    );

    await for (final chunk in stream) {
      chunkCount++;

      if (chunkCount == 1) {
        debugPrint(
            '🗺️ AttractionAiService: Получен первый чанк достопримечательностей');
      }

      final newObjects = parser.addChunk(chunk);
      if (newObjects.isNotEmpty) {
        for (final obj in newObjects) {
          if (places.length >= limit) break;
          try {
            final place = AttractionPlace.fromJson(obj);
            final key =
                place.name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
            if (key.isEmpty) continue;
            if (seen.add(key)) {
              places.add(place);
            }
          } catch (_) {
            // ignore
          }
        }
      }

      if (places.length > lastEmittedPlacesCount) {
        lastEmittedPlacesCount = places.length;
        debugPrint(
            '🗺️ AttractionAiService: Отправлен частичный результат: ${places.length} мест');
        yield List<AttractionPlace>.unmodifiable(places);
        if (places.length >= limit) {
          debugPrint(
              '🗺️ AttractionAiService: Получено $limit мест, завершаем streaming');
          return;
        }
      }

      if (chunkCount >= maxChunks || parser.bufferLength >= maxPayload) {
        debugPrint(
            '🛑 AttractionAiService: Прерывание streaming мест (chunkCount=$chunkCount, size=${parser.bufferLength})');
        break;
      }
    }

    debugPrint(
        '🗺️ AttractionAiService: Streaming достопримечательностей завершен, всего чанков: $chunkCount');
  }

  Stream<List<AttractionPlace>> fetchTopAttractionsStream({
    required String cityHint,
    int limit = 7,
    String? interestsHint,
  }) async* {
    const int maxChunks = 4000;
    const int maxPayload = 250000;
    final prompt = _buildPreviewPrompt(
      cityHint: cityHint,
      limit: limit,
      interestsHint: interestsHint,
    );

    debugPrint(
        '🗺️ AttractionAiService: Начинаем streaming ТОП мест для $cityHint');
    final parser = _StreamingJsonArrayParser();
    final places = <AttractionPlace>[];
    final seen = <String>{};
    int chunkCount = 0;
    int lastEmittedPlacesCount = 0;

    final stream = _fastClient.generateTextStream(prompt).timeout(
      const Duration(seconds: 60),
      onTimeout: (sink) {
        debugPrint(
            '🛑 AttractionAiService: Таймаут ожидания чанка ТОП мест (no-events)');
        sink.close();
      },
    );

    await for (final chunk in stream) {
      chunkCount++;

      if (chunkCount == 1) {
        debugPrint(
            '🗺️ AttractionAiService: Получен первый чанк ТОП достопримечательностей');
      }

      final newObjects = parser.addChunk(chunk);
      if (newObjects.isNotEmpty) {
        for (final obj in newObjects) {
          if (places.length >= limit) break;
          try {
            final place = AttractionPlace.fromJson(obj);
            final key =
                place.name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
            if (key.isEmpty) continue;
            if (seen.add(key)) {
              places.add(place);
            }
          } catch (_) {
            // ignore
          }
        }
      }

      if (places.length > lastEmittedPlacesCount) {
        lastEmittedPlacesCount = places.length;
        debugPrint(
            '🗺️ AttractionAiService: Отправлен частичный ТОП: ${places.length} мест');
        yield List<AttractionPlace>.unmodifiable(places);
        if (places.length >= limit) {
          debugPrint(
              '🗺️ AttractionAiService: Получено $limit ТОП мест, завершаем streaming');
          return;
        }
      }

      if (chunkCount >= maxChunks || parser.bufferLength >= maxPayload) {
        debugPrint(
            '🛑 AttractionAiService: Прерывание streaming ТОП мест (chunkCount=$chunkCount, size=${parser.bufferLength})');
        break;
      }
    }

    debugPrint(
        '🗺️ AttractionAiService: Streaming ТОП мест завершен, всего чанков: $chunkCount');
  }

  Future<List<AttractionPlace>> fetchTopAttractions({
    required String cityHint,
    int limit = 7,
    String? interestsHint,
  }) async {
    final prompt = _buildPreviewPrompt(
      cityHint: cityHint,
      limit: limit,
      interestsHint: interestsHint,
    );

    final response = await _fastClient.generateText(prompt);
    final jsonString = _extractJson(response);

    if (jsonString == null) {
      debugPrint('🗺️ AttractionAiService: Не удалось извлечь JSON для ТОП');
      return const [];
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .map((e) => AttractionPlace.fromJson(e as Map<String, dynamic>))
            .take(limit)
            .toList();
      }
      if (decoded is Map && decoded['places'] is List) {
        return (decoded['places'] as List)
            .map((e) => AttractionPlace.fromJson(e as Map<String, dynamic>))
            .take(limit)
            .toList();
      }
    } catch (e) {
      debugPrint('🗺️ AttractionAiService: Ошибка парсинга ТОП: $e');
    }

    return const [];
  }

  Future<List<AttractionPlace>> fetchAttractions({
    required double latitude,
    required double longitude,
    String? cityHint,
    int limit = 8,
    String? interestsHint,
  }) async {
    final prompt = _buildPrompt(
      latitude: latitude,
      longitude: longitude,
      cityHint: cityHint,
      limit: limit,
      interestsHint: interestsHint,
    );

    final response = await _fastClient.generateText(prompt);
    final jsonString = _extractJson(response);

    if (jsonString == null) {
      debugPrint('🗺️ AttractionAiService: Не удалось извлечь JSON');
      return const [];
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .map((e) => AttractionPlace.fromJson(e as Map<String, dynamic>))
            .take(limit)
            .toList();
      }
      if (decoded is Map && decoded['places'] is List) {
        return (decoded['places'] as List)
            .map((e) => AttractionPlace.fromJson(e as Map<String, dynamic>))
            .take(limit)
            .toList();
      }
    } catch (e) {
      debugPrint('🗺️ AttractionAiService: Ошибка парсинга ответа: $e');
    }

    return const [];
  }

  Future<List<AttractionRoute>> fetchRoutes({
    required double latitude,
    required double longitude,
    String? cityHint,
    int routesCount = 3,
    int stopsPerRoute = 6,
    String? interestsHint,
  }) async {
    final prompt = _buildRoutesPrompt(
      latitude: latitude,
      longitude: longitude,
      cityHint: cityHint,
      routesCount: routesCount,
      stopsPerRoute: stopsPerRoute,
      interestsHint: interestsHint,
    );

    final response = await _fastClient.generateText(prompt);
    final jsonString = _extractJson(response);

    if (jsonString == null) {
      debugPrint(
          '🗺️ AttractionAiService: Не удалось извлечь JSON для маршрутов');
      return const [];
    }

    try {
      final decoded = jsonDecode(jsonString);
      final rawRoutes = decoded is List
          ? decoded
          : decoded is Map<String, dynamic> && decoded['routes'] is List
              ? decoded['routes']
              : null;

      if (rawRoutes is List) {
        return rawRoutes
            .map((e) => AttractionRoute.fromJson(e as Map<String, dynamic>))
            .where((route) => route.stops.isNotEmpty)
            .take(routesCount)
            .toList();
      }
    } catch (e) {
      debugPrint('🗺️ AttractionAiService: Ошибка парсинга маршрутов: $e');
    }

    return const [];
  }

  String _buildPreviewPrompt({
    required String cityHint,
    required int limit,
    String? interestsHint,
  }) {
    final location = cityHint.trim().isNotEmpty ? cityHint.trim() : 'этом городе';
    final interestsPart = interestsHint != null && interestsHint.isNotEmpty
        ? ' Интересы: $interestsHint.'
        : '';

    return '''
Ты местный гид. Город: $location.$interestsPart
Дай $limit самых известных достопримечательностей.
Это должен быть план экскурсии: места должны идти по порядку маршрута, чтобы человек мог посетить их без возвратов и лишних кругов.

Верни ТОЛЬКО JSON массив:
[{"name":"Эрмитаж","category":"museum"},{"name":"Дворцовая площадь","category":"sight"}]

ВАЖНО:
- Только реальные места
- КОНКРЕТНЫЕ названия
- Без описаний и лишнего текста
- category: museum, sight, park, view, food, coffee
''';
  }

  String _buildPrompt({
    required double latitude,
    required double longitude,
    String? cityHint,
    required int limit,
    String? interestsHint,
  }) {
    final location = cityHint != null && cityHint.isNotEmpty
        ? cityHint
        : 'координаты ($latitude, $longitude)';

    final interestsPart = interestsHint != null && interestsHint.isNotEmpty
        ? ' Интересы: $interestsHint.'
        : '';

    return '''
Ты местный гид в городе $location.$interestsPart

Назови $limit КОНКРЕТНЫХ известных мест (музеи, памятники, площади, парки и т.д.) с их ТОЧНЫМИ НАЗВАНИЯМИ.
Пользователь может перемещаться не только пешком, но и на метро, автобусе, такси и другом транспорте — поэтому можно включать места из разных районов города.
Старайся дать МАКСИМУМ разнообразия, избегай повторов и очень похожих объектов.

Верни ТОЛЬКО JSON массив:
[{"name":"Эрмитаж","description":"Крупнейший музей","category":"museum","latitude":59.9398,"longitude":30.3146},{"name":"Дворцовая площадь","description":"Главная площадь","category":"sight","latitude":59.9399,"longitude":30.3156}]

ВАЖНО:
- Только РЕАЛЬНЫЕ известные места
- КОНКРЕТНЫЕ названия (НЕ "Набережная", А "Дворцовая набережная")
- Краткое описание (до 80 символов)
- category: museum, sight, park, coffee, food, view
- Добавь latitude/longitude (примерные, но внутри города/региона), числа. Если не уверен — ставь 0.
- Без id
''';
  }

  String? _extractJson(String response) {
    // 1) если внутри есть ```...``` — пробуем сначала оттуда
    final codeBlock = RegExp(r'```(?:json)?(.*?)```', dotAll: true);
    final match = codeBlock.firstMatch(response);
    if (match != null) {
      final inner = match.group(1);
      if (inner != null) {
        final candidate = _extractFirstJsonValue(inner.trim());
        if (candidate != null) return candidate;
      }
    }

    // 2) иначе пробуем вытащить первый валидный JSON из всей строки
    return _extractFirstJsonValue(response.trim());
  }

  String? _extractFirstJsonValue(String text) {
    final startBrace = text.indexOf('{');
    final startBracket = text.indexOf('[');
    final start = _minPositive(startBrace, startBracket);
    if (start == -1) return null;

    final opener = text[start];
    if (opener != '{' && opener != '[') return null;

    final stack = <String>[opener];
    bool inString = false;
    bool escape = false;

    for (int i = start + 1; i < text.length; i++) {
      final ch = text[i];

      if (inString) {
        if (escape) {
          escape = false;
          continue;
        }
        if (ch == r'\') {
          escape = true;
          continue;
        }
        if (ch == '"') {
          inString = false;
        }
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
        if (stack.isEmpty) {
          continue;
        }
        final last = stack.last;
        final isMatch =
            (last == '{' && ch == '}') || (last == '[' && ch == ']');
        if (!isMatch) {
          // Если структура сломана — не рискуем возвращать мусор.
          return null;
        }
        stack.removeLast();
        if (stack.isEmpty) {
          final candidate = text.substring(start, i + 1);
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

  String _buildRoutesPrompt({
    required double latitude,
    required double longitude,
    String? cityHint,
    required int routesCount,
    required int stopsPerRoute,
    String? interestsHint,
  }) {
    final location = cityHint != null && cityHint.isNotEmpty
        ? cityHint
        : '($latitude, $longitude)';

    final interestsPart = interestsHint != null && interestsHint.isNotEmpty
        ? ' Интересы: $interestsHint.'
        : '';

    return '''
Ты местный гид в $location.$interestsPart

Создай $routesCount маршрутов по $stopsPerRoute КОНКРЕТНЫХ известных мест в каждом.
Пользователь может перемещаться пешком, на метро, автобусе, такси и другом транспорте — допускаются комбинированные маршруты.
В description маршрута кратко укажи, какой транспорт уместен (например: "пешком + метро" / "автобус + пешком" / "такси + пешком").

Верни ТОЛЬКО JSON:
[{"name":"Исторический центр","description":"Главные достопримечательности","stops":[{"name":"Эрмитаж","description":"Крупнейший музей России","category":"museum","latitude":59.9398,"longitude":30.3146},{"name":"Дворцовая площадь","description":"Центральная площадь города","category":"sight","latitude":59.9399,"longitude":30.3156}]}]

ВАЖНО:
- КОНКРЕТНЫЕ названия мест (НЕ "Парк", А "Летний сад")  
- Маршрут ДОЛЖЕН БЫТЬ РЕАЛЬНЫМ и географически связным: без "телепортов" между разными частями города и без многократных возвратов назад
- Представь, что люди реально идут/едут и собирают точки ПО ПУТИ: выбирай порядок, который минимизирует время/расстояние между соседними остановками
- Начинай маршрут с точки, ближайшей к координатам ($latitude, $longitude) (или к центру города), затем добавляй ближайшие следующие точки
- Краткие описания (до 80 символов)
- category: museum, sight, park, coffee, food, view
- Добавь latitude/longitude (примерные, но внутри города/региона), числа. Старайся НЕ ставить 0; 0 — только если совсем не можешь оценить.
- БЕЗ id, БЕЗ distance
''';
  }
}

class _StreamingJsonArrayParser {
  String _buffer = '';
  int _index = 0;
  bool _started = false;
  bool _inString = false;
  bool _escape = false;
  int _objDepth = 0;
  int _objStart = -1;

  int get bufferLength => _buffer.length;

  List<Map<String, dynamic>> addChunk(String chunk) {
    _buffer += chunk;
    final out = <Map<String, dynamic>>[];

    for (; _index < _buffer.length; _index++) {
      final ch = _buffer[_index];

      if (!_started) {
        if (ch == '[') {
          _started = true;
        }
        continue;
      }

      if (_inString) {
        if (_escape) {
          _escape = false;
          continue;
        }
        if (ch == r'\') {
          _escape = true;
          continue;
        }
        if (ch == '"') {
          _inString = false;
        }
        continue;
      }

      if (ch == '"') {
        _inString = true;
        continue;
      }

      if (_objDepth == 0) {
        if (ch == '{') {
          _objDepth = 1;
          _objStart = _index;
        }
        continue;
      }

      if (ch == '{') {
        _objDepth++;
        continue;
      }
      if (ch == '}') {
        _objDepth--;
        if (_objDepth == 0 && _objStart != -1) {
          final candidate = _buffer.substring(_objStart, _index + 1);
          try {
            final decoded = jsonDecode(candidate);
            if (decoded is Map<String, dynamic>) {
              out.add(decoded);
            } else if (decoded is Map) {
              out.add(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {
            // ignore
          }
          _objStart = -1;
        }
      }

      // тримим буфер, чтобы не рос бесконечно
      if (_index > 12000 && _objDepth == 0) {
        _buffer = _buffer.substring(_index);
        _index = 0;
      }
    }

    return out;
  }
}
