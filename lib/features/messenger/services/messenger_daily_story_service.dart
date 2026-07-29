import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/friend_profile_repository.dart';
import '../data/messenger_storage_repository.dart';
import '../data/messenger_story_repository.dart';
import '../data/messenger_story_schedule_repository.dart';
import '../models/friend_profile.dart';
import '../models/messenger_message.dart';
import '../models/messenger_story.dart';
import '../models/messenger_thread.dart';
import '../services/messenger_story_prompt_builder.dart';
import '../../personalization/data/friend_persona_repository.dart';
import '../../personalization/models/friend_persona.dart';
import '../../../services/ai_image_generation_service.dart';
import '../../../services/credit_service.dart';

enum _SceneCategory {
  outdoor,
  urban,
  home,
  sport,
  culture,
  food,
  travel,
  nature,
}

class MessengerDailyStoryService {
  static const Duration _defaultTtl = Duration(hours: 24);
  static const int _chatContextMessageLimit = 20;
  static const Duration _chatContextWindow = Duration(hours: 48);

  // ── outdoor ───────────────────────────────────────────────────

  static const _scenePark = _StoryScene(
    key: 'park',
    category: _SceneCategory.outdoor,
    activityRu: 'на прогулке в парке',
    sceneEn:
        'walking in a beautiful green city park with tall trees and a pathway',
    sceneOnlyEn:
        'a peaceful park pathway with dappled sunlight through green trees and a wooden bench',
  );
  static const _sceneBeach = _StoryScene(
    key: 'beach',
    category: _SceneCategory.outdoor,
    activityRu: 'на пляже',
    sceneEn: 'walking on a sandy beach with ocean waves and clear blue sky',
    sceneOnlyEn:
        'turquoise ocean waves washing over sandy beach with seashells',
  );
  static const _sceneMountain = _StoryScene(
    key: 'mountain',
    category: _SceneCategory.outdoor,
    activityRu: 'в горах',
    sceneEn: 'standing on a scenic mountain trail with panoramic valley views',
    sceneOnlyEn:
        'a breathtaking mountain panorama with misty valleys and dramatic clouds',
  );
  static const _sceneGarden = _StoryScene(
    key: 'garden',
    category: _SceneCategory.outdoor,
    activityRu: 'в саду',
    sceneEn: 'exploring a lush botanical garden full of colorful flowers',
    sceneOnlyEn:
        'close-up of vibrant exotic flowers and lush tropical plants in a garden',
  );
  static const _sceneRiverside = _StoryScene(
    key: 'riverside',
    category: _SceneCategory.outdoor,
    activityRu: 'у реки',
    sceneEn: 'strolling along a peaceful riverside path at golden hour',
    sceneOnlyEn:
        'a calm river reflecting golden sunset light with silhouetted trees',
  );

  // ── urban ─────────────────────────────────────────────────────

  static const _sceneStreet = _StoryScene(
    key: 'street',
    category: _SceneCategory.urban,
    activityRu: 'на улице',
    sceneEn:
        'walking on a lively European city street with beautiful architecture',
    sceneOnlyEn:
        'a charming old European street with cobblestones, cafe awnings, and flower boxes',
  );
  static const _sceneNightCity = _StoryScene(
    key: 'night_city',
    category: _SceneCategory.urban,
    activityRu: 'гуляю вечером',
    sceneEn: 'walking through a vibrant neon-lit city street at night',
    sceneOnlyEn: 'neon signs and city lights reflected in wet asphalt at night',
  );
  static const _sceneMarket = _StoryScene(
    key: 'market',
    category: _SceneCategory.urban,
    activityRu: 'на рынке',
    sceneEn:
        'browsing a colorful outdoor street market with vendors and lights',
    sceneOnlyEn:
        'colorful fresh fruits and exotic spices at a street market stall',
  );
  static const _sceneArtDistrict = _StoryScene(
    key: 'art_district',
    category: _SceneCategory.urban,
    activityRu: 'в арт-квартале',
    sceneEn:
        'strolling through a creative art district with colorful street murals',
    sceneOnlyEn: 'a large vibrant street mural painting on a brick wall',
  );
  static const _sceneSquare = _StoryScene(
    key: 'square',
    category: _SceneCategory.urban,
    activityRu: 'на площади',
    sceneEn: 'standing in a historic city square with a beautiful fountain',
    sceneOnlyEn:
        'a grand city fountain surrounded by historic buildings at golden hour',
  );

  // ── home ──────────────────────────────────────────────────────

  static const _sceneHome = _StoryScene(
    key: 'home',
    category: _SceneCategory.home,
    activityRu: 'дома',
    sceneEn: 'relaxing in a bright modern living room at home',
    sceneOnlyEn:
        'a cozy living room corner with soft throw blankets, candles, and warm string lights',
  );
  static const _sceneKitchen = _StoryScene(
    key: 'kitchen',
    category: _SceneCategory.home,
    activityRu: 'на кухне',
    sceneEn: 'cooking in a bright stylish home kitchen',
    sceneOnlyEn:
        'a beautifully plated homemade meal with fresh herbs on a kitchen counter',
  );
  static const _sceneBedroom = _StoryScene(
    key: 'bedroom',
    category: _SceneCategory.home,
    activityRu: 'дома утром',
    sceneEn: 'in a cozy bright bedroom with morning sunlight through windows',
    sceneOnlyEn:
        'soft morning sunlight streaming through sheer white curtains onto rumpled bedsheets',
  );
  static const _sceneBalcony = _StoryScene(
    key: 'balcony',
    category: _SceneCategory.home,
    activityRu: 'на балконе',
    sceneEn:
        'enjoying morning coffee on a sunny apartment balcony with city view',
    sceneOnlyEn:
        'a steaming cup of coffee on a balcony railing overlooking a city morning',
  );
  static const _sceneHomeOffice = _StoryScene(
    key: 'home_office',
    category: _SceneCategory.home,
    activityRu: 'работаю из дома',
    sceneEn: 'working at a stylish home office desk with a laptop',
    sceneOnlyEn:
        'a minimal desk setup with laptop, coffee cup, and a green plant',
  );

  // ── sport ─────────────────────────────────────────────────────

