import 'dart:math';

import '../models/friend_profile.dart';

class FriendAvatarPrompt {
  final String prompt;
  final String hairstyle;
  final String ethnicity;
  final String skinTone;
  final String bodyType;
  final String heightCategory;
  final String facialFeatures;

  const FriendAvatarPrompt({
    required this.prompt,
    required this.hairstyle,
    required this.ethnicity,
    required this.skinTone,
    required this.bodyType,
    required this.heightCategory,
    required this.facialFeatures,
  });
}

class FriendAvatarPromptBuilder {
  static const List<String> _hairstyles = [
    'soft waves',
    'sleek straight hair',
    'textured short crop',
    'shoulder-length layers',
    'side-swept style',
    'curly hair',
    'messy bun',
    'low ponytail',
    'half-up hairstyle',
    'neat fade with styled top',
  ];

  static const List<String> _faceShapes = [
    'oval face shape',
    'round face shape',
    'heart-shaped face',
    'square face shape',
    'diamond face shape',
    'soft angular face',
    'long face shape',
  ];

  static const List<String> _noseShapes = [
    'straight nose',
    'slightly upturned nose',
    'softly curved nose',
    'defined bridge nose',
    'short nose',
    'slender nose',
    'prominent nose',
  ];

  static const List<String> _lipShapes = [
    'full lips',
    'thin lips',
    'medium lips',
    'bow-shaped upper lip',
    'softly defined lips',
    'wide lips',
  ];

  static const List<String> _cheekbones = [
    'high cheekbones',
    'subtle cheekbones',
    'defined cheekbones',
    'soft cheekbones',
  ];

  static const List<String> _jawlines = [
    'soft jawline',
    'defined jawline',
    'angular jawline',
    'rounded jawline',
  ];

  static const List<String> _foreheads = [
    'smooth forehead',
    'high forehead',
    'medium forehead',
    'softly rounded forehead',
  ];

  static const List<String> _brows = [
    'soft arched eyebrows',
    'straight eyebrows',
    'defined eyebrows',
    'full eyebrows',
    'delicate eyebrows',
  ];

  static const List<String> _eyeShapes = [
    'almond-shaped eyes',
    'round eyes',
    'deep-set eyes',
    'slightly hooded eyes',
    'wide-set eyes',
  ];

  static const List<String> _skinDetails = [
    'light freckles',
    'subtle freckles',
    'clear skin',
    'natural skin texture',
    'small beauty mark on the cheek',
  ];

  static const List<String> _maleTops = [
    "men's fitted blazer",
    "men's button-up shirt",
    "men's knit sweater",
    "men's plain t-shirt",
    "men's turtleneck",
    "men's lightweight hoodie",
    "men's denim shirt",
  ];

  static const List<String> _femaleTops = [
    "women's fitted blazer",
    "women's silk blouse",
    "women's ribbed top",
    "women's knit sweater",
    "women's plain t-shirt",
    "women's turtleneck",
    "women's cardigan",
  ];

  static const List<String> _maleBottoms = [
    "men's tailored trousers",
    "men's dark jeans",
    "men's chino pants",
    "men's black trousers",
    "men's straight-leg jeans",
  ];

  static const List<String> _femaleBottoms = [
    "women's high-waisted jeans",
    "women's midi skirt",
    "women's pleated skirt",
    "women's dark jeans",
    "women's straight-leg jeans",
  ];

  static const List<String> _outerwear = [
    'leather jacket',
    'denim jacket',
    'trench coat',
    'light bomber jacket',
    'longline coat',
  ];

  static const List<String> _maleFootwear = [
    "men's clean white sneakers",
    "men's ankle boots",
    "men's classic loafers",
    "men's sleek sneakers",
  ];

  static const List<String> _femaleFootwear = [
    "women's clean white sneakers",
    "women's ankle boots",
    "women's minimalist heels",
    "women's sleek sneakers",
  ];

