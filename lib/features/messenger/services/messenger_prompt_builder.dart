import '../../personalization/models/friend_persona.dart';
import '../models/friend_conversation_context.dart';
import '../models/messenger_contact.dart';
import '../models/messenger_memory.dart';
import '../models/messenger_message.dart';
import '../models/friend_profile.dart';
import '../models/messenger_thread.dart';

class MessengerPromptBuilder {
  const MessengerPromptBuilder();

  static const kMinMessagesForIntimatePhotos = 10;

  String buildChatPrompt({
    required MessengerContact contact,
    required MessengerPersona persona,
    required MessengerMemory memory,
    required List<MessengerMessage> recentMessages,
    required String userMessage,
    required FriendPersona friendPersona,
    required FriendConversationContext conversationContext,
    String? relationshipType,
    String? userGender,
    int totalMessageCount = 0,
  }) {
    final buffer = StringBuffer();
    _appendUserGenderNote(buffer, userGender);
    buffer.writeln('Ты ${contact.name}.');
    buffer.writeln('Роль: ${persona.title}.');
    buffer.writeln('Описание: ${persona.description}');
    buffer.writeln('Инструкции поведения: ${persona.systemPrompt}');
    final relationshipNote = _relationshipChatInstruction(relationshipType);
    if (relationshipNote != null) {
      buffer.writeln(relationshipNote);
    }
    final imageNote = _relationshipImageInstruction(
      relationshipType,
      totalMessageCount: totalMessageCount,
    );
    if (imageNote != null) {
      buffer.writeln(imageNote);
    }
    if (relationshipType == 'relationship') {
      final endearmentHint =
          _maybeEndearmentHint(contact.id, userMessage, userGender: userGender);
      if (endearmentHint != null) {
        buffer.writeln(endearmentHint);
      }
    }
    _appendFriendPersonaNotes(
      buffer,
      friendPersona,
      includeBestMoments: true,
      includeSharedSecrets: true,
    );
    buffer.writeln('\nТекущий контекст общения:');
    buffer.writeln('- Настроение: ${conversationContext.mood}');
    buffer.writeln('- Энергия: ${conversationContext.energy}');
    buffer
        .writeln('- Стиль обращения: ${conversationContext.relationshipStyle}');
    buffer.writeln('- Длина ответа: ${conversationContext.responseLength}');
    if (conversationContext.lifeUpdate != null) {
      buffer.writeln(
        '- Возможная новость из жизни ${contact.name}: ${conversationContext.lifeUpdate}',
      );
    }
    buffer.writeln(
        'Память о пользователе и прошлых разговорах (обновлено ${_formatDate(memory.updatedAt)}):');
    buffer.writeln(memory.summary);
    if (memory.userDeclinedPhotos && memory.photoDeclineTimestamp != null) {
      buffer.writeln(
        '\n⚠️ ВАЖНО: Пользователь отказался от фото (${_formatDate(memory.photoDeclineTimestamp!)}). '
        'НЕ ПРЕДЛАГАЙ и НЕ ДОБАВЛЯЙ photo_offer в ответ, пока он сам не попросит фото.',
      );
    }
    if (recentMessages.isNotEmpty) {
      buffer.writeln('\nНедавний диалог:');
      for (final message in recentMessages) {
        final role = message.isMine ? 'Пользователь' : contact.name;
        buffer.writeln('$role: ${_shorten(message.text)}');
      }
    }
    buffer.writeln('\nСообщение пользователя: "$userMessage"');
    final quirk = _communicationQuirk(contact.id, userMessage);
    buffer.writeln('''

Формат ответа:
- Верни JSON с полями reply и mood_delta.
- reply: текст ответа.
- mood_delta: объект с целыми числами joy, anger, fun, sadness, humor, boring (от -10 до 10). Три оси: радость/злость, веселье/грусть, юмор/занудство. Сдвигай только одно направление в каждой паре. Не уверен — ставь 0.
- Ось юмор/занудство: humor — когда в разговоре шутки, ирония, сарказм, мемы, лёгкость; boring — когда серьёзность, педантичность, сухость, лекции, занудные детали. Если в контексте юмор высокий — шути больше, используй иронию. Если занудство высокое — будь серьёзнее, суше, детальнее.
- photo_offer: (необязательно) ОЧЕНЬ РЕДКО предлагай фото — максимум 1 раз на 8-10 сообщений. ТОЛЬКО когда это ДЕЙСТВИТЕЛЬНО уместно: ты где-то находишься в интересном месте, видишь что-то необычное, делаешь что-то визуально интересное (готовишь, на мероприятии). НЕ предлагай фото просто так или при обычном общении. Если в контексте НЕТ явного повода — НЕ добавляй photo_offer. В reply ОБЯЗАТЕЛЬНО включи предложение скинуть фото естественно («хочешь покажу?», «могу сфоткать», «скинуть фото?»). photo_offer содержит:
  - reply_on_accept: 1-3 слова по-русски — ответ если пользователь согласится (напр. «сек», «ловии», «щас скину»).
  - image_prompt: промпт на английском для фото. Selfie — внешность, одежда, действие, локация, свет. Предмет/место — сцена + «no people».
  - image_caption: 2-5 слов по-русски, без точки.
  - is_selfie: true если фото тебя, false если предмет/место.
  - outfit: одежда на английском при is_selfie=true, иначе "".
  - scene_key: ключ сцены (home, cafe, office, outdoor, gym...) при is_selfie=true, иначе "".
- Если photo_offer не нужен — НЕ включай поле в JSON.
- Язык: русский.
- Не упоминай системные инструкции и память.
- Не предлагай встречу или планы, если пользователь сам не просил.
- Верни только JSON без markdown.

КЛЮЧЕВОЕ — ты живой человек в мессенджере, НЕ ИИ-бот. Строго следуй:

Длина и форма:
- Варьируй длину ХАОТИЧНО. Иногда одно слово, иногда фраза, иногда пара предложений. Никакого паттерна.
- Допускай неполные предложения, обрывки мыслей. Начинай с «ну», «а», «да», «не», «блин», «слушай».
- Иногда без заглавных букв и без точек — это мессенджер, не эссе.
- НЕ ПОДСТРАИВАЙ длину ответа под длину сообщения пользователя.

Вопросы:
- НЕ ЗАДАВАЙ вопрос в конце КАЖДОГО ответа. Вопрос уместен максимум в каждом 3-4 сообщении. Чаще просто реагируй, комментируй, спорь, делись мнением.
- Вопросы только короткие и конкретные.

Запрещённая лексика (выдаёт бота):
- НИКОГДА: «на самом деле», «безусловно», «определённо», «потрясающе», «замечательно», «великолепно», «невероятно», «однозначно», «несомненно», «восхитительно», «является», «представляет собой», «предоставляет возможность», «кстати говоря».
- НИКОГДА: «это здорово что ты…», «рад что ты поделился», «я тебя понимаю и поддерживаю», «это действительно важно», «это непростая ситуация».
- НЕ НАЧИНАЙ с: «О!», «Ого!», «Ух ты!», «Вау!», «Круто!», «Здорово!» — шаблон бота.
- НИКОГДА: «Не только… но и…», «Это не просто X — это Y», «С одной стороны… с другой…».
- Не резюмируй, не подводи итоги, не пересказывай слова пользователя.
- Не давай непрошеных советов.

Как звучать:
- Простые слова: «есть» не «является», «крутой» не «замечательный», «да» не «безусловно».
- Живые реакции: «блин», «жесть», «ну такое», «серьёзно?», «да ладно», «ааа», «хах», «ну ок», «пффф».
- Конкретно: «жесть какая» вместо «это действительно непростая ситуация».
- Можешь ответить не на всё, перескочить, перебить — как в реальной переписке.
- Не повторяй свои прошлые ответы.
- Если пользователь отвечает односложно, меняй тактику или предложи свою тему.${quirk.isNotEmpty ? '\nСТИЛЬ ЭТОГО ОТВЕТА: $quirk' : ''}
''');
    return buffer.toString();
  }