  static const _sceneGym = _StoryScene(
    key: 'gym',
    category: _SceneCategory.sport,
    activityRu: 'в зале',
    sceneEn: 'working out at a modern gym with fitness equipment',
    sceneOnlyEn:
        'a pair of sneakers and a water bottle next to dumbbells on a gym floor',
  );
  static const _scenePool = _StoryScene(
    key: 'pool',
    category: _SceneCategory.sport,
    activityRu: 'в бассейне',
    sceneEn: 'at a beautiful outdoor swimming pool on a sunny day',
    sceneOnlyEn:
        'crystal clear turquoise pool water with sunlight creating patterns',
  );
  static const _sceneYoga = _StoryScene(
    key: 'yoga',
    category: _SceneCategory.sport,
    activityRu: 'на йоге',
    sceneEn: 'doing yoga in a peaceful sunlit studio with wooden floor',
    sceneOnlyEn:
        'a yoga mat with incense and candles in a peaceful sunlit studio',
  );
  static const _sceneRunning = _StoryScene(
    key: 'running',
    category: _SceneCategory.sport,
    activityRu: 'на пробежке',
    sceneEn: 'jogging on a scenic park path in the early morning',
    sceneOnlyEn: 'running shoes on a scenic trail in soft morning light',
  );
  static const _sceneDance = _StoryScene(
    key: 'dance',
    category: _SceneCategory.sport,
    activityRu: 'на танцах',
    sceneEn: 'dancing in a bright dance studio with mirrors',
    sceneOnlyEn:
        'a pair of dance shoes on a polished wooden floor with mirror reflections',
  );

  // ── culture ───────────────────────────────────────────────────

  static const _sceneLibrary = _StoryScene(
    key: 'library',
    category: _SceneCategory.culture,
    activityRu: 'в библиотеке',
    sceneEn: 'reading in a beautiful old library with tall bookshelves',
    sceneOnlyEn:
        'an open vintage book on a wooden reading desk with a warm desk lamp',
  );
  static const _sceneMuseum = _StoryScene(
    key: 'museum',
    category: _SceneCategory.culture,
    activityRu: 'в музее',
    sceneEn: 'visiting a modern art museum gallery with paintings',
    sceneOnlyEn:
        'a striking painting hanging in an art museum with soft gallery lighting',
  );
  static const _sceneBookstore = _StoryScene(
    key: 'bookstore',
    category: _SceneCategory.culture,
    activityRu: 'в книжном',
    sceneEn: 'browsing books in a cozy indie bookstore with warm lighting',
    sceneOnlyEn:
        'stacks of colorful books on a cozy bookstore shelf with warm light',
  );
  static const _sceneGallery = _StoryScene(
    key: 'gallery',
    category: _SceneCategory.culture,
    activityRu: 'в галерее',
    sceneEn: 'viewing contemporary art in a modern white gallery space',
    sceneOnlyEn:
        'a modern art installation in a clean white gallery space with dramatic lighting',
  );
  static const _sceneTheater = _StoryScene(
    key: 'theater',
    category: _SceneCategory.culture,
    activityRu: 'в театре',
    sceneEn: 'at an elegant theater lobby with red curtains and chandeliers',
    sceneOnlyEn:
        'ornate theater ceiling and chandelier with red velvet details',
  );

  // ── food ──────────────────────────────────────────────────────

  static const _sceneCafe = _StoryScene(
    key: 'cafe',
    category: _SceneCategory.food,
    activityRu: 'в кафе',
    sceneEn: 'sitting in a cozy aesthetic cafe with a coffee cup and pastries',
    sceneOnlyEn:
        'a beautiful latte art coffee cup next to a croissant on a marble cafe table',
  );
  static const _sceneRestaurant = _StoryScene(
    key: 'restaurant',
    category: _SceneCategory.food,
    activityRu: 'в ресторане',
    sceneEn: 'dining at a beautiful restaurant with elegant decor and candles',
    sceneOnlyEn:
        'an elegantly plated gourmet dish with a glass of wine in candlelight',
  );
  static const _sceneBakery = _StoryScene(
    key: 'bakery',
    category: _SceneCategory.food,
    activityRu: 'в пекарне',
    sceneEn: 'at a charming bakery with fresh croissants and warm lighting',
    sceneOnlyEn:
        'fresh golden croissants and pastries arranged on a rustic wooden board',
  );
  static const _sceneFoodMarket = _StoryScene(
    key: 'food_market',
    category: _SceneCategory.food,
    activityRu: 'на фуд-маркете',
    sceneEn: 'exploring a trendy gourmet food market with diverse stalls',
    sceneOnlyEn:
        'a vibrant display of artisan cheeses and fresh bread at a gourmet market',
  );
  static const _scenePicnic = _StoryScene(
    key: 'picnic',
    category: _SceneCategory.food,
    activityRu: 'на пикнике',
    sceneEn: 'having a picnic on green grass with a blanket and fresh food',
    sceneOnlyEn:
        'a summer picnic spread with fruits, wine, and cheese on a checkered blanket',
  );

  // ── travel ────────────────────────────────────────────────────

  static const _sceneAirport = _StoryScene(
    key: 'airport',
    category: _SceneCategory.travel,
    activityRu: 'в аэропорту',
    sceneEn:
        'at a modern airport terminal with large windows and a travel suitcase',
    sceneOnlyEn:
        'a passport, boarding pass, and coffee cup on an airport window ledge with planes outside',
  );
  static const _sceneTrain = _StoryScene(
    key: 'train',
    category: _SceneCategory.travel,
    activityRu: 'в поезде',
    sceneEn: 'looking out a train window at beautiful passing countryside',
    sceneOnlyEn:
        'a blurred countryside landscape passing by through a rain-dotted train window',
  );
  static const _sceneHotel = _StoryScene(
    key: 'hotel',
    category: _SceneCategory.travel,
    activityRu: 'в отеле',
    sceneEn: 'relaxing in a modern hotel room with a panoramic window view',
    sceneOnlyEn:
        'a luxurious hotel room bed with city skyline visible through floor-to-ceiling windows',
  );
  static const _sceneViewpoint = _StoryScene(
    key: 'viewpoint',
    category: _SceneCategory.travel,
    activityRu: 'на смотровой',
    sceneEn:
        'at a scenic viewpoint overlooking a beautiful city panorama at sunset',
    sceneOnlyEn:
        'a panoramic city skyline view from a high observation deck at sunset',
  );
  static const _sceneRoadTrip = _StoryScene(
    key: 'road_trip',
    category: _SceneCategory.travel,
    activityRu: 'в путешествии',
    sceneEn: 'on a road trip standing by a car on a scenic mountain highway',
    sceneOnlyEn: 'a winding scenic mountain road stretching into the distance',
  );

  // ── nature ────────────────────────────────────────────────────

