import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image/image.dart' as img;

import '../../models/generation_task.dart';
import '../../services/proxied_image_service.dart';
import '../../widgets/proxied_network_image.dart';
import '../home/home_navigation_screen.dart';
import 'background_generation_provider.dart';
import 'photosession_providers.dart';
import 'fullscreen_image_viewer.dart';
import 'theme/photosession_palette.dart';
import 'theme/photosession_theme_scope.dart';
import 'tutorial/photosession_tutorial.dart';
import 'widgets/photosession_watermark_label.dart';
import '../../providers/credit_providers.dart';
import '../subscription/post_generation_offer_sheet.dart';
import '../subscription/paid_feature_gate.dart';
import '../subscription/purchase_routes.dart';
import 'photosession_support_error.dart';

class PhotosessionGenerationScreen extends ConsumerStatefulWidget {
  const PhotosessionGenerationScreen({
    super.key,
    required this.taskId,
  });

  final String taskId;

  @override
  ConsumerState<PhotosessionGenerationScreen> createState() =>
      _PhotosessionGenerationScreenState();
}

class _PhotosessionGenerationScreenState
    extends ConsumerState<PhotosessionGenerationScreen>
    with TickerProviderStateMixin {
  bool _saving = false;
  bool _makePublic = true;
  bool _wasEverLoading = false;
  bool _animatedToResult = false;
  final _imageAreaKey = GlobalKey();
  final _saveButtonKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  final _doneButtonKey = GlobalKey();
  final _communityKey = GlobalKey();
  bool _isTutorialVisible = false;
  bool _didTryAutoTutorial = false;
  bool _generationAutoTutorialChain = false;

  late final BackgroundGenerationNotifier _notifier;
  late final AnimationController _shimmerController;
  late final AnimationController _resultController;
  late final Animation<double> _resultFade;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(backgroundGenerationProvider.notifier);
    _notifier.markObserved(widget.taskId);

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _resultController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
      value: 1.0,
    );

    _resultFade = CurvedAnimation(
      parent: _resultController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _notifier.markUnobserved(widget.taskId);
    _shimmerController.dispose();
    _resultController.dispose();
    super.dispose();
  }

  GenerationTask? _findTask() {
    final tasks = ref.watch(backgroundGenerationProvider);
    for (final task in tasks) {
      if (task.id == widget.taskId) return task;
    }
    return null;
  }

  void _retry() {
    ref.read(backgroundGenerationProvider.notifier).retryTask(widget.taskId);
  }

  /// Добавляет watermark на изображение для free/trial пользователей
  Future<Uint8List> _addWatermarkToImage(Uint8List imageBytes) async {
    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final sourceImage = frame.image;

      final imageWidth = sourceImage.width;
      final imageHeight = sourceImage.height;
      final padding = imageWidth * 0.025;
      final fontSize = imageHeight >= 1500
          ? 24.0
          : imageHeight >= 800
              ? 16.0
              : 12.0;
      final verticalPadding = imageHeight >= 1500
          ? 12.0
          : imageHeight >= 800
              ? 8.0
              : 6.0;
      final horizontalPadding = imageHeight >= 1500
          ? 16.0
          : imageHeight >= 800
              ? 12.0
              : 8.0;
      final borderRadius = imageHeight >= 800 ? 8.0 : 6.0;
      final strokeWidth = photosessionWatermarkStrokeWidth(fontSize);
      final textSize = measurePhotosessionWatermarkLabel(
        fontSize: fontSize,
        strokeWidth: strokeWidth,
      );

      final blockWidth = textSize.width + horizontalPadding * 2;
      final blockHeight = textSize.height + verticalPadding * 2;
      final x = imageWidth - blockWidth - padding;
      final y = imageHeight - blockHeight - padding;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(sourceImage, Offset.zero, Paint());

      final shadowRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2, y - 2, blockWidth + 4, blockHeight + 4),
        Radius.circular(borderRadius),
      );
      canvas.drawRRect(
        shadowRect,
        Paint()..color = const Color(0xB4000000),
      );

      final backgroundRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, blockWidth, blockHeight),
        Radius.circular(borderRadius),
      );
      canvas.drawRRect(
        backgroundRect,
        Paint()..color = const Color(0x99000000),
      );

      paintPhotosessionWatermarkLabel(
        canvas,
        Offset(x + horizontalPadding, y + verticalPadding),
        fontSize: fontSize,
        fillColor: Colors.white,
        strokeWidth: strokeWidth,
      );

      final picture = recorder.endRecording();
      final watermarkedImage =
          await picture.toImage(imageWidth, imageHeight);
      sourceImage.dispose();

      final pngData = await watermarkedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      watermarkedImage.dispose();
      if (pngData == null) {
        debugPrint('🔴 WATERMARK: Не удалось закодировать изображение');
        return imageBytes;
      }

      final decoded = img.decodeImage(pngData.buffer.asUint8List());
      if (decoded == null) {
        debugPrint('🔴 WATERMARK: Не удалось декодировать изображение');
        return imageBytes;
      }

      final watermarkedBytes = img.encodeJpg(decoded, quality: 95);
      debugPrint(
        '✅ WATERMARK: Добавлен на изображение '
        '(${imageWidth}x$imageHeight, блок: ${blockWidth.round()}x${blockHeight.round()})',
      );
      return Uint8List.fromList(watermarkedBytes);
    } catch (e) {
      debugPrint('🔴 WATERMARK: Ошибка наложения watermark: $e');
      return imageBytes;
    }
  }

  Future<void> _saveToGallery(String imageUrl) async {
    setState(() => _saving = true);
    try {
      final service = ProxiedImageService();
      var bytes = await service.downloadImage(imageUrl);
      if (bytes == null) throw Exception('Не удалось загрузить изображение');

      // Проверяем, нужен ли watermark (для free/trial пользователей)
      final creditUsage = ref.read(creditUsageNotifierProvider).valueOrNull;
      final shouldAddWatermark = creditUsage != null &&
          (creditUsage.isFreeUser || creditUsage.isTrialUser);

      // Накладываем watermark если нужно
      if (shouldAddWatermark) {
        debugPrint('🔍 SAVE: Пользователь free/trial - накладываем watermark');
        bytes = await _addWatermarkToImage(bytes);
      }

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'photosession_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) await Gal.requestAccess(toAlbum: true);

      await Gal.putImage(filePath, album: 'AI Video Maker');

      if (!mounted) return;
      final palette = PhotosessionPalette.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Фото сохранено в галерею'),
          backgroundColor: palette.success,
        ),
      );

      await file.delete();
    } catch (e) {
      if (!mounted) return;
      final palette = PhotosessionPalette.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kDebugMode ? 'Ошибка: $e' : 'Не удалось сохранить фото',
          ),
          backgroundColor: palette.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareImage(String imageUrl) async {
    setState(() => _saving = true);
    File? tempFile;
    try {
      final service = ProxiedImageService();
      var bytes = await service.downloadImage(imageUrl);
      if (bytes == null) throw Exception('Не удалось загрузить изображение');

      // Проверяем, нужен ли watermark (для free/trial пользователей)
      final creditUsage = ref.read(creditUsageNotifierProvider).valueOrNull;
      final shouldAddWatermark = creditUsage != null &&
          (creditUsage.isFreeUser || creditUsage.isTrialUser);

      // Накладываем watermark если нужно
      if (shouldAddWatermark) {
        debugPrint('🔍 SHARE: Пользователь free/trial - накладываем watermark');
        bytes = await _addWatermarkToImage(bytes);
      }

      final tempDir = await getTemporaryDirectory();
      final fileName =
          'photosession_${DateTime.now().millisecondsSinceEpoch}.jpg';
      tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);

      if (mounted) setState(() => _saving = false);

      await Share.shareXFiles(
        [XFile(tempFile.path, mimeType: 'image/jpeg', name: fileName)],
        subject: 'Моё AI-изображение',
      );

      _scheduleFileDeletion(tempFile);
    } catch (e) {
      debugPrint('Ошибка при шеринге: $e');
      if (mounted) {
        final palette = PhotosessionPalette.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Не удалось поделиться'),
            backgroundColor: palette.danger,
          ),
        );
      }
      if (tempFile != null) _scheduleFileDeletion(tempFile);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _scheduleFileDeletion(File file) {
    Future.delayed(const Duration(seconds: 30), () async {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    });
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

  void _goToPhotosessionHome() {
    final task = _findTask();
    final success = task != null && !task.isActive && !task.isError;
    if (success) {
      ref.read(postPhotosessionReviewHomeTriggerProvider.notifier).state = true;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeNavigationScreen()),
      (route) => false,
    );
  }

  void _scheduleGenerationTutorialIfNeeded({bool force = false}) {
    if (!mounted || _isTutorialVisible) return;

    final palette = PhotosessionPalette.of(context);

    runPhotosessionAutoTutorialChain(
      context: context,
      ref: ref,
      force: force,
      scenario: PhotosessionTutorialScenario.generation,
      schedulingGateOk: () => mounted && !_isTutorialVisible,
      buildTargets: _buildGenerationTutorialTargets,
      getDidTryAuto: () => _didTryAutoTutorial,
      setDidTryAuto: (v) => _didTryAutoTutorial = v,
      getChainActive: () => _generationAutoTutorialChain,
      setChainActive: (v) => _generationAutoTutorialChain = v,
      onShow: (targets) {
        final store = ref.read(photosessionTutorialStoreProvider);
        _isTutorialVisible = true;
        TutorialCoachMark(
          targets: targets,
          colorShadow: palette.depth,
          opacityShadow: 0.78,
          hideSkip: true,
          paddingFocus: 0,
          pulseEnable: false,
          beforeFocus:
              photosessionTutorialBeforeFocus(targets, hasImages: true),
          onFinish: () async {
            _isTutorialVisible = false;
            await store.markSeen(PhotosessionTutorialScenario.generation);
            // После tutorial показываем offer sheet для free пользователей
            _showPostGenerationOfferIfNeeded();
          },
          onSkip: () {
            _isTutorialVisible = false;
            store.markSeen(PhotosessionTutorialScenario.generation);
            // После tutorial показываем offer sheet для free пользователей
            _showPostGenerationOfferIfNeeded();
            return true;
          },
        ).showForPhotosession(context);
      },
    );
  }

  /// Показывает soft-paywall после первой генерации для free пользователей
  void _showPostGenerationOfferIfNeeded() {
    if (!mounted) return;

    // Показываем offer sheet асинхронно
    Future.microtask(() async {
      if (!mounted) return;

      final task = _findTask();
      final previewUrl = task?.presetPreviewUrl;

      await showPostGenerationOfferIfNeeded(
        context: context,
        ref: ref,
        previewImageUrl: previewUrl,
      );
    });
  }

  List<TargetFocus> _buildGenerationTutorialTargets() {
    final task = _findTask();
    if (task == null) return const [];

    final screenH = MediaQuery.sizeOf(context).height;
    // Фиксированный offset от screenH, независимый от высоты изображения —
    // не скачет при дозагрузке layout в beforeFocus.
    final imageBubbleOffset = Offset(0, -(screenH * 0.38));
    const defaultTutorialPadding =
        EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    const imageTutorialPadding =
        EdgeInsets.symmetric(horizontal: 16, vertical: 12);

    final steps = <({
      GlobalKey key,
      String id,
      String title,
      String description,
      IconData icon,
      ContentAlign align,
      double paddingFocus,
      Offset contentOffset,
      EdgeInsets contentPadding,
    })>[];

    if (_imageAreaKey.currentContext != null) {
      steps.add((
        key: _imageAreaKey,
        id: 'generation_image',
        title: task.isActive ? 'Генерация идёт в фоне' : 'Ваш результат',
        description: task.isActive
            ? 'Пока изображение создаётся, можно спокойно вернуться назад: задача продолжит выполняться в фоне и появится на витрине.'
            : 'Нажмите на изображение, чтобы открыть его крупно и проверить детали лица, одежды и света перед сохранением.',
        icon: task.isActive ? Icons.hourglass_top_rounded : Icons.photo_rounded,
        align: ContentAlign.bottom,
        paddingFocus: 10,
        contentOffset: imageBubbleOffset,
        contentPadding: imageTutorialPadding,
      ));
    }

    if (!task.isActive && !task.isError) {
      if (_saveButtonKey.currentContext != null) {
        steps.add((
          key: _saveButtonKey,
          id: 'generation_save',
          title: 'Сохраните фото',
          description:
              'Если вариант получился удачным, сохраняйте его в галерею. Так вы сможете вернуться к лучшим кадрам позже и сравнить разные генерации.',
          icon: Icons.download_rounded,
          align: ContentAlign.top,
          paddingFocus: 10,
          contentOffset: Offset.zero,
          contentPadding: defaultTutorialPadding,
        ));
      }
      if (_shareButtonKey.currentContext != null) {
        steps.add((
          key: _shareButtonKey,
          id: 'generation_share',
          title: 'Поделитесь результатом',
          description:
              'Отправьте фото друзьям, клиенту или в соцсети прямо отсюда. Это удобно, если хотите быстро показать идею и собрать обратную связь.',
          icon: Icons.share_rounded,
          align: ContentAlign.top,
          paddingFocus: 10,
          contentOffset: Offset.zero,
          contentPadding: defaultTutorialPadding,
        ));
      }
      if (task.taskType == GenerationTaskType.userImage &&
          _communityKey.currentContext != null) {
        steps.add((
          key: _communityKey,
          id: 'generation_community',
          title: 'Поделитесь с сообществом',
          description:
              'Откройте изображение для сообщества — другие смогут создать своё по этой идее. За каждый лайк вы получите 1 кредит (максимум 50).',
          icon: Icons.public_rounded,
          align: ContentAlign.top,
          paddingFocus: 10,
          contentOffset: Offset.zero,
          contentPadding: defaultTutorialPadding,
        ));
      }
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
          paddingFocus: steps[i].paddingFocus,
          contentOffset: steps[i].contentOffset,
          contentPadding: steps[i].contentPadding,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final task = _findTask();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (task == null) {
      return PhotosessionThemeScope(
          child: Scaffold(
        appBar: AppBar(
          backgroundColor: colors.surfaceContainerLowest,
          foregroundColor: colors.onSurface,
          surfaceTintColor: Colors.transparent,
          title: const Text('Генерация'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: colors.onSurface.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Задача не найдена',
                style: TextStyle(
                  color: colors.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      ));
    }

    if (task.isActive) {
      _wasEverLoading = true;
      _animatedToResult = false;
    }

    // Туториал запускается через onLoaded у ProxiedNetworkImage — после отображения фото

    final String appBarTitle;
    if (task.isActive) {
      appBarTitle = 'Создание...';
    } else if (task.isError) {
      appBarTitle = 'Ошибка';
    } else {
      appBarTitle = 'Готово!';
    }

    final scaffold = Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.surfaceContainerLowest,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        leading: task.isError
            ? null
            : IconButton(
                onPressed: _goToPhotosessionHome,
                tooltip: 'На главный экран',
                icon: const Icon(Icons.home_rounded),
              ),
        title: Text(
          appBarTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          PhotosessionTutorialHelpButton(
            onPressed: () => _scheduleGenerationTutorialIfNeeded(force: true),
            compact: true,
            plain: true,
          ),
        ],
      ),
      body: task.isActive
          ? _buildLoadingState(task, colors)
          : task.isError
              ? _buildErrorState(task, colors)
              : _buildResultState(task, colors),
    );

    return PhotosessionThemeScope(child: scaffold);
  }

  // ---------------------------------------------------------------------------
  // Loading state — skeleton UI с magic shimmer
  // ---------------------------------------------------------------------------

  Widget _buildLoadingState(GenerationTask task, ColorScheme colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyedSubtree(
            key: _imageAreaKey,
            child: _buildPhotoSkeleton(colors),
          ),
          const SizedBox(height: 24),
          // Статус занимает точно ту же высоту, что и кнопки в результате
          // (Row 52 + gap 16 + button 48 = 116)
          SizedBox(
            height: 116,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    task.statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Можете вернуться — генерация продолжится в фоне',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSkeleton(ColorScheme colors) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, _) {
        final t = _shimmerController.value;
        final sweep = t * 3 - 1;
        final pulse = math.sin(t * 2 * math.pi);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withOpacity(0.06 + 0.04 * pulse),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(color: colors.surfaceContainerHighest),
                  ),
                  Positioned.fill(
                    child: _MagicGradientSweep(
                      sweep: sweep,
                      primaryColor: colors.primary,
                      tertiaryColor: colors.tertiary,
                      baseColor: colors.surfaceContainerHighest,
                    ),
                  ),
                  Center(
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      size: 48,
                      color: colors.primary
                          .withOpacity(0.12 + 0.08 * pulse.clamp(0, 1)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Error state
  // ---------------------------------------------------------------------------

  Widget _buildErrorState(GenerationTask task, ColorScheme colors) {
    final isBalanceError = isPhotosessionBalanceError(task.errorMessage);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: colors.errorContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: colors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              task.displayError,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: colors.onSurface.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isBalanceError
                  ? 'Пополните баланс и запустите генерацию снова.'
                  : buildPhotosessionSupportAdvice(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurface.withOpacity(0.65),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: isBalanceError
                  ? () => Navigator.of(context).push(tokenPurchaseRoute())
                  : _retry,
              icon: Icon(
                isBalanceError
                    ? Icons.account_balance_wallet_rounded
                    : Icons.refresh_rounded,
              ),
              label: Text(
                isBalanceError ? 'Купить кредиты' : 'Попробовать снова',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (!isBalanceError) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => contactPhotosessionSupport(
                  context,
                  rawError: task.errorMessage,
                ),
                icon: const Icon(Icons.email_outlined),
                label: const Text('Написать на почту'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(200, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Вернуться назад'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Result state — fade-in + scale при переходе из loading
  // ---------------------------------------------------------------------------

  Widget _buildResultState(GenerationTask task, ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    if (!_animatedToResult) {
      _animatedToResult = true;
      if (_wasEverLoading) {
        _shimmerController.stop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _resultController.forward(from: 0);
        });
      }
    }

    final resultUrl = task.resultImageUrl!;
    final isUserImage = task.taskType == GenerationTaskType.userImage;

    // Проверяем, нужен ли watermark (для free/trial пользователей)
    final creditUsage = ref.watch(creditUsageNotifierProvider).valueOrNull;
    final shouldShowWatermark = creditUsage != null &&
        (creditUsage.isFreeUser || creditUsage.isTrialUser);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: KeyedSubtree(
              key: _imageAreaKey,
              child: GestureDetector(
                onTap: () => _openFullscreen(
                  resultUrl,
                  'result_${task.presetId}',
                ),
                child: Hero(
                  tag: 'result_${task.presetId}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ProxiedNetworkImage(
                          url: resultUrl,
                          // Форматов кадра теперь много (квадрат, сторис,
                          // альбом), поэтому показываем результат целиком.
                          fit: isUserImage ? BoxFit.contain : BoxFit.cover,
                          loadingBuilder: (context) =>
                              _buildImageLoadShimmer(colors),
                          errorBuilder: (context) => Container(
                            color: colors.surfaceContainerHighest,
                            child:
                                const Center(child: Icon(Icons.broken_image)),
                          ),
                          onLoaded: _scheduleGenerationTutorialIfNeeded,
                        ),
                        if (shouldShowWatermark)
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: palette.depth.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 16,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  PhotosessionWatermarkLabel(fontSize: 12),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        FadeTransition(
          opacity: _resultFade,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: _saveButtonKey,
                        onPressed:
                            _saving ? null : () => _saveToGallery(resultUrl),
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_rounded),
                        label: const Text(
                          'Сохранить',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: _shareButtonKey,
                        onPressed:
                            _saving ? null : () => _shareImage(resultUrl),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text(
                          'Поделиться',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (isUserImage) ...[
                  const SizedBox(height: 8),
                  _buildCommunityToggle(task, colors),
                ],
                const SizedBox(height: 8),
                FilledButton(
                  key: _doneButtonKey,
                  onPressed: _goToPhotosessionHome,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Готово',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommunityToggle(GenerationTask task, ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    return KeyedSubtree(
      key: _communityKey,
      child: Material(
        color: colors.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: task.createdPresetId == null
              ? null
              : () => _togglePublic(task, colors),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Switch(
                  value: _makePublic,
                  onChanged: task.createdPresetId == null
                      ? null
                      : (_) => _togglePublic(task, colors),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _makePublic ? 'Сделать приватным' : 'Сделать публичным',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      Text(
                        _makePublic
                            ? 'Пресет опубликован: 1 лайк = 1 кредит'
                            : '1 лайк = 1 кредит',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.public,
                  size: 20,
                  color: _makePublic
                      ? palette.success
                      : colors.onSurface.withOpacity(0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _togglePublic(GenerationTask task, ColorScheme colors) async {
    final presetId = task.createdPresetId;
    if (presetId == null) return;
    final newValue = !_makePublic;
    if (!newValue) {
      final allowed = await ensurePrivatePresetAccess(context, ref);
      if (!allowed || !mounted) return;
    }
    setState(() => _makePublic = newValue);
    try {
      final repo = ref.read(showcaseRepositoryProvider);
      if (newValue) {
        final tagService = ref.read(presetTagServiceProvider);
        await tagService.updateTagsForPublicPreset(presetId, task.prompt);
        await repo.makePublic(presetId);
        if (mounted) {
          final palette = PhotosessionPalette.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Пресет опубликован! Получайте кредиты за каждый лайк'),
              backgroundColor: palette.success,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else {
        await repo.makePrivate(presetId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Пресет скрыт из публичного каталога'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Ошибка изменения публичности: $e');
      if (mounted) setState(() => _makePublic = !newValue);
    }
  }

  Widget _buildImageLoadShimmer(ColorScheme colors) {
    return Shimmer.fromColors(
      baseColor: colors.surfaceContainerHighest,
      highlightColor: colors.surface,
      period: const Duration(milliseconds: 1600),
      child: Container(
        color: colors.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.photo_rounded,
            size: 48,
            color: colors.onSurface.withOpacity(0.08),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Magic gradient sweep — отдельный виджет для чистоты кода
// -----------------------------------------------------------------------------

class _MagicGradientSweep extends StatelessWidget {
  const _MagicGradientSweep({
    required this.sweep,
    required this.primaryColor,
    required this.tertiaryColor,
    required this.baseColor,
  });

  final double sweep;
  final Color primaryColor;
  final Color tertiaryColor;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    final palette = PhotosessionPalette.of(context);
    return ShaderMask(
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment(sweep, -0.5),
          end: Alignment(sweep + 1.5, 0.5),
          colors: [
            Colors.transparent,
            primaryColor.withOpacity(0.1),
            palette.textPrimary.withValues(alpha: 0.28),
            tertiaryColor.withOpacity(0.1),
            Colors.transparent,
          ],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.srcATop,
      child: Container(color: baseColor),
    );
  }
}