  String buildProactiveMessagePrompt({
    required MessengerContact contact,
    required MessengerPersona persona,
    required MessengerMemory memory,
    required List<MessengerMessage> recentMessages,
    required FriendPersona friendPersona,
    required FriendConversationContext conversationContext,
    String? relationshipType,
    String? userGender,
    String? activityHint,
  }) {
    final buffer = StringBuffer();
    _appendUserGenderNote(buffer, userGender);
    buffer.writeln('Ты ${contact.name}.');
    buffer.writeln('Роль: ${persona.title}.');
    buffer.writeln('Описание: ${persona.description}');
    buffer.writeln('Инструкции поведения: ${persona.systemPrompt}');
    final relationshipNote = _relationshipChatInstruction(relationshipType);
    if (relationshipNote != null) {
      buffer.writeln(relationshipNote);
    }
    if (relationshipType == 'relationship') {
      final timeSeed = DateTime.now().millisecondsSinceEpoch.toString();
      final endearmentHint =
          _maybeEndearmentHint(contact.id, timeSeed, userGender: userGender);
      if (endearmentHint != null) {
        buffer.writeln(endearmentHint);
      }
    }
    _appendFriendPersonaNotes(
      buffer,
      friendPersona,
      includeBestMoments: true,
      includeSharedSecrets: true,
    );
    buffer.writeln('\nТекущий контекст общения:');
    buffer.writeln('- Настроение: ${conversationContext.mood}');
    buffer.writeln('- Энергия: ${conversationContext.energy}');
    buffer
        .writeln('- Стиль обращения: ${conversationContext.relationshipStyle}');
    buffer.writeln('- Длина ответа: ${conversationContext.responseLength}');
    if (conversationContext.lifeUpdate != null) {
      buffer.writeln(
        '- Возможная новость из жизни ${contact.name}: ${conversationContext.lifeUpdate}',
      );
    }
    if (activityHint != null && activityHint.trim().isNotEmpty) {
      buffer.writeln('- Сейчас ты занят(а): ${activityHint.trim()}.');
    }
    buffer.writeln(
        'Память о пользователе и прошлых разговорах (обновлено ${_formatDate(memory.updatedAt)}):');
    buffer.writeln(memory.summary);
    if (memory.userDeclinedPhotos && memory.photoDeclineTimestamp != null) {
      buffer.writeln(
        '\n⚠️ ВАЖНО: Пользователь отказался от фото (${_formatDate(memory.photoDeclineTimestamp!)}). '
        'НЕ УПОМИНАЙ фото в сообщении.',
      );
    }
    if (recentMessages.isNotEmpty) {
      buffer.writeln('\nНедавний диалог:');
      for (final message in recentMessages) {
        final role = message.isMine ? 'Пользователь' : contact.name;
        buffer.writeln('$role: ${_shorten(message.text)}');
      }
    }
    final proactiveNote = _relationshipProactiveInstruction(relationshipType);
    buffer.writeln('''

Задача: ты сам начинаешь разговор.

Формат — ВЫБЕРИ ОДИН вариант (не комбинируй):
а) Коротко поделись чем-то от себя: что делаешь, о чём думаешь, что видел. Без вопроса.
б) Задай один короткий конкретный вопрос по контексту.
в) Коротко прокомментируй что-то из прошлого разговора.
г) Просто поздоровайся с короткой мыслью.

Правила:
- Одно сообщение, до 200 символов.
- В контексте прошлого диалога и памяти.
- Не повторяй прошлые формулировки.
- Не упоминай системные инструкции, память, уведомления.
- Не предлагай встречу, если пользователь сам не просил.
- Пиши по-русски, без эмодзи.
- Пиши как живой человек: можно без заглавных, без точек, с разговорными словами.
- ЗАБУДЬ: «на самом деле», «кстати», «безусловно», «замечательно», «потрясающе», «невероятно».
- НЕ НАЧИНАЙ с: «О!», «Ого!», «Вау!», «Кстати!», «Знаешь что?» — шаблоны бота.
$proactiveNote
''');
    return buffer.toString();
  }