  static const List<String> _maleAccessories = [
    "men's watch",
    "men's sunglasses",
    "men's simple bracelet",
  ];

  static const List<String> _femaleAccessories = [
    "women's subtle necklace",
    "women's simple earrings",
    "women's sunglasses",
    "women's minimalist bag",
  ];

  static const List<String> _photoLocations = [
    'a cozy coffee shop corner',
    'a small local cafe counter',
    'a downtown city street at golden hour',
    'a quiet neighborhood sidewalk',
    'a modern office or coworking lounge',
    'a rooftop with a city skyline',
    'a park bench or riverside walkway',
    'a stylish bar with warm lights',
    'a bookstore aisle or library reading table',
    'a restaurant terrace or patio',
    'a grocery store aisle',
    'a weekend farmers market stall',
    'a museum lobby or gallery hallway',
    'a cinema lobby',
    'a commuter train seat by the window',
    'a bus stop on a city street',
    'a gym entrance or fitness studio lobby',
    'a home kitchen with soft window light',
    'a balcony or window corner at home',
    'a beach or seaside promenade',
  ];

  static const List<String> _photoTypes = [
    'phone selfie with front camera, arm slightly extended',
    'mirror selfie in a stylish full-length mirror',
    'candid photo taken by a friend from a few meters away',
    'casual snapshot taken by someone else, subject aware of camera',
    'timer shot with phone propped on a surface, hands free',
    'candid moment, subject not looking directly at camera',
    'photo taken by a friend mid-conversation, natural expression',
    'casual portrait shot by a friend with phone camera',
  ];

  static const List<String> _casualPoses = [
    'standing relaxed with one hand in pocket, weight on one leg',
    'leaning casually against a wall with arms crossed loosely',
    'sitting at a table, leaning forward slightly with elbows on the surface',
    'walking on a street, caught mid-step, looking toward camera',
    'looking to the side with a relaxed natural smile',
    'laughing candidly with head tilted back slightly',
    'holding a coffee cup near face level, warm expression',
    'adjusting hair casually with one hand',
    'sitting on outdoor steps with knees drawn up, relaxed',
    'leaning on a railing or fence, looking out then turning to camera',
    'standing with hands behind back, friendly open posture',
    'sitting cross-legged on a bench, holding a book or phone',
    'crouching down petting or reaching for something on the ground',
    'mid-wave, hand raised greeting the camera',
    'over-the-shoulder glance back at camera while walking away',
    'stretching arms after standing up, natural and candid',
    'sitting in a deep armchair, legs crossed, relaxed',
    'standing with one foot up on a low wall or ledge',
    'browsing items on a shelf, turned partway toward camera',
    'holding sunglasses in hand, squinting slightly in sunlight',
    'tying shoe on a raised surface, looking up at camera',
    'standing at a counter ordering, turned sideways to camera',
  ];

  static const List<String> _romanticPoses = [
    'standing confidently with one hand on hip, chest forward, seductive smile',
    'leaning against a wall, back slightly arched, warm flirty gaze at camera',
    'sitting at a table, body angled toward camera, chin on hand, intense eye contact',
    'walking toward camera, hair flowing, smoldering confident look',
    'looking over bare shoulder, soft profile, knowing seductive smile',
    'laughing with head tilted back, hand on chest, sparkling eyes',
    'holding a cocktail glass, legs crossed, sultry warm look at camera',
    'playing with hair seductively, biting lower lip slightly',
    'lying on a bed propped on elbows, looking up at camera invitingly',
    'sitting on a windowsill, legs crossed high, dreamy inviting gaze',
    'blowing a kiss toward camera with playful wink',
    'over-the-shoulder glance, mysterious seductive half-smile',
    'stretching sensually in soft morning light near a window',
    'lying on a couch, one knee raised, comfortable and inviting pose',
    'standing with hip cocked, hand running through hair, alluring stance',
    'touching collarbone or necklace, looking through eyelashes seductively',
    'sitting sideways on a chair, arched back, turning to camera warmly',
    'close-up leaning toward camera, lips slightly parted, intimate gaze',
    'walking along a beach barefoot, wind in hair, looking back over shoulder',
    'mirror selfie showing full outfit, confident hand on waist',
    'kneeling on a bed, soft light, looking down at camera with a smile',
    'leaning forward on a table, décolletage visible, playful expression',
  ];

