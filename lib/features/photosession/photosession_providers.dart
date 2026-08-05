import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/photosession_backend.dart';
import '../../data/dual_backend_showcase_repository.dart';
import '../../data/dual_backend_user_generation_repository.dart';
import '../../config/ai_proxy_config.dart';
import '../../services/nutrition_analysis/deepseek/deepseek_client.dart';
import '../../services/nutrition_analysis/deepseek/deepseek_config.dart';
import '../../data/appwrite_failover_showcase_repository.dart';
import '../../data/appwrite_failover_user_generation_repository.dart';
import '../../data/appwrite_showcase_repository.dart';
import '../../data/appwrite_user_generation_repository.dart';
import '../../data/local_user_generation_repository.dart';
import '../../data/showcase_repository.dart';
import '../../data/firebase_showcase_repository.dart';
import '../../data/user_generation_repository.dart';
import '../../data/firebase_user_generation_repository.dart';
import '../../services/generation_migration_service.dart';
import '../../models/photo_session_preset.dart';
import '../../models/preset_tag.dart';
import '../../models/photosession_provider.dart';
import '../../services/image_prompt_service.dart';
import '../../services/appwrite_storage_service.dart';
import '../../services/firebase_storage_service.dart';
import '../../services/photosession_dual_upload_service.dart';
import '../../services/photosession_remote_storage.dart';
import '../../services/preset_cache_service.dart';
import '../../services/proxied_image_service.dart';
import '../../services/prompt_safety_service.dart';
import '../../services/prompt_translation_service.dart';
import '../../services/photosession_generation_router.dart';
import '../../services/ai_image_captioning_service.dart';
import '../../services/appwrite_apibost_proxy_service.dart';
import '../../services/apibost_model_catalog.dart';
import '../../services/client_apibost_images_service.dart';
import '../../services/client_apibost_proxy_service.dart';
import '../../services/client_apibost_video_service.dart';
import '../../services/piapi_faceswap_service.dart';
import '../../services/piapi_image_captioning_service.dart';
import '../../services/piapi_upload_service.dart';
import '../../services/reference_face_mask_service.dart';
import '../../services/reference_style_preparation_service.dart';
import '../../services/device_id_service.dart';
import '../../services/preset_reward_service.dart';
import '../../services/preset_tag_service.dart';
import '../../services/instagram_scraper_service.dart';
import '../../services/photo_input_validation_service.dart';
import '../../services/preset_thumbnail_service.dart';

final selectedPresetTagIdProvider =
    StateProvider<String?>((ref) => PresetTag.idAll);

final deviceIdProvider = FutureProvider<String>((ref) async {
  return await DeviceIdService.instance.getDeviceId();
});

const faceSwapPresetId = 'faceswap';

bool isFaceSwapPresetId(String presetId) {
  return presetId == faceSwapPresetId || presetId.startsWith('faceswap_');
}

/// Множество presetId, с которыми текущий пользователь уже делал генерации.
/// Используется в фильтре "Мои" наряду с пользовательскими пресетами.
final usedPresetIdsProvider = StreamProvider<Set<String>>((ref) {
  final deviceIdAsync = ref.watch(deviceIdProvider);
  return deviceIdAsync.when(
    data: (deviceId) {
      final repo = ref.watch(userGenerationRepositoryProvider);
      return repo.watchUsedPresetIds(deviceId);
    },
    loading: () => Stream.value(<String>{}),
    error: (_, __) => Stream.value(<String>{}),
  );
});

final showcaseRepositoryProvider = Provider<ShowcaseRepository>((ref) {
  final cache = ref.watch(presetCacheServiceProvider);
  final appwrite = AppwriteShowcaseRepository(cacheService: cache);
  final firebase = FirebaseShowcaseRepository(cacheService: cache);
  if (clientDualBackendMirrorEnabled()) {
    if (useAppwriteBackend()) {
      return DualBackendShowcaseRepository(
        primary: appwrite,
        secondary: firebase,
      );
    }
    return DualBackendShowcaseRepository(
      primary: firebase,
      secondary: appwrite,
    );
  }
  if (useAppwriteBackend()) {
    return AppwriteFailoverShowcaseRepository(
      appwrite: appwrite,
      firebase: firebase,
    );
  }
  return firebase;
});

final presetTagServiceProvider = Provider<PresetTagService>((ref) {
  return PresetTagService(
    repository: ref.watch(showcaseRepositoryProvider),
    tagExtractor: ref.watch(promptTagExtractorProvider),
  );
});

