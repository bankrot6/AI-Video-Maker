import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/credit_config.dart';
import '../../models/generation_task.dart';
import '../../models/photosession_provider.dart';
import '../../models/user_generation.dart';
import '../../providers/credit_providers.dart';
import '../../services/photo_input_validation_service.dart';
import '../../widgets/credit_counter_widget.dart';
import '../../widgets/photo_validation_status_card.dart';
import '../../widgets/proxied_network_image.dart';
import 'background_generation_provider.dart';
import 'fullscreen_image_viewer.dart';
import 'photosession_generation_screen.dart';
import 'photosession_providers.dart';
import 'photosession_support_error.dart';
import 'theme/photosession_palette.dart';
import 'theme/photosession_theme_scope.dart';
import 'tutorial/photosession_tutorial.dart';
import '../subscription/paid_feature_gate.dart';
import '../subscription/purchase_routes.dart';
import '../subscription/subscription_providers.dart';

class PhotosessionFaceSwapScreen extends ConsumerStatefulWidget {
  const PhotosessionFaceSwapScreen({
    super.key,
    this.initialReferenceUrl,
    this.initialPresetId,
  });

  final String? initialReferenceUrl;
  final String? initialPresetId;

  @override
  ConsumerState<PhotosessionFaceSwapScreen> createState() =>
      _PhotosessionFaceSwapScreenState();
}

