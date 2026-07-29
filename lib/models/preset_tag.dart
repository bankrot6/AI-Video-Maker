import 'package:flutter/material.dart';

import 'image_generation_request.dart';
import 'photo_session_preset.dart';

class PresetTag {
  const PresetTag({
    required this.id,
    required this.name,
    required this.icon,
  });

  final String id;
  final String name;
  final IconData icon;

  static const String idAll = 'all';
  static const String idTrending = 'trending';

  static const String idCustom = 'custom';

  static const String idLiked = 'liked';

  static const PresetTag likedFeedTag = PresetTag(
    id: idLiked,
    name: 'Лайки',
    icon: Icons.favorite,
  );

  /// Стили изображений для фильтрации ленты (как при создании пресета).
  static List<PresetTag> get styles => ImageStyle.values
      .map(
        (style) => PresetTag(
          id: style.id,
          name: style.label,
          icon: style.icon,
        ),
      )
      .toList(growable: false);

  /// Тематические категории изображений (для AI-разметки при публикации).
  static const List<PresetTag> categories = [
    PresetTag(id: 'люди', name: 'Люди', icon: Icons.people_alt_rounded),
    PresetTag(id: 'портрет', name: 'Портреты', icon: Icons.face_rounded),
    PresetTag(id: 'животные', name: 'Животные', icon: Icons.pets_rounded),
    PresetTag(id: 'природа', name: 'Природа', icon: Icons.terrain_rounded),
    PresetTag(id: 'город', name: 'Город', icon: Icons.location_city_rounded),
    PresetTag(id: 'космос', name: 'Космос', icon: Icons.rocket_launch_rounded),
    PresetTag(id: 'фэнтези', name: 'Фэнтези', icon: Icons.auto_awesome_rounded),
    PresetTag(id: 'аниме', name: 'Аниме', icon: Icons.animation_rounded),
    PresetTag(id: 'арт', name: 'Арт', icon: Icons.brush_rounded),
    PresetTag(id: '3d', name: '3D', icon: Icons.view_in_ar_rounded),
    PresetTag(id: 'еда', name: 'Еда', icon: Icons.restaurant_rounded),
    PresetTag(id: 'автомобили', name: 'Машины', icon: Icons.directions_car_rounded),
    PresetTag(id: 'техника', name: 'Техника', icon: Icons.memory_rounded),
    PresetTag(id: 'интерьер', name: 'Интерьеры', icon: Icons.chair_rounded),
    PresetTag(id: 'мода', name: 'Мода', icon: Icons.checkroom_rounded),
    PresetTag(id: 'спорт', name: 'Спорт', icon: Icons.sports_soccer_rounded),
    PresetTag(id: 'бизнес', name: 'Бизнес', icon: Icons.business_center_rounded),
    PresetTag(id: 'абстракция', name: 'Абстракция', icon: Icons.blur_on_rounded),
    PresetTag(id: 'праздник', name: 'Праздники', icon: Icons.celebration_rounded),
    PresetTag(id: 'цветы', name: 'Цветы', icon: Icons.local_florist_rounded),
    PresetTag(id: 'ретро', name: 'Ретро', icon: Icons.camera_roll_rounded),
    PresetTag(id: 'минимализм', name: 'Минимализм', icon: Icons.crop_square_rounded),
    PresetTag(id: 'роскошь', name: 'Роскошь', icon: Icons.diamond_rounded),
    PresetTag(id: 'логотип', name: 'Логотипы', icon: Icons.auto_awesome_motion_rounded),
  ];

  /// Словарь категорий для автоматической разметки сгенерированных картинок.
  static List<String> get generationTagIds =>
      categories.map((tag) => tag.id).toList(growable: false);

  static List<PresetTag> get all => [
    const PresetTag(id: idAll, name: 'Все', icon: Icons.grid_view_rounded),
    const PresetTag(
        id: idTrending, name: 'В тренде', icon: Icons.trending_up_rounded),
    const PresetTag(id: idCustom, name: 'Мои', icon: Icons.person_rounded),
    ...styles,
  ];

  static PresetTag? byId(String id) {
    if (id.isEmpty || id == idAll) return null;
    if (id == idLiked) return likedFeedTag;
    for (final tag in all) {
      if (tag.id == id) return tag;
    }
    return null;
  }

  static bool isStyleId(String id) =>
      ImageStyle.values.any((style) => style.id == id);

  static bool userHasMyFeedPresets({
    required List<PhotoSessionPreset> presets,
    required String? deviceId,
    required Set<String> usedPresetIds,
  }) {
    if (deviceId == null) return false;
    return presets.any((p) {
      if (p.hasTag('custom')) {
        return p.ownerId == null || p.ownerId == deviceId;
      }
      return usedPresetIds.contains(p.id);
    });
  }

  static List<PresetTag> chipsForFeed({
    required List<PhotoSessionPreset> presets,
    required String? deviceId,
    required Set<String> usedPresetIds,
  }) {
    final out = List<PresetTag>.from(all);
    if (!userHasMyFeedPresets(
      presets: presets,
      deviceId: deviceId,
      usedPresetIds: usedPresetIds,
    )) {
      out.removeWhere((t) => t.id == idCustom);
    }

    final hasLiked =
        deviceId != null && presets.any((p) => p.isLikedBy(deviceId));
    if (!hasLiked) return out;

    final afterCustom = out.indexWhere((t) => t.id == idCustom);
    final anchor = afterCustom >= 0
        ? afterCustom
        : out.indexWhere((t) => t.id == idTrending);
    if (anchor < 0) {
      out.add(likedFeedTag);
      return out;
    }
    out.insert(anchor + 1, likedFeedTag);
    return out;
  }
}
