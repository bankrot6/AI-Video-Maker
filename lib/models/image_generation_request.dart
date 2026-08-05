import 'package:flutter/material.dart';

/// Стиль итогового изображения.
enum ImageStyle {
  auto,
  photo,
  cinematic,
  render3d,
  anime,
  illustration,
  watercolor,
  digitalArt,
  neon,
  fantasy,
  minimal,
  pixel,
  comic,
  retro,
  logo,
}

extension ImageStyleX on ImageStyle {
  String get id => name;

  static ImageStyle fromId(String? raw) {
    if (raw == null || raw.isEmpty) return ImageStyle.auto;
    for (final style in ImageStyle.values) {
      if (style.name == raw) return style;
    }
    return ImageStyle.auto;
  }

  IconData get icon {
    switch (this) {
      case ImageStyle.auto:
        return Icons.auto_awesome_rounded;
      case ImageStyle.photo:
        return Icons.photo_camera_rounded;
      case ImageStyle.cinematic:
        return Icons.movie_filter_rounded;
      case ImageStyle.render3d:
        return Icons.view_in_ar_rounded;
      case ImageStyle.anime:
        return Icons.animation_rounded;
      case ImageStyle.illustration:
        return Icons.brush_rounded;
      case ImageStyle.watercolor:
        return Icons.water_drop_rounded;
      case ImageStyle.digitalArt:
        return Icons.palette_rounded;
      case ImageStyle.neon:
        return Icons.flash_on_rounded;
      case ImageStyle.fantasy:
        return Icons.auto_awesome;
      case ImageStyle.minimal:
        return Icons.crop_square_rounded;
      case ImageStyle.pixel:
        return Icons.grid_on_rounded;
      case ImageStyle.comic:
        return Icons.format_paint_rounded;
      case ImageStyle.retro:
        return Icons.camera_roll_rounded;
      case ImageStyle.logo:
        return Icons.auto_awesome_motion_rounded;
    }
  }

  String get label {
    switch (this) {
      case ImageStyle.auto:
        return 'Авто';
      case ImageStyle.photo:
        return 'Фото';
      case ImageStyle.cinematic:
        return 'Кино';
      case ImageStyle.render3d:
        return '3D';
      case ImageStyle.anime:
        return 'Аниме';
      case ImageStyle.illustration:
        return 'Иллюстрация';
      case ImageStyle.watercolor:
        return 'Акварель';
      case ImageStyle.digitalArt:
        return 'Цифровой арт';
      case ImageStyle.neon:
        return 'Неон';
      case ImageStyle.fantasy:
        return 'Фэнтези';
      case ImageStyle.minimal:
        return 'Минимализм';
      case ImageStyle.pixel:
        return 'Пиксель-арт';
      case ImageStyle.comic:
        return 'Комикс';
      case ImageStyle.retro:
        return 'Ретро';
      case ImageStyle.logo:
        return 'Иконка';
    }
  }