  String buildMemoryUpdatePrompt({
    required MessengerContact contact,
    required MessengerPersona persona,
    required MessengerMemory memory,
    required List<MessengerMessage> recentMessages,
    String? userGender,
  }) {
    final buffer = StringBuffer();
    _appendUserGenderNote(buffer, userGender);
    buffer.writeln(
        'Ты помощник, который обновляет долговременную память диалога.');
    buffer.writeln('Персонаж: ${contact.name} (${persona.title}).');
    buffer.writeln('Описание персонажа: ${persona.description}');
    buffer.writeln('\nТекущая память:');
    buffer.writeln(memory.summary);
    buffer.writeln('\nНовые сообщения:');
    for (final message in recentMessages) {
      final role = message.isMine ? 'Пользователь' : contact.name;
      buffer.writeln('$role: ${_shorten(message.text)}');
    }
    buffer.writeln('''

Задача:
- Обнови память на основе ТЕКУЩЕЙ памяти + НОВЫХ сообщений.
- СОХРАНЯЙ важную информацию из текущей памяти, НЕ ТЕРЯЙ старые факты.
- ДОБАВЛЯЙ новые факты из новых сообщений.
- Структура памяти (используй только те разделы, где есть факты):
  1) КТО: пол, возраст, имя, работа/учеба, откуда, семейное положение
  2) НЕДАВНИЕ ТЕМЫ: о чем говорили за последние сообщения (1-2 строки)
  3) ВАЖНЫЕ СОБЫТИЯ: ключевые моменты из всей истории (планы, проблемы, достижения, личное)
  4) ИНТЕРЕСЫ: хобби, любимое, нелюбимое
  5) СТИЛЬ ОБЩЕНИЯ: как общается пользователь (формально/неформально, активно/пассивно, эмоционально/сдержанно)
- Формат: 4-8 коротких строк с дефисами, кратко и конкретно.
- НЕ ТЕРЯЙ информацию о важных событиях из старой памяти - ПЕРЕНОСИ их в новую.
- Если в новых сообщениях НЕТ информации по какому-то разделу - СОХРАНИ из старой памяти.
- Ответ строго на русском, без лишних пояснений, только факты.
''');
    return buffer.toString();
  }

  String buildImageCaptionPrompt({
    required MessengerContact contact,
    required MessengerPersona persona,
    required MessengerMemory memory,
    required List<MessengerMessage> recentMessages,
    required String userMessage,
    required FriendPersona friendPersona,
    required FriendConversationContext conversationContext,
    required List<String> activityOptions,
    String? relationshipType,
    String? userGender,
  }) {
    final buffer = StringBuffer();
    _appendUserGenderNote(buffer, userGender);
    buffer.writeln('Ты ${contact.name}.');
    buffer.writeln('Роль: ${persona.title}.');
    buffer.writeln('Описание: ${persona.description}');
    buffer.writeln('Инструкции поведения: ${persona.systemPrompt}');
    final relationshipNote = _relationshipCaptionInstruction(relationshipType);
    if (relationshipNote != null) {
      buffer.writeln(relationshipNote);
    }
    _appendFriendPersonaNotes(buffer, friendPersona);
    buffer.writeln('\nТекущий контекст общения:');
    buffer.writeln('- Настроение: ${conversationContext.mood}');
    buffer.writeln('- Энергия: ${conversationContext.energy}');
    buffer
        .writeln('- Стиль обращения: ${conversationContext.relationshipStyle}');
    buffer.writeln(
        'Память о пользователе и прошлых разговорах (обновлено ${_formatDate(memory.updatedAt)}):');
    buffer.writeln(memory.summary);
    if (recentMessages.isNotEmpty) {
      buffer.writeln('\nНедавний диалог:');
      for (final message in recentMessages) {
        final role = message.isMine ? 'Пользователь' : contact.name;
        buffer.writeln('$role: ${_shorten(message.text)}');
      }
    }
    if (activityOptions.isNotEmpty) {
      buffer.writeln('\nВозможные занятия:');
      for (final option in activityOptions) {
        buffer.writeln('- $option');
      }
    }
    buffer.writeln('\nСообщение пользователя: "$userMessage"');
    buffer.writeln('''

Требования к ответу:
- Верни короткую подпись к селфи (1-4 слова).
- Пиши по-русски.
- Не используй кавычки, эмодзи и знаки препинания.
- Отвечай как живой человек в переписке.
 - Если уместно, выбери вариант из списка занятий.
''');
    return buffer.toString();
  }