  static const List<String> _cameraAngles = [
    'shot at eye level, straight on',
    'shot slightly from below, subtle upward angle',
    'shot slightly from above at a gentle downward angle',
    'shot at three-quarter angle from the left side',
    'shot at three-quarter angle from the right side',
    'low angle looking up, giving a powerful confident feel',
    'slight Dutch angle tilt for dynamic composition',
    'shot from waist height looking up naturally',
  ];

  static const List<String> _framings = [
    'close-up: face and upper shoulders fill the frame',
    'medium close-up: head down to mid-chest visible',
    'medium shot: subject visible from waist up',
    'medium-full shot: subject visible from above the knees',
    'full body shot: entire person visible head to toe',
    'environmental portrait: person in the lower third, location prominent',
  ];

  static const List<String> _expressions = [
    'warm genuine smile showing teeth',
    'slight confident closed-mouth smile',
    'relaxed neutral expression with soft eyes',
    'laughing openly with mouth open',
    'soft thoughtful look, gazing slightly past camera',
    'playful grin with raised eyebrow',
    'calm serious but approachable resting expression',
    'caught mid-laugh, eyes slightly squinted',
    'subtle knowing half-smile',
    'bright surprised happy expression',
  ];

  static const List<List<String>> _ethnicityTiers = [
    ['caucasian', 'east_asian'],
    ['latino', 'middle_eastern', 'mixed'],
    ['south_asian', 'african'],
  ];

  static const Map<String, List<String>> _ethnicSkinTones = {
    'caucasian': ['fair', 'light', 'medium', 'light olive'],
    'east_asian': ['light', 'light medium', 'medium', 'warm beige'],
    'south_asian': ['medium', 'olive', 'warm tan', 'brown'],
    'african': ['medium brown', 'rich brown', 'dark brown', 'deep dark'],
    'latino': ['light', 'medium', 'olive', 'warm tan', 'light brown'],
    'middle_eastern': ['light', 'medium', 'olive', 'warm tan'],
    'mixed': ['light', 'medium', 'olive', 'tan', 'light brown'],
  };

  static const List<String> _bodyTypes = [
    'slim',
    'athletic',
    'average',
    'curvy',
    'stocky',
  ];

  static const List<String> _heightCategories = [
    'short',
    'average',
    'tall',
  ];

  static const List<String> _romanticLocations = [
    'a stylish bar with dim warm lighting and candles',
    'a rooftop lounge at sunset with city skyline panorama',
    'a luxury hotel lobby or poolside area',
    'a tropical beach at golden hour, waves in background',
    'a cozy bedroom with soft warm morning light through curtains',
    'a restaurant terrace with candlelight at dusk',
    'a boutique hotel balcony with panoramic city view',
    'a yacht deck on calm water, sunset colors',
    'a penthouse apartment with floor-to-ceiling windows',
    'a tropical resort infinity pool edge',
    'a dimly lit upscale wine bar with velvet seating',
    'a luxury spa lounge with soft ambient lighting',
    'a trendy nightclub VIP area with neon accents',
    'a sunlit high-end fitness studio mirror area',
    'a chic apartment bathroom mirror, soft lighting',
  ];

  static const List<String> _romanticExpressions = [
    'seductive confident smile, direct soft eye contact',
    'lips slightly parted, intense smoldering gaze',
    'playful knowing smirk with one eyebrow slightly raised',
    'warm inviting smile showing teeth, sparkling eyes',
    'sultry closed-mouth smile, eyes half-lidded',
    'laughing flirtatiously, head tilted, hand near face',
    'mysterious half-smile, looking through eyelashes',
    'confident relaxed expression, direct alluring gaze at camera',
    'biting lower lip subtly, playful teasing eye contact',
    'soft dreamy look with parted lips, gazing at camera warmly',
  ];