  static const _sceneForest = _StoryScene(
    key: 'forest',
    category: _SceneCategory.nature,
    activityRu: 'в лесу',
    sceneEn: 'walking through a peaceful sunlit forest path with green trees',
    sceneOnlyEn:
        'sunbeams filtering through tall pine trees onto a mossy forest floor',
  );
  static const _sceneLake = _StoryScene(
    key: 'lake',
    category: _SceneCategory.nature,
    activityRu: 'на озере',
    sceneEn:
        'sitting by a calm beautiful lake surrounded by trees at golden hour',
    sceneOnlyEn:
        'a glass-like lake perfectly reflecting mountains and pink sunset sky',
  );
  static const _sceneSunset = _StoryScene(
    key: 'sunset',
    category: _SceneCategory.nature,
    activityRu: 'любуюсь закатом',
    sceneEn: 'watching a breathtaking sunset from a hilltop',
    sceneOnlyEn:
        'a dramatic sunset sky with vibrant orange and purple clouds over the horizon',
  );
  static const _sceneFlowerField = _StoryScene(
    key: 'flower_field',
    category: _SceneCategory.nature,
    activityRu: 'в цветочном поле',
    sceneEn: 'standing in a stunning colorful wildflower field',
    sceneOnlyEn:
        'endless rows of lavender stretching to the horizon in warm golden light',
  );
  static const _sceneEmbankment = _StoryScene(
    key: 'embankment',
    category: _SceneCategory.nature,
    activityRu: 'на набережной',
    sceneEn: 'walking along a scenic waterfront embankment at sunset',
    sceneOnlyEn:
        'a waterfront promenade with old-fashioned street lamps and evening boat lights',
  );

  // ── all scenes (40 scenes × 8 categories) ────────────────────

  static const List<_StoryScene> _allScenes = [
    _scenePark,
    _sceneBeach,
    _sceneMountain,
    _sceneGarden,
    _sceneRiverside,
    _sceneStreet,
    _sceneNightCity,
    _sceneMarket,
    _sceneArtDistrict,
    _sceneSquare,
    _sceneHome,
    _sceneKitchen,
    _sceneBedroom,
    _sceneBalcony,
    _sceneHomeOffice,
    _sceneGym,
    _scenePool,
    _sceneYoga,
    _sceneRunning,
    _sceneDance,
    _sceneLibrary,
    _sceneMuseum,
    _sceneBookstore,
    _sceneGallery,
    _sceneTheater,
    _sceneCafe,
    _sceneRestaurant,
    _sceneBakery,
    _sceneFoodMarket,
    _scenePicnic,
    _sceneAirport,
    _sceneTrain,
    _sceneHotel,
    _sceneViewpoint,
    _sceneRoadTrip,
    _sceneForest,
    _sceneLake,
    _sceneSunset,
    _sceneFlowerField,
    _sceneEmbankment,
  ];

  // ── chat context hints (recent messages → scene) ──────────────

  static const List<_SceneHint> _chatContextHints = [
    _SceneHint(['парк', 'прогулк', 'гулял', 'гуляю', 'сквер'], _scenePark),
    _SceneHint(['пляж', 'мор', 'океан', 'загор', 'купал'], _sceneBeach),
    _SceneHint(['гор', 'поход', 'хайк', 'альпин', 'треккинг'], _sceneMountain),
    _SceneHint(['ботаник', 'оранжере', 'цветник'], _sceneGarden),
    _SceneHint(['река', 'речк'], _sceneRiverside),
    _SceneHint(['город', 'архитектур'], _sceneStreet),
    _SceneHint(['ночн', 'неон', 'вечеринк', 'клуб', 'бар'], _sceneNightCity),
    _SceneHint(
        ['рынок', 'ярмарк', 'базар', 'магазин', 'шоппинг'], _sceneMarket),
    _SceneHint(['граффити', 'стрит-арт', 'мурал'], _sceneArtDistrict),
    _SceneHint(['площад', 'фонтан'], _sceneSquare),
    _SceneHint(['дом', 'квартир', 'диван', 'сериал', 'фильм'], _sceneHome),
    _SceneHint(['кухн', 'готов', 'рецепт'], _sceneKitchen),
    _SceneHint(['утр', 'проснул', 'будильник'], _sceneBedroom),
    _SceneHint(['балкон', 'террас'], _sceneBalcony),
    _SceneHint(['работ', 'офис', 'дедлайн', 'задач'], _sceneHomeOffice),
    _SceneHint(['зал', 'трен', 'качал', 'штанг', 'фитнес'], _sceneGym),
    _SceneHint(['бассейн', 'плава'], _scenePool),
    _SceneHint(['йог', 'медитац', 'асан'], _sceneYoga),
    _SceneHint(['бег', 'пробеж', 'кросс'], _sceneRunning),
    _SceneHint(['танц', 'хореограф'], _sceneDance),
    _SceneHint(['библиотек'], _sceneLibrary),
    _SceneHint(['музе', 'выставк', 'экспонат'], _sceneMuseum),
    _SceneHint(['книжн'], _sceneBookstore),
    _SceneHint(['галере', 'искусств'], _sceneGallery),
    _SceneHint(['театр', 'спектакл', 'пьес'], _sceneTheater),
    _SceneHint(['кофе', 'кафе', 'латте', 'капучин'], _sceneCafe),
    _SceneHint(['ресторан', 'обед', 'ужин'], _sceneRestaurant),
    _SceneHint(['пекарн', 'булочн', 'круассан'], _sceneBakery),
    _SceneHint(['фуд-маркет', 'фудкорт'], _sceneFoodMarket),
    _SceneHint(['пикник', 'поляна'], _scenePicnic),
    _SceneHint(['аэропорт', 'самолёт', 'самолет', 'перелёт', 'перелет'],
        _sceneAirport),
    _SceneHint(['поезд', 'вагон', 'электричк'], _sceneTrain),
    _SceneHint(['отел', 'гостиниц'], _sceneHotel),
    _SceneHint(['смотров', 'панорам', 'обзорн'], _sceneViewpoint),
    _SceneHint(['путешеств', 'поездк', 'тур'], _sceneRoadTrip),
    _SceneHint(['лес', 'чащ', 'гриб'], _sceneForest),
    _SceneHint(['озер', 'пруд'], _sceneLake),
    _SceneHint(['закат', 'рассвет'], _sceneSunset),
    _SceneHint(['лавандов', 'подсолнух', 'маков'], _sceneFlowerField),
    _SceneHint(['набережн', 'причал'], _sceneEmbankment),
    _SceneHint(['рожден', 'именин', 'праздник'], _sceneRestaurant),
    _SceneHint(['концерт', 'выступлен'], _sceneNightCity),
    _SceneHint(['учеб', 'лекци', 'экзамен', 'универ'], _sceneLibrary),
    _SceneHint(['книг', 'чита'], _sceneLibrary),
  ];

  // ── hobby-to-scene hints (persona hobbies → preferred scene) ──

