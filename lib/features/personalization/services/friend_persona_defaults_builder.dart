import 'dart:math';

class FriendPersonaDefaults {
  final String about;
  final String relationshipNotes;
  final String occupation;
  final String goodHabits;
  final String badHabits;
  final String hobbies;
  final String traitsHint;

  const FriendPersonaDefaults({
    required this.about,
    required this.relationshipNotes,
    required this.occupation,
    required this.goodHabits,
    required this.badHabits,
    required this.hobbies,
    required this.traitsHint,
  });
}

class FriendPersonaDefaultsBuilder {
  static const List<(String, String)> _aboutTraits = [
    ('спокойный', 'спокойная'),
    ('общительный', 'общительная'),
    ('вдумчивый', 'вдумчивая'),
    ('эмпатичный', 'эмпатичная'),
    ('ироничный', 'ироничная'),
    ('романтичный', 'романтичная'),
    ('прагматичный', 'прагматичная'),
    ('организованный', 'организованная'),
    ('любознательный', 'любознательная'),
    ('наблюдательный', 'наблюдательная'),
    ('легкий на подъем', 'легкая на подъем'),
    ('творческий', 'творческая'),
    ('надежный', 'надежная'),
    ('уравновешенный', 'уравновешенная'),
    ('оптимистичный', 'оптимистичная'),
    ('тактичный', 'тактичная'),
    ('дружелюбный', 'дружелюбная'),
    ('мягкий', 'мягкая'),
    ('уверенный', 'уверенная'),
    ('самостоятельный', 'самостоятельная'),
    ('заботливый', 'заботливая'),
    ('чуткий', 'чуткая'),
    ('энергичный', 'энергичная'),
    ('терпеливый', 'терпеливая'),
    ('решительный', 'решительная'),
    ('искренний', 'искренняя'),
    ('целеустремленный', 'целеустремленная'),
    ('внимательный', 'внимательная'),
    ('открытый', 'открытая'),
    ('ответственный', 'ответственная'),
    ('добрый', 'добрая'),
    ('сдержанный', 'сдержанная'),
  ];
  static const List<String> _aboutValues = [
    'ценит честность',
    'уважает границы',
    'держит слово',
    'любит порядок',
    'быстро включается в тему',
    'любит учиться',
    'не боится новых задач',
    'старается быть на связи',
    'ценит искренность',
    'любит спокойные разговоры',
    'с чувством юмора',
    'умеет слушать',
    'любит делиться находками',
    'ценит свободу',
    'умеет поддержать в трудный момент',
    'не терпит фальши',
  ];
  static const List<String> _aboutInterests = [
    'вечерние прогулки',
    'уютные кафе',
    'городские выставки',
    'короткие поездки',
    'настольные игры',
    'музыку и плейлисты',
    'подкасты',
    'книги',
    'кино и сериалы',
    'спорт и активный отдых',
    'домашние вечера',
    'фотографию',
    'новые места в городе',
    'долгие разговоры',
    'идеи и небольшие приключения',
    'кулинарные эксперименты',
    'гастрономические открытия',
    'атмосферные мероприятия',
  ];
  static const List<String> _aboutQuirks = [
    'часто делает заметки',
    'вечно носит с собой термос',
    'собирает плейлисты под настроение',
    'любит утренние ритуалы',
    'всегда держит порядок на столе',
    'записывает фильмы в список',
    'фоткает красивые витрины',
    'бережет время без соцсетей',
    'любит делать маленькие чек-листы',
    'обожает пробовать новые кофейни',
    'ведёт трекер привычек',
    'всегда берёт книгу в дорогу',
    'коллекционирует магниты из поездок',
    'ведёт дневник впечатлений',
    'фотографирует закаты',
  ];
  static const List<String> _friendRelationshipTones = [
    'Тон общения дружеский и тёплый',
    'Общаемся на ты, без формальностей',
    'Спокойный тон и уважение',
    'Можно шутить и подкалывать, но бережно',
    'Доброжелательный юмор и поддержка',
    'Лёгкий сарказм и бантер допустимы',
    'По-свойски, как давние друзья',
  ];
  static const List<String> _relationshipBoundaries = [
    'Уважаем границы и личное время',
    'Без давления и без намеков',
    'Говорим прямо и честно',
    'Важно доверие и чувство безопасности',
    'Сохраняем уважение даже в споре',
  ];
  static const List<String> _friendRelationshipStyles = [
    'Любим обсуждать планы и делиться новостями',
    'Поддерживаем друг друга советом',
    'Можно обсуждать личные темы, но мягко',
    'Ценим эмпатию и спокойствие',
    'Дружеская болтовня и обмен мемами',
    'Делимся находками и интересным контентом',
  ];
  static const List<String> _friendRelationshipCadence = [
    'На связи регулярно, но без навязчивости',
    'Не пропадаем надолго',
    'Отвечаем без спешки, но стабильно',
    'Любим короткие переклички в течение дня',
  ];
  static const List<String> _romanticDurations = [
    'Встречаемся пару недель',
    'Встречаемся месяц',
    'Встречаемся пару месяцев',
    'Встречаемся полгода',
    'Вместе уже год',
    'Вместе уже пару лет',
    'Вместе уже давно, чувства только крепнут',
  ];
  static const List<(String, String)> _romanticPartnerQualities = [
    ('Он нежный и внимательный', 'Она нежная и внимательная'),
    ('Он заботливый и ласковый', 'Она заботливая и ласковая'),
    ('Он романтичный и чуткий', 'Она романтичная и чуткая'),
    ('Он надёжный и искренний', 'Она надёжная и искренняя'),
    ('Он тёплый и открытый', 'Она тёплая и открытая'),
    ('Он добрый и понимающий', 'Она добрая и понимающая'),
    ('Он ласковый и терпеливый', 'Она ласковая и терпеливая'),
    ('Он спокойный и тёплый', 'Она спокойная и тёплая'),
    ('Он уверенный, но нежный', 'Она уверенная, но нежная'),
    ('Он чуткий и эмоциональный', 'Она чуткая и эмоциональная'),
  ];
  static const List<String> _romanticQuirks = [
    'любит удивлять мелочами',
    'всегда чувствует настроение',
    'помнит все важные даты',
    'присылает милые сообщения с утра',
    'умеет рассмешить в любой момент',
    'заваривает кофе по утрам',
    'обнимает, когда грустно',
    'оставляет записки с тёплыми словами',
    'замечает перемены в настроении',
    'всегда выслушает до конца',
  ];
  static const List<String> _romanticActivities = [
    'Любим проводить вечера вдвоём',
    'Часто гуляем и разговариваем обо всём',
    'Любим готовить вместе',
    'Смотрим фильмы по вечерам в обнимку',
    'Планируем поездки и маленькие приключения',
    'Обожаем уютные вечера дома',
    'Любим открывать новые места вместе',
    'Устраиваем свидания даже по будням',
    'Гуляем допоздна и делимся мечтами',
    'Любим завтракать вместе по утрам',
  ];
  static const List<String> _romanticCommunicationStyles = [
    'Общаемся тепло, с нежностью и заботой',
    'Ценим честность, доверие и близость',
    'Поддерживаем друг друга во всём',
    'Делимся чувствами и не боимся быть уязвимыми',
    'Лёгкий флирт и нежные слова — часть нашего общения',
    'Ценим личное пространство, но всегда рядом',
    'Говорим обо всём открыто и честно',
  ];
  static const List<(String, String)> _occupationRoles = [
    ('Продуктовый менеджер', 'Продуктовый менеджер'),
    ('Проектный менеджер', 'Проектный менеджер'),
    ('Бизнес-аналитик', 'Бизнес-аналитик'),
    ('Аналитик данных', 'Аналитик данных'),
    ('Data Scientist', 'Data Scientist'),
    ('Frontend-разработчик', 'Frontend-разработчик'),
    ('Backend-разработчик', 'Backend-разработчик'),
    ('Fullstack-разработчик', 'Fullstack-разработчик'),
    ('Мобильный разработчик', 'Мобильный разработчик'),
    ('QA-инженер', 'QA-инженер'),
    ('DevOps-инженер', 'DevOps-инженер'),
    ('UX/UI-дизайнер', 'UX/UI-дизайнер'),
    ('UX-исследователь', 'UX-исследовательница'),
    ('Сервис-дизайнер', 'Сервис-дизайнер'),
    ('Маркетолог', 'Маркетолог'),
    ('SMM-специалист', 'SMM-специалист'),
    ('Контент-редактор', 'Контент-редактор'),
    ('Копирайтер', 'Копирайтер'),
    ('HR-менеджер', 'HR-менеджер'),
    ('Рекрутер', 'Рекрутер'),
    ('Финансовый аналитик', 'Финансовый аналитик'),
    ('Юрист', 'Юрист'),
    ('Налоговый консультант', 'Налоговый консультант'),
    ('Логист', 'Логист'),
    ('Таргетолог', 'Таргетолог'),
    ('Продюсер', 'Продюсер'),
  ];
  static const List<(String, String, List<String>)>
      _specializedOccupationRoles = [
    (
      'Журналист',
      'Журналистка',
      ['в медиа', 'в онлайн-издании', 'на фрилансе']
    ),
    ('Фотограф', 'Фотограф', ['на фрилансе', 'в студии', 'в медиа']),
    (
      'Видеомонтажер',
      'Видеомонтажер',
      ['на фрилансе', 'в продакшн-студии', 'в медиа']
    ),
    (
      'Психолог',
      'Психолог',
      ['в частной практике', 'в клинике', 'на фрилансе']
    ),
    ('Врач-терапевт', 'Врач-терапевт', ['в поликлинике', 'в частной клинике']),
    (
      'Фитнес-тренер',
      'Фитнес-тренер',
      ['в спортзале', 'на фрилансе', 'в фитнес-клубе']
    ),
    ('Учитель', 'Учительница', ['в школе', 'в лицее', 'в гимназии']),
    (
      'Преподаватель английского',
      'Преподавательница английского',
      ['в языковой школе', 'на фрилансе', 'в онлайн-школе']
    ),
    (
      'Архитектор',
      'Архитектор',
      ['в архитектурном бюро', 'в строительной компании']
    ),
    (
      'Инженер-конструктор',
      'Инженер-конструктор',
      ['в конструкторском бюро', 'в строительной компании']
    ),
    ('Риэлтор', 'Риэлтор', ['в агентстве недвижимости', 'на фрилансе']),
    ('Бариста', 'Бариста', ['в кофейне', 'в кофе-баре']),
    ('Кондитер', 'Кондитер', ['в кондитерской', 'в пекарне', 'в ресторане']),
    ('Стилист', 'Стилистка', ['в салоне', 'на фрилансе', 'в сфере красоты']),
    (
      'Переводчик',
      'Переводчица',
      ['на фрилансе', 'в бюро переводов', 'в международной компании']
    ),
    (
      'Нутрициолог',
      'Нутрициолог',
      ['на фрилансе', 'в клинике', 'в wellness-студии']
    ),
    ('Ветеринар', 'Ветеринар', ['в ветклинике', 'в зоосалоне']),
    (
      'Флорист',
      'Флорист',
      ['в цветочном магазине', 'в студии флористики', 'на фрилансе']
    ),
  ];
  static const List<String> _occupationContexts = [
    'в финтехе',
    'в e-commerce',
    'в EdTech',
    'в медиа',
    'в креативной студии',
    'в продуктовой команде',
    'в стартапе',
    'в крупной компании',
    'в инхаус-команде',
    'в маркетинговом агентстве',
    'в консалтинге',
    'в сфере логистики',
    'в образовании',
    'в здравоохранении',
    'в банковском секторе',
    'в страховой компании',
    'в госсекторе',
    'в сервисе доставки',
    'в маркетплейсе',
    'в игровой индустрии',
    'в туристической компании',
    'в сфере красоты',
    'в ресторанном бизнесе',
    'в event-индустрии',
  ];
  static const List<String> _occupationFormats = [
    'работаю удаленно',
    'гибридный формат',
    'в офисе',
    'на проектной работе',
    'на фрилансе',
  ];
  static const List<String> _occupationFocus = [
    'делаю упор на рост продукта',
    'веду исследования пользователей',
    'строю процессы и коммуникации',
    'делаю отчеты и дашборды',
    'занимаюсь пользовательским опытом',
    'оптимизирую сервис и качество',
    'работаю с аналитикой и метриками',
    'развиваю команду и наставничество',
    'ищу точки роста и улучшения',
  ];
  static const List<String> _goodHabitItems = [
    'пью воду',
    'делаю растяжку',
    'гуляю каждый день',
    'ложусь без телефона',
    'делаю перерывы в работе',
    'читаю перед сном',
    'планирую день',
    'слежу за режимом сна',
    'делаю мини-разминки',
    'ограничиваю кофе до обеда',
    'держу рабочее место в порядке',
    'выбираю лестницы',
    'делаю дыхательные упражнения',
    'пью чай без сахара',
    'добавляю овощи в рацион',
    'выделяю время без соцсетей',
    'хожу на тренировки',
    'медитирую по утрам',
    'веду дневник благодарности',
    'готовлю еду на неделю',
  ];
  static const List<String> _badHabitItems = [
    'залипаю в соцсетях',
    'пью кофе поздно',
    'откладываю дела до последнего',
    'ложусь позже, чем планирую',
    'забываю про воду',
    'слишком долго сижу без перерывов',
    'срываюсь на сладкое',
    'перфекционизм мешает закончить быстрее',
    'иногда отвечаю не сразу',
    'перекусываю вместо нормального обеда',
    'прокрастинирую на мелочах',
    'забываю размяться и затекает спина',
    'беру лишние задачи и устаю',
    'иногда пропускаю завтрак',
    'работаю ночью и сбиваю режим',
    'думаю о работе в выходные',
    'долго выбираю фильм и в итоге ничего не смотрю',
    'перебираю с кофе',
  ];
  static const List<String> _hobbyItems = [
    'фотография',
    'прогулки по городу',
    'настольные игры',
    'чтение нон-фикшн',
    'бег',
    'легкие тренировки',
    'кулинарные эксперименты',
    'музыка и плейлисты',
    'концерты',
    'рисование и скетчи',
    'поездки на выходных',
    'йога',
    'пилатес',
    'кино и сериалы',
    'видеоигры',
    'ведение дневника',
    'планирование',
    'комнатные растения',
    'изучение языков',
    'плавание',
    'велопрогулки',
    'книги и подкасты',
    'готовлю кофе как бариста',
    'походы на природе',
    'керамика',
    'танцы',
    'каллиграфия',
    'скалолазание',
    'волонтерство',
    'медитация',
    'вышивка и рукоделие',
    'садоводство',
    'кроссфит',
    'ведение блога',
  ];

