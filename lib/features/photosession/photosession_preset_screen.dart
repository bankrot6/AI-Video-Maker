import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/credit_config.dart';
import '../../models/photo_session_preset.dart';
import '../../models/photosession_provider.dart';
import '../../models/user_generation.dart';
import '../../providers/credit_providers.dart';
import '../../services/prompt_sections.dart';
import '../../services/proxied_image_service.dart';
import '../../widgets/credit_counter_widget.dart';
import '../../widgets/preset_like_chip.dart';
import '../../widgets/edit_text/full_screen_text_editor_screen.dart';
import 'background_generation_provider.dart';
import '../subscription/paid_feature_gate.dart';
import '../subscription/purchase_routes.dart';
import 'fullscreen_image_viewer.dart';
import 'photosession_generation_screen.dart';
import 'photosession_providers.dart';
import 'preset_likes_provider.dart';
import 'photosession_support_error.dart';
import 'theme/photosession_palette.dart';
import 'theme/photosession_theme_scope.dart';
import 'tutorial/photosession_tutorial.dart';
import 'widgets/photosession_segmented_tabs.dart';
import 'widgets/photosession_watermark_label.dart';
import '../../widgets/generated_media_view.dart';

class PhotosessionPresetScreen extends ConsumerStatefulWidget {
  const PhotosessionPresetScreen({super.key, required this.preset});

  final PhotoSessionPreset preset;

  @override
  ConsumerState<PhotosessionPresetScreen> createState() =>
      _PhotosessionPresetScreenState();
}