  static const List<_SceneHint> _hobbyToSceneHints = [
    _SceneHint(['книг', 'чита', 'литератур', 'роман'], _sceneLibrary),
    _SceneHint(['книг', 'чита'], _sceneBookstore),
    _SceneHint(['спорт', 'фитнес', 'трен', 'качал'], _sceneGym),
    _SceneHint(['йог', 'медитац', 'пилатес'], _sceneYoga),
    _SceneHint(['плаван', 'бассейн'], _scenePool),
    _SceneHint(['бег', 'пробеж', 'марафон'], _sceneRunning),
    _SceneHint(['танц', 'хореограф', 'балет', 'сальса'], _sceneDance),
    _SceneHint(['кофе', 'кафе', 'бариста'], _sceneCafe),
    _SceneHint(['готов', 'кулинар', 'рецепт', 'выпеч'], _sceneKitchen),
    _SceneHint(['пекарн', 'хлеб', 'выпечк'], _sceneBakery),
    _SceneHint(['путешеств', 'поездк', 'тур'], _sceneRoadTrip),
    _SceneHint(['самолёт', 'самолет', 'аэропорт'], _sceneAirport),
    _SceneHint(['фото', 'камер', 'фотограф'], _sceneViewpoint),
    _SceneHint(['рисов', 'арт', 'скетч', 'живопис'], _sceneGallery),
    _SceneHint(['граффит', 'стрит-арт'], _sceneArtDistrict),
    _SceneHint(['музык', 'концерт', 'гитар', 'фортепиан'], _sceneNightCity),
    _SceneHint(['театр', 'пьес', 'актёр', 'актер'], _sceneTheater),
    _SceneHint(['музе', 'выставк', 'экскурс'], _sceneMuseum),
    _SceneHint(['природ', 'кемпинг'], _sceneForest),
    _SceneHint(['сад', 'цвет', 'растен', 'флорист'], _sceneGarden),
    _SceneHint(['прогулк', 'гулять', 'парк'], _scenePark),
    _SceneHint(['пляж', 'серфинг', 'мор'], _sceneBeach),
    _SceneHint(['гор', 'поход', 'скалолаз'], _sceneMountain),
    _SceneHint(['озер', 'рыбалк'], _sceneLake),
  ];

  // ── selfie shot hints (person in frame) ───────────────────────

  static const List<String> _selfieShotHints = [
    'taking a candid selfie',
    'taking a smiling selfie',
    'taking a close-up selfie',
    'taking a half-body selfie',
    'taking a casual selfie',
    'taking a relaxed selfie',
    'posing casually for a photo',
    'captured in a candid moment',
    'looking naturally at the camera',
  ];

  static const List<String> _romanticSelfieShotHints = [
    'taking a flirty selfie with a playful smile',
    'taking a seductive close-up selfie',
    'posing confidently for a sultry selfie',
    'taking a sensual half-body selfie',
    'looking alluringly at the camera',
    'posing with a teasing flirty expression',
    'captured in a seductive candid moment',
    'taking a provocative yet classy selfie',
    'posing with bedroom eyes for a selfie',
  ];

  // ── scene-only shot hints (no person, objects / environment) ──

  static const List<String> _sceneOnlyShotHints = [
    'aesthetic',
    'atmospheric',
    'artistic',
    'moody',
    'vibrant',
    'dreamy',
    'cinematic',
    'cozy',
    'warm and inviting',
  ];

  static const List<String> _romanticSceneOnlyShotHints = [
    'romantic',
    'intimate',
    'sensual',
    'dreamy',
    'warm and seductive',
    'soft and intimate',
    'alluring',
    'passionate',
  ];

  // ── romantic preferred scenes ───────────────────────────────────

  static const List<_StoryScene> _romanticPreferredScenes = [
    _sceneBedroom,
    _sceneHome,
    _sceneBalcony,
    _scenePool,
    _sceneBeach,
    _sceneHotel,
    _sceneSunset,
    _sceneFlowerField,
    _sceneEmbankment,
    _scenePicnic,
    _sceneRestaurant,
    _sceneNightCity,
    _sceneYoga,
    _scenePark,
    _sceneRiverside,
    _sceneCafe,
    _sceneGarden,
  ];

  static const List<String> _lightHints = [
    'soft daylight',
    'golden hour light',
    'warm indoor light',
    'bright natural light',
    'soft window light',
    'moody evening light',
    'early morning light',
    'vibrant afternoon sunlight',
  ];

  // ── hobby prop hints (add hobby-specific props to selfies) ────

  static const List<_HobbyHint> _hobbyPropHints = [
    _HobbyHint(
      ['книга', 'читать', 'литератур', 'book', 'read'],
      'with a book in hand',
    ),
    _HobbyHint(
      ['музык', 'плейлист', 'науш', 'music', 'playlist', 'headphone'],
      'with headphones on',
    ),
    _HobbyHint(
      ['фото', 'камера', 'photo', 'camera'],
      'holding a camera',
    ),
    _HobbyHint(
      ['рис', 'арт', 'скетч', 'design', 'art', 'sketch'],
      'with a sketchbook',
    ),
    _HobbyHint(
      ['спорт', 'фитнес', 'йога', 'трен', 'gym', 'workout'],
      'wearing sporty outfit',
    ),
    _HobbyHint(
      ['готов', 'кулинар', 'рецепт', 'cook', 'kitchen'],
      'holding a small plate of food',
    ),
    _HobbyHint(
      ['путеше', 'поход', 'trip', 'travel'],
      'with a small backpack',
    ),
    _HobbyHint(
      ['игр', 'гейм', 'play', 'game'],
      'with a game controller nearby',
    ),
    _HobbyHint(
      ['кофе', 'кафе', 'coffee', 'cafe'],
      'holding a coffee cup',
    ),
  ];

  // ── outfit pools per category (female) ─────────────────────────

