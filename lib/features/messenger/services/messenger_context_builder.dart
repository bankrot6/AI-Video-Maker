import '../models/friend_conversation_context.dart';
import '../models/messenger_contact.dart';
import '../models/messenger_message.dart';
import '../models/messenger_thread.dart';
import '../models/messenger_mood_state.dart';
import '../../personalization/models/friend_persona.dart';

class MessengerContextBuilder {
  const MessengerContextBuilder();

  FriendConversationContext build({
    required MessengerContact contact,
    required MessengerPersona persona,
    required FriendPersona friendPersona,
    required List<MessengerMessage> recentMessages,
    required String userMessage,
    MessengerMoodState? moodState,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final normalizedUser = _normalize(userMessage);
    final recentUserText = _normalize(
      [
        userMessage,
        ...recentMessages
            .where((message) => message.isMine)
            .map((message) => message.text),
      ].join(' '),
    );

    final sentiment = _sentimentScore('$normalizedUser $recentUserText');
    final traitHints = _normalize(
      '${friendPersona.about} '
      '${friendPersona.characterTraits} '
      '${friendPersona.relationshipNotes} '
      '${friendPersona.occupation} '
      '${friendPersona.goodHabits} '
      '${friendPersona.badHabits} '
      '${friendPersona.hobbies} '
      '${persona.description}',
    );
    final mood = moodState == null
        ? _pickMood(contact.id, timestamp, sentiment, traitHints)
        : _formatMood(moodState);
    final energy = _pickEnergy(normalizedUser, traitHints);
    final responseLength =
        _pickResponseLength(userMessage, contact.id, timestamp);
    final relationshipStyle =
        _pickRelationshipStyle(recentUserText, traitHints);
    final lifeUpdate = _pickLifeUpdate(
      contactId: contact.id,
      userMessage: userMessage,
      now: timestamp,
    );

    return FriendConversationContext(
      mood: mood,
      energy: energy,
      responseLength: responseLength,
      relationshipStyle: relationshipStyle,
      lifeUpdate: lifeUpdate,
    );
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  int _sentimentScore(String text) {
    const positives = [
      'класс',
      'здорово',
      'супер',
      'круто',
      'рад',
      'радость',
      'спасибо',
      'отлично',
      'счастлив',
      'смешно',
      'улыб',
      'нрав',
      'люблю',
    ];
    const negatives = [
      'плохо',
      'ужас',
      'груст',
      'устал',
      'злой',
      'бесит',
      'печал',
      'разочар',
      'обид',
      'бол',
      'проблем',
      'не могу',
    ];

    int score = 0;
    for (final word in positives) {
      if (text.contains(word)) score += 1;
    }
    for (final word in negatives) {
      if (text.contains(word)) score -= 1;
    }
    return score;
  }

  String _pickMood(
    String contactId,
    DateTime now,
    int sentiment,
    String traitHints,
  ) {
    final seed = _stableHash('${contactId}_${_dateKey(now)}');
    final variations = [
      'спокойный',
      'бодрый',
      'расслабленный',
      'вдумчивый',
      'ленивый',
      'рассеянный',
      'воодушевлённый',
      'слегка раздражённый',
      'сонный',
      'игривый',
    ];
    final variation = variations[seed % variations.length];
    if (traitHints.contains('спокой')) {
      return 'спокойный и внимательный ($variation)';
    }
    if (traitHints.contains('энерг') || traitHints.contains('весел')) {
      return 'бодрый и разговорчивый ($variation)';
    }
    if (sentiment <= -2) {
      return 'поддерживающий и спокойный ($variation)';
    }
    if (sentiment >= 2) {
      return 'дружелюбный и бодрый ($variation)';
    }
    return 'нейтральный и дружелюбный ($variation)';
  }

  String _formatMood(MessengerMoodState moodState) {
    final joy = moodState.joy;
    final anger = moodState.anger;
    final fun = moodState.fun;
    final sadness = moodState.sadness;
    final humor = moodState.humor;
    final boring = moodState.boring;
    final joyBalance = joy - anger;
    final funBalance = fun - sadness;
    final humorBalance = humor - boring;
    final joyLabel =
        _axisLabel(joyBalance, positive: 'радость', negative: 'злость');
    final funLabel =
        _axisLabel(funBalance, positive: 'веселье', negative: 'грусть');
    final humorLabel =
        _axisLabel(humorBalance, positive: 'юмор', negative: 'занудство');
    return 'радость $joy/100, злость $anger/100, веселье $fun/100, '
        'грусть $sadness/100, юмор $humor/100, занудство $boring/100. '
        'Баланс радость/злость: $joyLabel. '
        'Баланс веселье/грусть: $funLabel. '
        'Баланс юмор/занудство: $humorLabel.';
  }

  String _axisLabel(
    int value, {
    required String positive,
    required String negative,
  }) {
    if (value >= 30) return 'выраженная $positive';
    if (value <= -30) return 'выраженная $negative';
    if (value >= 10) return 'легкая $positive';
    if (value <= -10) return 'легкая $negative';
    return 'ровное';
  }

  String _pickEnergy(String userText, String traitHints) {
    if (traitHints.contains('энерг')) {
      return 'высокая';
    }
    if (traitHints.contains('спокой') || traitHints.contains('тихий')) {
      return 'низкая';
    }
    if (userText.contains('!!!') || userText.contains('!!')) {
      return 'высокая';
    }
    if (userText.contains('устал') || userText.contains('сонный')) {
      return 'низкая';
    }
    return 'средняя';
  }

  String _pickResponseLength(
    String userMessage,
    String contactId,
    DateTime now,
  ) {
    final length = userMessage.trim().length;
    final seed = _stableHash('${contactId}_${userMessage}_${now.minute}');
    final roll = seed % 100;

    if (length <= 10) {
      if (roll < 50) return 'микро (1-3 слова)';
      return 'коротко (1 фраза)';
    }
    if (length <= 24) {
      if (roll < 25) return 'микро (1-5 слов)';
      if (roll < 65) return 'коротко (1 предложение)';
      return 'средне (1-2 предложения)';
    }
    if (length <= 80) {
      if (roll < 20) return 'коротко (1 предложение)';
      if (roll < 70) return 'средне (1-3 предложения)';
      return 'подробнее (2-4 предложения)';
    }
    if (roll < 15) return 'коротко (1-2 предложения)';
    if (roll < 55) return 'средне (2-3 предложения)';
    return 'подробнее (3-5 предложений)';
  }

  String _pickRelationshipStyle(String text, String traitHints) {
    if (traitHints.contains('на вы') || traitHints.contains('официаль')) {
      return 'на вы';
    }
    if (text.contains('вы ') ||
        text.contains('вам ') ||
        text.contains('вас ')) {
      return 'на вы';
    }
    return 'на ты';
  }

  String? _pickLifeUpdate({
    required String contactId,
    required String userMessage,
    required DateTime now,
  }) {
    final roll = _stableHash('${contactId}_${userMessage}_${now.hour}');
    if (roll % 5 != 0) return null;
    const updates = [
      'сегодня разгребал(а) дела, наконец всё разобрал(а).',
      'утром ходил(а) гулять, проветрился(лась).',
      'поймал(а) себя на мысли, что давно не отдыхал(а).',
      'залип(ла) на новый трек — на повторе весь день.',
      'сегодня удалось поработать спокойно.',
      'нашел(а) статью, хочу потом обсудить.',
      'делал(а) уборку, стало уютнее.',
      'в целом ровное настроение, без качелей.',
      'опоздал(а) на работу, но даже не заметили.',
      'проспал(а), пытаюсь войти в ритм.',
      'завис(ла) в ютубе на два часа.',
      'готовил(а) что-то новое — вышло неплохо.',
      'купил(а) кофе по дороге, настроение лучше.',
      'застрял(а) в пробке, листаю ленту.',
      'пересматриваю старый сериал, ностальгия.',
      'затащил(а) в игре, до сих пор на эмоциях.',
      'весь день звонки, голова гудит.',
      'поругался(лась) с коллегой, бесит.',
      'дочитал(а) книгу, не знаю за что взяться.',
      'сходил(а) в зал, ноги ватные.',
      'заказал(а) еду, жду доставку.',
      'нашел(а) мем, умираю.',
      'сегодня лень вообще что-либо делать.',
      'залип(ла) в тикток, время пролетело.',
    ];
    final seed = _stableHash('${contactId}_${_dateKey(now)}');
    return updates[seed % updates.length];
  }

  String _dateKey(DateTime now) {
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }

  int _stableHash(String input) {
    const int prime = 16777619;
    int hash = 2166136261;
    for (final code in input.codeUnits) {
      hash ^= code;
      hash = (hash * prime) & 0x7fffffff;
    }
    return hash.abs();
  }
}
