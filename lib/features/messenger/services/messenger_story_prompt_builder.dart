import '../models/friend_profile.dart';

class MessengerStoryPromptBuilder {
  const MessengerStoryPromptBuilder();

  String buildStoryPrompt({
    required String friendName,
    required String activity,
    required String caption,
    FriendProfile? profile,
    bool isSelfie = true,
  }) {
    final buffer = StringBuffer();
    final isRomantic = profile?.isRomantic ?? false;
    buffer.writeln(
        'Vertical video, 9:16 aspect ratio, realistic, 5 seconds, 720p.');
    if (!isSelfie) {
      final activityEn = _mapActivity(activity);
      if (activityEn != null && activityEn.isNotEmpty) {
        buffer.writeln('Scene: $activityEn.');
      }
      final safeCaption = _safeCaption(caption);
      if (safeCaption != null && safeCaption.isNotEmpty) {
        buffer.writeln('Mood: $safeCaption.');
      } else if (isRomantic) {
        buffer.writeln('Mood: romantic, intimate, warm, sensual.');
      } else {
        buffer.writeln('Mood: calm, natural.');
      }
      buffer.writeln(
          'No people, no phones, no devices, no screen frames, environmental focus, natural light, no text, no watermark, no logos.');
      return buffer.toString();
    }
    buffer.writeln('The subject matches the reference image.');
    if (profile != null) {
      _writeIdentityBlock(buffer, profile);
    } else {
      buffer.writeln('Keep the same face and overall appearance.');
    }
    final activityEn = _mapActivity(activity);
    if (activityEn != null && activityEn.isNotEmpty) {
      buffer.writeln('The person is $activityEn.');
    }
    final safeCaption = _safeCaption(caption);
    if (safeCaption != null && safeCaption.isNotEmpty) {
      buffer.writeln('Mood: $safeCaption.');
    } else if (isRomantic) {
      buffer.writeln('Mood: seductive, flirty, sensual, confident.');
    } else {
      buffer.writeln('Mood: friendly, casual, natural.');
    }
    if (isRomantic) {
      buffer.writeln(
          'Natural light, sensual, intimate, gentle camera movement, no text, no watermark, no logos.');
    } else {
      buffer.writeln(
          'Natural light, candid, gentle camera movement, no text, no watermark, no logos.');
    }
    buffer.writeln('Person: $friendName.');
    return buffer.toString();
  }

  String buildStoryImagePrompt({
    required String friendName,
    required String activity,
    required String caption,
    FriendProfile? profile,
    bool isSelfie = true,
    String? sceneDescriptionEn,
    String? outfitEn,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
        'Vertical photo, 9:16 aspect ratio, realistic, natural light.');
    final resolvedScene = _resolveScene(activity, sceneDescriptionEn);
    final isRomantic = profile?.isRomantic ?? false;
    if (!isSelfie) {
      if (resolvedScene != null && resolvedScene.isNotEmpty) {
        buffer.writeln('Scene: $resolvedScene.');
      }
      final safeCaption = _safeCaption(caption);
      if (safeCaption != null && safeCaption.isNotEmpty) {
        buffer.writeln('Mood: $safeCaption.');
      } else if (isRomantic) {
        buffer.writeln('Mood: romantic, intimate, warm, sensual.');
      } else {
        buffer.writeln('Mood: calm, natural.');
      }
      buffer.writeln(
          'No people, no phones, no devices, no screen frames, environmental focus, no text, no watermark, no logos.');
      return buffer.toString();
    }
    buffer.writeln('The subject matches the reference image.');
    if (profile != null) {
      _writeIdentityBlock(buffer, profile);
    } else {
      buffer.writeln('Keep the same face and overall appearance.');
    }
    final normalizedOutfit = outfitEn?.trim() ?? '';
    if (normalizedOutfit.isNotEmpty) {
      buffer.writeln('Outfit: $normalizedOutfit.');
    } else {
      final season = _seasonLabel(DateTime.now());
      buffer.writeln(
          'Season: $season. Pick an outfit appropriate for the scene and season.');
    }
    if (resolvedScene != null && resolvedScene.isNotEmpty) {
      buffer.writeln('The person is $resolvedScene.');
    }
    final safeCaption = _safeCaption(caption);
    if (safeCaption != null && safeCaption.isNotEmpty) {
      buffer.writeln('Mood: $safeCaption.');
    } else if (isRomantic) {
      buffer.writeln('Mood: seductive, flirty, sensual, confident.');
    } else {
      buffer.writeln('Mood: friendly, casual, natural.');
    }
    if (isRomantic) {
      buffer.writeln(
          'Natural light, sensual, intimate, no text, no watermark, no logos.');
    } else {
      buffer.writeln(
          'Natural light, candid, no text, no watermark, no logos.');
    }
    buffer.writeln('Person: $friendName.');
    return buffer.toString();
  }