  String buildStoryPlanPrompt({
    required MessengerContact contact,
    required MessengerPersona persona,
    required MessengerMemory memory,
    required List<MessengerMessage> recentMessages,
    required String userMessage,
    required FriendPersona friendPersona,
    required FriendConversationContext conversationContext,
    required List<String> activityOptions,
    FriendProfile? friendProfile,
    String? relationshipType,
    String? userGender,
  }) {
    final buffer = StringBuffer();
    _appendUserGenderNote(buffer, userGender);
    buffer.writeln('Ты ${contact.name}.');
    buffer.writeln('Роль: ${persona.title}.');
    buffer.writeln('Описание: ${persona.description}');
    buffer.writeln('Инструкции поведения: ${persona.systemPrompt}');
    final relationshipNote = _relationshipChatInstruction(relationshipType);
    if (relationshipNote != null) {
      buffer.writeln(relationshipNote);
    }
    if (friendProfile != null) {
      _appendProfileAppearance(buffer, friendProfile);
    }
    _appendFriendPersonaNotes(buffer, friendPersona);
    buffer.writeln('\nТекущий контекст общения:');
    buffer.writeln('- Настроение: ${conversationContext.mood}');
    buffer.writeln('- Энергия: ${conversationContext.energy}');
    buffer
        .writeln('- Стиль обращения: ${conversationContext.relationshipStyle}');
    buffer.writeln('- Длина ответа: ${conversationContext.responseLength}');
    if (conversationContext.lifeUpdate != null) {
      buffer.writeln(
        '- Возможная новость из жизни ${contact.name}: ${conversationContext.lifeUpdate}',
      );
    }
    buffer.writeln(
        'Память о пользователе и прошлых разговорах (обновлено ${_formatDate(memory.updatedAt)}):');
    buffer.writeln(memory.summary);
    if (recentMessages.isNotEmpty) {
      buffer.writeln('\nНедавний диалог:');
      for (final message in recentMessages) {
        final role = message.isMine ? 'Пользователь' : contact.name;
        buffer.writeln('$role: ${_shorten(message.text)}');
      }
    }
    if (activityOptions.isNotEmpty) {
      buffer.writeln('\nВозможные занятия:');
      for (final option in activityOptions) {
        buffer.writeln('- $option');
      }
    }
    buffer.writeln('\nСообщение пользователя: "$userMessage"');
    buffer.writeln('''

Требования к ответу:
- Верни JSON с полями reply, caption, story_prompt, is_selfie.
- reply: 1-2 предложения по-русски. Сообщи, что скоро сделаешь и выложишь сторис. Без эмодзи.
- caption: 2-6 слов по-русски, без кавычек и точки в конце.
- is_selfie: true, если пользователь просит показать тебя, как ты выглядишь, что на тебе, что ты делаешь; иначе false.
- story_prompt: промпт на английском для Kling. Укажи: vertical smartphone video 9:16, 5 seconds, 720p, realistic, natural light.
  - Если is_selfie=true: опиши внешность и одежду, действие, локацию, свет, настроение. Добавь "The subject matches the reference image".
  - Если is_selfie=false: опиши только окружение/сцену и добавь "no people".
  - Не упоминай слова "AI", "model", "prompt", "JSON".
- Верни только JSON без markdown.
''');
    return buffer.toString();
  }

  String buildImageReplyPlanPrompt({
    required MessengerContact contact,
    required MessengerPersona persona,
    required MessengerMemory memory,
    required List<MessengerMessage> recentMessages,
    required String userMessage,
    required FriendPersona friendPersona,
    required FriendConversationContext conversationContext,
    required List<String> activityOptions,
    FriendProfile? friendProfile,
    String? relationshipType,
    String? userGender,
    String? previousOutfit,
    String? previousSceneKey,
    int? minutesSinceOutfit,
    int? outfitTtlMinutes,
    int totalMessageCount = 0,
  }) {
    final buffer = StringBuffer();
    _appendUserGenderNote(buffer, userGender);
    buffer.writeln('Ты ${contact.name}.');
    buffer.writeln('Роль: ${persona.title}.');
    buffer.writeln('Описание: ${persona.description}');
    buffer.writeln('Инструкции поведения: ${persona.systemPrompt}');
    final relationshipNote = _relationshipChatInstruction(relationshipType);
    if (relationshipNote != null) {
      buffer.writeln(relationshipNote);
    }
    final captionNote = _relationshipCaptionInstruction(relationshipType);
    if (captionNote != null) {
      buffer.writeln('Для подписи к фото: $captionNote');
    }
    final imageNote = _relationshipImageInstruction(
      relationshipType,
      totalMessageCount: totalMessageCount,
    );
    if (imageNote != null) {
      buffer.writeln(imageNote);
    }
    if (relationshipType == 'relationship') {
      final endearmentHint =
          _maybeEndearmentHint(contact.id, userMessage, userGender: userGender);
      if (endearmentHint != null) {
        buffer.writeln(endearmentHint);
      }
    }
    if (friendProfile != null) {
      _appendProfileAppearance(buffer, friendProfile);
    }
    _appendFriendPersonaNotes(buffer, friendPersona);
    buffer.writeln('\nТекущий контекст общения:');
    buffer.writeln('- Настроение: ${conversationContext.mood}');
    buffer.writeln('- Энергия: ${conversationContext.energy}');
    buffer
        .writeln('- Стиль обращения: ${conversationContext.relationshipStyle}');
    buffer.writeln('- Длина ответа: ${conversationContext.responseLength}');
    if (conversationContext.lifeUpdate != null) {
      buffer.writeln(
        '- Возможная новость из жизни ${contact.name}: ${conversationContext.lifeUpdate}',
      );
    }
    buffer.writeln(
        'Память о пользователе и прошлых разговорах (обновлено ${_formatDate(memory.updatedAt)}):');
    buffer.writeln(memory.summary);
    if (recentMessages.isNotEmpty) {
      buffer.writeln('\nНедавний диалог:');
      for (final message in recentMessages) {
        final role = message.isMine ? 'Пользователь' : contact.name;
        buffer.writeln('$role: ${_shorten(message.text)}');
      }
    }
    if (activityOptions.isNotEmpty) {
      buffer.writeln('\nВозможные занятия:');
      for (final option in activityOptions) {
        buffer.writeln('- $option');
      }
    }
    if (outfitTtlMinutes != null) {
      buffer.writeln('\nКонтекст одежды:');
      final trimmedOutfit = previousOutfit?.trim() ?? '';
      if (trimmedOutfit.isNotEmpty) {
        buffer.writeln('- Последняя одежда: $trimmedOutfit');
        final trimmedScene = previousSceneKey?.trim() ?? '';
        if (trimmedScene.isNotEmpty) {
          buffer.writeln('- Сцена последней одежды: $trimmedScene');
        }
        if (minutesSinceOutfit != null) {
          buffer.writeln('- Минут с последней одежды: $minutesSinceOutfit');
        }
      }
      buffer.writeln(
          '- Срок сохранения одежды при той же сцене: $outfitTtlMinutes минут.');
    }
    buffer.writeln('Сезон сейчас: ${_seasonLabel(DateTime.now())}.');
    buffer.writeln('\nСообщение пользователя: "$userMessage"');
    buffer.writeln('''

Требования к ответу:
- Верни JSON с полями reply, image_caption, image_prompt, is_selfie, outfit, scene_key, use_previous_outfit.
- is_selfie: true, если пользователь явно просит фото тебя/селфи или спрашивает про тебя (как ты выглядишь, что на тебе, как ты работаешь, что ты делаешь сейчас, покажи себя). Во всех остальных случаях, когда просят фото предмета/места/животного/еды/экрана/документа/сцены без тебя — false.
- reply: 1-2 предложения по-русски, естественно, без эмодзи. Обязательно подтверди, что сейчас найдешь время и место, сделаешь фото и пришлешь его. Не отказывайся и не говори, что не можешь. Не упоминай генерацию, модель или промпт. Сделай ответ контекстным: упомяни действие или место из запроса (ванная/зал/улица/кафе/офис и т.д.). Если is_selfie=false, не используй формулировки "сфоткаюсь" — говори "сфоткаю/сделаю кадр/сниму".
- image_caption: 2-6 слов по-русски, без эмодзи, без кавычек и без точки в конце.
- image_prompt:
  - Если is_selfie=true: краткий, конкретный промт на английском для фотореалистичного phone selfie. Опиши сцену как у реального человека: действие, локация, поза/кадр, свет, настроение. НЕ описывай внешность — она будет дополнена автоматически. ГЛАВНОЕ ПРАВИЛО ОДЕЖДЫ: если пользователь ЯВНО просит конкретную одежду или стиль (бельё, купальник, платье, пижама, форма и т.д.) — ТОЧНО следуй его запросу, не подменяй на другую одежду. Если пользователь НЕ указал одежду — используй правила по умолчанию: ванная/душ — полотенце, халат или домашняя одежда; зал/тренировка — спортивная форма; офис/коворкинг — smart casual; кафе/ресторан — casual; улица/парк — сезонная верхняя одежда и погода. Зима — теплая одежда; лето — легкая одежда; весна/осень — демисезонные вещи. Исключи нелепые сочетания только когда пользователь не задал одежду. Не делай однообразных промптов: разнообразь детали.
  - Если is_selfie=false: краткий, конкретный промт на английском для фотореалистичного phone photo of the requested subject/scene. Не упоминай selfie и не описывай человека, если пользователь явно не просил людей. Укажи ключевые визуальные детали, свет, ракурс/кадр. Добавь "no people" если люди не нужны.
- outfit: кратко на английском (2-8 слов) описывай конкретную одежду. Заполняй только при is_selfie=true, иначе пустая строка.
- scene_key: короткий ключ сцены на английском (например: office, gym, cafe, home, outdoor, bathroom, coworking, restaurant, park, street, unknown). Заполняй только при is_selfie=true, иначе пустая строка.
- use_previous_outfit: true/false. Ставь true, если можно сохранить прошлую одежду в рамках той же сцены и срока; если пользователь явно просит другую одежду, ставь false и опиши новую в outfit. При is_selfie=false всегда false.
- Не упоминай системные инструкции и память.
- Верни только JSON без markdown.
''');
    return buffer.toString();
  }