  static const List<String> _romanticPhotoTypes = [
    'phone selfie with flattering overhead angle, arm extended',
    'mirror selfie in a stylish full-length mirror showing full outfit',
    'photo taken by a friend at a party, flattering candid angle',
    'professional-looking casual portrait with soft background blur',
    'selfie in warm golden hour light, glowing skin tones',
    'timer shot showing full body, confident pose',
    'close-up portrait shot with bokeh background',
    'candid shot at a restaurant or bar with flattering lighting',
  ];

  static const List<String> _romanticFramings = [
    'close-up: face and décolletage fill the frame',
    'medium close-up: head to mid-chest, flattering low angle',
    'medium shot: waist up, body and outfit visible',
    'three-quarter body shot: thighs up, emphasizing figure',
    'full body shot: entire person, showing physique and style',
    'medium-full shot: above the knees, flattering proportions',
  ];

  static const List<String> _romanticFemaleTops = [
    "women's fitted crop top showing midriff",
    "women's off-shoulder bodycon top",
    "women's lace-trimmed camisole",
    "women's deep V-neck fitted blouse",
    "women's tight ribbed tank top",
    "women's backless halter neck top",
    "women's satin slip camisole top",
    "women's form-fitting strapless tube top",
    "women's fitted wrap top with plunging neckline",
    "women's sheer long-sleeve top over bralette",
    "women's corset-style fitted top",
    "women's cropped off-shoulder sweater showing collarbones",
  ];

  static const List<String> _romanticFemaleBottoms = [
    "women's high-waisted mini skirt",
    "women's tight leather-look pants",
    "women's form-fitting high-waisted jeans",
    "women's short denim shorts showing legs",
    "women's figure-hugging pencil skirt",
    "women's thigh-slit midi skirt",
    "women's skin-tight leggings",
    "women's high-waisted fitted shorts",
  ];

  static const List<String> _romanticDresses = [
    "women's fitted bodycon mini dress",
    "women's elegant cocktail dress with deep neckline",
    "women's figure-hugging backless mini dress",
    "women's tight satin slip dress",
    "women's form-fitting wrap dress showing legs",
    "women's off-shoulder bodycon dress",
    "women's cut-out detail fitted dress",
    "women's thigh-slit evening dress",
    "women's strapless fitted mini dress",
    "women's lace-trimmed lingerie-inspired slip dress",
  ];

  static const List<String> _romanticFemaleFootwear = [
    "women's strappy high heels",
    "women's stiletto heels",
    "women's elegant ankle-strap heels",
    "women's platform heels",
    "women's knee-high boots with heels",
    "women's sleek pointed-toe pumps",
  ];

  static const List<String> _romanticFemaleAccessories = [
    "delicate gold layered necklaces on décolletage",
    "sparkling drop earrings",
    "thin gold body chain",
    "elegant choker necklace",
    "dainty ankle bracelet",
    "statement cocktail ring",
    "designer clutch bag",
  ];

  static const List<String> _romanticMaleTops = [
    "men's fitted V-neck t-shirt showing physique",
    "men's slim-fit button-up shirt with top buttons undone",
    "men's tight fitted henley shirt",
    "men's well-fitted casual blazer over fitted t-shirt",
    "men's form-fitting crew neck tee showing arms",
    "men's fitted polo shirt",
    "men's slim-fit linen shirt partially unbuttoned",
  ];

  static const List<String> _romanticMaleBottoms = [
    "men's slim-fit dark jeans",
    "men's well-tailored chino pants",
    "men's fitted black trousers",
    "men's slim-fit dress pants",
  ];

  static const List<String> _romanticMaleAccessories = [
    "men's luxury watch",
    "men's stylish sunglasses",
    "men's simple silver chain necklace",
    "men's leather bracelet",
  ];