  static const Map<_SceneCategory, List<String>> _femaleOutfits = {
    _SceneCategory.outdoor: [
      'light denim jacket over white t-shirt with blue jeans and white sneakers',
      'beige trench coat with black turtleneck and slim dark pants',
      'oversized knit sweater with leggings and ankle boots',
      'casual sundress with a light cardigan and sandals',
      'puffer vest over striped long-sleeve shirt with jeans',
    ],
    _SceneCategory.urban: [
      'cropped leather jacket with high-waisted jeans and black boots',
      'oversized blazer over crop top with wide-leg pants',
      'trendy midi skirt with fitted turtleneck and heeled boots',
      'bomber jacket with slip dress and white sneakers',
      'elegant long coat with all-black outfit underneath',
    ],
    _SceneCategory.home: [
      'cozy oversized hoodie with cotton shorts',
      'soft cashmere sweater with leggings',
      'silk pajama set in pastel colors',
      'comfy cropped sweatshirt with joggers',
      'loose linen shirt with soft lounge pants',
    ],
    _SceneCategory.sport: [
      'matching workout set in pastel pink',
      'sports bra with high-waisted black leggings',
      'athletic tank top with running shorts',
      'yoga outfit in earth tones with bare feet',
      'sporty zip-up jacket with fitted leggings',
    ],
    _SceneCategory.culture: [
      'elegant blouse tucked into tailored trousers',
      'chic turtleneck with pleated midi skirt',
      'smart blazer with dark jeans and heeled boots',
      'knit sweater dress with tights and ankle boots',
      'silk blouse with high-waisted pants and flats',
    ],
    _SceneCategory.food: [
      'cozy knit cardigan over simple t-shirt dress',
      'white blouse with jeans and heeled ankle boots',
      'cute sweater with a-line skirt',
      'casual linen dress with minimal jewelry',
      'relaxed blouse with wide-leg pants and flats',
    ],
    _SceneCategory.travel: [
      'comfortable hoodie with joggers and clean sneakers',
      'light parka with skinny jeans and a crossbody bag',
      'linen button-up shirt with cargo pants',
      'casual denim jacket over maxi dress',
      'layered outfit with scarf and leather backpack',
    ],
    _SceneCategory.nature: [
      'flannel shirt tied at the waist with hiking shorts',
      'athletic fleece with trail pants and hiking boots',
      'light down jacket with jeans and boots',
      'cozy beanie with windbreaker and leggings',
      'outdoor vest over long-sleeve henley with jeans',
    ],
  };

  // ── romantic outfit pools per category (female) ───────────────

  static const Map<_SceneCategory, List<String>> _romanticFemaleOutfits = {
    _SceneCategory.outdoor: [
      'fitted off-shoulder top with high-waisted shorts and strappy sandals',
      'flowy mini dress with a thin belt and heeled sandals',
      'crop top with high-waisted skinny jeans and ankle boots',
      'bodycon sundress with a light sheer cardigan',
      'tight tank top with a mini skirt and wedge sandals',
    ],
    _SceneCategory.urban: [
      'form-fitting mini dress with heels and statement jewelry',
      'leather pants with a lace camisole and heeled boots',
      'bodycon dress with a cropped jacket and strappy heels',
      'sheer blouse with high-waisted leather skirt and boots',
      'tight crop top with high-waisted pants and stilettos',
    ],
    _SceneCategory.home: [
      'silk slip dress in soft champagne color',
      'oversized boyfriend shirt with bare legs',
      'lace-trimmed satin camisole with silk shorts',
      'cozy cropped sweater with cotton shorts',
      'satin robe loosely tied over a lace bralette',
    ],
    _SceneCategory.sport: [
      'matching sports bra and high-waisted leggings set',
      'fitted crop top with yoga pants',
      'athletic bralette with bike shorts',
      'form-fitting workout bodysuit',
      'sports bra with low-rise joggers showing midriff',
    ],
    _SceneCategory.culture: [
      'elegant form-fitting cocktail dress with heels',
      'deep v-neck blouse with tailored pencil skirt',
      'off-shoulder top with fitted high-waisted trousers',
      'backless top with elegant wide-leg pants',
      'fitted turtleneck dress with knee-high boots',
    ],
    _SceneCategory.food: [
      'low-cut blouse with a fitted mini skirt',
      'elegant wrap dress showing a hint of cleavage',
      'satin camisole with tailored pants and heels',
      'off-shoulder sweater dress with thigh-high boots',
      'fitted crop cardigan with high-waisted trousers',
    ],
    _SceneCategory.travel: [
      'crop top with high-waisted shorts and sunglasses',
      'fitted sundress with strappy sandals',
      'off-shoulder top with denim shorts',
      'bodycon mini dress with a leather jacket',
      'halter top with linen pants and wedges',
    ],
    _SceneCategory.nature: [
      'fitted tank top tied at the waist with short shorts',
      'light sundress with bare shoulders',
      'crop top with flowy skirt and sandals',
      'open flannel shirt over a bikini top with denim shorts',
      'fitted athletic top with yoga shorts',
    ],
  };

  // ── outfit pools per category (male) ──────────────────────────

  static const Map<_SceneCategory, List<String>> _maleOutfits = {
    _SceneCategory.outdoor: [
      'casual denim jacket over white t-shirt with chinos',
      'beige overcoat with dark turtleneck and trousers',
      'knit sweater with jeans and suede boots',
      'quilted vest over flannel shirt with dark jeans',
      'bomber jacket with joggers and clean sneakers',
    ],
    _SceneCategory.urban: [
      'leather jacket with black jeans and chelsea boots',
      'streetwear hoodie with cargo pants and high-tops',
      'smart overcoat with tailored pants and loafers',
      'polo shirt with slim chinos and white sneakers',
      'printed shirt with dark jeans and boots',
    ],
    _SceneCategory.home: [
      'plain white t-shirt with cotton sweatpants',
      'cozy crewneck sweater with shorts',
      'soft gray hoodie with black joggers',
      'henley shirt with lounge pants',
      'casual flannel shirt over plain tee with shorts',
    ],
    _SceneCategory.sport: [
      'athletic tank top with training shorts',
      'compression shirt with black joggers',
      'sporty zip-up hoodie with track pants',
      'sleeveless workout shirt with gym shorts',
      'running shirt with athletic shorts and sneakers',
    ],
    _SceneCategory.culture: [
      'navy blazer with white shirt and chinos',
      'turtleneck sweater with tailored trousers',
      'smart casual button-up with dark jeans',
      'linen suit jacket with rolled-up sleeves and pants',
      'cashmere v-neck sweater with dress pants',
    ],
    _SceneCategory.food: [
      'casual button-up shirt with dark jeans',
      'nice polo with chinos and loafers',
      'knit sweater over collared shirt with pants',
      'relaxed linen shirt with dark trousers',
      'smart casual blazer over simple t-shirt with jeans',
    ],
    _SceneCategory.travel: [
      'comfortable hoodie with jeans and sneakers',
      'light windbreaker with cargo pants',
      'layered flannel shirt with jeans and boots',
      'casual zip jacket with joggers and trail shoes',
      'henley with rolled-up jeans and leather boots',
    ],
    _SceneCategory.nature: [
      'flannel shirt with hiking pants and boots',
      'outdoor fleece jacket with cargo pants',
      'light down vest over long-sleeve shirt with jeans',
      'waterproof softshell jacket with trail pants',
      'beanie with quilted jacket and dark jeans',
    ],
  };

  // ── romantic outfit pools per category (male) ─────────────────