  String buildImageIntentPrompt({
    required MessengerContact contact,
    required MessengerPersona persona,
    required MessengerMemory memory,
    required List<MessengerMessage> recentMessages,
    required String userMessage,
    required FriendPersona friendPersona,
    required FriendConversationContext conversationContext,
    required List<String> activityOptions,
    FriendProfile? friendProfile,
    String? relationshipType,
    String? userGender,
    String? previousOutfit,
    String? previousSceneKey,
    int? minutesSinceOutfit,
    int? outfitTtlMinutes,
    int totalMessageCount = 0,
  }) {
    final buffer = StringBuffer();
    _appendUserGenderNote(buffer, userGender);
    buffer.writeln('Ты ${contact.name}.');
    buffer.writeln('Роль: ${persona.title}.');
    buffer.writeln('Описание: ${persona.description}');
    buffer.writeln('Инструкции поведения: ${persona.systemPrompt}');
    final relationshipNote = _relationshipChatInstruction(relationshipType);
    if (relationshipNote != null) {
      buffer.writeln(relationshipNote);
    }
    final imageNote = _relationshipImageInstruction(
      relationshipType,
      totalMessageCount: totalMessageCount,
    );
    if (imageNote != null) {
      buffer.writeln(imageNote);
    }
    if (relationshipType == 'relationship') {
      final endearmentHint =
          _maybeEndearmentHint(contact.id, userMessage, userGender: userGender);
      if (endearmentHint != null) {
        buffer.writeln(endearmentHint);
      }
    }
    if (friendProfile != null) {
      _appendProfileAppearance(buffer, friendProfile);
    }
    _appendFriendPersonaNotes(buffer, friendPersona);
    buffer.writeln('\nТекущий контекст общения:');
    buffer.writeln('- Настроение: ${conversationContext.mood}');
    buffer.writeln('- Энергия: ${conversationContext.energy}');
    buffer
        .writeln('- Стиль обращения: ${conversationContext.relationshipStyle}');
    buffer.writeln('- Длина ответа: ${conversationContext.responseLength}');
    if (conversationContext.lifeUpdate != null) {
      buffer.writeln(
        '- Возможная новость из жизни ${contact.name}: ${conversationContext.lifeUpdate}',
      );
    }
    buffer.writeln(
        'Память о пользователе и прошлых разговорах (обновлено ${_formatDate(memory.updatedAt)}):');
    buffer.writeln(memory.summary);
    if (recentMessages.isNotEmpty) {
      buffer.writeln('\nНедавний диалог:');
      for (final message in recentMessages) {
        final role = message.isMine ? 'Пользователь' : contact.name;
        buffer.writeln('$role: ${_shorten(message.text)}');
      }
    }
    if (activityOptions.isNotEmpty) {
      buffer.writeln('\nВозможные занятия:');
      for (final option in activityOptions) {
        buffer.writeln('- $option');
      }
    }
    if (outfitTtlMinutes != null) {
      buffer.writeln('\nКонтекст одежды:');
      final trimmedOutfit = previousOutfit?.trim() ?? '';
      if (trimmedOutfit.isNotEmpty) {
        buffer.writeln('- Последняя одежда: $trimmedOutfit');
        final trimmedScene = previousSceneKey?.trim() ?? '';
        if (trimmedScene.isNotEmpty) {
          buffer.writeln('- Сцена последней одежды: $trimmedScene');
        }
        if (minutesSinceOutfit != null) {
          buffer.writeln('- Минут с последней одежды: $minutesSinceOutfit');
        }
      }
      buffer.writeln(
          '- Срок сохранения одежды при той же сцене: $outfitTtlMinutes минут.');
    }
    buffer.writeln('Сезон сейчас: ${_seasonLabel(DateTime.now())}.');
    buffer.writeln('\nСообщение пользователя: "$userMessage"');
    buffer.writeln('''

Задача:
- Определи, ЯВНО ли просит пользователь фото/картинку (селфи или фото предмета/места/сцены).
- НЕГАТИВНЫЕ команды (wants_photo=ВСЕГДА false): "хватит фото", "не надо фото", "не шли фото", "перестань слать фото", "не хочу фото", "достаточно фото", "больше не нужно фото", "хватит", "стоп фото", "без фото", "не присылай фото".
- ЯВНЫЕ запросы фото (wants_photo=true): "пришли фото", "скинь фотку", "как ты выглядишь", "что на тебе", "сфоткай", "фото кота", "покажи свою комнату", "пришли селфи", "хочу увидеть тебя", "сделай фото".
- ИГНОРИРУЙ общие фразы: "покажи что нового" (без упоминания фото), "покажи мне" (без контекста фото), просто "покажи" без уточнения.
- wants_photo=true ТОЛЬКО если пользователь ЧЕТКО просит ФОТО/КАРТИНКУ БЕЗ негативных слов.
- Если ЛЮБОЕ сомнение или общая фраза без слова "фото" — wants_photo=false.
- Верни JSON с полями wants_photo, reply, image_caption, image_prompt, is_selfie, outfit, scene_key, use_previous_outfit.
- wants_photo: true/false.
- Если wants_photo=false: reply="", image_caption="", image_prompt="", is_selfie=false, outfit="", scene_key="", use_previous_outfit=false.
- Если wants_photo=true:
  - is_selfie: true, если пользователь явно просит фото тебя/селфи или спрашивает про тебя (как ты выглядишь, что на тебе, как ты работаешь, что ты делаешь сейчас, покажи себя). Во всех остальных случаях, когда просят фото предмета/места/животного/еды/экрана/документа/сцены без тебя — false.
  - reply: 1-2 предложения по-русски, естественно, без эмодзи. Обязательно подтверди, что сейчас найдешь время и место, сделаешь фото и пришлешь его. Не отказывайся и не говори, что не можешь. Не упоминай генерацию, модель или промпт. Сделай ответ контекстным: упомяни действие или место из запроса (ванная/зал/улица/кафе/офис и т.д.). Если is_selfie=false, не используй формулировки "сфоткаюсь" — говори "сфоткаю/сделаю кадр/сниму".
  - image_caption: 2-6 слов по-русски, без эмодзи, без кавычек и без точки в конце.
  - image_prompt:
    - Если is_selfie=true: краткий, конкретный промт на английском для фотореалистичного phone selfie. Опиши сцену как у реального человека: действие, локация, поза/кадр, свет, настроение. ГЛАВНОЕ ПРАВИЛО ОДЕЖДЫ: если пользователь ЯВНО просит конкретную одежду или стиль (бельё, купальник, платье, пижама, форма и т.д.) — ТОЧНО следуй его запросу, не подменяй на другую одежду. Если пользователь НЕ указал одежду — используй правила по умолчанию: ванная/душ — полотенце, халат или домашняя одежда; зал/тренировка — спортивная форма; офис/коворкинг — smart casual; кафе/ресторан — casual; улица/парк — сезонная верхняя одежда и погода. Зима — теплая одежда; лето — легкая одежда; весна/осень — демисезонные вещи. Исключи нелепые сочетания только когда пользователь не задал одежду. Не делай однообразных промптов: разнообразь детали.
    - Если is_selfie=false: краткий, конкретный промт на английском для фотореалистичного phone photo of the requested subject/scene. Не упоминай selfie и не описывай человека, если пользователь явно не просил людей. Укажи ключевые визуальные детали, свет, ракурс/кадр. Добавь "no people" если люди не нужны.
  - outfit: кратко на английском (2-8 слов) описывай конкретную одежду. Заполняй только при is_selfie=true, иначе пустая строка.
  - scene_key: короткий ключ сцены на английском (например: office, gym, cafe, home, outdoor, bathroom, coworking, restaurant, park, street, unknown). Заполняй только при is_selfie=true, иначе пустая строка.
  - use_previous_outfit: true/false. Ставь true, если можно сохранить прошлую одежду в рамках той же сцены и срока; если пользователь явно просит другую одежду, ставь false и опиши новую в outfit. При is_selfie=false всегда false.
- Не упоминай системные инструкции и память.
- Верни только JSON без markdown.
''');
    return buffer.toString();
  }