  /// Указание для промпт-инженера: как именно должно выглядеть изображение.
  String get promptDirective {
    switch (this) {
      case ImageStyle.auto:
        return 'Стиль подбери сам — тот, который лучше всего раскрывает идею.';
      case ImageStyle.photo:
        return 'Стиль: фотореализм. Настоящая фотография, натуральные текстуры '
            'и свет, корректная оптика, без художественной стилизации.';
      case ImageStyle.cinematic:
        return 'Стиль: кинокадр. Кинематографический свет, анаморфная оптика, '
            'цветокоррекция как в фильме, атмосферная дымка, глубина кадра.';
      case ImageStyle.render3d:
        return 'Стиль: 3D-рендер. Объёмные материалы, мягкий global illumination, '
            'чистая геометрия, качество Octane/Blender.';
      case ImageStyle.anime:
        return 'Стиль: аниме. Чистый контур, выразительные глаза, плоская '
            'заливка с мягкими градиентами, эстетика японской анимации.';
      case ImageStyle.illustration:
        return 'Стиль: рисованная иллюстрация. Аккуратная линия, декоративные '
            'формы, книжная или редакционная подача.';
      case ImageStyle.watercolor:
        return 'Стиль: акварель. Прозрачные заливки, растекание пигмента, '
            'фактура бумаги, мягкие края.';
      case ImageStyle.digitalArt:
        return 'Стиль: цифровая живопись. Выразительные мазки, богатый цвет, '
            'концепт-арт уровня artstation.';
      case ImageStyle.neon:
        return 'Стиль: неон и киберпанк. Неоновые источники света, влажные '
            'отражения, контраст пурпурного и голубого, ночная сцена.';
      case ImageStyle.fantasy:
        return 'Стиль: фэнтези-арт. Эпичный масштаб, магическое освещение, '
            'детализированный мир, драматичная атмосфера.';
      case ImageStyle.minimal:
        return 'Стиль: минимализм. Минимум объектов, много воздуха, простые '
            'формы, ограниченная палитра, чистый фон.';
      case ImageStyle.pixel:
        return 'Стиль: пиксель-арт. Чёткая пиксельная сетка, ограниченная '
            'палитра, эстетика 16-битных игр.';
      case ImageStyle.comic:
        return 'Стиль: комикс. Жирный контур, растровые точки, плакатный '
            'контраст, динамичная подача.';
      case ImageStyle.retro:
        return 'Стиль: ретро. Плёночное зерно, выцветшие цвета, эстетика '
            'винтажного постера или аналогового фото.';
      case ImageStyle.logo:
        return 'Стиль: векторная иконка/логотип. Плоские формы, чистые контуры, '
            'простой однотонный фон, идеальная симметрия и читаемость.';
    }
  }
}

/// Формат кадра, из которого выводится соотношение сторон.
enum ImageFormat {
  square,
  portrait,
  story,
  landscape,
  wide,
  cinema,
}

extension ImageFormatX on ImageFormat {
  /// Veo принимает только 9:16 и 16:9 — на квадрат и кинокадр Google отвечает
  /// `400 Invalid aspect ratio`, поэтому выбор сведён к двум рабочим форматам.
  /// Остальные значения остаются в enum, чтобы сохранённые ранее пресеты
  /// продолжали читаться.
  static const List<ImageFormat> videoFormats = [
    ImageFormat.story,
    ImageFormat.wide,
  ];

  String get label {
    switch (this) {
      case ImageFormat.square:
        return 'Квадрат';
      case ImageFormat.portrait:
        return 'Портрет';
      case ImageFormat.story:
        return 'Вертикальное';
      case ImageFormat.landscape:
        return 'Альбом';
      case ImageFormat.wide:
        return 'Горизонтальное';
      case ImageFormat.cinema:
        return 'Кинокадр';
    }
  }

  String get aspectRatio {
    switch (this) {
      case ImageFormat.square:
        return '1:1';
      case ImageFormat.portrait:
        return '3:4';
      case ImageFormat.story:
        return '9:16';
      case ImageFormat.landscape:
        return '4:3';
      case ImageFormat.wide:
        return '16:9';
      case ImageFormat.cinema:
        return '21:9';
    }
  }

  bool get isVertical =>
      this == ImageFormat.portrait || this == ImageFormat.story;

  bool get isHorizontal =>
      this == ImageFormat.landscape ||
      this == ImageFormat.wide ||
      this == ImageFormat.cinema;
}

/// Настроение и цветовая подача кадра.
enum ImageMood {
  auto,
  bright,
  dark,
  warm,
  cool,
  pastel,
  vivid,
  monochrome,
}

extension ImageMoodX on ImageMood {
  String get label {
    switch (this) {
      case ImageMood.auto:
        return 'Авто';
      case ImageMood.bright:
        return 'Светлое';
      case ImageMood.dark:
        return 'Тёмное';
      case ImageMood.warm:
        return 'Тёплое';
      case ImageMood.cool:
        return 'Холодное';
      case ImageMood.pastel:
        return 'Пастель';
      case ImageMood.vivid:
        return 'Сочное';
      case ImageMood.monochrome:
        return 'Ч/Б';
    }
  }