final userGenerationRepositoryProvider =
    Provider<UserGenerationRepository>((ref) {
  // Новые пользователи и завершившие миграцию → хранение на устройстве
  if (GenerationMigrationService.instance.isLocalMode) {
    return LocalUserGenerationRepository();
  }

  // Старые пользователи — данные ещё на сервере (идёт фоновая миграция)
  final appwrite = AppwriteUserGenerationRepository();
  final firebase = FirebaseUserGenerationRepository();
  if (clientDualBackendMirrorEnabled()) {
    if (useAppwriteBackend()) {
      return DualBackendUserGenerationRepository(
        primary: appwrite,
        secondary: firebase,
      );
    }
    return DualBackendUserGenerationRepository(
      primary: firebase,
      secondary: appwrite,
    );
  }
  if (useAppwriteBackend()) {
    return AppwriteFailoverUserGenerationRepository(
      appwrite: appwrite,
      firebase: firebase,
    );
  }
  return firebase;
});

final presetRewardServiceProvider = Provider<PresetRewardService>((ref) {
  return PresetRewardService();
});

/// Виртуальный пресет для face swap в разделе «Мои».
/// Обложка — результат последней генерации (resultImageUrl).
final faceSwapPresetsProvider =
    FutureProvider<List<PhotoSessionPreset>>((ref) async {
  final usedIds = ref.watch(usedPresetIdsProvider).valueOrNull ?? {};
  final deviceId = await ref.watch(deviceIdProvider.future);
  final presetIds = usedIds.where(isFaceSwapPresetId).toList()
    ..sort((a, b) => b.compareTo(a));
  if (presetIds.isEmpty) return [];

  final repo = ref.read(userGenerationRepositoryProvider);
  final presets = <PhotoSessionPreset>[];
  for (final presetId in presetIds) {
    final generations = await repo.getGenerationsByPreset(
      presetId,
      deviceId: deviceId,
    );
    if (generations.isEmpty) continue;
    final latest = generations.first;
    final oldest = generations.last;
    presets.add(
      PhotoSessionPreset(
        id: presetId,
        title: 'Замена лица',
        prompt: '',
        previewImageUrl: latest.referenceImageUrl ?? latest.resultImageUrl,
        tags: ['custom'],
        createdAt: oldest.createdAt,
      ),
    );
  }
  presets.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return presets;
});

final faceSwapPresetProvider = FutureProvider<PhotoSessionPreset?>((ref) async {
  final presets = await ref.watch(faceSwapPresetsProvider.future);
  return presets.isEmpty ? null : presets.first;
});

final selectedPhotosessionProviderProvider =
    StateProvider<PhotosessionProvider>(
        (ref) => PhotosessionProvider.veoFast);

/// Единая фабрика ApiBost-сервиса: при включённом [clientSideApiBostEnabled]
/// генерация идёт напрямую по relay (Yandex → NL) с клиентским резервом
/// кредитов; иначе — через серверную функцию `apibost-proxy` (старая схема).
PhotosessionGenerationService _apiBostService({
  required String model,
  required double temperature,
}) {
  if (!clientSideApiBostEnabled()) {
    return AppwriteApiBostProxyService(model: model, temperature: temperature);
  }
  switch (ApiBostModelCatalog.transportFor(model)) {
    case ApiBostTransport.videoChatCompletions:
      return ClientApiBostVideoService(model: model);
    case ApiBostTransport.openAiImages:
    case ApiBostTransport.openAiChatCompletions:
      return ClientApiBostImagesService(model: model, temperature: temperature);
    case ApiBostTransport.geminiGenerateContent:
      return ClientApiBostProxyService(model: model, temperature: temperature);
  }
}

/// Сервис генерации для выбранной модели.
///
/// Раньше на каждую модель существовал отдельный провайдер, и добавление модели
/// требовало правок и здесь, и в switch-е оркестратора. Family убирает это
/// дублирование: маршрутизацию целиком определяет [ApiBostModelCatalog].
final photosessionGenerationServiceProvider =
    Provider.family<PhotosessionGenerationService, PhotosessionProvider>(
        (ref, provider) {
  return _apiBostService(
    model: provider.apiBostModel,
    temperature: 0.7,
  );
});