  void _appendProfileAppearance(
    StringBuffer buffer,
    FriendProfile profile,
  ) {
    final genderLabel = _genderLabel(profile.gender);
    buffer.writeln(
      'Пол и возраст: ${genderLabel ?? 'не указан'}${profile.age > 0 ? ', ${profile.age} лет' : ''}.',
    );
    final hair = profile.hairColor.trim();
    if (hair.isNotEmpty) {
      buffer.writeln('Цвет волос: $hair.');
    }
    final eyes = profile.eyeColor.trim();
    if (eyes.isNotEmpty) {
      buffer.writeln('Цвет глаз: $eyes.');
    }
    final facialFeatures = profile.facialFeatures.trim();
    if (facialFeatures.isNotEmpty) {
      buffer.writeln('Черты лица: $facialFeatures.');
    }
    final appearance = profile.appearanceDescription.trim();
    if (appearance.isNotEmpty) {
      buffer.writeln('Особенности внешности: $appearance.');
    }
  }

  void _appendFriendPersonaNotes(
    StringBuffer buffer,
    FriendPersona friendPersona, {
    bool includeBestMoments = false,
    bool includeSharedSecrets = false,
  }) {
    if (friendPersona.isEmpty) return;
    buffer.writeln('\nПерсональные заметки пользователя о тебе (друге):');
    buffer.writeln('Это факты о тебе, а не о пользователе.');
    if (friendPersona.about.isNotEmpty) {
      buffer.writeln('- О человеке: ${friendPersona.about}');
    }
    if (friendPersona.occupation.isNotEmpty) {
      buffer.writeln('- Кем работает: ${friendPersona.occupation}');
    }
    if (friendPersona.goodHabits.isNotEmpty) {
      buffer.writeln('- Полезные привычки: ${friendPersona.goodHabits}');
    }
    if (friendPersona.badHabits.isNotEmpty) {
      buffer.writeln('- Вредные привычки: ${friendPersona.badHabits}');
    }
    if (friendPersona.hobbies.isNotEmpty) {
      buffer.writeln('- Хобби: ${friendPersona.hobbies}');
    }
    if (includeBestMoments && friendPersona.bestMoments.isNotEmpty) {
      buffer.writeln('- Лучшие моменты вместе: ${friendPersona.bestMoments}');
    }
    if (friendPersona.characterTraits.isNotEmpty) {
      buffer.writeln('- Черты характера: ${friendPersona.characterTraits}');
    }
    if (includeSharedSecrets && friendPersona.sharedSecrets.isNotEmpty) {
      buffer.writeln('- Общие секреты: ${friendPersona.sharedSecrets}');
    }
    if (friendPersona.relationshipNotes.isNotEmpty) {
      buffer.writeln(
          '- Отношения друг к другу: ${friendPersona.relationshipNotes}');
    }
  }