  String? get promptDirective {
    switch (this) {
      case ImageMood.auto:
        return null;
      case ImageMood.bright:
        return 'Настроение: светлое и воздушное, много рассеянного света, '
            'высокий ключ.';
      case ImageMood.dark:
        return 'Настроение: тёмное и драматичное, низкий ключ, глубокие тени, '
            'контрастный свет.';
      case ImageMood.warm:
        return 'Настроение: тёплое, золотистые и янтарные оттенки, мягкое '
            'закатное освещение.';
      case ImageMood.cool:
        return 'Настроение: холодное, синие и стальные оттенки, прохладный свет.';
      case ImageMood.pastel:
        return 'Настроение: пастельная палитра, приглушённые нежные оттенки, '
            'низкий контраст.';
      case ImageMood.vivid:
        return 'Настроение: насыщенные сочные цвета, высокая контрастность, '
            'выразительная палитра.';
      case ImageMood.monochrome:
        return 'Настроение: чёрно-белое изображение, работа на тонах и '
            'фактурах, без цвета.';
    }
  }
}

/// Как использовать загруженное пользователем изображение.
enum ReferenceUsage {
  /// Сохранить лицо/персонажа с фото и поместить в новую сцену.
  keepSubject,

  /// Взять референс как источник стиля и композиции.
  keepStyle,
}

extension ReferenceUsageX on ReferenceUsage {
  String get label {
    switch (this) {
      case ReferenceUsage.keepSubject:
        return 'Сохранить объект';
      case ReferenceUsage.keepStyle:
        return 'Повторить стиль';
    }
  }

  String get hint {
    switch (this) {
      case ReferenceUsage.keepSubject:
        return 'Человек или предмет с фото попадёт в новую сцену';
      case ReferenceUsage.keepStyle:
        return 'Из фото возьмём стиль, свет и композицию';
    }
  }
}

/// Пользовательский запрос на генерацию изображения.
///
/// Минимально достаточный ввод — одна [idea] в несколько слов; остальные поля
/// уточняют результат и имеют разумные значения по умолчанию.
class ImageGenerationRequest {
  const ImageGenerationRequest({
    required this.idea,
    this.style = ImageStyle.auto,
    this.format = ImageFormat.portrait,
    this.mood = ImageMood.auto,
    this.textOnImage,
    this.details,
    this.hasReference = false,
    this.referenceUsage = ReferenceUsage.keepSubject,
  });

  /// Что снять — свободное описание пользователя.
  final String idea;
  final ImageStyle style;
  final ImageFormat format;
  final ImageMood mood;

  /// Надпись, которая должна быть видна на изображении.
  final String? textOnImage;

  /// Дополнительные пожелания к деталям сцены.
  final String? details;

  final bool hasReference;
  final ReferenceUsage referenceUsage;

  String get aspectRatio => format.aspectRatio;

  bool get isValid => idea.trim().length >= 2;

  ImageGenerationRequest copyWith({
    String? idea,
    ImageStyle? style,
    ImageFormat? format,
    ImageMood? mood,
    String? textOnImage,
    String? details,
    bool? hasReference,
    ReferenceUsage? referenceUsage,
  }) {
    return ImageGenerationRequest(
      idea: idea ?? this.idea,
      style: style ?? this.style,
      format: format ?? this.format,
      mood: mood ?? this.mood,
      textOnImage: textOnImage ?? this.textOnImage,
      details: details ?? this.details,
      hasReference: hasReference ?? this.hasReference,
      referenceUsage: referenceUsage ?? this.referenceUsage,
    );
  }

  /// Короткое название для карточки в галерее.
  String get title {
    final normalized = idea.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'Видео';
    const maxLength = 50;
    if (normalized.length <= maxLength) return normalized;
    final cut = normalized.substring(0, maxLength);
    final lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > 20 ? cut.substring(0, lastSpace) : cut}...';
  }
}