DeepSeekClient _makeDeepSeekClient({
  bool enableCaching = false,
  bool fastMode = false,
}) {
  final proxyBaseUrl = AiProxyConfig.deepSeekBaseUrl();
  final proxyToken = AiProxyConfig.token;
  if (proxyBaseUrl != null && proxyToken != null) {
    return DeepSeekClient(
      config: DeepSeekConfig(
        apiKey: '',
        baseUrl: proxyBaseUrl,
        proxyToken: proxyToken,
        fastMode: fastMode,
      ),
      enableCaching: enableCaching,
    );
  }
  return DeepSeekClient.fromEnvironment(
    enableCaching: enableCaching,
    fastMode: fastMode,
  );
}

final _deepSeekImagePromptServiceProvider =
    Provider<DeepSeekImagePromptService>((ref) {
  return DeepSeekImagePromptService(client: _makeDeepSeekClient());
});

/// Промпт-инженер: короткая идея пользователя → детальный промпт.
final imagePromptServiceProvider = Provider<ImagePromptService>((ref) {
  return ref.watch(_deepSeekImagePromptServiceProvider);
});

/// Смягчение формулировок промпта под фильтр безопасности видеомодели.
final promptSafetyServiceProvider = Provider<PromptSafetyService>((ref) {
  return DeepSeekPromptSafetyService(
    client: _makeDeepSeekClient(fastMode: true),
  );
});

/// Автоматическая разметка сгенерированных изображений по категориям.
final promptTagExtractorProvider = Provider<PromptTagExtractor>((ref) {
  return ref.watch(_deepSeekImagePromptServiceProvider);
});

final firebaseStorageServiceProvider = Provider<FirebaseStorageService>((ref) {
  return FirebaseStorageService();
});

final photosessionDualUploadServiceProvider =
    Provider<PhotosessionDualUploadService?>((ref) {
  logPhotosessionBackendConfigOnce();
  if (!clientDualBackendMirrorEnabled()) {
    debugPrint(
      'PhotosessionDualUploadService: null — двойная загрузка в AW+Firebase Storage отключена',
    );
    return null;
  }
  debugPrint(
    'PhotosessionDualUploadService: активен — результат/preview грузятся в оба Storage',
  );
  return PhotosessionDualUploadService(
    appwrite: AppwriteStorageService(),
    firebase: ref.read(firebaseStorageServiceProvider),
  );
});

final photosessionRemoteStorageProvider =
    Provider<PhotosessionRemoteStorage>((ref) {
  if (useAppwriteBackend()) {
    return AppwriteStorageService();
  }
  return FirebaseStorageService();
});

final presetCacheServiceProvider = Provider<PresetCacheService>((ref) {
  return PresetCacheService();
});

final proxiedImageServiceProvider = Provider<ProxiedImageService>((ref) {
  return ProxiedImageService();
});

final promptTranslationServiceProvider =
    Provider<PromptTranslationService>((ref) {
  return PromptTranslationService(client: _makeDeepSeekClient(fastMode: true));
});

final piApiFaceswapServiceProvider = Provider<PiApiFaceswapService>((ref) {
  return PiApiFaceswapService(taskUrl: AiProxyConfig.piApiTaskUrl());
});

final piApiUploadServiceProvider = Provider<PiApiUploadService>((ref) {
  return PiApiUploadService(uploadUrl: AiProxyConfig.piApiUploadUrl());
});

final photosessionImageCaptioningServiceProvider =
    Provider<AiImageCaptioningService>((ref) {
  return AiImageCaptioningRouter(
    services: [
      PiApiImageCaptioningService(
        taskUrl: AiProxyConfig.piApiTaskUrl(),
        uploadUrl: AiProxyConfig.piApiUploadUrl(),
      ),
    ],
  );
});

final referenceFaceMaskServiceProvider =
    Provider<ReferenceFaceMaskService>((ref) {
  return MlKitReferenceFaceMaskService(
    fallback: HeuristicReferenceFaceMaskService(),
  );
});

final referenceStylePreparationServiceProvider =
    Provider<ReferenceStylePreparationService>((ref) {
  return AiReferenceStylePreparationService(
    captioningService: ref.watch(photosessionImageCaptioningServiceProvider),
    faceMaskService: ref.watch(referenceFaceMaskServiceProvider),
    client: _makeDeepSeekClient(fastMode: true),
  );
});

final instagramScraperServiceProvider =
    Provider<InstagramScraperService>((ref) {
  return InstagramScraperService();
});

final photoInputValidationServiceProvider =
    Provider<PhotoInputValidationService>((
  ref,
) {
  return MlKitPhotoInputValidationService();
});

final postPhotosessionReviewHomeTriggerProvider =
    StateProvider<bool>((ref) => false);

final presetThumbnailServiceProvider = Provider<PresetThumbnailService>((ref) {
  return PresetThumbnailService();
});