class _PhotosessionPresetScreenState
    extends ConsumerState<PhotosessionPresetScreen> {
  final Map<String, String> _editedSections = {};
  int _selectedTab = 0;
  bool _usageTipsExpanded = false;
  List<UserGeneration> _generations = [];
  PhotosessionProvider _selectedProvider = PhotosessionProvider.veoFast;
  final _samplePhotoKey = GlobalKey();
  final _usageTipsSectionKey = GlobalKey();
  final _settingsSectionKey = GlobalKey();
  final _modelSelectorKey = GlobalKey();
  final _generateButtonKey = GlobalKey();
  final _publicityCardKey = GlobalKey();

  bool get _isCustomPreset => widget.preset.hasTag('custom');

  bool get _isOwnPreset {
    final deviceId = ref.read(deviceIdProvider).value;
    return deviceId != null && widget.preset.ownerId == deviceId;
  }

  bool _presetDeleting = false;
  final Set<String> _deletingGenerationIds = {};
  bool _isTutorialVisible = false;
  bool _didTryAutoTutorial = false;
  bool _presetAutoTutorialChain = false;

  String get _fullscreenPresetImageUrl {
    final full = widget.preset.previewImageUrl.trim();
    if (full.isNotEmpty) return full;
    return widget.preset.displayImageUrl;
  }

  @override
  void initState() {
    super.initState();
    final thumb = widget.preset.displayImageUrl.trim();
    final full = widget.preset.previewImageUrl.trim();
    final prefetch = <String>[];
    if (thumb.isNotEmpty) prefetch.add(thumb);
    if (full.isNotEmpty && full != thumb) prefetch.add(full);
    if (prefetch.isNotEmpty) ProxiedImageService().prefetch(prefetch);
    _loadGenerations();
    Future.microtask(
      () => ref.read(creditUsageNotifierProvider.notifier).refreshFromServer(),
    );
  }

  Future<void> _loadGenerations() async {
    try {
      final deviceId = ref.read(deviceIdProvider).value ??
          await ref.read(deviceIdProvider.future);
      final repo = ref.read(userGenerationRepositoryProvider);
      final generations = await repo.getGenerationsByPreset(
        widget.preset.id,
        deviceId: deviceId!,
      );
      if (mounted) setState(() => _generations = generations);
    } catch (e) {
      debugPrint('Ошибка загрузки генераций: $e');
    }
  }

  Future<void> _onDeletePresetPressed() async {
    final allowed = await ensureDeleteAccess(context, ref);
    if (!allowed || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Удалить пресет?'),
          content: const Text(
            'Пресет и вся история генераций по нему будут удалены с сервера. '
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
    await _executeDeletePreset();
  }

  Future<void> _executeDeletePreset() async {
    final palette = PhotosessionPalette.of(context);
    final deviceId = ref.read(deviceIdProvider).value ??
        await ref.read(deviceIdProvider.future);
    if (deviceId == null || !mounted) return;
    setState(() => _presetDeleting = true);
    try {
      final genRepo = ref.read(userGenerationRepositoryProvider);
      for (final g in List<UserGeneration>.from(_generations)) {
        if (!mounted) return;
        await genRepo.deleteGeneration(
          g.id,
          deviceId: deviceId,
          presetId: widget.preset.id,
        );
      }
      await ref.read(showcaseRepositoryProvider).deletePreset(
            widget.preset.id,
            ownerDeviceId: deviceId,
          );
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
    if (deviceId == null) return;
    setState(() => _deletingGenerationIds.add(generation.id));
    try {
      final ok =
          await ref.read(userGenerationRepositoryProvider).deleteGeneration(
                generation.id,
                deviceId: deviceId,
                presetId: widget.preset.id,
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

  Future<void> _startGeneration() async {
    final palette = PhotosessionPalette.of(context);
    try {
      final result =
          await ref.read(backgroundGenerationProvider.notifier).startGeneration(
                preset: widget.preset,
                prompt: _getEditedPrompt(),
                provider: _selectedProvider,
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

  Map<String, String> _parsePromptSections(String prompt) {
    final sections = PromptSections.parse(prompt);
    return {
      for (final key in sections.keys)
        PromptSections.displayTitle(key): sections[key] ?? '',
    };
  }

  String _getEditedPrompt() {
    final basePrompt = widget.preset.prompt;
    if (_editedSections.isEmpty) return basePrompt;

    var sections = PromptSections.parse(basePrompt);
    for (final key in sections.keys) {
      final edited = _editedSections[PromptSections.displayTitle(key)];
      if (edited != null) sections = sections.replace(key, edited);
    }
    return sections.compose();
  }

  Future<void> _editSection(String sectionName, String currentContent) async {
    final result = await FullScreenTextEditorScreen.open(
      context,
      title: sectionName,
      initialText: currentContent,
      hintText: 'Введите текст',
    );

    if (result != null && mounted) {
      setState(() => _editedSections[sectionName] = result);
    }
  }

  void _schedulePresetTutorialIfNeeded({bool force = false}) {
    if (!mounted || _isTutorialVisible || _usageTipsExpanded) return;

    final palette = PhotosessionPalette.of(context);

    runPhotosessionAutoTutorialChain(
      context: context,
      ref: ref,
      force: force,
      scenario: PhotosessionTutorialScenario.preset,
      schedulingGateOk: () =>
          mounted && !_isTutorialVisible && !_usageTipsExpanded,
      buildTargets: _buildPresetTutorialTargets,
      getDidTryAuto: () => _didTryAutoTutorial,
      setDidTryAuto: (v) => _didTryAutoTutorial = v,
      getChainActive: () => _presetAutoTutorialChain,
      setChainActive: (v) => _presetAutoTutorialChain = v,
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
            await store.markSeen(PhotosessionTutorialScenario.preset);
          },
          onSkip: () {
            _isTutorialVisible = false;
            store.markSeen(PhotosessionTutorialScenario.preset);
            return true;
          },
        ).showForPhotosession(context);
      },
    );
  }

  List<TargetFocus> _buildPresetTutorialTargets() {
    final steps = <({
      GlobalKey key,
      String id,
      String title,
      String description,
      IconData icon,
      ContentAlign align,
    })>[];

    final isImageTab = _selectedTab == 0;

    if (isImageTab && _usageTipsSectionKey.currentContext != null) {
      steps.add((
        key: _usageTipsSectionKey,
        id: 'preset_usage_tips',
        title: 'Советы для хорошего результата',
        description:
            'Здесь собраны рекомендации по работе с описанием сцены и есть кнопка запуска обучения. Если генерация вышла слабой, начните с этого блока.',
        icon: Icons.question_mark_rounded,
        align: ContentAlign.bottom,
      ));
    }

    if (!isImageTab && _settingsSectionKey.currentContext != null) {
      steps.add((
        key: _settingsSectionKey,
        id: 'preset_prompt',
        title: 'Исправьте описание сцены',
        description:
            'На вкладке «Промпт» собраны все блоки сцены: можно быстро поменять фон, образ, настроение и детали кадра, не переписывая описание целиком.',
        icon: Icons.tune_rounded,
        align: ContentAlign.bottom,
      ));
    }

    if (isImageTab && _samplePhotoKey.currentContext != null) {
      steps.add((
        key: _samplePhotoKey,
        id: 'preset_reference',
        title: 'Ориентир для результата',
        description:
            'Это образец сцены. Нажмите на него, чтобы рассмотреть детали: позу, стиль, одежду и атмосферу — именно это приложение будет стараться воссоздать.',
        icon: Icons.style_rounded,
        align: ContentAlign.bottom,
      ));
    }

    if (_modelSelectorKey.currentContext != null) {
      steps.add((
        key: _modelSelectorKey,
        id: 'preset_model',
        title: 'Выберите модель генерации',
        description:
            'Для первых тестов удобно начать с Veo 3.1 Lite: она быстрее и дешевле. Если нужно более детальное и качественное видео, выбирайте Veo 3.1 Fast или Pro.',
        icon: Icons.auto_awesome_mosaic_rounded,
        align: ContentAlign.top,
      ));
    }

    if (isImageTab && _publicityCardKey.currentContext != null) {
      steps.add((
        key: _publicityCardKey,
        id: 'preset_publicity',
        title: 'Сделайте пресет публичным',
        description:
            'Если пресет получился удачным, откройте его для сообщества. Публичные пресеты собирают лайки, а вы получаете кредиты за популярные работы.',
        icon: Icons.public_rounded,
        align: ContentAlign.top,
      ));
    }

    if (_generateButtonKey.currentContext != null) {
      steps.add((
        key: _generateButtonKey,
        id: 'preset_generate',
        title: 'Запустите генерацию',
        description:
            'Когда описание сцены вам нравится, запускайте генерацию. Потом можно сделать ещё версии с другой моделью или обновлённым описанием сцены.',
        icon: Icons.auto_awesome_rounded,
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    _schedulePresetTutorialIfNeeded();

    final scaffold = Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: colors.surfaceContainerLowest,
        foregroundColor: colors.onSurface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.preset.title ?? 'AI-видео',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          _buildLikeButton(),
          if (_isCustomPreset && _isOwnPreset) _buildDeletePresetButton(),
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: CreditCounterWidget(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: PhotosessionSegmentedTabs(
              selected: _selectedTab,
              onChanged: (index) => setState(() => _selectedTab = index),
              segments: const ['Видео', 'Промпт'],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedTab,
        children: [
          _buildImageTab(colors),
          _buildPromptTab(colors),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(colors),
    );

    return PhotosessionThemeScope(child: scaffold);
  }

  Widget _buildImageTab(ColorScheme colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPresetPreview(colors),
          const SizedBox(height: 16),
          if (!_isCustomPreset) ...[
            KeyedSubtree(
              key: _usageTipsSectionKey,
              child: _buildUsageTipsSection(colors),
            ),
            const SizedBox(height: 16),
          ],
          if (_isCustomPreset && _isOwnPreset) ...[
            KeyedSubtree(
              key: _publicityCardKey,
              child: _buildPublicityCard(colors),
            ),
            const SizedBox(height: 16),
          ],
          if (_generations.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildHistorySection(colors),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPresetPreview(ColorScheme colors) {
    return KeyedSubtree(
      key: _samplePhotoKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isCustomPreset ? 'ВАША СЦЕНА' : 'ОБРАЗЕЦ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withOpacity(0.5),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _openFullscreen(
              _fullscreenPresetImageUrl,
              'preset_${widget.preset.id}',
            ),
            child: Hero(
              tag: 'preset_${widget.preset.id}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: GeneratedMediaView(
                    url: widget.preset.displayImageUrl,
                    fit: BoxFit.cover,
                    onFullscreen: () => _openFullscreen(
                      _fullscreenPresetImageUrl,
                      'preset_${widget.preset.id}',
                    ),
                    loadingBuilder: (context) => Container(
                      color: colors.surfaceContainerHighest,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorBuilder: (context) => Container(
                      color: colors.surfaceContainerHighest,
                      child: const Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageTipsSection(ColorScheme colors) {
    return _buildExpandableSection(
      colors: colors,
      title: 'Как получить свой вариант этой сцены',
      expanded: _usageTipsExpanded,
      onToggle: () => setState(() => _usageTipsExpanded = !_usageTipsExpanded),
      leading: Tooltip(
        message: _usageTipsExpanded
            ? 'Сначала сверните блок с советами'
            : 'Показать подсказки',
        child: InkResponse(
          onTap: _usageTipsExpanded
              ? null
              : () => _schedulePresetTutorialIfNeeded(force: true),
          radius: 18,
          child: Icon(
            Icons.question_mark_rounded,
            size: 20,
            color: _usageTipsExpanded
                ? colors.onSurface.withOpacity(0.35)
                : colors.primary,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUsageTipItem(
            colors: colors,
            text:
                'Нажмите на образец, чтобы открыть его в полном размере.',
          ),
          _buildUsageTipItem(
            colors: colors,
            text:
                'В «Настройках сцены» отредактируйте описание — отдельные блоки или всё целиком.',
          ),
          _buildUsageTipItem(
            colors: colors,
            text:
                'Меняйте по одному блоку за раз, чтобы понять, что влияет на результат.',
          ),
          _buildUsageTipItem(
            colors: colors,
            text:
                'Каждый запуск создаёт новый вариант — генерируйте сцену несколько раз, пока не понравится.',
          ),
          _buildUsageTipItem(
            colors: colors,
            text:
                '«Вернуть оригинал» сбрасывает описание к исходному пресету.',
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
  }) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
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
          ),
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
      ),
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

  Widget _buildPublicityCard(ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    final isPublic = widget.preset.isPublic;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPublic
            ? palette.success.withValues(alpha: 0.14)
            : colors.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPublic ? palette.success : colors.outline.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPublic ? Icons.public : Icons.lock_outline,
            size: 20,
            color:
                isPublic ? palette.success : colors.onSurface.withOpacity(0.6),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPublic ? 'Публичный пресет' : 'Приватный пресет',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isPublic ? palette.success : colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPublic
                      ? 'Пресет видят все пользователи'
                      : 'Только вы видите этот пресет',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () async {
              if (isPublic) {
                final allowed = await ensurePrivatePresetAccess(context, ref);
                if (!allowed || !mounted) return;
              }
              try {
                final repo = ref.read(showcaseRepositoryProvider);
                if (isPublic) {
                  await repo.makePrivate(widget.preset.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Пресет теперь приватный'),
                        backgroundColor: palette.success,
                      ),
                    );
                  }
                } else {
                  final tagService = ref.read(presetTagServiceProvider);
                  await tagService.updateTagsForPublicPreset(
                    widget.preset.id,
                    widget.preset.prompt,
                  );
                  await repo.makePublic(widget.preset.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Пресет теперь публичный!'),
                        backgroundColor: palette.success,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Ошибка: $e'),
                    backgroundColor: palette.danger,
                  ),
                );
              }
            },
            icon: Icon(
              isPublic ? Icons.lock_outline : Icons.public,
              size: 18,
            ),
            label: Text(
              isPublic ? 'Скрыть' : 'Поделиться',
              style: const TextStyle(fontSize: 13),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptTab(ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    final sections = _parsePromptSections(widget.preset.prompt);

    return SingleChildScrollView(
      key: _settingsSectionKey,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.primary.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Icon(Icons.touch_app_rounded, size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Нажмите на блок, чтобы изменить его',
                    style: TextStyle(fontSize: 12, color: colors.primary),
                  ),
                ),
                if (_editedSections.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: palette.warning.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Изменено',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: palette.warning,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...sections.entries.map((entry) {
            final sectionName = entry.key;
            final sectionContent = _editedSections[sectionName] ?? entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PromptSectionCard(
                title: sectionName,
                content: sectionContent,
                isEdited: _editedSections.containsKey(sectionName),
                onTap: () => _editSection(sectionName, sectionContent),
                colors: colors,
              ),
            );
          }),
          if (_editedSections.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => setState(() => _editedSections.clear()),
                icon: const Icon(Icons.restore_rounded, size: 20),
                label: const Text('Вернуть оригинал'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    final creditUsage = ref.watch(creditUsageNotifierProvider).valueOrNull;
    final shouldShowWatermark = creditUsage != null &&
        (creditUsage.isFreeUser || creditUsage.isTrialUser);

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
                      'generation_${generation.id}',
                    ),
                    child: Hero(
                      tag: 'generation_${generation.id}',
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          GeneratedMediaThumbnail(
                            url: generation.resultImageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context) => Container(
                              color: colors.surfaceContainerHighest,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            ),
                            errorBuilder: (context) => Container(
                              color: colors.surfaceContainerHighest,
                              child: const Center(
                                  child: Icon(Icons.broken_image, size: 20)),
                            ),
                          ),
                          if (shouldShowWatermark)
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: palette.depth.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 10,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(width: 3),
                                    PhotosessionWatermarkLabel(fontSize: 8),
                                  ],
                                ),
                              ),
                            ),
                        ],
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

  Widget _buildBottomBar(ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    final usage = ref.watch(creditUsageNotifierProvider).valueOrNull;
    final isTierLocked = usage != null &&
        (usage.isFreeUser || usage.isTrialUser) &&
        !CreditCost.isTierAvailableForTrial(_selectedProvider.creditTier);
    final hasEnoughCredits =
        usage == null || usage.hasEnoughCredits(_selectedProvider.creditCost);
    final canGenerate = !isTierLocked && hasEnoughCredits;
    final hasGenerations = _generations.isNotEmpty;

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
          _buildProviderSelector(colors),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: _generateButtonKey,
            onPressed: canGenerate
                ? _startGeneration
                : () => Navigator.of(context).push(tokenPurchaseRoute()),
            icon: Icon(
              canGenerate
                  ? Icons.auto_awesome_rounded
                  : Icons.account_balance_wallet_rounded,
              size: 22,
            ),
            label: Text(
              canGenerate
                  ? (hasGenerations
                      ? 'Сгенерировать ещё раз'
                      : 'Сгенерировать видео')
                  : isTierLocked
                      ? 'Нужен PRO'
                      : 'Купить кредиты',
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
    return OutlinedButton(
      key: _modelSelectorKey,
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
          Icon(
            _providerIcon(_selectedProvider),
            size: 22,
            color: colors.primary,
          ),
          const SizedBox(width: 10),
          Text(
            _selectedProvider.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
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
    final palette = PhotosessionPalette.of(context);
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
                      children: PhotosessionProvider.values
                          .where((p) => p.isAvailable)
                          .map((p) {
                        final isSelected = _selectedProvider == p;
                        final usage =
                            ref.read(creditUsageNotifierProvider).valueOrNull;
                        final isLocked = usage != null &&
                            (usage.isFreeUser || usage.isTrialUser) &&
                            !CreditCost.isTierAvailableForTrial(p.creditTier);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: isLocked
                                  ? () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Модель доступна только подписчикам',
                                          ),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  : () {
                                      setState(() => _selectedProvider = p);
                                      Navigator.pop(context);
                                    },
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: colors.surfaceContainerHighest
                                              .withOpacity(0.6),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          isLocked
                                              ? Icons.lock_rounded
                                              : _providerIcon(p),
                                          size: 24,
                                          color: isSelected && !isLocked
                                              ? colors.primary
                                              : colors.onSurface
                                                  .withOpacity(0.6),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    p.label,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: colors.onSurface,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                if (p.sourceBadge != null) ...[
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: palette.accent
                                                          .withValues(
                                                              alpha: 0.16),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              5),
                                                    ),
                                                    child: Text(
                                                      p.sourceBadge!,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: palette.accent,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                ],
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: isLocked
                                                        ? colors.outline
                                                            .withOpacity(0.1)
                                                        : colors.primary
                                                            .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: Text(
                                                    isLocked ? 'PRO' : p.price,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: isLocked
                                                          ? colors.outline
                                                          : colors.primary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              isLocked
                                                  ? 'Доступна с подпиской PRO'
                                                  : p.description,
                                              style: TextStyle(
                                                fontSize: 13,
                                                height: 1.4,
                                                color: colors.onSurface
                                                    .withOpacity(0.7),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected && !isLocked)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 8),
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
                          ),
                        );
                      }).toList(),
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

  IconData _providerIcon(PhotosessionProvider p) {
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

  Widget _buildLikeButton() {
    final palette = PhotosessionPalette.of(context);
    final deviceId = ref.watch(deviceIdProvider).value;
    if (deviceId == null) return const SizedBox.shrink();

    ref.watch(presetLikesProvider);
    final likes = ref.read(presetLikesProvider.notifier);
    final snapshot = likes.resolve(widget.preset);
    final isLiked = snapshot.likedBy.contains(deviceId);

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: PresetLikeChip(
        count: snapshot.likesCount,
        isLiked: isLiked,
        busy: false,
        style: PresetLikeChipStyle.appBarPlain,
        onPressed: likes.isPending(widget.preset.id)
            ? null
            : () async {
                try {
                  await likes.toggle(widget.preset, deviceId);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка: $e'),
                      backgroundColor: palette.danger,
                    ),
                  );
                }
              },
      ),
    );
  }
}

class _PromptSectionCard extends StatelessWidget {
  const _PromptSectionCard({
    required this.title,
    required this.content,
    required this.isEdited,
    required this.onTap,
    required this.colors,
  });

  final String title;
  final String content;
  final bool isEdited;
  final VoidCallback onTap;
  final ColorScheme colors;

  IconData _getIconForSection(String title) {
    if (title.contains('Сохранение')) return Icons.face;
    if (title.contains('сцены') || title.contains('Описание')) {
      return Icons.landscape;
    }
    if (title.contains('Персонаж')) return Icons.person_outline;
    if (title.contains('Объекты')) return Icons.category_outlined;
    if (title.contains('Атмосфера')) return Icons.palette_outlined;
    if (title.contains('палитра')) return Icons.color_lens_outlined;
    if (title.contains('Технические')) return Icons.camera_outlined;
    return Icons.article_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final palette = PhotosessionPalette.of(context);
    final cardBg = colors.surfaceContainerHighest;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: palette.depth.withValues(alpha: 0.26),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: colors.outline.withOpacity(0.1)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: colors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getIconForSection(title),
                        size: 16,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    if (isEdited)
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: palette.warning,
                          shape: BoxShape.circle,
                        ),
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurface.withOpacity(0.3),
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