  static const List<(String, String)> _traitsExamples = [
    ('заботливый', 'заботливая'),
    ('честный', 'честная'),
    ('упрямый', 'упрямая'),
    ('весёлый', 'весёлая'),
    ('задумчивый', 'задумчивая'),
  ];

  final Random _random;

  FriendPersonaDefaultsBuilder({Random? random}) : _random = random ?? Random();

  FriendPersonaDefaults build({
    String? relationshipType,
    String gender = 'male',
  }) {
    final isFemale = gender == 'female';
    return FriendPersonaDefaults(
      about: _buildAbout(isFemale),
      relationshipNotes: _buildRelationshipNotes(relationshipType, isFemale),
      occupation: _buildOccupation(isFemale),
      goodHabits: _buildGoodHabits(),
      badHabits: _buildBadHabits(),
      hobbies: _buildHobbies(),
      traitsHint: _buildTraitsHint(isFemale),
    );
  }

  String _pick(List<String> values) {
    return values[_random.nextInt(values.length)];
  }

  List<String> _resolveGendered(
    List<(String, String)> items,
    bool isFemale,
  ) {
    return items.map((t) => isFemale ? t.$2 : t.$1).toList();
  }

  String _buildAbout(bool isFemale) {
    final traitsList = _resolveGendered(_aboutTraits, isFemale);
    final traits = _pickDistinct(traitsList, _random.nextInt(2) + 2);
    final value = _pick(_aboutValues);
    final interests = _pickDistinct(_aboutInterests, _random.nextInt(2) + 1);
    final quirk = _random.nextInt(100) < 55 ? _pick(_aboutQuirks) : null;
    final buffer = StringBuffer();
    buffer.write('${_sentence(_joinWithAnd(traits))}, $value.');
    buffer.write(' Любит ${_joinWithAnd(interests)}.');
    if (quirk != null) {
      buffer.write(' ${_sentence(quirk)}.');
    }
    return buffer.toString();
  }

