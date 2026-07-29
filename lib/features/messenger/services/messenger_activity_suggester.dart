import 'dart:collection';
import 'dart:math';

import '../models/messenger_message.dart';

class MessengerActivitySuggestion {
  final List<String> options;
  final String fallback;

  const MessengerActivitySuggestion({
    required this.options,
    required this.fallback,
  });
}

class MessengerActivitySuggester {
  final Random _random;

  MessengerActivitySuggester({Random? random}) : _random = random ?? Random();

  MessengerActivitySuggestion buildSuggestion({
    required String userMessage,
    required List<MessengerMessage> recentMessages,
  }) {
    final normalized = _normalize(
      [
        userMessage,
        ...recentMessages.map((message) => message.text),
      ].join(' '),
    );
    final options = <String>[];
    for (final hint in _hints) {
      if (hint.matches(normalized)) {
        options.addAll(hint.activities);
      }
    }
    final includeRandom = options.isEmpty || _random.nextDouble() < 0.35;
    if (includeRandom) {
      options.addAll(_pickRandom(_defaultActivities, count: 3));
    }
    final unique = LinkedHashSet<String>();
    for (final option in options) {
      final trimmed = option.trim();
      if (trimmed.isNotEmpty) unique.add(trimmed);
    }
    final limited = unique.take(7).toList();
    final fallbackSource = limited.isNotEmpty ? limited : _defaultActivities;
    final fallback = fallbackSource[_random.nextInt(fallbackSource.length)];
    return MessengerActivitySuggestion(
      options: limited,
      fallback: fallback,
    );
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _pickRandom(List<String> items, {required int count}) {
    if (items.isEmpty) return const [];
    final pool = List<String>.of(items);
    pool.shuffle(_random);
    return pool.take(count).toList();
  }
}

class _ActivityHint {
  final List<String> keywords;
  final List<String> activities;

  const _ActivityHint(this.keywords, this.activities);

  bool matches(String text) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }
}

const List<String> _defaultActivities = [
  'гуляю',
  'на прогулке',
  'занят(а) делами',
  'в дороге',
  'отдыхаю',
  'пью кофе',
  'в кафе',
  'дома',
  'слушаю музыку',
  'смотрю сериал',
  'готовлю',
  'убираюсь',
];

const List<_ActivityHint> _hints = [
  _ActivityHint(
    ['ванн', 'душ', 'сануз', 'bathroom', 'shower'],
    ['в ванной', 'в душе', 'в ванной комнате'],
  ),
  _ActivityHint(
    ['гуля', 'прогул', 'парк', 'улиц', 'сквер', 'двор'],
    ['гуляю', 'на прогулке', 'в парке'],
  ),
  _ActivityHint(
    ['бег', 'пробеж', 'спорт', 'трен', 'зал', 'фитнес'],
    ['на пробежке', 'тренируюсь', 'в зале'],
  ),
  _ActivityHint(
    ['работ', 'офис', 'дедлайн', 'задач', 'проект'],
    ['на работе', 'занят(а) делами', 'в офисе'],
  ),
  _ActivityHint(
    ['учеб', 'курс', 'лекц', 'дз', 'домашк', 'экзам', 'семинар'],
    ['учусь', 'разбираю задания', 'на учебе'],
  ),
  _ActivityHint(
    ['еда', 'поел', 'поела', 'обед', 'ужин', 'завтрак', 'кафе', 'ресторан'],
    ['обедаю', 'в кафе', 'перекусываю'],
  ),
  _ActivityHint(
    ['кофе', 'латте', 'капуч'],
    ['пью кофе', 'в кофейне', 'на кофе-брейке'],
  ),
  _ActivityHint(
    ['магазин', 'покуп', 'шоп', 'заказ', 'доставка'],
    ['в магазине', 'покупаю кое-что', 'разбираюсь с покупками'],
  ),
  _ActivityHint(
    ['дом', 'квартир', 'комнат', 'диван'],
    ['дома', 'отдыхаю дома', 'разбираюсь по дому'],
  ),
  _ActivityHint(
    ['дорог', 'еду', 'в пути', 'метро', 'автобус', 'такси', 'машин'],
    ['в дороге', 'еду по делам', 'по пути'],
  ),
  _ActivityHint(
    ['музык', 'плейлист', 'трек', 'наушн'],
    ['слушаю музыку', 'в наушниках', 'слушаю трек'],
  ),
  _ActivityHint(
    ['фильм', 'сериал', 'кино', 'ютуб', 'стрим'],
    ['смотрю фильм', 'залипаю в сериал', 'смотрю видео'],
  ),
  _ActivityHint(
    ['книга', 'чита', 'роман', 'статья'],
    ['читаю книгу', 'чуть-чуть читаю', 'читаю статью'],
  ),
  _ActivityHint(
    ['готов', 'кухн', 'рецепт'],
    ['готовлю', 'на кухне', 'делаю перекус'],
  ),
  _ActivityHint(
    ['уборк', 'прибир', 'порядок'],
    ['убираюсь', 'разбираю вещи', 'наводю порядок'],
  ),
];
