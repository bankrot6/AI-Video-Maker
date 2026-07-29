import '../models/photo_session_preset.dart';

abstract class ShowcaseRepository {
  Future<List<PhotoSessionPreset>> getPresets({int limit = 0});

  Future<List<PhotoSessionPreset>> fetchPresetsForUiBootstrap({int limit = 0});

  /// Постраничная потоковая загрузка. Каждый emit — накопленный отсортированный
  /// список (растёт по мере загрузки страниц). Первый emit — первая страница.
  Stream<List<PhotoSessionPreset>> streamPresetsBootstrap() async* {
    yield await fetchPresetsForUiBootstrap();
  }

  Future<PhotoSessionPreset?> getPresetById(String id);
  Future<PhotoSessionPreset> createPreset({
    required String prompt,
    required String previewImageUrl,
    String? title,
    List<String>? tags,
    String? imageStyle,
    String? ownerId,
    String? clientAssignedPresetId,
    String? pairedPreviewImageUrl,
  });

  Stream<List<PhotoSessionPreset>> watchPresets({int limit = 0});

  Future<void> toggleLike(String presetId, String deviceId);

  Future<void> updateTags(String presetId, List<String> tags);

  Future<void> makePublic(String presetId);

  Future<void> makePrivate(String presetId);

  Future<void> deletePreset(String presetId, {required String ownerDeviceId});
}