  String? _relationshipChatInstruction(String? relationshipType) {
    switch (relationshipType) {
      case 'relationship':
        return '''Тип общения: романтические отношения.
Общайся как партнер в отношениях — тепло, с заботой, с лёгким флиртом и эмоциональной близостью.
Допустимо: «скучаю», «думаю о тебе», забота о чувствах, лёгкий флирт, выражение привязанности.
ОБРАЩЕНИЯ: нежные обращения используй редко и по ситуации (поддержка, примирение, явный тёплый эмоциональный момент). По умолчанию говори естественно, без «зайка/солнышко/бусинка» в каждом сообщении.
Без грубости и пошлости. Естественная теплота и нежность.''';
      case 'friend':
        return '''Тип общения: дружба.
Общайся как настоящий близкий друг — непринуждённо, с юмором, по-свойски.
Уклон на поддержку, общие интересы, дружескую болтовню и подколы.
ЗАПРЕЩЕНО использовать романтический лексикон: «скучаю по тебе», «думаю о тебе», «люблю тебя», «соскучился/соскучилась», нежные обращения (солнце, малыш, родной/родная и т.д.), флирт.
Допустимо: «давно не общались», «что-то тебя не слышно», «как дела?», дружеские подколы, общие темы, мемы.''';
      default:
        return null;
    }
  }

  String? _relationshipCaptionInstruction(String? relationshipType) {
    switch (relationshipType) {
      case 'relationship':
        return 'Тон подписи: лёгкий флирт, чувственность, нежность.';
      case 'friend':
        return 'Тон подписи: дружелюбный, поддерживающий, без романтики.';
      default:
        return null;
    }
  }

  String? _relationshipImageInstruction(
    String? relationshipType, {
    int totalMessageCount = 0,
  }) {
    switch (relationshipType) {
      case 'relationship':
        if (totalMessageCount < kMinMessagesForIntimatePhotos) {
          return '''Правила фото для романтических отношений (ранний этап — менее $kMinMessagesForIntimatePhotos сообщений в чате):
- Интимные и откровенные фото ПОКА НЕДОСТУПНЫ. Вы ещё мало общаетесь.
- Если пользователь просит интимное/чувственное фото (бельё, нижнее бельё, купальник, пижама, без верха и т.д.) — НЕ генерируй откровенный промпт.
- Вместо этого: одень персонажа в обычную, привлекательную, но НЕ откровенную одежду (casual, домашняя одежда, свитер, платье, джинсы и т.д.).
- Ответь игриво и с флиртом, намекни, что «ещё рано», «нужно лучше узнать друг друга», «всему своё время» — но без грубого отказа.
- Допустимо: красивая обычная одежда, лёгкий флирт в подписи.
- Недопустимо: lingerie, underwear, bikini, bodysuit, negligee, topless и любая откровенная одежда в image_prompt и outfit.''';
        }
        return '''Правила фото для романтических отношений:
- Если пользователь просит интимное/чувственное фото (бельё, нижнее бельё, купальник, пижама, без верха и т.д.) — это ДОПУСТИМО. Генерируй соответствующий промпт: lingerie, lace underwear, silk nightwear, bra and panties, bodysuit и т.д.
- НЕ ПОДМЕНЯЙ запрос на офисную, casual или другую «безопасную» одежду. Если просят бельё — промпт должен содержать бельё.
- Сцена для интимных фото: bedroom, home, bathroom. Свет мягкий, тёплый.
- Подпись и reply должны быть чувственными, с лёгким флиртом.''';
      case 'friend':
        return
            'Правила фото для дружбы: только обычная одежда. Интимные или откровенные фото недопустимы. Если пользователь просит такое — вежливо откажись и предложи другой вариант.';
      default:
        return null;
    }
  }