  final Random _random;

  FriendAvatarPromptBuilder({Random? random}) : _random = random ?? Random();

  FriendAvatarPrompt build({
    required String gender,
    required int age,
    required String hairColor,
    required String eyeColor,
    required String relationshipType,
    String? about,
    String? relationshipNotes,
    String? hairstyle,
    String? ethnicity,
    String? skinTone,
    String? bodyType,
    String? heightCategory,
    String? userWishes,
  }) {
    final genderLabel = gender == 'female' ? 'woman' : 'man';
    final hair = _mapHair(hairColor);
    final eyes = _mapEyes(eyeColor);
    final isRomantic = relationshipType == FriendProfile.relationshipRomantic;

    final resolvedHairstyle = _resolveHairstyle(hairstyle);
    final resolvedEthnicity = _resolveEthnicity(ethnicity);
    final resolvedSkinTone = _resolveSkinTone(skinTone, resolvedEthnicity);
    final resolvedBodyType = _resolveBodyType(bodyType, gender);
    final resolvedHeight = _resolveHeightCategory(heightCategory);

    final ethnicityLabel = _mapEthnicity(resolvedEthnicity);
    final skinToneLabel = _mapSkinTone(resolvedSkinTone);
    final bodyTypeLabel = _mapBodyType(resolvedBodyType, gender);
    final heightLabel = _mapHeight(resolvedHeight, gender);

    final style = isRomantic
        ? (gender == 'female'
            ? 'very attractive, seductive, alluring, confident, glamorous, sensual'
            : 'very attractive, confident, charismatic, well-groomed, masculine')
        : 'friendly, natural-looking, casual, approachable';

    final personaHints = _buildPersonaHints(about, relationshipNotes);
    final photoType =
        isRomantic ? _pickFrom(_romanticPhotoTypes) : _pickFrom(_photoTypes);
    final pose = _pickPose(isRomantic);
    final cameraAngle = _pickFrom(_cameraAngles);
    final framing =
        isRomantic ? _pickFrom(_romanticFramings) : _pickFrom(_framings);
    final expression = isRomantic
        ? _pickFrom(_romanticExpressions)
        : _pickFrom(_expressions);

    final facialFeatures = _buildFacialFeatures();

    final buffer = StringBuffer();
    buffer.writeln('Photo type: $photoType.');
    buffer.writeln('Framing: $framing.');
    buffer.writeln('Camera angle: $cameraAngle.');
    buffer.writeln(
        'Looks like a real social media post by a real person, not a studio or AI-generated image.');
    buffer.writeln(
        'Subject: a $style $age-year-old $ethnicityLabel $genderLabel.');
    buffer.writeln('Ethnicity: $ethnicityLabel. Skin tone: $skinToneLabel.');
    buffer.writeln('Build: $bodyTypeLabel, $heightLabel.');
    buffer.writeln('$hair hair, $eyes eyes.');
    buffer.writeln('Hairstyle: $resolvedHairstyle.');
    buffer.writeln('Facial features: $facialFeatures.');
    buffer.writeln(
        'Distinct facial structure and proportions; avoid generic AI face.');
    buffer.writeln('Pose: $pose.');
    buffer.writeln('Expression: $expression.');
    if (isRomantic) {
      buffer.writeln('Outfit: ${_pickRomanticOutfit(gender)}.');
      buffer.writeln(
          'Outfit is form-fitting, flattering, and accentuates the body; shows skin tastefully like a dating app profile photo.');
    } else {
      buffer.writeln('Outfit: ${_pickOutfit(gender)}.');
      buffer.writeln(
          'Outfit must match the location and activity: gym -> athletic wear, office/coworking -> smart casual, cafe/park -> casual, beach -> summer casual, home -> relaxed loungewear.');
    }
    if (personaHints.isNotEmpty) {
      buffer.writeln('Personality or vibe hints: $personaHints.');
    }
    final wishes = (userWishes ?? '').trim();
    if (wishes.isNotEmpty) {
      buffer.writeln('User wishes (must be reflected in the image): $wishes.');
    }
    if (isRomantic) {
      buffer.writeln('Location: ${_pickFrom(_romanticLocations)}.');
    } else {
      buffer.writeln('Location: ${_pickLocation()}.');
    }
    buffer.writeln(
        'Real environment, not studio; avoid plain, white, or blurry bokeh-only backdrops.');
    buffer
        .writeln('Natural light, candid, high quality, no text, no watermark.');
    buffer.writeln(
        'Realistic phone camera quality with slight natural lens characteristics.');
    buffer
        .writeln('Avoid heavy filters; no childlike or older facial features.');
    buffer
        .writeln('Age-accurate: the person must look exactly $age years old.');
    if (isRomantic) {
      buffer.writeln(
          'Dating app / dating site profile photo vibe: seductive, flirty, body-confident, flattering angles and warm lighting.');
      buffer.writeln(
          'Emphasize physical attractiveness, confident body language, and alluring presence.');
    } else {
      buffer.writeln('Everyday social media profile vibe, casual and unposed.');
    }
    return FriendAvatarPrompt(
      prompt: buffer.toString().trim(),
      hairstyle: resolvedHairstyle,
      ethnicity: resolvedEthnicity,
      skinTone: resolvedSkinTone,
      bodyType: resolvedBodyType,
      heightCategory: resolvedHeight,
      facialFeatures: facialFeatures,
    );
  }