class _PhotosessionFaceSwapScreenState
    extends ConsumerState<PhotosessionFaceSwapScreen> {
  File? _referencePhoto;
  String? _referenceImageUrl;
  File? _userPhoto;
  PhotoInputValidationResult? _userPhotoValidation;
  bool _isUserPhotoValidationInProgress = false;
  PhotosessionProvider _selectedProvider = PhotosessionProvider.veoFast;
  bool _useExactFaceSwap = false;
  bool _presetDeleting = false;

  FaceSwapMode get _faceSwapMode =>
      _useExactFaceSwap ? FaceSwapMode.exact : FaceSwapMode.style;
  List<UserGeneration> _generations = [];
  final _referenceCardKey = GlobalKey();
  final _userFaceCardKey = GlobalKey();
  final _modeSelectorKey = GlobalKey();
  final _generateButtonKey = GlobalKey();
  final _faceSwapTipsHeaderKey = GlobalKey();
  bool _faceSwapTipsExpanded = false;
  bool _isTutorialVisible = false;
  bool _didTryAutoTutorial = false;
  bool _faceSwapAutoTutorialChain = false;
  final Set<String> _deletingGenerationIds = {};

  static const _faceSwapPresetId = 'faceswap';
  static const _exactFaceSwapCreditCost = CreditCost.economyGeneration;

  String get _currentPresetId => widget.initialPresetId ?? _faceSwapPresetId;

  bool get _isPresetMode =>
      widget.initialReferenceUrl != null &&
      widget.initialReferenceUrl!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _referenceImageUrl = widget.initialReferenceUrl?.trim();
    if (_isPresetMode) _loadGenerations();
    Future.microtask(
      () => ref.read(creditUsageNotifierProvider.notifier).refreshFromServer(),
    );
  }

  Future<void> _loadGenerations() async {
    try {
      final deviceId = ref.read(deviceIdProvider).value ??
          await ref.read(deviceIdProvider.future);
      if (deviceId == null || deviceId.isEmpty) return;
      final repo = ref.read(userGenerationRepositoryProvider);
      final generations = await repo.getGenerationsByPreset(
        _currentPresetId,
        deviceId: deviceId,
      );
      if (mounted) setState(() => _generations = generations);
    } catch (e) {
      debugPrint('FaceSwap: ошибка загрузки истории: $e');
    }
  }

  Future<void> _onDeleteGenerationPressed(UserGeneration generation) async {
    final allowed = await ensureDeleteAccess(context, ref);
    if (!allowed || !mounted) return;
    final palette = PhotosessionPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Удалить генерацию?'),
          content: const Text(
            'Видео будет удалено из истории на сервере. Отменить это нельзя.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final deviceId = ref.read(deviceIdProvider).value ??
        await ref.read(deviceIdProvider.future);
    if (deviceId == null || deviceId.isEmpty) return;
    setState(() => _deletingGenerationIds.add(generation.id));
    try {
      final ok =
          await ref.read(userGenerationRepositoryProvider).deleteGeneration(
                generation.id,
                deviceId: deviceId,
                presetId: _currentPresetId,
              );
      if (!mounted) return;
      if (ok) {
        setState(() {
          _generations.removeWhere((e) => e.id == generation.id);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Не удалось удалить генерацию'),
            backgroundColor: palette.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deletingGenerationIds.remove(generation.id));
      }
    }
  }

  Future<void> _onDeletePresetPressed() async {
    final allowed = await ensureDeleteAccess(context, ref);
    if (!allowed || !mounted) return;
    final palette = PhotosessionPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Удалить пресет?'),
          content: const Text(
            'Пресет и вся история генераций по нему будут удалены. '
            'Это действие нельзя отменить.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final deviceId = ref.read(deviceIdProvider).value ??
        await ref.read(deviceIdProvider.future);
    if (deviceId == null || deviceId.isEmpty) return;
    setState(() => _presetDeleting = true);
    try {
      final genRepo = ref.read(userGenerationRepositoryProvider);
      for (final g in List<UserGeneration>.from(_generations)) {
        if (!mounted) return;
        await genRepo.deleteGeneration(
          g.id,
          deviceId: deviceId,
          presetId: _currentPresetId,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось удалить: $e'),
          backgroundColor: palette.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _presetDeleting = false);
    }
  }

  Widget _buildDeletePresetButton() {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 2),
      child: IconButton(
        tooltip: 'Удалить пресет',
        onPressed: _presetDeleting ? null : _onDeletePresetPressed,
        icon: _presetDeleting
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            : Icon(
                Icons.delete_outline_rounded,
                color: Theme.of(context).colorScheme.onSurface,
              ),
      ),
    );
  }

  Future<void> _pickPhoto(bool isReference) async {
    if (_isPresetMode && isReference) {
      return;
    }

    await _pickPhotoFromGallery(isReference);
  }

  Future<void> _pickPhotoFromGallery(bool isReference) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (xFile == null || !mounted) return;
    final file = File(xFile.path);
    if (isReference) {
      setState(() => _referencePhoto = file);
      return;
    }
    await _setUserPhoto(file);
  }

  Future<void> _setUserPhoto(File file) async {
    setState(() {
      _userPhoto = file;
      _userPhotoValidation = null;
      _isUserPhotoValidationInProgress = true;
    });

    final validator = ref.read(photoInputValidationServiceProvider);
    final result = await validator.validate(file);
    if (!mounted || _userPhoto?.path != file.path) return;

    setState(() {
      _userPhotoValidation = result;
      _isUserPhotoValidationInProgress = false;
    });
  }

  Future<void> _startGeneration() async {
    final palette = PhotosessionPalette.of(context);
    final hasReference = _referencePhoto != null || _referenceImageUrl != null;
    if (!hasReference || _userPhoto == null) return;

    try {
      final provider = _useExactFaceSwap
          ? PhotosessionProvider.veoFast
          : _selectedProvider;
      final result = await ref
          .read(backgroundGenerationProvider.notifier)
          .startFaceSwapGeneration(
            referencePhoto: _referencePhoto,
            referenceImageUrl: _referenceImageUrl,
            userPhoto: _userPhoto!,
            faceSwapMode: _faceSwapMode,
            provider: provider,
            creditCostOverride:
                _useExactFaceSwap ? _exactFaceSwapCreditCost : null,
            presetId: _isPresetMode ? _currentPresetId : null,
          );

      if (!mounted) return;

      if (!result.isSuccess) {
        if (result.reason == 'insufficient_credits' ||
            result.reason == 'tier_locked') {
          Navigator.of(context).push(
            tokenPurchaseRoute(),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Не удалось подготовить списание кредитов'),
              backgroundColor: palette.danger,
            ),
          );
        }
        return;
      }

      Navigator.of(context)
          .push(
        photosessionRoute(
          PhotosessionGenerationScreen(taskId: result.taskId!),
        ),
      )
          .then((_) {
        if (mounted) _loadGenerations();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(normalizePhotosessionErrorMessage(e.toString())),
          backgroundColor: palette.danger,
        ),
      );
    }
  }

  void _openFullscreen(String imageUrl, String heroTag) {
    Navigator.of(context).push(
      photosessionRoute(
        FullscreenImageViewer(
          imageUrl: imageUrl,
          heroTag: heroTag,
        ),
      ),
    );
  }

  void _scheduleFaceSwapTutorialIfNeeded({bool force = false}) {
    if (!mounted || _isTutorialVisible || _faceSwapTipsExpanded) return;

    final palette = PhotosessionPalette.of(context);

    runPhotosessionAutoTutorialChain(
      context: context,
      ref: ref,
      force: force,
      scenario: PhotosessionTutorialScenario.faceSwap,
      schedulingGateOk: () =>
          mounted && !_isTutorialVisible && !_faceSwapTipsExpanded,
      buildTargets: _buildFaceSwapTutorialTargets,
      getDidTryAuto: () => _didTryAutoTutorial,
      setDidTryAuto: (v) => _didTryAutoTutorial = v,
      getChainActive: () => _faceSwapAutoTutorialChain,
      setChainActive: (v) => _faceSwapAutoTutorialChain = v,
      onShow: (targets) {
        final store = ref.read(photosessionTutorialStoreProvider);
        _isTutorialVisible = true;
        TutorialCoachMark(
          targets: targets,
          colorShadow: palette.depth,
          opacityShadow: 0.78,
          hideSkip: true,
          paddingFocus: 10,
          pulseEnable: false,
          beforeFocus:
              photosessionTutorialBeforeFocus(targets, hasImages: true),
          onFinish: () async {
            _isTutorialVisible = false;
            await store.markSeen(PhotosessionTutorialScenario.faceSwap);
          },
          onSkip: () {
            _isTutorialVisible = false;
            store.markSeen(PhotosessionTutorialScenario.faceSwap);
            return true;
          },
        ).showForPhotosession(context);
      },
    );
  }

  List<TargetFocus> _buildFaceSwapTutorialTargets() {
    final steps = <({
      GlobalKey key,
      String id,
      String title,
      String description,
      IconData icon,
      ContentAlign align,
    })>[];

    if (_faceSwapTipsHeaderKey.currentContext != null) {
      steps.add((
        key: _faceSwapTipsHeaderKey,
        id: 'faceswap_tips',
        title: 'Как сделать ролик с собой',
        description:
            'Кратко: референс задаёт сцену, ваше фото лица — кто появится в клипе. Из этого блока можно снова открыть пошаговое обучение.',
        icon: Icons.question_mark_rounded,
        align: ContentAlign.bottom,
      ));
    }

    if (_referenceCardKey.currentContext != null) {
      steps.add((
        key: _referenceCardKey,
        id: 'faceswap_reference',
        title: 'Выберите сцену-референс',
        description:
            'Референс задаёт композицию, одежду, свет и атмосферу будущего ролика. Если хотите повторить конкретную идею — начните отсюда.',
        icon: Icons.image_outlined,
        align: ContentAlign.bottom,
      ));
    }

    if (_userFaceCardKey.currentContext != null) {
      steps.add((
        key: _userFaceCardKey,
        id: 'faceswap_user',
        title: 'Добавьте своё лицо',
        description:
            'Загрузите чёткое фото лица анфас — без очков, сильных теней и фильтров. Так модель точнее перенесёт вас в видео.',
        icon: Icons.face_retouching_natural_rounded,
        align: ContentAlign.bottom,
      ));
    }

    if (_modeSelectorKey.currentContext != null) {
      steps.add((
        key: _modeSelectorKey,
        id: 'faceswap_mode',
        title: 'Выберите режим',
        description:
            'Точная замена вставит вас в готовую сцену. «Воссоздать стиль» сохранит атмосферу референса, но допустит новую позу и композицию в ролике.',
        icon: Icons.palette_outlined,
        align: ContentAlign.top,
      ));
    }

    if (_generateButtonKey.currentContext != null) {
      steps.add((
        key: _generateButtonKey,
        id: 'faceswap_generate',
        title: 'Создайте видео',
        description:
            'Когда референс и лицо загружены — запускайте генерацию ролика. Готовый клип можно открыть, сохранить и отправить.',
        icon: Icons.videocam_rounded,
        align: ContentAlign.top,
      ));
    }

    return [
      for (var i = 0; i < steps.length; i++)
        buildPhotosessionTutorialTarget(
          context: context,
          key: steps[i].key,
          id: steps[i].id,
          title: steps[i].title,
          description: steps[i].description,
          step: i + 1,
          total: steps.length,
          icon: steps[i].icon,
          align: steps[i].align,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final usage = ref.watch(creditUsageNotifierProvider).valueOrNull;
    final hasPaidSubscription =
        ref.watch(subscriptionProvider).valueOrNull?.isPaidUser ?? false;
    final hasReference = _referencePhoto != null || _referenceImageUrl != null;
    final requiredCredits = _useExactFaceSwap
        ? _exactFaceSwapCreditCost
        : _selectedProvider.creditCost;
    final effectiveTier = _selectedProvider.creditTier;
    final isTierLocked = !_useExactFaceSwap &&
        !CreditCost.isTierAccessible(
          effectiveTier,
          hasPaidSubscription: hasPaidSubscription,
        );
    final hasEnoughCredits =
        usage == null || usage.hasEnoughCredits(requiredCredits);
    final canGenerate = hasReference &&
        _userPhoto != null &&
        !_isUserPhotoValidationInProgress &&
        !(_userPhotoValidation?.isBlocking ?? false) &&
        !isTierLocked &&
        hasEnoughCredits;

    _scheduleFaceSwapTutorialIfNeeded();

    final scaffold = Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.surfaceContainerLowest,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Замена лица',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_isPresetMode) _buildDeletePresetButton(),
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: CreditCounterWidget(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPhotoComparison(colors),
            const SizedBox(height: 16),
            _buildFaceSwapTipsSection(colors),
            if (_isPresetMode && _generations.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildHistorySection(colors),
            ],
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(colors, canGenerate),
    );

    return PhotosessionThemeScope(child: scaffold);
  }

  Widget _buildPhotoComparison(ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'РЕФЕРЕНС',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface.withOpacity(0.5),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _isPresetMode ? null : () => _pickPhoto(true),
                    child: KeyedSubtree(
                      key: _referenceCardKey,
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: _referencePhoto != null ||
                                _referenceImageUrl != null
                            ? Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          palette.depth.withValues(alpha: 0.28),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      if (_referencePhoto != null)
                                        Image.file(
                                          _referencePhoto!,
                                          fit: BoxFit.cover,
                                        )
                                      else
                                        ProxiedNetworkImage(
                                          url: _referenceImageUrl!,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (_) => Container(
                                            color:
                                                colors.surfaceContainerHighest,
                                            child: const Center(
                                              child: SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                          errorBuilder: (_) => Container(
                                            color:
                                                colors.surfaceContainerHighest,
                                            child: const Icon(
                                              Icons.broken_image,
                                              size: 32,
                                            ),
                                          ),
                                        ),
                                      if (!_isPresetMode)
                                        Positioned(
                                          right: 8,
                                          top: 8,
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: palette.depth
                                                  .withValues(alpha: 0.5),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.edit_rounded,
                                              size: 16,
                                              color: palette.textPrimary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: colors.primary.withOpacity(0.3),
                                    width: 2,
                                  ),
                                  color: colors.primary.withOpacity(0.05),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.image_outlined,
                                      size: 32,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Добавить\nреференс',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ВАШЕ ЛИЦО',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface.withOpacity(0.5),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _pickPhoto(false),
                    child: KeyedSubtree(
                      key: _userFaceCardKey,
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: _userPhoto != null
                            ? Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          palette.depth.withValues(alpha: 0.28),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.file(_userPhoto!,
                                          fit: BoxFit.cover),
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: palette.depth
                                                .withValues(alpha: 0.5),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.edit_rounded,
                                            size: 16,
                                            color: palette.textPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: colors.primary.withOpacity(0.3),
                                    width: 2,
                                  ),
                                  color: colors.primary.withOpacity(0.05),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo_rounded,
                                      size: 32,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Добавить\nлицо',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        PhotoValidationStatusCard(
          isChecking: _isUserPhotoValidationInProgress,
          result: _userPhotoValidation,
        ),
      ],
    );
  }

  Widget _buildFaceSwapTipsSection(ColorScheme colors) {
    return _buildExpandableSection(
      colors: colors,
      title: 'Как сделать ролик с собой',
      expanded: _faceSwapTipsExpanded,
      onToggle: () =>
          setState(() => _faceSwapTipsExpanded = !_faceSwapTipsExpanded),
      headerTutorialKey: _faceSwapTipsHeaderKey,
      leading: Tooltip(
        message: _faceSwapTipsExpanded
            ? 'Сначала сверните блок с советами'
            : 'Показать подсказки',
        child: InkResponse(
          onTap: _faceSwapTipsExpanded
              ? null
              : () => _scheduleFaceSwapTutorialIfNeeded(force: true),
          radius: 18,
          child: Icon(
            Icons.question_mark_rounded,
            size: 20,
            color: _faceSwapTipsExpanded
                ? colors.onSurface.withOpacity(0.35)
                : colors.primary,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Слева — сцена-референс, справа — ваше лицо. В точной замене вы появляетесь в этой сцене; в режиме стиля атмосфера референса сохраняется, а композиция ролика может измениться.',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: colors.onSurface.withOpacity(0.78),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Для чистого результата:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withOpacity(0.82),
            ),
          ),
          const SizedBox(height: 10),
          _buildUsageTipItem(
            colors: colors,
            text:
                'Берите референс с понятной позой и светом — так проще перенести вас в ролик.',
          ),
          _buildUsageTipItem(
            colors: colors,
            text:
                'Фото лица: анфас, без сильных теней, очков и тяжёлых фильтров.',
          ),
          _buildUsageTipItem(
            colors: colors,
            text:
                'Если клип слабый — сначала смените исходные фото, затем попробуйте другой режим.',
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableSection({
    required ColorScheme colors,
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget leading,
    required Widget child,
    Widget? badge,
    GlobalKey? headerTutorialKey,
  }) {
    final header = InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Center(child: leading),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface.withOpacity(0.8),
                ),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              badge,
            ],
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: colors.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        headerTutorialKey != null
            ? KeyedSubtree(
                key: headerTutorialKey,
                child: SizedBox(
                  width: double.infinity,
                  child: header,
                ),
              )
            : header,
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: expanded
                ? Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withOpacity(0.42),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colors.outlineVariant.withOpacity(0.3),
                      ),
                    ),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }

  Widget _buildUsageTipItem({
    required ColorScheme colors,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: colors.onSurface.withOpacity(0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'ИСТОРИЯ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurface.withOpacity(0.5),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_generations.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface.withOpacity(0.6),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 3 / 4,
          ),
          itemCount: _generations.length,
          itemBuilder: (context, index) {
            final generation = _generations[index];
            final isBusy = _deletingGenerationIds.contains(generation.id);
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: () => _openFullscreen(
                      generation.resultImageUrl,
                      'faceswap_gen_${generation.id}',
                    ),
                    child: Hero(
                      tag: 'faceswap_gen_${generation.id}',
                      child: ProxiedNetworkImage(
                        url: generation.resultImageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context) => Container(
                          color: colors.surfaceContainerHighest,
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                        errorBuilder: (context) => Container(
                          color: colors.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Icons.broken_image, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: palette.depth.withValues(alpha: 0.5),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: isBusy
                            ? null
                            : () => _onDeleteGenerationPressed(generation),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: isBusy
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: palette.textPrimary,
                                  ),
                                )
                              : Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: palette.textPrimary,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBottomBar(ColorScheme colors, bool canGenerate) {
    final palette = PhotosessionPalette.of(context);
    final hasBlockingValidationIssue =
        _userPhotoValidation?.isBlocking ?? false;
    final usage = ref.watch(creditUsageNotifierProvider).valueOrNull;
    final hasPaidSubscription =
        ref.watch(subscriptionProvider).valueOrNull?.isPaidUser ?? false;
    final requiredCredits = _useExactFaceSwap
        ? _exactFaceSwapCreditCost
        : _selectedProvider.creditCost;
    final isTierLocked = !_useExactFaceSwap &&
        !CreditCost.isTierAccessible(
          _selectedProvider.creditTier,
          hasPaidSubscription: hasPaidSubscription,
        );
    final hasEnoughCredits =
        usage == null || usage.hasEnoughCredits(requiredCredits);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: palette.depth.withValues(alpha: 0.32),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: _modeSelectorKey,
            child: _buildProviderSelector(colors),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: _generateButtonKey,
            onPressed: canGenerate
                ? _startGeneration
                : (!hasEnoughCredits || isTierLocked)
                    ? () => Navigator.of(context).push(tokenPurchaseRoute())
                    : (_userPhoto == null
                        ? () => _pickPhoto(false)
                        : _isUserPhotoValidationInProgress
                            ? null
                            : hasBlockingValidationIssue
                                ? () => _pickPhoto(false)
                                : () => _pickPhoto(true)),
            icon: Icon(
              canGenerate
                  ? Icons.auto_awesome_rounded
                  : (!hasEnoughCredits || isTierLocked)
                      ? Icons.account_balance_wallet_rounded
                      : Icons.add_a_photo_rounded,
              size: 22,
            ),
            label: Text(
              canGenerate
                  ? 'Создать видео'
                  : isTierLocked
                      ? 'Нужен PRO'
                      : !hasEnoughCredits
                          ? 'Купить кредиты'
                          : (_userPhoto == null
                              ? 'Добавить своё лицо'
                              : _isUserPhotoValidationInProgress
                                  ? 'Проверяем лицо...'
                                  : hasBlockingValidationIssue
                                      ? 'Выбрать другое лицо'
                                      : 'Добавить референс'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector(ColorScheme colors) {
    final hasPaidSubscription =
        ref.watch(subscriptionProvider).valueOrNull?.isPaidUser ?? false;
    final effectiveProvider = _useExactFaceSwap
        ? PhotosessionProvider.veoFast
        : _selectedProvider;
    final isLocked = !_useExactFaceSwap &&
        !CreditCost.isTierAccessible(
          effectiveProvider.creditTier,
          hasPaidSubscription: hasPaidSubscription,
        );
    final icon = _useExactFaceSwap
        ? Icons.face_retouching_natural_rounded
        : _faceSwapProviderIcon(_selectedProvider);
    final label =
        _useExactFaceSwap ? 'Qubico Faceswap' : effectiveProvider.label;
    final priceLabel = _useExactFaceSwap
        ? '$_exactFaceSwapCreditCost кредитов'
        : isLocked
            ? 'PRO'
            : effectiveProvider.price;
    return OutlinedButton(
      onPressed: () => _showModelSelectionSheet(colors),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        side: BorderSide(color: colors.outline.withOpacity(0.3), width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: colors.primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isLocked
                  ? colors.outline.withOpacity(0.1)
                  : colors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              priceLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isLocked ? colors.outline : colors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: colors.onSurface.withOpacity(0.4),
            size: 20,
          ),
        ],
      ),
    );
  }

  void _showModelSelectionSheet(ColorScheme colors) {
    final hasPaidSubscription =
        ref.read(subscriptionProvider).valueOrNull?.isPaidUser ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_mosaic_rounded,
                        color: colors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Выберите модель генерации',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        ...PhotosessionProvider.values
                            .where((p) =>
                                p.isAvailable &&
                                p.supportsImageEditing &&
                                p != PhotosessionProvider.veoLite)
                            .map((p) {
                          final isSelected =
                              !_useExactFaceSwap && _selectedProvider == p;
                          final isLocked = !CreditCost.isTierAccessible(
                            p.creditTier,
                            hasPaidSubscription: hasPaidSubscription,
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildModelOption(
                              colors: colors,
                              icon: _faceSwapProviderIcon(p),
                              label: p.label,
                              sourceBadge: p.sourceBadge,
                              priceOrPro: isLocked ? 'PRO' : p.price,
                              priceColor:
                                  isLocked ? colors.outline : colors.primary,
                              priceBg: isLocked
                                  ? colors.outline.withOpacity(0.1)
                                  : colors.primary.withOpacity(0.12),
                              description: isLocked
                                  ? 'Доступна с подпиской PRO'
                                  : p.description,
                              isSelected: isSelected,
                              isLocked: isLocked,
                              onTap: isLocked
                                  ? () => _showLockedSnackbar(context)
                                  : () => setState(() {
                                        _selectedProvider = p;
                                        _useExactFaceSwap = false;
                                        Navigator.pop(context);
                                      }),
                            ),
                          );
                        }),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildModelOption(
                            colors: colors,
                            icon: Icons.face_retouching_natural_rounded,
                            label: 'Qubico Faceswap',
                            sourceBadge: null,
                            priceOrPro: '$_exactFaceSwapCreditCost кредитов',
                            priceColor: colors.primary,
                            priceBg: colors.primary.withOpacity(0.12),
                            description:
                                'Специализированная модель точной замены лица. '
                                'Сохраняет позу, фон и освещение — меняет только лицо.',
                            isSelected: _useExactFaceSwap,
                            isLocked: false,
                            onTap: () => setState(() {
                              _selectedProvider =
                                  PhotosessionProvider.veoFast;
                              _useExactFaceSwap = true;
                              Navigator.pop(context);
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLockedSnackbar(BuildContext ctx) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('Модель доступна только подписчикам'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildModelOption({
    required ColorScheme colors,
    required IconData icon,
    required String label,
    required String? sourceBadge,
    required String priceOrPro,
    required Color priceColor,
    required Color priceBg,
    required String description,
    required bool isSelected,
    required bool isLocked,
    required VoidCallback onTap,
  }) {
    final palette = PhotosessionPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: isLocked ? 0.5 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected && !isLocked
                    ? colors.primary
                    : colors.outline.withOpacity(0.2),
                width: isSelected && !isLocked ? 2.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isLocked ? Icons.lock_rounded : icon,
                    size: 24,
                    color: isSelected && !isLocked
                        ? colors.primary
                        : colors.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (sourceBadge != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                sourceBadge,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: palette.accent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: priceBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              priceOrPro,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: priceColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: colors.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected && !isLocked)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: colors.primary,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _faceSwapProviderIcon(PhotosessionProvider p) {
    switch (p) {
      case PhotosessionProvider.veoLite:
        return Icons.flash_on_rounded;
      case PhotosessionProvider.veoFast:
        return Icons.bolt_rounded;
      case PhotosessionProvider.veoPro:
        return Icons.rocket_launch_rounded;
      case PhotosessionProvider.veoFastPreview:
        return Icons.auto_awesome_rounded;
      case PhotosessionProvider.veoPro4k:
        return Icons.diamond_rounded;
    }
  }
}
