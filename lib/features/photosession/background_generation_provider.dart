import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../config/photosession_backend.dart';
import '../../config/credit_config.dart';
import '../../services/generation_migration_service.dart';
import '../../services/local_generation_storage.dart';
import '../../services/client_apibost_video_service.dart';
import '../../services/photosession_dual_upload_service.dart';
import '../../models/generation_task.dart';
import '../../models/photo_session_preset.dart';
import '../../models/photosession_provider.dart';
import '../../models/preset_tag.dart';
import '../../providers/credit_providers.dart';
import '../../services/localization/app_localization_service.dart';
import '../../services/apibost_model_catalog.dart';
import '../../services/appwrite_apibost_proxy_service.dart';
import '../../services/generated_media.dart';
import '../../services/video_poster_service.dart';
import '../../services/photosession_generation_router.dart';
import '../../services/piapi_upload_service.dart';
import '../../services/post_photosession_review_service.dart';
import '../../services/credit_service.dart';
import '../../services/pending_credit_reservation_store.dart';
import '../subscription/subscription_providers.dart';
import 'photosession_providers.dart';

/// Данные для публикации сгенерированного изображения в галерее.
class GeneratedImageData {
  const GeneratedImageData({
    required this.prompt,
    required this.title,
    this.imageStyle,
  });
  final String prompt;
  final String title;
  final String? imageStyle;
}

class GenerationStartResult {
  const GenerationStartResult._({
    this.taskId,
    this.reason,
    this.remainingCredits,
  });

  const GenerationStartResult.success(String taskId) : this._(taskId: taskId);

  const GenerationStartResult.failure({
    required String reason,
    int? remainingCredits,
  }) : this._(
          reason: reason,
          remainingCredits: remainingCredits,
        );

  final String? taskId;
  final String? reason;
  final int? remainingCredits;

  bool get isSuccess => taskId != null;
}

final backgroundGenerationProvider =
    StateNotifierProvider<BackgroundGenerationNotifier, List<GenerationTask>>(
        (ref) {
  return BackgroundGenerationNotifier(ref);
});

class BackgroundGenerationNotifier extends StateNotifier<List<GenerationTask>> {
  BackgroundGenerationNotifier(this._ref) : super([]) {
    unawaited(_refundOrphanReservations());
  }

  final Ref _ref;
  final Set<String> _observedTaskIds = {};
  final Map<String, int> _autoRetryAttempts = {};
  final Map<String, GeneratedImageData> _generatedImageData = {};
  final Map<String, int> _creditCostOverrides = {};
  final Map<String, CreditReservation> _reservations = {};
  final PendingCreditReservationStore _reservationStore =
      PendingCreditReservationStore();

  /// Промпт после обработки санитайзером: держим отдельно от задачи, чтобы
  /// повторные попытки не гоняли LLM заново и уходили с тем же текстом.
  final Map<String, String> _safePrompts = {};
  final Set<String> _relaxedTaskIds = {};

  static const int _maxAutoRetries = 2;