  static const Map<_SceneCategory, List<String>> _romanticMaleOutfits = {
    _SceneCategory.outdoor: [
      'fitted henley with sleeves rolled up and slim dark jeans',
      'well-fitted v-neck t-shirt with chinos showing off physique',
      'tailored polo with fitted shorts and clean sneakers',
      'slim-fit button-up with top buttons undone and dark jeans',
      'fitted linen shirt partially unbuttoned with slim pants',
    ],
    _SceneCategory.urban: [
      'tight-fit black t-shirt with leather jacket and dark jeans',
      'fitted dress shirt with sleeves rolled up and tailored pants',
      'slim turtleneck with fitted coat and dress pants',
      'well-fitted v-neck sweater with dark jeans and boots',
      'smart fitted blazer over a plain white t-shirt and jeans',
    ],
    _SceneCategory.home: [
      'shirtless with low-rise sweatpants',
      'open robe over bare chest with cotton pants',
      'fitted tank top with joggers',
      'plain white t-shirt with loose lounge pants',
      'unbuttoned flannel shirt showing chest with lounge pants',
    ],
    _SceneCategory.sport: [
      'sleeveless compression shirt showing muscular arms with shorts',
      'fitted tank top with training shorts',
      'shirtless with athletic shorts and sneakers',
      'compression top with fitted joggers',
      'muscle tee with gym shorts',
    ],
    _SceneCategory.culture: [
      'fitted turtleneck showing physique with tailored trousers',
      'well-tailored suit jacket over fitted t-shirt',
      'dress shirt with top buttons undone and slim pants',
      'fitted cashmere sweater with dark trousers',
      'slim blazer with v-neck t-shirt and chinos',
    ],
    _SceneCategory.food: [
      'fitted button-up with sleeves rolled and top buttons open',
      'well-fitted polo emphasizing build with dark chinos',
      'slim cashmere sweater with tailored pants',
      'dress shirt slightly unbuttoned with fitted pants',
      'fitted henley with dark jeans and a watch',
    ],
    _SceneCategory.travel: [
      'fitted tank top with shorts and sunglasses',
      'open linen shirt over fitted undershirt with shorts',
      'slim v-neck tee with cargo shorts',
      'fitted polo with rolled-up chinos',
      'athletic zip-up showing fit physique with joggers',
    ],
    _SceneCategory.nature: [
      'fitted tank top with hiking shorts',
      'open flannel shirt showing chest with jeans',
      'sleeveless athletic shirt with outdoor shorts',
      'fitted long-sleeve henley rolled up with cargo pants',
      'moisture-wicking shirt showing physique with trail shorts',
    ],
  };

  // ── service fields ────────────────────────────────────────────

  final MessengerStorageRepository _storageRepository;
  final MessengerStoryRepository _storyRepository;
  final MessengerStoryScheduleRepository _scheduleRepository;
  final AiImageGenerationService _imageService;
  final FriendPersonaRepository _personaRepository;
  final FriendProfileRepository _friendProfileRepository;
  final MessengerStoryPromptBuilder _promptBuilder;
  final Random _random;

  bool _syncInFlight = false;

  MessengerDailyStoryService({
    required MessengerStorageRepository storageRepository,
    required MessengerStoryRepository storyRepository,
    required MessengerStoryScheduleRepository scheduleRepository,
    required AiImageGenerationService imageService,
    required FriendPersonaRepository personaRepository,
    required FriendProfileRepository friendProfileRepository,
    MessengerStoryPromptBuilder? promptBuilder,
    Random? random,
  })  : _storageRepository = storageRepository,
        _storyRepository = storyRepository,
        _scheduleRepository = scheduleRepository,
        _imageService = imageService,
        _personaRepository = personaRepository,
        _friendProfileRepository = friendProfileRepository,
        _promptBuilder = promptBuilder ?? const MessengerStoryPromptBuilder(),
        _random = random ?? Random();

  // ── public API ────────────────────────────────────────────────

  Future<int> ensureDailyStories({
    String contactId = 'friend',
    int count = 3,
    Duration ttl = _defaultTtl,
  }) async {
    if (_syncInFlight) return 0;
    _syncInFlight = true;
    try {
      final now = DateTime.now();
      var anchorAt = _scheduleRepository.loadAnchorAt(contactId);
      if (anchorAt == null) {
        await _ensureAnchor(contactId, now);
        anchorAt = now;
      }
      final todayAnchor = _anchorForDay(anchorAt, now);
      if (now.isBefore(todayAnchor)) {
        return 0;
      }
      final lastPublishedAt =
          _scheduleRepository.loadLastPublishedAt(contactId);
      if (lastPublishedAt != null && !lastPublishedAt.isBefore(todayAnchor)) {
        return 0;
      }
      return _generateStoriesForContact(
        contactId: contactId,
        count: count,
        ttl: ttl,
        anchorTime: now,
      );
    } catch (e) {
      debugPrint('Ошибка генерации ежедневных сторис: $e');
      return 0;
    } finally {
      _syncInFlight = false;
    }
  }

  Future<int> generateInitialStories({
    String contactId = 'friend',
    int count = 3,
    Duration ttl = _defaultTtl,
  }) async {
    if (_syncInFlight) return 0;
    _syncInFlight = true;
    try {
      final now = DateTime.now();
      await _ensureAnchor(contactId, now);
      final lastPublishedAt =
          _scheduleRepository.loadLastPublishedAt(contactId);
      if (lastPublishedAt != null && _isSameDay(lastPublishedAt, now)) {
        return 0;
      }
      return _generateStoriesForContact(
        contactId: contactId,
        count: count,
        ttl: ttl,
        anchorTime: now,
      );
    } catch (e) {
      debugPrint('Ошибка генерации первых сторис: $e');
      return 0;
    } finally {
      _syncInFlight = false;
    }
  }

  // ── generation ────────────────────────────────────────────────

  Future<int> _generateStoriesForContact({
    required String contactId,
    required int count,
    required Duration ttl,
    required DateTime anchorTime,
  }) async {
    if (!await _imageService.isAvailable()) {
      return 0;
    }
    final thread = await _storageRepository.loadThreadById(contactId);
    final friendProfile = _friendProfileRepository.load(contactId);
    final friendPersona = await _safeLoadPersona(contactId);
    final avatarFile = _resolveAvatarFile(friendProfile);
    if (avatarFile == null) {
      return 0;
    }
    final plans = _buildPlans(
      thread: thread,
      friendProfile: friendProfile,
      friendPersona: friendPersona,
      count: count,
    );
    if (plans.isEmpty) {
      return 0;
    }
    var created = 0;
    final isFreeUser = await CreditService().isFreeUser();
    
    for (var i = 0; i < plans.length; i += 1) {
      final hasCredits = await CreditService().hasCreditsForStory();
      if (!hasCredits) break;
      
      final canUseFreeStory = await CreditService().canUseFreeStory();
      final isLocked = isFreeUser && !canUseFreeStory;
      
      final plan = plans[i];
      final result = await _generateImage(plan, avatarFile);
      if (result.file == null) continue;
      await CreditService().useStoryCredits();
      
      if (isFreeUser && !isLocked) {
        await CreditService().useFreeStory();
      }
      
      final createdAt = DateTime.now();
      final story = MessengerStory(
        id: '${createdAt.microsecondsSinceEpoch}-$contactId-$i',
        contactId: thread.contact.id,
        contactName: thread.contact.name,
        caption: '',
        createdAt: createdAt,
        expiresAt: createdAt.add(ttl),
        aspectRatio: '9:16',
        imagePath: result.file?.path,
        avatarPath: thread.contact.avatarPath,
        prompt: plan.prompt,
        isLocked: isLocked,
      );
      await _storyRepository.saveStory(story);
      created += 1;
    }
    if (created > 0) {
      await _scheduleRepository.saveLastPublishedAt(contactId, anchorTime);
    }
    return created;
  }