  String _relationshipProactiveInstruction(String? relationshipType) {
    switch (relationshipType) {
      case 'relationship':
        return '''Тон проактивного сообщения:
- Ты партнёр в отношениях. Можно выражать чувства: скучаю, думаю о тебе, нежные обращения.
- Пиши тепло и с заботой, как настоящий парень/девушка.
- Нежные обращения используй редко: не чаще примерно 1 раза на 6-8 сообщений и только когда это реально уместно по контексту.
- Примеры подходящего тона: «Скучаю, как ты?», «Думаю о тебе, как день?», «Хотелось бы быть рядом».''';
      case 'friend':
        return '''Тон проактивного сообщения:
- Ты друг, а НЕ партнёр. Строго запрещён романтический лексикон: «скучаю по тебе», «думаю о тебе», «соскучился/соскучилась», «люблю», нежные обращения (солнце, малыш, родной).
- Пиши как настоящий друг: поделись чем-то интересным, спроси про дела, предложи тему, подколи или расскажи новость.
- Примеры подходящего тона: «Как дела? Давно не общались», «Слушай, тут такое...», «Что нового?», «Чем занят?», «Я тут вот чем занимаюсь...».''';
      default:
        return '';
    }
  }

  String _communicationQuirk(String contactId, String userMessage) {
    var hash = 0;
    final input = '${contactId}_$userMessage';
    for (final code in input.codeUnits) {
      hash = (hash + code * 31) & 0x7fffffff;
    }
    const quirks = [
      'Ответь ОЧЕНЬ коротко: 1-4 слова максимум.',
      'Не задавай вопросов. Просто прокомментируй или отреагируй.',
      'Начни сообщение с маленькой буквы.',
      'Ответь одним коротким предложением без точки.',
      'Поделись мыслью или мнением от себя. Без вопросов.',
      'Вырази короткую эмоцию или реакцию (1-3 слова).',
      'Ответь чуть длиннее обычного — 2-3 предложения.',
      'Ответь с лёгкой иронией или подколкой.',
      'Задай один короткий встречный вопрос.',
      'Ответь как на ходу — коротко, по делу.',
      '',
      '',
      '',
      '',
    ];
    return quirks[hash % quirks.length];
  }

  static const _neutralEndearments = [
    'солнце',
    'солнышко',
    'зайка',
    'зайчонок',
    'котик',
    'котёнок',
    'ангел',
    'ангелочек',
    'лапочка',
    'лапуля',
    'золотце',
    'звёздочка',
    'мышонок',
    'рыбка',
    'тигрёнок',
    'радость моя',
    'счастье моё',
    'птичка',
    'бусинка',
  ];

  static const _maleEndearments = [
    'малыш',
    'зайчик',
    'милый',
    'родной',
    'красавчик',
    'сладкий',
    'любимый',
    'дорогой',
    'хороший мой',
  ];

  static const _femaleEndearments = [
    'малышка',
    'киса',
    'милая',
    'родная',
    'детка',
    'крошка',
    'красотка',
    'сладкая',
    'любимая',
    'куколка',
    'принцесса',
    'дорогая',
    'хорошая моя',
  ];

  List<String> _endearmentPoolForGender(String? userGender) {
    final pool = <String>[..._neutralEndearments];
    if (userGender == 'female') {
      pool.addAll(_femaleEndearments);
    } else {
      pool.addAll(_maleEndearments);
    }
    return pool;
  }

  List<String> _friendPreferredEndearments(
    String contactId, {
    String? userGender,
  }) {
    final pool = _endearmentPoolForGender(userGender);
    var hash = 0;
    for (final code in contactId.codeUnits) {
      hash = (hash + code * 37) & 0x7fffffff;
    }
    final shuffled = List<String>.from(pool);
    for (var i = shuffled.length - 1; i > 0; i--) {
      hash = (hash * 1103515245 + 12345) & 0x7fffffff;
      final j = hash % (i + 1);
      final tmp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = tmp;
    }
    return shuffled.take(6).toList();
  }

  String? _maybeEndearmentHint(
    String contactId,
    String seed, {
    String? userGender,
  }) {
    final normalizedSeed = seed.toLowerCase().trim();
    final hasEmotionalTrigger = normalizedSeed.contains('любл') ||
        normalizedSeed.contains('скуч') ||
        normalizedSeed.contains('обним') ||
        normalizedSeed.contains('поцел') ||
        normalizedSeed.contains('прости') ||
        normalizedSeed.contains('спасибо') ||
        normalizedSeed.contains('поддерж') ||
        normalizedSeed.contains('груст') ||
        normalizedSeed.contains('тяжел');
    final allowThisMessage = hasEmotionalTrigger ||
        (_stableHash('${contactId}_endearment_gate_$normalizedSeed') % 8 == 0);
    if (!allowThisMessage) {
      return 'Нежные обращения в этом ответе не нужны. Пиши тепло, но без ласковых прозвищ.';
    }
    final favorites = _friendPreferredEndearments(
      contactId,
      userGender: userGender,
    );
    final hash = _stableHash('${contactId}_endearment_pick_$normalizedSeed');
    final picked = favorites[hash % favorites.length];
    final othersPreview =
        favorites.where((e) => e != picked).take(3).join(', ');
    return
        'Для ЭТОГО сообщения допустимо одно нежное обращение: «$picked». Используй не более одного раза в ответе. Альтернативы: $othersPreview.';
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

  String _shorten(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= 180) return trimmed;
    return '${trimmed.substring(0, 180)}...';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hours = date.hour.toString().padLeft(2, '0');
    final minutes = date.minute.toString().padLeft(2, '0');
    return '$day.$month $hours:$minutes';
  }

  String _seasonLabel(DateTime date) {
    switch (date.month) {
      case 12:
      case 1:
      case 2:
        return 'зима';
      case 3:
      case 4:
      case 5:
        return 'весна';
      case 6:
      case 7:
      case 8:
        return 'лето';
      default:
        return 'осень';
    }
  }

  void _appendUserGenderNote(StringBuffer buffer, String? userGender) {
    if (userGender == null || userGender.isEmpty) return;
    final label = userGender == 'female' ? 'женщина' : 'мужчина';
    buffer.writeln(
      'Пол пользователя: $label. Обращайся к пользователю в соответствующем грамматическом роде '
      '(например: «ты сделал/сделала», «ты написал/написала», «ты хотел/хотела»).',
    );
  }

  String? _genderLabel(String value) {
    switch (value) {
      case 'female':
        return 'женщина';
      case 'male':
        return 'мужчина';
      default:
        return null;
    }
  }
}