  static bool _isHttpImageUrl(String value) {
    final v = value.trim();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  static String? _httpUrlOrNull(String? value) {
    if (value == null || value.isEmpty) return null;
    return _isHttpImageUrl(value) ? value.trim() : null;
  }

  bool _isRetryableError(String? errorMessage) {
    if (errorMessage == null) return true;
    final lower = errorMessage.toLowerCase();
    return !(lower.contains('кредит') ||
        lower.contains('требуется обновление приложения') ||
        lower.contains('requires app update') ||
        lower.contains('server balance check') ||
        lower.contains('余额不足') ||
        lower.contains('剩余额度') ||
        lower.contains('额度不足') ||
        lower.contains('insufficient balance') ||
        lower.contains('remaining balance') ||
        lower.contains('remaining credit') ||
        lower.contains('quota is not enough') ||
        lower.contains('слишком длинное') ||
        lower.contains('не настроен') ||
        lower.contains('больше не доступно') ||
        _isBlockedContentError(errorMessage) ||
        lower.contains('файл пользователя не найден') ||
        lower.contains('не найдено референсное изображение') ||
        lower.contains('пресет') ||
        lower.contains('историю'));
  }

  Future<bool> _tryAutoRetry(
    String taskId,
    String? errorMessage,
    Future<void> Function(String) runner,
  ) async {
    if (!_isRetryableError(errorMessage)) return false;
    final attempts = _autoRetryAttempts[taskId] ?? 0;
    if (attempts >= _maxAutoRetries) {
      _autoRetryAttempts.remove(taskId);
      return false;
    }
    _autoRetryAttempts[taskId] = attempts + 1;
    final attemptNumber = attempts + 1;
    _setTaskState(
      taskId,
      status: GenerationStatus.generating,
      statusMessage: 'Повторная попытка $attemptNumber из $_maxAutoRetries...',
    );
    await Future.delayed(Duration(seconds: 3 * attemptNumber));
    if (_findTask(taskId) == null) return true;
    await runner(taskId);
    return true;
  }

  void markObserved(String taskId) => _observedTaskIds.add(taskId);

  void markUnobserved(String taskId) {
    _observedTaskIds.remove(taskId);
    Future.microtask(() {
      if (!mounted) return;
      final task = _findTask(taskId);
      if (task != null && task.isCompleted) {
        removeTask(taskId);
      }
    });
  }

  bool isObserved(String taskId) => _observedTaskIds.contains(taskId);

  Future<GenerationStartResult> startGeneration({
    required PhotoSessionPreset preset,
    File? userPhoto,
    required String prompt,
    PhotosessionProvider provider = PhotosessionProvider.veoFast,
    GenerationTaskType taskType = GenerationTaskType.preset,
    GeneratedImageData? generatedImageData,
    String aspectRatio = '3:4',
    File? referenceImage,
  }) async {
    final taskId = '${preset.id}_${DateTime.now().millisecondsSinceEpoch}';

    final startResult = await _prepareCreditsForTask(
      taskId: taskId,
      provider: provider,
      taskType: taskType,
      presetId: preset.id,
      userPhotoPath: userPhoto?.path ?? '',
    );
    if (!startResult.isSuccess) {
      return startResult;
    }

    if (taskType == GenerationTaskType.userImage &&
        generatedImageData != null) {
      _generatedImageData[taskId] = generatedImageData;
    }

    state = [
      GenerationTask(
        id: taskId,
        presetId: preset.id,
        presetTitle: preset.title,
        presetPreviewUrl: preset.displayImageUrl,
        status: GenerationStatus.generating,
        statusMessage: 'Генерируем видео (1-3 минуты)...',
        userPhotoPath: userPhoto?.path ?? '',
        prompt: prompt,
        createdAt: DateTime.now(),
        provider: provider,
        taskType: taskType,
        aspectRatio: aspectRatio,
        referenceImageUrl: referenceImage?.path,
      ),
      ...state,
    ];

    _runGeneration(taskId);
    return GenerationStartResult.success(taskId);
  }

  Future<GenerationStartResult> startFaceSwapGeneration({
    File? referencePhoto,
    String? referenceImageUrl,
    required File userPhoto,
    required FaceSwapMode faceSwapMode,
    PhotosessionProvider provider = PhotosessionProvider.veoPro,
    int? creditCostOverride,
    String? presetId,
  }) async {
    final trimmedReferenceImageUrl = referenceImageUrl?.trim();
    if (referencePhoto == null &&
        (trimmedReferenceImageUrl == null ||
            trimmedReferenceImageUrl.isEmpty)) {
      throw ArgumentError(
        'Нужен referencePhoto или referenceImageUrl',
      );
    }

    final taskId = 'faceswap_${DateTime.now().millisecondsSinceEpoch}';
    final requestedPresetId = presetId?.trim();
    final taskPresetId =
        requestedPresetId != null && requestedPresetId.isNotEmpty
            ? requestedPresetId
            : taskId;
    if (creditCostOverride != null) {
      _creditCostOverrides[taskId] = creditCostOverride;
    }

    final startResult = await _prepareCreditsForTask(
      taskId: taskId,
      provider: provider,
      taskType: GenerationTaskType.faceSwap,
      faceSwapMode: faceSwapMode,
      creditCostOverride: creditCostOverride,
    );
    if (!startResult.isSuccess) {
      return startResult;
    }

    final refUrl = referencePhoto != null
        ? referencePhoto.path
        : trimmedReferenceImageUrl!;

    state = [
      GenerationTask(
        id: taskId,
        presetId: taskPresetId,
        presetTitle: 'Замена лица',
        presetPreviewUrl: refUrl,
        status: GenerationStatus.generating,
        statusMessage: 'Генерируем видео (1-3 минуты)...',
        userPhotoPath: userPhoto.path,
        prompt: '',
        createdAt: DateTime.now(),
        provider: provider,
        taskType: GenerationTaskType.faceSwap,
        referenceImageUrl: refUrl,
        faceSwapMode: faceSwapMode,
      ),
      ...state,
    ];

    _runFaceSwapGeneration(taskId);
    return GenerationStartResult.success(taskId);
  }

  Future<void> retryTask(String taskId) async {
    final task = _findTask(taskId);
    if (task == null) return;
    _autoRetryAttempts.remove(taskId);
    _relaxedTaskIds.remove(taskId);

    if (task.userPhotoPath.isNotEmpty &&
        !File(task.userPhotoPath).existsSync()) {
      _setTaskState(
        taskId,
        status: GenerationStatus.error,
        statusMessage: '',
        errorMessage:
            'Фото больше не доступно. Выберите новое фото и попробуйте снова.',
      );
      return;
    }

    if (task.taskType == GenerationTaskType.faceSwap &&
        task.referenceImageUrl != null &&
        !task.referenceImageUrl!.startsWith('http') &&
        !File(task.referenceImageUrl!).existsSync()) {
      _setTaskState(
        taskId,
        status: GenerationStatus.error,
        statusMessage: '',
        errorMessage:
            'Референсное фото больше не доступно. Выберите новое фото и попробуйте снова.',
      );
      return;
    }

    final creditCostOverride = _creditCostOverrides[taskId];
    final canProceed = creditCostOverride == null
        ? await _ref
            .read(creditUsageNotifierProvider.notifier)
            .canGenerate(task.provider.creditTier)
        : (await _ref
                .read(creditServiceProvider)
                .checkCredits(creditCostOverride))
            .allowed;
    if (!canProceed) {
      _setTaskState(
        taskId,
        status: GenerationStatus.error,
        statusMessage: '',
        errorMessage: 'Недостаточно кредитов для повторной генерации.',
      );
      return;
    }

    _setTaskState(
      taskId,
      status: GenerationStatus.generating,
      statusMessage: 'Генерируем видео (1-3 минуты)...',
    );

    if (task.taskType == GenerationTaskType.faceSwap) {
      _runFaceSwapGeneration(taskId);
    } else {
      _runGeneration(taskId);
    }
  }

  void removeTask(String taskId) {
    state = state.where((t) => t.id != taskId).toList();
    _autoRetryAttempts.remove(taskId);
    _creditCostOverrides.remove(taskId);
    _forgetReservation(taskId);
    _safePrompts.remove(taskId);
    _relaxedTaskIds.remove(taskId);
  }

  GenerationTask? _findTask(String taskId) {
    for (final task in state) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  /// Списывает ли кредиты сам бэкенд-сервис (через apibost-proxy на сервере).
  ///
  /// Важно: enum [PhotosessionProvider.isApiBost] описывает только явные
  /// apibost*-значения, но фактически piapi/googleFlash/flash тоже маршрутятся
  /// в [AppwriteApiBostProxyService] (см. photosession_providers.dart), который
  /// списывает кредиты на сервере. Поэтому решение о резервировании кредитов
  /// нужно принимать по реальному сервису, а не по enum — иначе для этих
  /// провайдеров кредиты спишутся дважды (verify-trial + apibost-proxy).
  ///
  /// Не self-charging (нужен клиентский reserve через verify-trial):
  ///  - faceswap в режиме [FaceSwapMode.exact] → PiAPI faceswap.
  bool _serverChargesCredits({
    required GenerationTaskType taskType,
    FaceSwapMode? faceSwapMode,
  }) {
    // При клиентской генерации ApiBost серверная функция apibost-proxy не
    // вызывается, поэтому кредиты не списываются сервером — их резервирует
    // клиент через verify-trial (reserve_credits). Значит все провайдеры идут
    // по ветке клиентского резерва (exact-faceswap и так был там).
    if (clientSideApiBostEnabled()) return false;
    if (taskType == GenerationTaskType.faceSwap) {
      // Style-transfer faceswap идёт через ApiBost, exact — через PiAPI faceswap.
      return faceSwapMode != FaceSwapMode.exact;
    }
    return true;
  }

  Future<GenerationStartResult> _prepareCreditsForTask({
    required String taskId,
    required PhotosessionProvider provider,
    required GenerationTaskType taskType,
    FaceSwapMode? faceSwapMode,
    int? creditCostOverride,
    String? presetId,
    String? userPhotoPath,
  }) async {
    final creditNotifier = _ref.read(creditUsageNotifierProvider.notifier);

    if (_serverChargesCredits(
      taskType: taskType,
      faceSwapMode: faceSwapMode,
    )) {
      final usage = await creditNotifier.refreshFromServer();
      final hasPaidSubscription =
          _ref.read(subscriptionProvider).valueOrNull?.isPaidUser ?? false;
      if (!CreditCost.isTierAccessible(
        provider.creditTier,
        hasPaidSubscription: hasPaidSubscription,
      )) {
        return GenerationStartResult.failure(
          reason: 'tier_locked',
          remainingCredits: usage.remainingCredits,
        );
      }
      final requiredCredits =
          creditCostOverride ?? CreditCost.forGeneration(provider.creditTier);
      if (!usage.hasEnoughCredits(requiredCredits)) {
        return GenerationStartResult.failure(
          reason: 'insufficient_credits',
          remainingCredits: usage.remainingCredits,
        );
      }
      return const GenerationStartResult.success('');
    }

    final reservation = creditCostOverride == null
        ? await creditNotifier.reserveGenerationCredits(provider.creditTier)
        : await creditNotifier.reserveCredits(
            creditCostOverride,
            countAsFreeGeneration: false,
          );

    if (!reservation.success || reservation.reservation == null) {
      return GenerationStartResult.failure(
        reason: reservation.reason,
        remainingCredits: reservation.remainingCredits,
      );
    }

    _reservations[taskId] = reservation.reservation!;
    await _reservationStore.add(
      PendingCreditReservation(
        taskId: taskId,
        reservation: reservation.reservation!,
        providerName: provider.name,
        presetId: presetId,
        userPhotoPath: userPhotoPath,
      ),
    );
    return const GenerationStartResult.success('');
  }

  /// Снимает резерв без возврата: запрос к модели уже оплачен.
  void _forgetReservation(String taskId) {
    _reservations.remove(taskId);
    unawaited(_reservationStore.remove(taskId));
  }

  /// Процесс мог умереть между списанием кредитов и результатом (обрыв связи на
  /// мобильной сети, выгрузка приложения из памяти). Задачи живут только в
  /// памяти, поэтому всё, что осталось на диске к моменту запуска, — потерянные
  /// генерации.
  ///
  /// Видео за это время дорендерилось и уже оплачено провайдеру, поэтому сначала
  /// делается попытка забрать результат в историю пользователя. Кредиты
  /// возвращаются только если результата действительно нет: задача провалилась,
  /// ссылка истекла (у ApiBost это примерно два часа) или контур вообще не умеет
  /// возвращаться к задачам.
  Future<void> _refundOrphanReservations() async {
    final orphans = await _reservationStore.drain();
    if (orphans.isEmpty) return;
    final creditNotifier = _ref.read(creditUsageNotifierProvider.notifier);
    for (final orphan in orphans) {
      if (await _recoverOrphanResult(orphan)) continue;
      debugPrint('🎬 BackgroundGen: возврат потерянного резерва '
          '${orphan.reservation.amount} кредитов (${orphan.taskId})');
      await creditNotifier.rollbackReservation(orphan.reservation);
    }
  }

  /// Догружает оплаченное видео потерянной генерации и пишет его в историю.
  /// `true` — результат доставлен, кредиты возвращать не нужно.
  Future<bool> _recoverOrphanResult(PendingCreditReservation orphan) async {
    final providerTaskId = orphan.providerTaskId;
    final provider = _providerByName(orphan.providerName);
    if (providerTaskId == null || provider == null) return false;

    try {
      final service = _ref.read(photosessionGenerationServiceProvider(provider));
      if (service is! ClientApiBostVideoService) return false;

      final result = await service.resumeTask(providerTaskId);
      if (!result.isSuccess || result.imageUrl == null) {
        debugPrint('🎬 BackgroundGen: задача $providerTaskId не догрузилась: '
            '${result.errorMessage}');
        return false;
      }

      final (resultImageUrl, dualResultUrls) =
          await _persistResultImageWithDual(result.imageUrl!);
      final deviceId = await _ref.read(deviceIdProvider.future);
      await _ref.read(userGenerationRepositoryProvider).createGeneration(
            presetId: orphan.presetId ?? '',
            userImageUrl: orphan.userPhotoPath ?? '',
            resultImageUrl: resultImageUrl,
            deviceId: deviceId,
            clientAssignedDocumentId: clientDualBackendMirrorEnabled()
                ? 'gen_${DateTime.now().millisecondsSinceEpoch}'
                : null,
            pairedUserImageUrl: null,
            pairedResultImageUrl:
                dualResultUrls?.pairedHttpRelativeTo(resultImageUrl),
            pairedReferenceImageUrl: null,
          );
      debugPrint('🎬 BackgroundGen: оплаченное видео восстановлено в историю: '
          '$resultImageUrl');
      return true;
    } catch (e) {
      debugPrint('🎬 BackgroundGen: восстановление $providerTaskId не удалось: $e');
      return false;
    }
  }

  PhotosessionProvider? _providerByName(String? name) {
    if (name == null) return null;
    for (final provider in PhotosessionProvider.values) {
      if (provider.name == name) return provider;
    }
    return null;
  }

  /// Контент заблокирован модерацией: запрос к ApiBost выполнен (и оплачен),
  /// поэтому кредиты НЕ возвращаются — это повторяет анти-абьюз логику серверной
  /// функции apibost-proxy и не даёт фармить запрещённый контент бесплатно.
  /// Проверка идёт по корням слов: формулировки сообщений меняются по падежам
  /// («политикой безопасности», «правилам безопасности», «заблокирован»).
  bool _isBlockedContentError(String? errorMessage) {
    if (errorMessage == null) return false;
    final lower = errorMessage.toLowerCase();
    return lower.contains('безопасност') ||
        lower.contains('заблокирова') ||
        lower.contains('отклонила промпт') ||
        lower.contains('prohibited') ||
        lower.contains('rai_policy');
  }

  Future<void> _rollbackReservationIfNeeded(
    String taskId, {
    String? errorMessage,
  }) async {
    if (_isBlockedContentError(errorMessage)) {
      // Списание оставляем, лишь убираем локальный хэндл резерва.
      _forgetReservation(taskId);
      return;
    }
    final reservation = _reservations.remove(taskId);
    await _reservationStore.remove(taskId);
    if (reservation == null) return;
    await _ref
        .read(creditUsageNotifierProvider.notifier)
        .rollbackReservation(reservation);
  }

  Future<void> _refreshCreditsFromServer() async {
    await _ref.read(creditUsageNotifierProvider.notifier).refreshFromServer();
  }

  /// Фильтр Responsible AI у видеомодели отклоняет безобидные сцены из-за
  /// формулировок (человек без указанного возраста, ракурс «вид сзади»),
  /// поэтому текст нормализуется до первой отправки, а не только после отказа.
  Future<String> _safePrompt(String taskId, String prompt) async {
    final cached = _safePrompts[taskId];
    if (cached != null) return cached;

    String? normalized;
    try {
      normalized = await _ref.read(promptSafetyServiceProvider).normalize(
            prompt,
            maxLength: ApiBostModelCatalog.maxVideoPromptTextLength,
          );
    } catch (e) {
      debugPrint('🎬 BackgroundGen: нормализация промпта не удалась: $e');
    }
    final result = normalized ?? prompt;
    _safePrompts[taskId] = result;
    return result;
  }

  /// Повторять отклонённый текст без изменений бессмысленно, но переписанный
  /// консервативнее — как правило проходит. Даём ровно одну такую попытку.
  Future<bool> _tryRelaxAndRetry(String taskId, String? errorMessage) async {
    if (!_isBlockedContentError(errorMessage)) return false;
    if (!_relaxedTaskIds.add(taskId)) return false;

    final current = _safePrompts[taskId] ?? _findTask(taskId)?.prompt;
    if (current == null || current.isEmpty) return false;

    _setTaskState(
      taskId,
      status: GenerationStatus.generating,
      statusMessage: 'Корректируем описание под правила модели...',
    );

    String? relaxed;
    try {
      relaxed = await _ref.read(promptSafetyServiceProvider).relax(
            current,
            maxLength: ApiBostModelCatalog.maxVideoPromptTextLength,
          );
    } catch (e) {
      debugPrint('🎬 BackgroundGen: смягчение промпта не удалось: $e');
    }
    if (relaxed == null || relaxed.isEmpty || _findTask(taskId) == null) {
      return false;
    }

    _safePrompts[taskId] = relaxed;
    await _runGeneration(taskId);
    return true;
  }

  Future<void> _runGeneration(String taskId) async {
    final task = _findTask(taskId);
    if (task == null) return;

    try {
      _setTaskState(
        taskId,
        status: GenerationStatus.generating,
        statusMessage: 'Генерируем видео (1-3 минуты)...',
      );

      var service =
          _ref.read(photosessionGenerationServiceProvider(task.provider));
      if (service is ClientApiBostVideoService) {
        service = service.withTaskListener(
          (providerTaskId) => unawaited(
            _reservationStore.attachProviderTask(taskId, providerTaskId),
          ),
        );
      }

      debugPrint(
        '🎬 BackgroundGen: taskId=$taskId '
        'запрошен=${task.provider.name} '
        'сервис=${service.runtimeType}',
      );

      final referenceImageUrl = task.taskType == GenerationTaskType.userImage
          ? task.referenceImageUrl
          : null;

      final prompt = await _safePrompt(taskId, task.prompt);
      if (_findTask(taskId) == null) return;

      final PhotosessionGenerationResult result;
      if (referenceImageUrl != null && referenceImageUrl.isNotEmpty) {
        debugPrint('🎬 BackgroundGen: генерация по референсу пользователя');
        result = service is ReferenceImageGenerationService
            ? await (service as ReferenceImageGenerationService)
                .generateFromReference(
                referenceImageUrl: referenceImageUrl,
                prompt: prompt,
                resolution: '2K',
                aspectRatio: task.aspectRatio,
              )
            : await service.generateWithFace(
                userImageUrl: referenceImageUrl,
                scenePrompt: prompt,
                resolution: '2K',
                aspectRatio: task.aspectRatio,
              );
      } else if (task.userPhotoPath.isEmpty) {
        debugPrint('🎬 BackgroundGen: text-to-image (без фото пользователя)');
        result = await service.generateImage(
          prompt: prompt,
          resolution: '2K',
          aspectRatio: task.aspectRatio,
        );
      } else {
        result = await service.generateWithFace(
          userImageUrl: task.userPhotoPath,
          scenePrompt: prompt,
          resolution: '2K',
          aspectRatio: task.aspectRatio,
        );
      }

      if (_findTask(taskId) == null) return;

      if (!result.isSuccess || result.imageUrl == null) {
        final errMsg = result.errorMessage ?? 'Не удалось создать видео.';

        final retried = await _tryRelaxAndRetry(taskId, errMsg) ||
            await _tryAutoRetry(taskId, errMsg, _runGeneration);
        if (!retried) {
          await _rollbackReservationIfNeeded(taskId, errorMessage: errMsg);
          if (service is AppwriteApiBostProxyService) {
            await _refreshCreditsFromServer();
          }
          _setTaskState(
            taskId,
            status: GenerationStatus.error,
            statusMessage: '',
            errorMessage: errMsg,
          );
        }
        return;
      }
      _forgetReservation(taskId);
      if (service is AppwriteApiBostProxyService) {
        await _refreshCreditsFromServer();
      }

      _setTaskState(
        taskId,
        status: GenerationStatus.uploading,
        statusMessage: 'Сохраняем результат...',
      );

      final (resultImageUrl, dualResultUrls) =
          await _persistResultImageWithDual(result.imageUrl!);

      if (_findTask(taskId) == null) return;

      _setTaskState(
        taskId,
        status: GenerationStatus.saving,
        statusMessage: 'Сохраняем в историю...',
      );

      final deviceId = await _ref.read(deviceIdProvider.future);

      if (task.taskType == GenerationTaskType.userImage) {
        final presetData = _generatedImageData[taskId];
        if (presetData != null) {
          var previewUrl = resultImageUrl;
          String? pairedPreviewUrl = _httpUrlOrNull(
            dualResultUrls?.pairedHttpRelativeTo(resultImageUrl),
          );

          if (!_isHttpImageUrl(previewUrl)) {
            try {
              final previewFile = File(previewUrl);
              if (previewFile.existsSync()) {
                final dual = _ref.read(photosessionDualUploadServiceProvider);
                if (dual != null) {
                  final urls = await dual.uploadPresetPreview(previewFile);
                  final chosen = urls.firstHttpPrimaryOrMirror();
                  if (chosen != null) {
                    previewUrl = chosen;
                    pairedPreviewUrl =
                        _httpUrlOrNull(urls.pairedHttpRelativeTo(chosen)) ??
                            pairedPreviewUrl;
                  }
                  debugPrint(
                    'BackgroundGeneration: dual preview previewUrl=$previewUrl '
                    'paired=$pairedPreviewUrl',
                  );
                } else {
                  final storage = _ref.read(photosessionRemoteStorageProvider);
                  final uploaded =
                      await storage.uploadPresetPreview(previewFile);
                  if (uploaded != null && _isHttpImageUrl(uploaded)) {
                    previewUrl = uploaded;
                    debugPrint(
                      'BackgroundGeneration: загружен preview пресета: $previewUrl',
                    );
                  }
                }
              } else {
                debugPrint(
                  'BackgroundGeneration: локальный файл результата не найден '
                  'для обложки пресета: $previewUrl',
                );
              }
            } catch (e) {
              debugPrint(
                'BackgroundGeneration: uploadPresetPreview failed: $e',
              );
            }
          }

          if (!_isHttpImageUrl(previewUrl)) {
            _generatedImageData.remove(taskId);
            _setTaskState(
              taskId,
              status: GenerationStatus.error,
              statusMessage: '',
              errorMessage:
                  'Не удалось сохранить обложку пресета в облако (нет публичного URL). '
                  'Проверьте Storage и ключи Appwrite/Firebase, затем повторите генерацию.',
            );
            return;
          }

          pairedPreviewUrl = _httpUrlOrNull(pairedPreviewUrl);

          final thumbnailUrl = await _uploadPresetThumbnail(result.imageUrl!);

          final repo = _ref.read(showcaseRepositoryProvider);
          final created = await repo.createPreset(
            prompt: presetData.prompt,
            previewImageUrl: previewUrl,
            title: presetData.title,
            tags: [PresetTag.idCustom],
            imageStyle: presetData.imageStyle,
            ownerId: deviceId,
            pairedPreviewImageUrl: pairedPreviewUrl,
            thumbnailUrl: thumbnailUrl,
          );
          try {
            await _ref
                .read(presetTagServiceProvider)
                .updateTagsForPublicPreset(created.id, presetData.prompt);
          } catch (e) {
            debugPrint('BackgroundGeneration: updateTagsForPublicPreset $e');
          }
          _generatedImageData.remove(taskId);
          _setTaskState(
            taskId,
            status: GenerationStatus.saving,
            statusMessage: 'Сохраняем в историю...',
            createdPresetId: created.id,
          );
        }
      } else {
        final generationRepo = _ref.read(userGenerationRepositoryProvider);
        final genId = clientDualBackendMirrorEnabled()
            ? 'gen_${DateTime.now().millisecondsSinceEpoch}'
            : null;
        await generationRepo.createGeneration(
          presetId: task.presetId,
          userImageUrl: task.userPhotoPath,
          resultImageUrl: resultImageUrl,
          deviceId: deviceId,
          clientAssignedDocumentId: genId,
          pairedUserImageUrl: null,
          pairedResultImageUrl:
              dualResultUrls?.pairedHttpRelativeTo(resultImageUrl),
          pairedReferenceImageUrl: null,
        );
      }

      if (_findTask(taskId) == null) return;

      _setTaskState(
        taskId,
        status: GenerationStatus.completed,
        statusMessage: 'Готово!',
        resultImageUrl: resultImageUrl,
      );
      unawaited(_recordPostSessionReviewGeneration());
    } catch (e) {
      debugPrint('BackgroundGeneration error for $taskId: $e');
      final catchTask = _findTask(taskId);
      if (catchTask != null) {
        final errMsg = e.toString();

        final retried = await _tryAutoRetry(taskId, errMsg, _runGeneration);
        if (!retried) {
          await _rollbackReservationIfNeeded(taskId, errorMessage: errMsg);
          if (_serverChargesCredits(
            taskType: catchTask.taskType,
          )) {
            await _refreshCreditsFromServer();
          }
          _setTaskState(
            taskId,
            status: GenerationStatus.error,
            statusMessage: '',
            errorMessage: errMsg,
          );
        }
      }
    }
  }

  Future<void> _runFaceSwapGeneration(String taskId) async {
    final task = _findTask(taskId);
    if (task == null) return;

    try {
      _setTaskState(
        taskId,
        status: GenerationStatus.generating,
        statusMessage: 'Генерируем видео (1-3 минуты)...',
      );

      final referenceUrl = task.referenceImageUrl;
      if (referenceUrl == null) {
        _setTaskState(
          taskId,
          status: GenerationStatus.error,
          statusMessage: '',
          errorMessage: 'Не найдено референсное изображение.',
        );
        return;
      }

      debugPrint(
        '🎬 BackgroundGen FaceSwap: режим=${task.faceSwapMode?.name} '
        'провайдер=${task.provider.name}',
      );

      String resultImageUrl;
      String savedReferenceUrl = await _persistReferenceImage(referenceUrl);

      var chargedOnServer = false;
      if (task.faceSwapMode == FaceSwapMode.exact) {
        // Точная замена лица — только PiAPI, требует публичных URL
        final uploadService = _ref.read(piApiUploadServiceProvider);

        final uploadedRefUrl = await _prepareFaceSwapTargetUrl(
          referenceUrl,
          uploadService,
        );
        if (uploadedRefUrl == null) {
          const errMsg = 'Не удалось загрузить референс на сервер.';
          final retried =
              await _tryAutoRetry(taskId, errMsg, _runFaceSwapGeneration);
          if (!retried) {
            _setTaskState(
              taskId,
              status: GenerationStatus.error,
              statusMessage: '',
              errorMessage: errMsg,
            );
          }
          return;
        }

        final userFile = File(task.userPhotoPath);
        final uploadedUserUrl = await uploadService.uploadImage(userFile);
        if (uploadedUserUrl == null) {
          const errMsg = 'Не удалось загрузить изображения на сервер.';
          final retried =
              await _tryAutoRetry(taskId, errMsg, _runFaceSwapGeneration);
          if (!retried) {
            _setTaskState(
              taskId,
              status: GenerationStatus.error,
              statusMessage: '',
              errorMessage: errMsg,
            );
          }
          return;
        }

        if (_findTask(taskId) == null) return;

        final faceswapService = _ref.read(piApiFaceswapServiceProvider);
        final result = await faceswapService.swapFace(
          targetImageUrl: uploadedRefUrl,
          swapImageUrl: uploadedUserUrl,
        );

        if (_findTask(taskId) == null) return;

        if (!result.isSuccess || result.imageUrl == null) {
          final errMsg =
              result.errorMessage ?? 'Не удалось выполнить замену лица.';
          final retried =
              await _tryAutoRetry(taskId, errMsg, _runFaceSwapGeneration);
          if (!retried) {
            await _rollbackReservationIfNeeded(taskId, errorMessage: errMsg);
            _setTaskState(
              taskId,
              status: GenerationStatus.error,
              statusMessage: '',
              errorMessage: errMsg,
            );
          }
          return;
        }

        resultImageUrl = result.imageUrl!;
      } else {
        // Воссоздание стиля — ApiBost с двумя изображениями.
        // Каптирование и маскирование лица не нужны: Gemini видит оба изображения напрямую.
        final service =
            _ref.read(photosessionGenerationServiceProvider(task.provider));

        if (_findTask(taskId) == null) return;

        _setTaskState(
          taskId,
          status: GenerationStatus.generating,
          statusMessage: 'Генерируем видео (1-3 минуты)...',
        );

        debugPrint(
          '🎬 BackgroundGen FaceSwap style via ApiBost: '
          'провайдер=${task.provider.name}',
        );

        // image_urls[0] = референс сцены, image_urls[1] = фото пользователя.
        // Промпт простой и прямой — сложные инструкции с "IMAGE 1 / IMAGE 2"
        // путают модель и она возвращает исходное фото без изменений.
        const styleTransferPrompt =
            'Generate a brand new photorealistic portrait. '
            'Use the FIRST photo only as a scene reference: copy its background, '
            'setting, lighting, outfit, pose and composition. '
            'Use the SECOND photo only as an identity reference: the generated person '
            'must have the exact face, age, gender, skin tone and hair from the second photo. '
            'Do NOT return either of the input photos — create a completely new image '
            'that combines the scene from photo 1 with the identity from photo 2. '
            'Vertical portrait, 3:4, photorealistic, high quality. '
            'Any visible text must be in Cyrillic.';

        final result = await (service as dynamic).generateWithFace(
          userImageUrl: task.userPhotoPath,
          scenePrompt: styleTransferPrompt,
          referenceImageUrl: savedReferenceUrl,
          resolution: '2K',
          aspectRatio: '3:4',
        );
        chargedOnServer = service is AppwriteApiBostProxyService;

        if (_findTask(taskId) == null) return;

        if (!result.isSuccess || result.imageUrl == null) {
          final errMsg =
              result.errorMessage ?? 'Не удалось создать видео.';
          final retried =
              await _tryAutoRetry(taskId, errMsg, _runFaceSwapGeneration);
          if (!retried) {
            await _rollbackReservationIfNeeded(taskId, errorMessage: errMsg);
            if (chargedOnServer) {
              await _refreshCreditsFromServer();
            }
            _setTaskState(
              taskId,
              status: GenerationStatus.error,
              statusMessage: '',
              errorMessage: errMsg,
            );
          }
          return;
        }

        resultImageUrl = result.imageUrl!;
      }

      if (_findTask(taskId) == null) return;
      _forgetReservation(taskId);
      if (chargedOnServer) {
        await _refreshCreditsFromServer();
      }

      _setTaskState(
        taskId,
        status: GenerationStatus.uploading,
        statusMessage: 'Сохраняем результат...',
      );

      final dualPair = await _persistResultImageWithDual(resultImageUrl);
      resultImageUrl = dualPair.$1;
      final dualResultUrlsFace = dualPair.$2;

      if (_findTask(taskId) == null) return;

      _setTaskState(
        taskId,
        status: GenerationStatus.saving,
        statusMessage: 'Сохраняем в историю...',
      );

      final deviceId = await _ref.read(deviceIdProvider.future);
      final generationRepo = _ref.read(userGenerationRepositoryProvider);
      final genIdFs = clientDualBackendMirrorEnabled()
          ? 'gen_${DateTime.now().millisecondsSinceEpoch}'
          : null;
      await generationRepo.createGeneration(
        presetId: task.presetId,
        userImageUrl: task.userPhotoPath,
        resultImageUrl: resultImageUrl,
        deviceId: deviceId,
        referenceImageUrl: savedReferenceUrl,
        clientAssignedDocumentId: genIdFs,
        pairedUserImageUrl: null,
        pairedResultImageUrl:
            dualResultUrlsFace?.pairedHttpRelativeTo(resultImageUrl),
        pairedReferenceImageUrl: null,
      );

      if (_findTask(taskId) == null) return;

      _setTaskState(
        taskId,
        status: GenerationStatus.completed,
        statusMessage: 'Готово!',
        resultImageUrl: resultImageUrl,
      );
      unawaited(_recordPostSessionReviewGeneration());
    } catch (e) {
      debugPrint('BackgroundGeneration FaceSwap error for $taskId: $e');
      final task = _findTask(taskId);
      if (_findTask(taskId) != null) {
        final errMsg = e.toString();
        final retried =
            await _tryAutoRetry(taskId, errMsg, _runFaceSwapGeneration);
        if (!retried) {
          await _rollbackReservationIfNeeded(taskId, errorMessage: errMsg);
          if (task != null &&
              _serverChargesCredits(
                taskType: task.taskType,
                faceSwapMode: task.faceSwapMode,
              )) {
            await _refreshCreditsFromServer();
          }
          _setTaskState(
            taskId,
            status: GenerationStatus.error,
            statusMessage: '',
            errorMessage: errMsg,
          );
        }
      }
    }
  }

  Future<void> _recordPostSessionReviewGeneration() async {
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      await PostPhotosessionReviewService.recordSuccessfulGeneration(prefs);
    } catch (_) {}
  }

  void _setTaskState(
    String taskId, {
    required GenerationStatus status,
    required String statusMessage,
    String? resultImageUrl,
    String? errorMessage,
    String? createdPresetId,
    PhotosessionProvider? provider,
  }) {
    state = [
      for (final t in state)
        if (t.id == taskId)
          GenerationTask(
            id: t.id,
            presetId: t.presetId,
            presetTitle: t.presetTitle,
            presetPreviewUrl: t.presetPreviewUrl,
            status: status,
            statusMessage: statusMessage,
            resultImageUrl: resultImageUrl,
            errorMessage: errorMessage,
            userPhotoPath: t.userPhotoPath,
            prompt: t.prompt,
            createdAt: t.createdAt,
            provider: provider ?? t.provider,
            taskType: t.taskType,
            referenceImageUrl: t.referenceImageUrl,
            faceSwapMode: t.faceSwapMode,
            createdPresetId: createdPresetId ?? t.createdPresetId,
            aspectRatio: t.aspectRatio,
          )
        else
          t,
    ];
  }

  Future<(String, DualSideImageUrls?)> _persistResultImageWithDual(
    String imageUrl,
  ) async {
    // Новые пользователи / после миграции — сохраняем локально, не загружаем на сервер
    if (GenerationMigrationService.instance.isLocalMode) {
      return _persistResultImageLocally(imageUrl);
    }

    try {
      final resultFile = await _resolveReferenceFile(imageUrl);
      if (resultFile == null) {
        debugPrint(
            'BackgroundGeneration: файл не найден для загрузки: $imageUrl');
        return (imageUrl, null);
      }
      final dual = _ref.read(photosessionDualUploadServiceProvider);
      if (dual != null) {
        final urls = await dual.uploadResultImage(resultFile);
        final preferred = urls.firstHttpPrimaryOrMirror();
        if (preferred != null) {
          return (preferred, urls);
        }
      }
      final storage = _ref.read(photosessionRemoteStorageProvider);
      final uploadedUrl = await storage.uploadResultImage(resultFile);
      if (uploadedUrl == null) {
        debugPrint(
          'BackgroundGeneration: uploadResultImage вернул null для $imageUrl',
        );
      }
      return (uploadedUrl ?? imageUrl, null);
    } catch (e) {
      debugPrint('BackgroundGeneration: ошибка загрузки результата: $e');
      return (imageUrl, null);
    }
  }

  /// Сохраняет изображение локально на устройство (без загрузки на сервер).
  Future<(String, DualSideImageUrls?)> _persistResultImageLocally(
    String imageUrl,
  ) async {
    try {
      final storage = LocalGenerationStorage.instance;

      // Если это уже локальный путь — возвращаем как есть
      if (LocalGenerationStorage.isLocalPath(imageUrl)) {
        return (imageUrl, null);
      }

      // Скачиваем с временного URL AI-сервиса и сохраняем локально
      final localPath = await storage.saveImageFromUrl(
        imageUrl,
        id: 'gen_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (localPath != null) {
        debugPrint(
          'BackgroundGeneration: сохранено локально: $localPath',
        );
        return (localPath, null);
      }

      // Fallback: если не удалось сохранить локально — возвращаем оригинальный URL
      debugPrint(
        'BackgroundGeneration: не удалось сохранить локально, используем URL',
      );
      return (imageUrl, null);
    } catch (e) {
      debugPrint('BackgroundGeneration: ошибка локального сохранения: $e');
      return (imageUrl, null);
    }
  }

  Future<String> _persistReferenceImage(String referenceUrl) async {
    if (_isHttpImageUrl(referenceUrl)) return referenceUrl;

    try {
      final file = File(referenceUrl);
      if (!file.existsSync()) return referenceUrl;

      final dual = _ref.read(photosessionDualUploadServiceProvider);
      if (dual != null) {
        final urls = await dual.uploadPresetPreview(file);
        final preferred = urls.firstHttpPrimaryOrMirror();
        if (preferred != null) return preferred;
      }

      final storage = _ref.read(photosessionRemoteStorageProvider);
      final uploadedUrl = await storage.uploadPresetPreview(file);
      return uploadedUrl ?? referenceUrl;
    } catch (e) {
      debugPrint('BackgroundGeneration: ошибка загрузки референса: $e');
      return referenceUrl;
    }
  }

  /// Обложка пресета для сетки: из видео берётся первый кадр, потому что
  /// показывать в списке само видео дорого. Неудача не критична — пресет
  /// создастся без обложки, а карточка построит кадр локально.
  Future<String?> _uploadPresetThumbnail(String localResultPath) async {
    if (!GeneratedMedia.isVideo(localResultPath)) return null;

    File? poster;
    try {
      final bytes = await VideoPosterService().extractFrame(localResultPath);
      if (bytes == null) return null;

      final directory = await getTemporaryDirectory();
      poster = File(path.join(
        directory.path,
        'preset_poster_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ));
      await poster.writeAsBytes(bytes, flush: true);

      final dual = _ref.read(photosessionDualUploadServiceProvider);
      if (dual != null) {
        final urls = await dual.uploadPresetPreview(poster);
        return _httpUrlOrNull(urls.firstHttpPrimaryOrMirror());
      }
      final storage = _ref.read(photosessionRemoteStorageProvider);
      return _httpUrlOrNull(await storage.uploadPresetPreview(poster));
    } catch (e) {
      debugPrint('BackgroundGeneration: обложка пресета не создана: $e');
      return null;
    } finally {
      try {
        if (poster != null && await poster.exists()) await poster.delete();
      } catch (_) {}
    }
  }

  Future<String?> _prepareFaceSwapTargetUrl(
    String referenceUrl,
    PiApiUploadService uploadService,
  ) async {
    final trimmed = referenceUrl.trim();
    if (_isPiApiUploadUrl(trimmed)) return trimmed;

    final file = await _resolveReferenceFile(trimmed);
    if (file == null) {
      debugPrint(
          'BackgroundGeneration: не удалось подготовить target для FaceSwap: $trimmed');
      return null;
    }
    return uploadService.uploadImage(file);
  }

  bool _isPiApiUploadUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    final host = uri?.host.toLowerCase() ?? '';
    return host == 'upload.theapi.app' || host.endsWith('.theapi.app');
  }

  Future<File?> _resolveReferenceFile(String source) async {
    if (!source.startsWith('http://') && !source.startsWith('https://')) {
      final file = File(source);
      return file.existsSync() ? file : null;
    }

    try {
      final proxiedImageService = _ref.read(proxiedImageServiceProvider);
      final bytes = await proxiedImageService.downloadImage(source);
      if (bytes == null || bytes.isEmpty) {
        return null;
      }

      final tempDir = await getTemporaryDirectory();
      final ext = _resolveReferenceExtension(source);
      final file = File(
        path.join(
          tempDir.path,
          'photosession_reference_${DateTime.now().microsecondsSinceEpoch}$ext',
        ),
      );
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (e) {
      debugPrint('BackgroundGeneration reference download error: $e');
      return null;
    }
  }

  String _resolveReferenceExtension(String source) {
    final parsed = Uri.tryParse(source);
    final ext = path.extension(parsed?.path ?? source).toLowerCase();
    if (ext == '.jpg' || ext == '.jpeg' || ext == '.png' || ext == '.webp') {
      return ext;
    }
    return '.jpg';
  }
}
