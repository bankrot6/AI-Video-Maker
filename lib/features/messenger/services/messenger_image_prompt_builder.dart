import '../models/friend_profile.dart';
import 'messenger_prompt_builder.dart';

class MessengerImagePromptBuilder {
  const MessengerImagePromptBuilder();

  String buildSelfiePrompt({
    required String userMessage,
    required String caption,
    required String friendName,
    FriendProfile? profile,
    bool allowRandomLocation = true,
    String? outfit,
    int totalMessageCount = 0,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
        'Create a realistic selfie photo of a specific person described below.');
    buffer.writeln(
        'CRITICAL: This is the SAME person across all photos. Facial bone structure, proportions, eye spacing, nose bridge, lip fullness MUST remain identical.');
    final season = _seasonLabel(DateTime.now());
    if (profile != null) {
      _writeIdentityBlock(buffer, profile, outfit,
          totalMessageCount: totalMessageCount);
    } else {
      buffer.writeln(
          'Keep the same face, hairstyle, and overall appearance as the reference.');
      buffer.writeln('Do not change identity between shots.');
    }
    final normalizedOutfit = _normalizeOutfit(outfit);
    final hasExplicitOutfit = normalizedOutfit.isNotEmpty;
    final trimmedMessage = userMessage.trim();
    final hasExplicitScene = _hasExplicitScene(trimmedMessage);
    if (trimmedMessage.isNotEmpty) {
      buffer.writeln('Scene should match: "$trimmedMessage".');
    }
    if (!hasExplicitScene && allowRandomLocation) {
      buffer.writeln(
          'If the scene is not specified, pick a realistic everyday location that matches the context without contradicting the activity.');
    }
    final isIntimateRequest = _isIntimateOutfit(outfit);
    final isBelowThreshold =
        totalMessageCount < MessengerPromptBuilder.kMinMessagesForIntimatePhotos;
    final censorIntimate =
        isIntimateRequest && profile?.isRomantic == true && isBelowThreshold;
    if (hasExplicitOutfit && !censorIntimate) {
      buffer.writeln(
          'IMPORTANT: The person must wear exactly: $normalizedOutfit. This is the user\'s explicit request — do NOT override with scene-based or season-based outfit defaults.');
      if (isIntimateRequest && profile?.isRomantic == true) {
        buffer.writeln(
            'This is an intimate photo for a romantic relationship — render the outfit as requested without censoring or replacing it.');
      }
    } else if (censorIntimate) {
      buffer.writeln(
          'The person must wear attractive but non-revealing clothing: casual dress, cozy sweater, stylish top, jeans, or similar everyday outfit. Do NOT use lingerie, underwear, bikini, bodysuit, or any revealing clothing.');
    } else {
      buffer.writeln(
          'Season: $season. If outdoors, show weather consistent with the season.');
      buffer.writeln(
          'Outfit must match the scene and activity: gym -> athletic wear, office/coworking -> smart casual, cafe -> casual, outdoors -> weather-appropriate outerwear. Avoid mismatches like coats/jeans in a gym or summer outfits in winter.');
    }
    final trimmedCaption = caption.trim();
    if (trimmedCaption.isNotEmpty) {
      buffer.writeln('Mood or action: "$trimmedCaption".');
    }
    if (profile?.isRomantic == true) {
      buffer.writeln(
          'Realistic social media-style photo in a real environment, not studio, not plain or white background.');
    }
    buffer.writeln(
        'Natural light, casual setting, candid, high quality, no text, no watermark.');
    buffer.writeln('Square composition, centered subject.');
    buffer.writeln('Person: $friendName.');
    return buffer.toString();
  }