  String _pickLocation() {
    return _photoLocations[_random.nextInt(_photoLocations.length)];
  }

  String _pickPose(bool isRomantic) {
    final pool = isRomantic ? _romanticPoses : _casualPoses;
    return pool[_random.nextInt(pool.length)];
  }

  String _resolveHairstyle(String? value) {
    final normalized = _normalizeHairstyle(value);
    if (normalized.isNotEmpty) return normalized;
    return _hairstyles[_random.nextInt(_hairstyles.length)];
  }

  String _resolveEthnicity(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) return normalized;
    const bool isRuStoreBuild = bool.fromEnvironment('RUSTORE');
    if (isRuStoreBuild) return _resolveRuStoreEthnicity();
    final tier = _ethnicityTiers[_random.nextInt(_ethnicityTiers.length)];
    return tier[_random.nextInt(tier.length)];
  }

  String _resolveRuStoreEthnicity() {
    final roll = _random.nextInt(100);
    if (roll < 82) return 'caucasian';
    if (roll < 87) return 'east_asian';
    if (roll < 91) return 'mixed';
    if (roll < 94) return 'latino';
    if (roll < 97) return 'middle_eastern';
    if (roll < 99) return 'south_asian';
    return 'african';
  }

  String _resolveSkinTone(String? value, String ethnicity) {
    final normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) return normalized;
    final tones = _ethnicSkinTones[ethnicity] ?? _ethnicSkinTones['mixed']!;
    return tones[_random.nextInt(tones.length)];
  }

  String _resolveBodyType(String? value, String gender) {
    final normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) return normalized;
    final pool = gender == 'female'
        ? _bodyTypes.where((t) => t != 'stocky').toList()
        : _bodyTypes.where((t) => t != 'curvy').toList();
    return pool[_random.nextInt(pool.length)];
  }

  String _resolveHeightCategory(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isNotEmpty) return normalized;
    return _heightCategories[_random.nextInt(_heightCategories.length)];
  }

  String _normalizeHairstyle(String? value) {
    if (value == null) return '';
    var text = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 80) {
      text = text.substring(0, 80).trim();
    }
    return text;
  }

  String _pickOutfit(String gender) {
    final isFemale = gender == 'female';
    final top = _pickFrom(isFemale ? _femaleTops : _maleTops);
    final bottom = _pickFrom(isFemale ? _femaleBottoms : _maleBottoms);
    final footwear = _pickFrom(isFemale ? _femaleFootwear : _maleFootwear);
    final parts = <String>[top, bottom, footwear];
    if (_random.nextInt(100) < 40) {
      parts.add(_outerwear[_random.nextInt(_outerwear.length)]);
    }
    if (_random.nextInt(100) < 40) {
      final accessories = isFemale ? _femaleAccessories : _maleAccessories;
      parts.add(accessories[_random.nextInt(accessories.length)]);
    }
    return parts.join(', ');
  }

  String _pickRomanticOutfit(String gender) {
    final isFemale = gender == 'female';
    if (isFemale && _random.nextInt(100) < 45) {
      final dress = _pickFrom(_romanticDresses);
      final footwear = _pickFrom(_romanticFemaleFootwear);
      final parts = <String>[dress, footwear];
      if (_random.nextInt(100) < 55) {
        parts.add(_pickFrom(_romanticFemaleAccessories));
      }
      return parts.join(', ');
    }
    final top =
        _pickFrom(isFemale ? _romanticFemaleTops : _romanticMaleTops);
    final bottom =
        _pickFrom(isFemale ? _romanticFemaleBottoms : _romanticMaleBottoms);
    final footwear =
        _pickFrom(isFemale ? _romanticFemaleFootwear : _maleFootwear);
    final parts = <String>[top, bottom, footwear];
    if (_random.nextInt(100) < 55) {
      final accessories =
          isFemale ? _romanticFemaleAccessories : _romanticMaleAccessories;
      parts.add(_pickFrom(accessories));
    }
    return parts.join(', ');
  }

  String _pickFrom(List<String> options) {
    return options[_random.nextInt(options.length)];
  }

  String _buildFacialFeatures() {
    final features = <String>[
      _pickFrom(_faceShapes),
      _pickFrom(_noseShapes),
      _pickFrom(_lipShapes),
      _pickFrom(_cheekbones),
      _pickFrom(_jawlines),
    ];
    final optionalPools = <List<String>>[
      _foreheads,
      _brows,
      _eyeShapes,
      _skinDetails,
    ];
    for (final pool in optionalPools) {
      if (_random.nextInt(100) < 55) {
        features.add(_pickFrom(pool));
      }
    }
    if (features.length == 5) {
      features.add(
        _pickFrom(optionalPools[_random.nextInt(optionalPools.length)]),
      );
    }
    return features.join(', ');
  }

  String _buildPersonaHints(String? about, String? relationshipNotes) {
    final parts = <String>[];
    final aboutHint = _sanitizeHint(about);
    if (aboutHint.isNotEmpty) {
      parts.add(aboutHint);
    }
    final relationshipHint = _sanitizeHint(relationshipNotes);
    if (relationshipHint.isNotEmpty) {
      parts.add(relationshipHint);
    }
    if (parts.isEmpty) return '';
    return parts.join(' ');
  }

  String _sanitizeHint(String? value) {
    if (value == null) return '';
    var text = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length > 160) {
      text = text.substring(0, 160).trim();
    }
    return text;
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

  String _mapEthnicity(String value) {
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

  String _mapSkinTone(String value) {
    return '$value skin tone';
  }

  String _mapBodyType(String value, String gender) {
    switch (value) {
      case 'slim':
        return gender == 'female' ? 'slim/slender build' : 'lean/slim build';
      case 'athletic':
        return 'athletic/fit build';
      case 'average':
        return 'average build';
      case 'curvy':
        return 'curvy/full-figured build';
      case 'stocky':
        return 'stocky/muscular build';
      default:
        return '$value build';
    }
  }

  String _mapHeight(String value, String gender) {
    switch (value) {
      case 'short':
        return gender == 'female' ? 'petite/short stature' : 'short stature';
      case 'average':
        return 'average height';
      case 'tall':
        return 'tall stature';
      default:
        return '$value height';
    }
  }
}