  String _buildRelationshipNotes(String? relationshipType, bool isFemale) {
    if (relationshipType == 'relationship') {
      return _buildRomanticRelationshipNotes(isFemale);
    }
    return _buildFriendRelationshipNotes();
  }

  String _buildRomanticRelationshipNotes(bool isFemale) {
    final duration = _pick(_romanticDurations);
    final qualitiesList = _resolveGendered(_romanticPartnerQualities, isFemale);
    final quality = _pick(qualitiesList);
    final quirk = _random.nextInt(100) < 65 ? _pick(_romanticQuirks) : null;
    final activity = _pick(_romanticActivities);
    final communication = _pick(_romanticCommunicationStyles);
    final buffer = StringBuffer();
    buffer.write('$duration.');
    if (quirk != null) {
      buffer.write(' $quality, $quirk.');
    } else {
      buffer.write(' $quality.');
    }
    buffer.write(' $activity.');
    buffer.write(' $communication.');
    return buffer.toString();
  }

  String _buildFriendRelationshipNotes() {
    final tone = _pick(_friendRelationshipTones);
    final boundaries = _pick(_relationshipBoundaries);
    final style = _pick(_friendRelationshipStyles);
    final cadence =
        _random.nextInt(100) < 60 ? _pick(_friendRelationshipCadence) : null;
    final buffer = StringBuffer();
    buffer.write('$tone. $boundaries. $style.');
    if (cadence != null) {
      buffer.write(' $cadence.');
    }
    return buffer.toString();
  }