  // ── plan building ─────────────────────────────────────────────

  List<_StoryImagePlan> _buildPlans({
    required MessengerThread thread,
    required FriendProfile? friendProfile,
    required FriendPersona friendPersona,
    required int count,
  }) {
    final isRomantic = friendProfile?.isRomantic ?? false;
    final chatScene = _matchChatContext(thread.messages);
    final hobbyScenes = _matchHobbyScenes(friendPersona);
    final scenes = _pickDiverseScenes(
      chatScene: chatScene,
      hobbyScenes: hobbyScenes,
      count: count,
      isRomantic: isRomantic,
    );
    final selfieSlots = _buildSelfieSlots(count, isRomantic: isRomantic);
    final lightHints = _pickUniqueHints(_lightHints, count);
    final selfieShotHints = _pickUniqueHints(
      isRomantic ? _romanticSelfieShotHints : _selfieShotHints,
      count,
    );
    final sceneOnlyShotHints = _pickUniqueHints(
      isRomantic ? _romanticSceneOnlyShotHints : _sceneOnlyShotHints,
      count,
    );
    final hobbyProps = _pickHobbyPropHints(friendPersona, friendProfile, count);
    final outfits = _pickOutfits(
      gender: friendProfile?.gender ?? 'male',
      scenes: scenes,
      selfieSlots: selfieSlots,
      isRomantic: isRomantic,
    );
    final plans = <_StoryImagePlan>[];
    for (var i = 0; i < scenes.length; i += 1) {
      final scene = scenes[i];
      final isSelfie = selfieSlots[i];
      final String sceneDescription;
      if (isSelfie) {
        sceneDescription = _buildSelfieDescription(
          scene: scene,
          shotHint: selfieShotHints[i],
          lightHint: lightHints[i],
          hobbyHint: hobbyProps[i],
        );
      } else {
        sceneDescription = _buildSceneOnlyDescription(
          scene: scene,
          shotHint: sceneOnlyShotHints[i],
          lightHint: lightHints[i],
        );
      }
      final prompt = _promptBuilder.buildStoryImagePrompt(
        friendName: thread.contact.name,
        activity: scene.activityRu,
        caption: '',
        profile: friendProfile,
        isSelfie: isSelfie,
        sceneDescriptionEn: sceneDescription,
        outfitEn: isSelfie ? outfits[i] : null,
      );
      plans.add(
        _StoryImagePlan(
          prompt: prompt,
          isSelfie: isSelfie,
        ),
      );
    }
    return plans;
  }

  List<bool> _buildSelfieSlots(int count, {bool isRomantic = false}) {
    if (count <= 1) {
      return isRomantic ? [true] : [_random.nextBool()];
    }
    final int selfieCount;
    if (isRomantic) {
      selfieCount = count > 2 ? (count - 1 + _random.nextInt(2)) : count;
    } else {
      selfieCount = 1 + _random.nextInt(count > 2 ? 2 : 1);
    }
    final slots = List.generate(count, (i) => i < selfieCount);
    slots.shuffle(_random);
    return slots;
  }

  List<String> _pickOutfits({
    required String gender,
    required List<_StoryScene> scenes,
    required List<bool> selfieSlots,
    bool isRomantic = false,
  }) {
    final usedOutfits = <String>{};
    final outfits = <String>[];
    for (var i = 0; i < scenes.length; i++) {
      if (!selfieSlots[i]) {
        outfits.add('');
        continue;
      }
      final pool = _outfitPool(gender, scenes[i].category,
          isRomantic: isRomantic);
      final shuffled = List<String>.of(pool)..shuffle(_random);
      var picked = '';
      for (final outfit in shuffled) {
        if (!usedOutfits.contains(outfit)) {
          picked = outfit;
          break;
        }
      }
      if (picked.isEmpty && shuffled.isNotEmpty) {
        picked = shuffled.first;
      }
      if (picked.isNotEmpty) usedOutfits.add(picked);
      outfits.add(picked);
    }
    return outfits;
  }

  List<String> _outfitPool(
    String gender,
    _SceneCategory category, {
    bool isRomantic = false,
  }) {
    if (isRomantic) {
      final romanticMap =
          gender == 'female' ? _romanticFemaleOutfits : _romanticMaleOutfits;
      return romanticMap[category] ?? const [];
    }
    final map = gender == 'female' ? _femaleOutfits : _maleOutfits;
    return map[category] ?? const [];
  }

  // ── chat context matching ─────────────────────────────────────

  _StoryScene? _matchChatContext(List<MessengerMessage> messages) {
    final recent = _getRecentMessages(messages, _chatContextWindow);
    if (recent.isEmpty) return null;
    final text = _normalize(recent.map((m) => m.text).join(' '));
    if (text.isEmpty) return null;
    final matched = <_StoryScene>[];
    for (final hint in _chatContextHints) {
      if (hint.matches(text)) {
        matched.add(hint.scene);
      }
    }
    if (matched.isEmpty) return null;
    return matched[_random.nextInt(matched.length)];
  }