  void _writeIdentityBlock(StringBuffer buffer, FriendProfile profile) {
    final genderLabel = profile.gender == 'female' ? 'woman' : 'man';
    final hair = _mapHair(profile.hairColor);
    final eyes = _mapEyes(profile.eyeColor);
    final ethnicityLabel = _mapEthnicity(profile.ethnicity);

    buffer.writeln(
        'The person is a ${profile.age}-year-old $ethnicityLabel $genderLabel with $hair hair and $eyes eyes.');
    if (profile.skinTone.isNotEmpty) {
      buffer.writeln('Skin tone: ${profile.skinTone}.');
    }
    if (profile.bodyType.isNotEmpty || profile.heightCategory.isNotEmpty) {
      final bodyParts = <String>[];
      if (profile.bodyType.isNotEmpty) bodyParts.add(profile.bodyType);
      if (profile.heightCategory.isNotEmpty) {
        bodyParts.add('${profile.heightCategory} height');
      }
      buffer.writeln('Build: ${bodyParts.join(', ')}.');
    }
    final hairstyle = _normalizeHairstyle(profile.hairstyle);
    if (hairstyle.isNotEmpty) {
      buffer.writeln('Hairstyle: $hairstyle.');
    }
    final facialFeatures = profile.facialFeatures.trim();
    if (facialFeatures.isNotEmpty) {
      buffer.writeln('Facial structure: $facialFeatures.');
    }
    buffer.writeln(_appearanceHint(profile));
    final appearance = profile.appearanceDescription.trim();
    if (appearance.isNotEmpty) {
      buffer.writeln('Appearance details: $appearance.');
    }
  }

  String _appearanceHint(FriendProfile profile) {
    if (profile.isRomantic) {
      return 'Style: sexy, flirty, attractive, confident.';
    }
    return 'Style: casual, everyday, natural, not sexualized.';
  }

  String _mapEthnicity(String value) {
    if (value.isEmpty) return '';
    switch (value) {
      case 'caucasian':
        return 'Caucasian/European';
      case 'east_asian':
        return 'East Asian';
      case 'south_asian':
        return 'South Asian';
      case 'african':
        return 'Black/African';
      case 'latino':
        return 'Hispanic/Latino';
      case 'middle_eastern':
        return 'Middle Eastern';
      case 'mixed':
        return 'mixed-race';
      default:
        return value;
    }
  }

  String _mapHair(String value) {
    switch (value) {
      case 'blonde':
        return 'blonde';
      case 'brown':
        return 'light brown';
      case 'brunette':
        return 'brunette';
      case 'red':
        return 'red';
      default:
        return value;
    }
  }

  String _mapEyes(String value) {
    switch (value) {
      case 'blue':
        return 'blue';
      case 'green':
        return 'green';
      case 'brown':
        return 'brown';
      case 'gray':
        return 'gray';
      default:
        return value;
    }
  }

  String _normalizeHairstyle(String value) {
    var normalized = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length > 80) {
      normalized = normalized.substring(0, 80).trim();
    }
    return normalized;
  }

  String _seasonLabel(DateTime date) {
    switch (date.month) {
      case 12:
      case 1:
      case 2:
        return 'winter';
      case 3:
      case 4:
      case 5:
        return 'spring';
      case 6:
      case 7:
      case 8:
        return 'summer';
      default:
        return 'autumn';
    }
  }

  String? _resolveScene(String activity, String? sceneDescriptionEn) {
    final override = sceneDescriptionEn?.trim() ?? '';
    if (override.isNotEmpty) return override;
    return _mapActivity(activity);
  }

  String? _mapActivity(String value) {
    final normalized =
        value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    switch (normalized) {
      case 'гуляю':
      case 'на прогулке':
      case 'в парке':
        return 'walking outside in a park';
      case 'на пробежке':
      case 'тренируюсь':
      case 'в зале':
        return 'working out at the gym';
      case 'на работе':
      case 'занят(а) делами':
      case 'в офисе':
        return 'working at the office';
      case 'учусь':
      case 'на учебе':
      case 'разбираю задания':
        return 'studying at home';
      case 'обедаю':
      case 'в кафе':
      case 'перекусываю':
        return 'having coffee in a cafe';
      case 'пью кофе':
      case 'в кофейне':
      case 'на кофе-брейке':
        return 'drinking coffee in a cozy cafe';
      case 'в магазине':
      case 'покупаю кое-что':
      case 'разбираюсь с покупками':
        return 'shopping casually';
      case 'дома':
      case 'отдыхаю дома':
      case 'разбираюсь по дому':
        return 'relaxing at home';
      case 'в дороге':
      case 'еду по делам':
      case 'по пути':
        return 'riding in a car on the way';
      case 'слушаю музыку':
      case 'в наушниках':
      case 'слушаю трек':
        return 'listening to music with headphones';
      case 'смотрю фильм':
      case 'залипаю в сериал':
      case 'смотрю видео':
        return 'watching a movie at home';
      case 'читаю книгу':
      case 'чуть-чуть читаю':
      case 'читаю статью':
        return 'reading a book';
      case 'готовлю':
      case 'на кухне':
      case 'делаю перекус':
        return 'cooking in the kitchen';
      case 'убираюсь':
      case 'разбираю вещи':
      case 'наводю порядок':
        return 'tidying up at home';
      default:
        return null;
    }
  }

  String? _safeCaption(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (!_isAscii(trimmed)) return null;
    final sanitized = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), ' ').trim();
    if (sanitized.isEmpty) return null;
    return sanitized.length > 60 ? sanitized.substring(0, 60) : sanitized;
  }

  bool _isAscii(String value) {
    for (final unit in value.codeUnits) {
      if (unit > 127) return false;
    }
    return true;
  }
}