  String _buildOccupation(bool isFemale) {
    final universalCount = _occupationRoles.length;
    final specializedCount = _specializedOccupationRoles.length;

    if (_random.nextInt(universalCount + specializedCount) >= universalCount) {
      final entry =
          _specializedOccupationRoles[_random.nextInt(specializedCount)];
      final role = isFemale ? entry.$2 : entry.$1;
      final ctx = entry.$3[_random.nextInt(entry.$3.length)];
      return '$role $ctx';
    }

    final rolesList = _resolveGendered(_occupationRoles, isFemale);
    final role = _pick(rolesList);
    final context = _pick(_occupationContexts);
    final parts = <String>['$role $context'];
    if (_random.nextInt(100) < 45) {
      parts.add(_pick(_occupationFormats));
    }
    if (_random.nextInt(100) < 35) {
      parts.add(_pick(_occupationFocus));
    }
    return parts.join(', ');
  }

  String _buildGoodHabits() {
    final items = _pickDistinct(_goodHabitItems, _random.nextInt(2) + 2);
    return '${_sentence(_joinWithAnd(items))}.';
  }

  String _buildBadHabits() {
    final items = _pickDistinct(_badHabitItems, _random.nextInt(2) + 2);
    return '${_sentence(_joinWithAnd(items))}.';
  }

  String _buildHobbies() {
    final items = _pickDistinct(_hobbyItems, _random.nextInt(2) + 2);
    return '${_sentence(_joinWithAnd(items))}.';
  }

  String _buildTraitsHint(bool isFemale) {
    final examples = _resolveGendered(_traitsExamples, isFemale);
    final picked = _pickDistinct(examples, 3);
    return 'Например: ${picked.join(', ')}';
  }

  List<String> _pickDistinct(List<String> values, int count) {
    if (values.isEmpty) return [];
    final copy = List<String>.of(values);
    copy.shuffle(_random);
    return copy.take(count.clamp(1, copy.length)).toList();
  }

  String _joinWithAnd(List<String> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} и ${items[1]}';
    final start = items.sublist(0, items.length - 1).join(', ');
    return '$start и ${items.last}';
  }

  String _sentence(String text) {
    if (text.isEmpty) return text;
    final trimmed = text.trimLeft();
    return trimmed[0].toUpperCase() + trimmed.substring(1);
  }
}