  List<MessengerMessage> _getRecentMessages(
    List<MessengerMessage> messages,
    Duration window,
  ) {
    if (messages.isEmpty) return const [];
    final cutoff = DateTime.now().subtract(window);
    final recent = <MessengerMessage>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.time.isBefore(cutoff)) break;
      if (msg.text.trim().isNotEmpty) {
        recent.add(msg);
      }
      if (recent.length >= _chatContextMessageLimit) break;
    }
    return recent;
  }

  // ── hobby scene matching ──────────────────────────────────────

  List<_StoryScene> _matchHobbyScenes(FriendPersona persona) {
    final text = _normalize(
      '${persona.hobbies} ${persona.occupation} '
      '${persona.bestMoments} ${persona.about}',
    );
    if (text.isEmpty) return const [];
    final seen = <String>{};
    final matched = <_StoryScene>[];
    for (final hint in _hobbyToSceneHints) {
      if (hint.matches(text) && seen.add(hint.scene.key)) {
        matched.add(hint.scene);
      }
    }
    return matched;
  }

  // ── diverse scene picking (guarantees different categories) ───

  List<_StoryScene> _pickDiverseScenes({
    required _StoryScene? chatScene,
    required List<_StoryScene> hobbyScenes,
    required int count,
    bool isRomantic = false,
  }) {
    final selected = <_StoryScene>[];
    final usedCategories = <_SceneCategory>{};
    final usedKeys = <String>{};

    void tryAdd(_StoryScene scene) {
      if (selected.length >= count) return;
      if (usedKeys.contains(scene.key)) return;
      if (usedCategories.contains(scene.category)) return;
      selected.add(scene);
      usedCategories.add(scene.category);
      usedKeys.add(scene.key);
    }

    if (chatScene != null) {
      tryAdd(chatScene);
    }

    final shuffledHobbies = List<_StoryScene>.of(hobbyScenes)..shuffle(_random);
    for (final scene in shuffledHobbies) {
      tryAdd(scene);
    }

    if (isRomantic) {
      final romanticPool = List<_StoryScene>.of(_romanticPreferredScenes)
        ..shuffle(_random);
      for (final scene in romanticPool) {
        tryAdd(scene);
      }
    }

    final pool = List<_StoryScene>.of(_allScenes)..shuffle(_random);
    for (final scene in pool) {
      tryAdd(scene);
    }

    if (selected.length < count) {
      for (final scene in pool) {
        if (selected.length >= count) break;
        if (usedKeys.contains(scene.key)) continue;
        selected.add(scene);
        usedKeys.add(scene.key);
      }
    }

    return selected;
  }

  // ── scene description builders ────────────────────────────────

  String _buildSelfieDescription({
    required _StoryScene scene,
    required String shotHint,
    required String lightHint,
    required String hobbyHint,
  }) {
    final details = <String>[];
    final shot = shotHint.trim();
    final light = lightHint.trim();
    final hobby = hobbyHint.trim();
    if (shot.isNotEmpty) {
      details.add('$shot while ${scene.sceneEn}');
    } else {
      details.add(scene.sceneEn);
    }
    if (hobby.isNotEmpty) {
      details.add(hobby);
    }
    if (light.isNotEmpty) {
      details.add(light);
    }
    return details.join(', ');
  }

  String _buildSceneOnlyDescription({
    required _StoryScene scene,
    required String shotHint,
    required String lightHint,
  }) {
    final details = <String>[];
    final shot = shotHint.trim();
    final light = lightHint.trim();
    if (shot.isNotEmpty) {
      details.add('$shot photo of ${scene.sceneOnlyEn}');
    } else {
      details.add(scene.sceneOnlyEn);
    }
    if (light.isNotEmpty) {
      details.add(light);
    }
    return details.join(', ');
  }

  // ── utilities ─────────────────────────────────────────────────

  List<String> _pickUniqueHints(List<String> source, int count) {
    if (count <= 0) return const [];
    if (source.isEmpty) {
      return List<String>.filled(count, '');
    }
    final shuffled = List<String>.of(source)..shuffle(_random);
    final picked = <String>[];
    var index = 0;
    while (picked.length < count) {
      if (index >= shuffled.length) {
        shuffled.shuffle(_random);
        index = 0;
      }
      picked.add(shuffled[index]);
      index += 1;
    }
    return picked;
  }

  List<String> _pickHobbyPropHints(
    FriendPersona persona,
    FriendProfile? profile,
    int count,
  ) {
    if (count <= 0) return const [];
    if (profile?.relationshipType != FriendProfile.relationshipFriend) {
      return List<String>.filled(count, '');
    }
    final extracted = _extractHobbyProps(persona);
    if (extracted.isEmpty) {
      return List<String>.filled(count, '');
    }
    extracted.shuffle(_random);
    final picked = <String>[];
    var index = 0;
    while (picked.length < count) {
      if (index >= extracted.length) {
        extracted.shuffle(_random);
        index = 0;
      }
      picked.add(extracted[index]);
      index += 1;
    }
    return picked;
  }

  List<String> _extractHobbyProps(FriendPersona persona) {
    final text = _normalize(
      '${persona.hobbies} ${persona.bestMoments} ${persona.relationshipNotes}',
    );
    if (text.isEmpty) return const [];
    final hints = <String>{};
    for (final hint in _hobbyPropHints) {
      if (hint.matches(text)) {
        hints.add(hint.hintEn);
      }
    }
    return hints.toList();
  }

  Future<FriendPersona> _safeLoadPersona(String contactId) async {
    try {
      return await _personaRepository.load(contactId);
    } catch (_) {
      return const FriendPersona();
    }
  }

  Future<void> _ensureAnchor(String contactId, DateTime anchorTime) async {
    final existing = _scheduleRepository.loadAnchorAt(contactId);
    if (existing != null) return;
    await _scheduleRepository.saveAnchorAt(contactId, anchorTime);
  }

  DateTime _anchorForDay(DateTime anchor, DateTime now) {
    return DateTime(
      now.year,
      now.month,
      now.day,
      anchor.hour,
      anchor.minute,
      anchor.second,
    );
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<AiImageGenerationResult> _generateImage(
    _StoryImagePlan plan,
    File? avatarFile,
  ) async {
    if (plan.isSelfie && avatarFile != null) {
      return _imageService.generateImageFromPromptWithReference(
        prompt: plan.prompt,
        referenceImage: avatarFile,
      );
    }
    return _imageService.generateImageFromPrompt(plan.prompt);
  }

  File? _resolveAvatarFile(FriendProfile? profile) {
    final path = profile?.avatarPath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return file;
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class _StoryImagePlan {
  final String prompt;
  final bool isSelfie;

  const _StoryImagePlan({
    required this.prompt,
    required this.isSelfie,
  });
}

class _StoryScene {
  final String key;
  final _SceneCategory category;
  final String activityRu;
  final String sceneEn;
  final String sceneOnlyEn;

  const _StoryScene({
    required this.key,
    required this.category,
    required this.activityRu,
    required this.sceneEn,
    required this.sceneOnlyEn,
  });
}

class _SceneHint {
  final List<String> keywords;
  final _StoryScene scene;

  const _SceneHint(this.keywords, this.scene);

  bool matches(String text) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }
}

class _HobbyHint {
  final List<String> keywords;
  final String hintEn;

  const _HobbyHint(this.keywords, this.hintEn);

  bool matches(String text) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }
}