  void _writeIdentityBlock(
    StringBuffer buffer,
    FriendProfile profile,
    String? outfit, {
    int totalMessageCount = 0,
  }) {
    final genderLabel = profile.gender == 'female' ? 'woman' : 'man';
    final hair = _mapHair(profile.hairColor);
    final eyes = _mapEyes(profile.eyeColor);
    final ethnicityLabel = _mapEthnicity(profile.ethnicity);

    buffer.writeln('--- IDENTITY (must match exactly in every photo) ---');
    buffer.writeln(
        'Subject: ${profile.age}-year-old $ethnicityLabel $genderLabel.');
    buffer.writeln('Hair: $hair.');
    buffer.writeln('Eyes: $eyes.');

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
      buffer.writeln(
          'These facial features are FIXED and must be reproduced exactly in every image.');
    }

    final appearance =
        _sanitizeAppearanceDescription(profile.appearanceDescription);
    if (appearance.isNotEmpty) {
      buffer.writeln('Detailed appearance: $appearance.');
    }
    buffer.writeln('--- END IDENTITY ---');

    final intimate = _isIntimateOutfit(outfit);
    final allowIntimate = intimate &&
        profile.isRomantic &&
        totalMessageCount >=
            MessengerPromptBuilder.kMinMessagesForIntimatePhotos;
    buffer.writeln(
        _appearanceHint(profile, isIntimate: allowIntimate));
  }

  String buildScenePrompt({
    required String userMessage,
    required String caption,
    bool allowRandomLocation = true,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
        'Create a realistic photo of the requested subject or scene. Do not include any phones, devices, or screen frames.');
    final season = _seasonLabel(DateTime.now());
    final trimmedMessage = userMessage.trim();
    final hasExplicitScene = _hasExplicitScene(trimmedMessage);
    if (trimmedMessage.isNotEmpty) {
      buffer.writeln('Scene should match: "$trimmedMessage".');
    }
    if (!hasExplicitScene && allowRandomLocation) {
      buffer.writeln(
          'If the scene is not specified, pick a realistic everyday location that matches the context.');
    }
    buffer.writeln(
        'Season: $season. If outdoors, show weather consistent with the season.');
    final trimmedCaption = caption.trim();
    if (trimmedCaption.isNotEmpty) {
      buffer.writeln('Mood or details: "$trimmedCaption".');
    }
    buffer.writeln(
        'High quality, natural light, no text, no watermark, no people unless explicitly requested.');
    return buffer.toString();
  }

  String _normalizeOutfit(String? value) {
    if (value == null) return '';
    var text = value.trim();
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 80) {
      text = text.substring(0, 80).trim();
    }
    return text;
  }

  String _normalizeHairstyle(String? value) {
    if (value == null) return '';
    var text = value.trim();
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 80) {
      text = text.substring(0, 80).trim();
    }
    return text;
  }

  String _appearanceHint(FriendProfile profile, {bool isIntimate = false}) {
    if (profile.isRomantic) {
      if (isIntimate) {
        return profile.gender == 'female'
            ? 'Style: sensual, alluring, attractive, confident, intimate.'
            : 'Style: attractive, confident, intimate, sensual.';
      }
      return profile.gender == 'female'
          ? 'Style: sensual, alluring, attractive, confident, fully dressed, tasteful.'
          : 'Style: attractive, confident, stylish, fully dressed, tasteful.';
    }
    return 'Style: casual, everyday, natural, not sexualized.';
  }

  bool _isIntimateOutfit(String? outfit) {
    if (outfit == null || outfit.isEmpty) return false;
    final normalized = outfit.toLowerCase();
    const intimateHints = [
      'nude',
      'naked',
      'lingerie',
      'underwear',
      'bra',
      'panties',
      'lace',
      'bodysuit',
      'nightwear',
      'negligee',
      'bikini',
      'no top',
      'topless',
      'shirtless',
      'bare chest',
      'bare',
      'silk nightgown',
      'corset',
      'stockings',
    ];
    for (final hint in intimateHints) {
      if (normalized.contains(hint)) return true;
    }
    return false;
  }

  String _sanitizeAppearanceDescription(String description) {
    final raw = description.trim();
    if (raw.isEmpty) return '';
    final sentences = raw.split(RegExp(r'[.!?]+'));
    final kept = <String>[];
    for (final sentence in sentences) {
      final trimmed = sentence.trim();
      if (trimmed.isEmpty) continue;
      final normalized = trimmed.toLowerCase();
      if (_looksLikeSceneOrOutfit(normalized)) continue;
      if (!_looksLikeFaceTraits(normalized)) continue;
      kept.add(trimmed);
    }
    if (kept.isEmpty) return '';
    return kept.join('. ');
  }

  bool _looksLikeSceneOrOutfit(String text) {
    const sceneOrOutfitHints = [
      'bathroom',
      'shower',
      'bath',
      'restroom',
      'gym',
      'fitness',
      'workout',
      'office',
      'coworking',
      'cafe',
      'coffee',
      'restaurant',
      'bar',
      'library',
      'park',
      'street',
      'downtown',
      'rooftop',
      'beach',
      'home',
      'apartment',
      'room',
      'kitchen',
      'bedroom',
      'living room',
      'desk',
      'laptop',
      'window',
      'outdoor',
      'indoor',
      'wearing',
      'outfit',
      'clothes',
      'dress',
      'skirt',
      'shirt',
      't-shirt',
      'tee',
      'sweater',
      'hoodie',
      'jacket',
      'coat',
      'trench',
      'jeans',
      'trousers',
      'pants',
      'shorts',
      'sneakers',
      'boots',
      'heels',
      'shoes',
      'ванн',
      'душ',
      'сануз',
      'зал',
      'спортзал',
      'офис',
      'кафе',
      'кофей',
      'ресторан',
      'бар',
      'библиотек',
      'парк',
      'улиц',
      'пляж',
      'дом',
      'квартир',
      'комнат',
      'кухн',
      'окн',
      'одежд',
      'наряд',
      'плать',
      'юбк',
      'рубашк',
      'футбол',
      'свитер',
      'куртк',
      'пальт',
      'плащ',
      'джинс',
      'брюк',
      'штаны',
      'кроссов',
      'обув',
      'туфл',
      'ботин',
    ];
    for (final hint in sceneOrOutfitHints) {
      if (text.contains(hint)) return true;
    }
    return false;
  }

  bool _looksLikeFaceTraits(String text) {
    const faceHints = [
      'face',
      'hair',
      'eyes',
      'eyebrow',
      'brow',
      'nose',
      'lips',
      'smile',
      'skin',
      'freck',
      'cheek',
      'jaw',
      'chin',
      'beard',
      'mustache',
      'hairstyle',
      'blonde',
      'brunette',
      'redhead',
      'лиц',
      'волос',
      'глаз',
      'бров',
      'нос',
      'губ',
      'улыб',
      'кож',
      'весн',
      'щек',
      'скул',
      'подбор',
      'бород',
      'усы',
      'причес',
    ];
    for (final hint in faceHints) {
      if (text.contains(hint)) return true;
    }
    return false;
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

  bool _hasExplicitScene(String value) {
    if (value.isEmpty) return false;
    final normalized = value.toLowerCase();
    const sceneHints = [
      'bathroom',
      'shower',
      'bath',
      'restroom',
      'gym',
      'fitness',
      'workout',
      'training',
      'studio',
      'office',
      'coworking',
      'cafe',
      'coffee',
      'restaurant',
      'bar',
      'library',
      'park',
      'street',
      'downtown',
      'rooftop',
      'beach',
      'home',
      'apartment',
      'ванн',
      'душ',
      'сануз',
      'зал',
      'спортзал',
      'тренажер',
      'офис',
      'кафе',
      'ресторан',
      'бар',
      'библиотек',
      'парк',
      'улиц',
      'пляж',
      'дом',
      'квартир',
      'работ',
    ];
    for (final hint in sceneHints) {
      if (normalized.contains(hint)) return true;
    }
    return false;
  }
}
