import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/credit_config.dart';
import '../../models/generation_task.dart';
import '../../models/image_generation_request.dart';
import '../../models/photo_session_preset.dart';
import '../../models/photosession_provider.dart';
import '../../models/preset_tag.dart';
import '../../providers/credit_providers.dart';
import '../../services/prompt_sections.dart';
import '../../widgets/edit_text/full_screen_text_editor_screen.dart';
import 'background_generation_provider.dart';
import 'photosession_generation_screen.dart';
import 'photosession_providers.dart';
import 'photosession_support_error.dart';
import 'theme/photosession_palette.dart';
import 'theme/photosession_theme_scope.dart';
import 'tutorial/photosession_tutorial.dart';
import 'widgets/photosession_segmented_tabs.dart';
import '../subscription/purchase_routes.dart';

class CustomPresetCreationScreen extends ConsumerStatefulWidget {
  const CustomPresetCreationScreen({super.key});

  @override
  ConsumerState<CustomPresetCreationScreen> createState() =>
      _CustomPresetCreationScreenState();
}

class _CustomPresetCreationScreenState
    extends ConsumerState<CustomPresetCreationScreen>
    with TickerProviderStateMixin {
  static const int _sceneFieldMinLines = 3;
  static const int _sceneFieldMaxLines = 8;

  static ButtonStyle _brownActionButtonStyle(PhotosessionPalette palette) =>
      FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.background,
        disabledBackgroundColor: palette.surface,
        disabledForegroundColor: palette.textSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      );

  static ButtonStyle _oliveOutlineButtonStyle(PhotosessionPalette palette) =>
      OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: palette.surfaceHigh.withValues(alpha: 0.45),
        foregroundColor: palette.accent,
        disabledForegroundColor: palette.textSecondary,
        side: BorderSide(color: palette.accentMuted, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      );

  final _ideaController = TextEditingController();
  final _textOnImageController = TextEditingController();
  final _detailsController = TextEditingController();
  final _scrollController = ScrollController();

  final _ideaFocus = FocusNode();
  final _textOnImageFocus = FocusNode();
  final _detailsFocus = FocusNode();

  final _ideaKey = GlobalKey();
  final _textOnImageKey = GlobalKey();
  final _detailsKey = GlobalKey();
  final _descriptionButtonKey = GlobalKey();
  final _segmentedTabsKey = GlobalKey();
  final _promptCardKey = GlobalKey();
  final _photoModelSelectorKey = GlobalKey();
  final _photoGenerateButtonKey = GlobalKey();

  int _selectedTab = 0;
  ImageStyle _selectedStyle = ImageStyle.auto;
  ImageFormat _selectedFormat = ImageFormat.portrait;
  ImageMood _selectedMood = ImageMood.auto;
  String? _generatedPrompt;
  final Map<String, String> _editedSections = {};
  bool _loading = false;
  String? _error;
  int _revealedSectionCount = 0;
  PhotosessionProvider _selectedProvider = PhotosessionProvider.googleFlash;
  bool _isTutorialVisible = false;
  bool _didTryAutoTutorial = false;
  bool _didTryResultTutorial = false;
  bool _customAutoTutorialChain = false;
  static const _shimmerSectionTitles = [
    'Главный объект',
    'Окружение и фон',
    'Композиция',
    'Свет',
    'Цвет и стиль',
    'Детали',
    'Технические параметры',
  ];

  @override
  void initState() {
    super.initState();
    void onDescriptionFocusChanged() {
      if (mounted) setState(() {});
    }

    _ideaFocus
      ..addListener(onDescriptionFocusChanged)
      ..addListener(() => _scrollToFieldOnFocus(_ideaFocus, _ideaKey));
    _textOnImageFocus
      ..addListener(onDescriptionFocusChanged)
      ..addListener(
        () => _scrollToFieldOnFocus(_textOnImageFocus, _textOnImageKey),
      );
    _detailsFocus
      ..addListener(onDescriptionFocusChanged)
      ..addListener(() => _scrollToFieldOnFocus(_detailsFocus, _detailsKey));

    for (final controller in [
      _ideaController,
      _textOnImageController,
      _detailsController,
    ]) {
      controller.addListener(_handleDescriptionInputChanged);
    }

    Future.microtask(
      () => ref.read(creditUsageNotifierProvider.notifier).refreshFromServer(),
    );
  }

  void _handleDescriptionInputChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _dismissKeyboard() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus && currentFocus.focusedChild != null) {
      currentFocus.unfocus();
    }
  }

  bool _descriptionCompactInputMode(BuildContext context) {
    if (_selectedTab != 0) return false;
    return MediaQuery.viewInsetsOf(context).bottom > 0;
  }

  void _scrollToFieldOnFocus(FocusNode focusNode, GlobalKey key) {
    if (focusNode.hasFocus && mounted) {
      Future.delayed(const Duration(milliseconds: 350), () {
        final context = key.currentContext;
        if (context != null && mounted) {
          final renderBox = context.findRenderObject() as RenderBox?;
          if (renderBox != null) {
            final fieldHeight = renderBox.size.height;
            final screenHeight = MediaQuery.of(this.context).size.height;
            final keyboardHeight =
                MediaQuery.of(this.context).viewInsets.bottom;

            final visibleHeight = screenHeight - keyboardHeight;
            final targetPosition =
                (visibleHeight - fieldHeight - 100) / visibleHeight;

            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: targetPosition.clamp(0.0, 0.3),
            );
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _ideaController.dispose();
    _textOnImageController.dispose();
    _detailsController.dispose();
    _scrollController.dispose();
    _ideaFocus.dispose();
    _textOnImageFocus.dispose();
    _detailsFocus.dispose();
    super.dispose();
  }

  ImageGenerationRequest get _request => ImageGenerationRequest(
        idea: _ideaController.text,
        style: _selectedStyle,
        format: _selectedFormat,
        mood: _selectedMood,
        textOnImage: _textOnImageController.text.trim().isEmpty
            ? null
            : _textOnImageController.text.trim(),
        details: _detailsController.text.trim().isEmpty
            ? null
            : _detailsController.text.trim(),
        hasReference: false,
      );

  Future<void> _generatePrompt() async {
    final request = _request;
    if (!request.isValid) {
      setState(() => _error = 'Напишите, что нужно нарисовать');
      return;
    }

    // DeepSeek-генерация описания — платный вызов внешнего API. Сверяем баланс
    // с сервером (источник истины) до вызова: при устаревшем локальном кэше промт
    // мог генерироваться при нулевом серверном балансе — это лишний расход денег.
    // Порог — реальная стоимость выбранной генерации, чтобы не создавать описание,
    // которое пользователь всё равно не сможет оплатить.
    var usage = await ref.read(creditUsageNotifierProvider.future);
    try {
      usage = await ref
          .read(creditUsageNotifierProvider.notifier)
          .refreshFromServer();
    } catch (_) {
      // Сервер недоступен — остаёмся на локальных данных, не блокируем жёстко.
    }
    if (usage.remainingCredits < _selectedProvider.creditCost) {
      if (!mounted) return;
      await Navigator.of(context).push<void>(paywallRoute<void>());
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _selectedTab = 1;
      _revealedSectionCount = 0;
    });

    try {
      final service = ref.read(imagePromptServiceProvider);
      final prompt = await service.buildPrompt(request);

      if (!mounted) return;

      if (prompt == null || prompt.isEmpty) {
        setState(() {
          _error = 'Не удалось создать описание изображения';
          _loading = false;
        });
        return;
      }

      setState(() {
        _generatedPrompt = prompt;
        _loading = false;
      });

      if (mounted) {
        _revealSectionsProgressively();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = normalizePhotosessionErrorMessage(e.toString());
          _loading = false;
        });
      }
    }
  }

  Future<void> _revealSectionsProgressively() async {
    final sections = _parsePromptSections(_generatedPrompt!);
    final count = sections.length;
    for (int i = 0; i < count; i++) {
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      setState(() => _revealedSectionCount = i + 1);
    }
  }

  Future<void> _generatePreset() async {
    if (_generatedPrompt == null) {
      setState(() => _error = 'Сначала создайте описание изображения');
      return;
    }

    setState(() => _error = null);

    final finalPrompt = _getEditedPrompt();
    final presetTitle = _request.title;
    final tempPresetId = 'image_${DateTime.now().millisecondsSinceEpoch}';

    final tempPreset = PhotoSessionPreset(
      id: tempPresetId,
      prompt: finalPrompt,
      previewImageUrl: '',
      title: presetTitle,
      tags: [PresetTag.idCustom],
      imageStyle: _selectedStyle.id,
      createdAt: DateTime.now(),
    );

    try {
      final result =
          await ref.read(backgroundGenerationProvider.notifier).startGeneration(
                preset: tempPreset,
                prompt: finalPrompt,
                provider: _selectedProvider,
                taskType: GenerationTaskType.userImage,
                aspectRatio: _selectedFormat.aspectRatio,
                referenceImage: null,
                generatedImageData: GeneratedImageData(
                  prompt: finalPrompt,
                  title: presetTitle,
                  imageStyle: _selectedStyle.id,
                ),
              );

      if (!mounted) return;
      if (!result.isSuccess) {
        if (result.reason == 'tier_locked') {
          Navigator.of(context).push(paywallRoute());
        } else if (result.reason == 'insufficient_credits') {
          Navigator.of(context).push(tokenPurchaseRoute());
        } else {
          final palette = PhotosessionPalette.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_creditFailureMessage(result.reason)),
              backgroundColor: palette.danger,
            ),
          );
        }
        return;
      }

      Navigator.of(context).push(
        photosessionRoute(
          PhotosessionGenerationScreen(taskId: result.taskId!),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final palette = PhotosessionPalette.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(normalizePhotosessionErrorMessage(e.toString())),
          backgroundColor: palette.danger,
        ),
      );
    }
  }

  String _creditFailureMessage(String? reason) {
    switch (reason) {
      case 'server_unconfigured':
        return 'Сервис кредитов не настроен в этой сборке';
      case 'device_not_registered':
        return 'Устройство не зарегистрировано на сервере. '
            'Проверьте интернет и перезапустите приложение';
      case 'server_unavailable':
        return 'Сервер кредитов недоступен. Проверьте интернет '
            'и попробуйте ещё раз';
      default:
        return 'Не удалось подготовить списание кредитов';
    }
  }

  /// Разбирает промпт на блоки по заголовкам вида «ГЛАВНЫЙ ОБЪЕКТ:».
  Map<String, String> _parsePromptSections(String prompt) {
    final sections = PromptSections.parse(prompt);
    return {
      for (final key in sections.keys)
        PromptSections.displayTitle(key): sections[key] ?? '',
    };
  }

  String _getEditedPrompt() {
    final basePrompt = _generatedPrompt ?? '';
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
      setState(() {
        _editedSections[sectionName] = result;
      });
    }
  }

  void _scheduleCustomTutorialIfNeeded({
    required PhotosessionTutorialScenario scenario,
    bool force = false,
  }) {
    if (!mounted || _isTutorialVisible) return;

    if (scenario == PhotosessionTutorialScenario.customCreation &&
        !force &&
        _didTryAutoTutorial) {
      return;
    }
    if (scenario == PhotosessionTutorialScenario.customCreationResult &&
        !force &&
        _didTryResultTutorial) {
      return;
    }

    bool getDidTry() {
      switch (scenario) {
        case PhotosessionTutorialScenario.customCreation:
          return _didTryAutoTutorial;
        case PhotosessionTutorialScenario.customCreationResult:
          return _didTryResultTutorial;
        default:
          return true;
      }
    }

    void setDidTry(bool v) {
      switch (scenario) {
        case PhotosessionTutorialScenario.customCreation:
          _didTryAutoTutorial = v;
          break;
        case PhotosessionTutorialScenario.customCreationResult:
          _didTryResultTutorial = v;
          break;
        default:
          break;
      }
    }

    final palette = PhotosessionPalette.of(context);

    runPhotosessionAutoTutorialChain(
      context: context,
      ref: ref,
      force: force,
      scenario: scenario,
      schedulingGateOk: () => mounted && !_isTutorialVisible,
      buildTargets: _buildCustomTutorialTargets,
      getDidTryAuto: getDidTry,
      setDidTryAuto: setDidTry,
      getChainActive: () => _customAutoTutorialChain,
      setChainActive: (v) => _customAutoTutorialChain = v,
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
          beforeFocus: photosessionTutorialBeforeFocus(targets),
          onFinish: () async {
            _isTutorialVisible = false;
            await store.markSeen(scenario);
          },
          onSkip: () {
            _isTutorialVisible = false;
            store.markSeen(scenario);
            return true;
          },
        ).showForPhotosession(context);
      },
    );
  }

  List<TargetFocus> _buildCustomTutorialTargets() {
    final steps = <({
      GlobalKey key,
      String id,
      String title,
      String description,
      IconData icon,
      ContentAlign align,
    })>[];

    if (_selectedTab == 0) {
      if (_ideaKey.currentContext != null) {
        steps.add((
          key: _ideaKey,
          id: 'custom_idea',
          title: 'Опишите идею',
          description:
              'Напишите, что нужно нарисовать — хватит нескольких слов: «кот-астронавт на Марсе», «логотип для пекарни». Остальное AI придумает сам.',
          icon: Icons.lightbulb_outline_rounded,
          align: ContentAlign.bottom,
        ));
      }
      if (_textOnImageKey.currentContext != null) {
        steps.add((
          key: _textOnImageKey,
          id: 'custom_text_on_image',
          title: 'Добавьте надпись',
          description:
              'Если на картинке нужен текст — поздравление, название, слоган — впишите его здесь дословно, и он появится на изображении.',
          icon: Icons.title_rounded,
          align: ContentAlign.top,
        ));
      }
      if (_descriptionButtonKey.currentContext != null) {
        steps.add((
          key: _descriptionButtonKey,
          id: 'custom_generate_prompt',
          title: 'Соберите описание',
          description:
              'Эта кнопка превращает вашу идею в подробный промпт. Потом его можно вручную поправить и сразу перейти к генерации.',
          icon: Icons.auto_awesome_rounded,
          align: ContentAlign.top,
        ));
      }
    } else if (_selectedTab == 1 && _generatedPrompt != null && !_loading) {
      if (_segmentedTabsKey.currentContext != null) {
        steps.add((
          key: _segmentedTabsKey,
          id: 'custom_tabs',
          title: 'Двигайтесь по шагам',
          description:
              'Сначала идея, затем готовый промпт. Возвращайтесь на любой шаг в любой момент.',
          icon: Icons.view_day_rounded,
          align: ContentAlign.bottom,
        ));
      }
      if (_promptCardKey.currentContext != null) {
        steps.add((
          key: _promptCardKey,
          id: 'custom_prompt_edit',
          title: 'Исправьте описание вручную',
          description:
              'Нажмите на любой блок, чтобы поправить объект, фон, свет, цвет или технические детали. Самый быстрый способ подогнать картинку под себя.',
          icon: Icons.edit_rounded,
          align: ContentAlign.bottom,
        ));
      }
      if (_photoModelSelectorKey.currentContext != null) {
        steps.add((
          key: _photoModelSelectorKey,
          id: 'custom_model',
          title: 'Выберите модель генерации',
          description:
              'Для первых тестов начните с обычной модели, а для сложных сцен и максимальной детализации переключайтесь на PRO.',
          icon: Icons.auto_awesome_mosaic_rounded,
          align: ContentAlign.top,
        ));
      }
      if (_photoGenerateButtonKey.currentContext != null) {
        steps.add((
          key: _photoGenerateButtonKey,
          id: 'custom_generate',
          title: 'Создайте изображение',
          description:
              'После генерации вы получите готовую картинку: её можно сохранить, отправить друзьям и при желании открыть для сообщества.',
          icon: Icons.auto_fix_high_rounded,
          align: ContentAlign.top,
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
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final descriptionFocusMode = _descriptionCompactInputMode(context);

    if (_selectedTab == 0 && !descriptionFocusMode) {
      _scheduleCustomTutorialIfNeeded(
        scenario: PhotosessionTutorialScenario.customCreation,
      );
    }

    return PhotosessionThemeScope(
      child: PopScope(
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: descriptionFocusMode
              ? null
              : AppBar(
                  elevation: 0,
                  backgroundColor: colors.surfaceContainerLowest,
                  foregroundColor: colors.onSurface,
                  surfaceTintColor: Colors.transparent,
                  title: const Text(
                    'Создать изображение',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                  ),
                  actions: [
                    PhotosessionTutorialHelpButton(
                      onPressed: () => _scheduleCustomTutorialIfNeeded(
                        scenario: PhotosessionTutorialScenario.customCreation,
                        force: true,
                      ),
                      compact: true,
                      plain: true,
                    ),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(60),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: KeyedSubtree(
                        key: _segmentedTabsKey,
                        child: PhotosessionSegmentedTabs(
                          selected: _selectedTab,
                          onChanged: (index) {
                            final promptEnabled =
                                _generatedPrompt != null || _loading;
                            if (index == 1 && !promptEnabled) return;
                            setState(() => _selectedTab = index);
                          },
                          segments: const [
                            'Идея',
                            'Промпт',
                          ],
                          enabled: [
                            true,
                            _generatedPrompt != null || _loading,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _dismissKeyboard,
            child: descriptionFocusMode
                ? SafeArea(
                    bottom: false,
                    child: _buildInputTab(theme, colors),
                  )
                : IndexedStack(
                    index: _selectedTab,
                    children: [
                      _buildInputTab(theme, colors),
                      _buildPromptTab(theme, colors),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptGenerationBar(ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    final usage = ref.watch(creditUsageNotifierProvider).valueOrNull;
    final isTierLocked = usage != null &&
        (usage.isFreeUser || usage.isTrialUser) &&
        !CreditCost.isTierAvailableForTrial(_selectedProvider.creditTier);
    final hasEnoughCredits =
        usage == null || usage.hasEnoughCredits(_selectedProvider.creditCost);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProviderSelector(colors, palette),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: FilledButton.icon(
              key: _photoGenerateButtonKey,
              onPressed: !_canGenerate
                  ? null
                  : isTierLocked
                      ? () => Navigator.of(context).push(paywallRoute())
                      : !hasEnoughCredits
                          ? () => Navigator.of(context).push(tokenPurchaseRoute())
                          : _generatePreset,
              icon: Icon(
                isTierLocked || !hasEnoughCredits
                    ? Icons.account_balance_wallet_rounded
                    : Icons.auto_fix_high,
                size: 24,
              ),
              label: Text(
                isTierLocked
                    ? 'Нужен PRO'
                    : !hasEnoughCredits
                        ? 'Купить кредиты'
                        : 'Создать за ${_selectedProvider.creditCost} кредитов',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: _brownActionButtonStyle(palette),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsSection(ThemeData theme, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OptionChipsRow<ImageStyle>(
          title: 'Стиль',
          values: ImageStyle.values,
          selected: _selectedStyle,
          labelOf: (value) => value.label,
          onSelected: (value) => setState(() => _selectedStyle = value),
        ),
        const SizedBox(height: 10),
        _OptionChipsRow<ImageFormat>(
          title: 'Формат',
          values: ImageFormat.values,
          selected: _selectedFormat,
          labelOf: (value) => '${value.label} · ${value.aspectRatio}',
          onSelected: (value) => setState(() => _selectedFormat = value),
        ),
        const SizedBox(height: 10),
        _OptionChipsRow<ImageMood>(
          title: 'Настроение',
          values: ImageMood.values,
          selected: _selectedMood,
          labelOf: (value) => value.label,
          onSelected: (value) => setState(() => _selectedMood = value),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildInputTab(ThemeData theme, ColorScheme colors) {
    final compactInputMode = _descriptionCompactInputMode(context);
    final ideaFocused = _ideaFocus.hasFocus;
    final detailsFocused = _detailsFocus.hasFocus;
    final textOnImageFocused = _textOnImageFocus.hasFocus;
    final showIdea = !compactInputMode ||
        ideaFocused ||
        (!detailsFocused && !textOnImageFocused);
    final showDetails = !compactInputMode || detailsFocused;
    final showTextOnImage = !compactInputMode || textOnImageFocused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              compactInputMode ? 12 : 24,
              compactInputMode ? 8 : 6,
              compactInputMode ? 12 : 24,
              compactInputMode ? 8 : 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: compactInputMode
                      ? const SizedBox.shrink()
                      : _buildOptionsSection(theme, colors),
                ),
                if (showIdea)
                  Expanded(
                    child: _buildInputField(
                      controller: _ideaController,
                      focusNode: _ideaFocus,
                      fieldKey: _ideaKey,
                      label: 'Что нарисовать',
                      hint: _ideaHint,
                      icon: Icons.lightbulb_outline_rounded,
                      minLines: _sceneFieldMinLines,
                      maxLines: _sceneFieldMaxLines,
                      expands: true,
                      centerHintWhenEmpty: true,
                      theme: theme,
                      colors: colors,
                    ),
                  ),
                if (showIdea && (showDetails || showTextOnImage))
                  const SizedBox(height: 12),
                if (showDetails)
                  Expanded(
                    child: _buildInputField(
                      controller: _detailsController,
                      focusNode: _detailsFocus,
                      fieldKey: _detailsKey,
                      label: 'Детали',
                      hint: 'Что обязательно должно быть в кадре: '
                          'предметы, цвета, время суток',
                      icon: Icons.auto_awesome_outlined,
                      required: false,
                      minLines: _sceneFieldMinLines,
                      maxLines: _sceneFieldMaxLines,
                      expands: true,
                      centerHintWhenEmpty: true,
                      theme: theme,
                      colors: colors,
                    ),
                  ),
                if (showDetails && showTextOnImage) const SizedBox(height: 12),
                if (showTextOnImage)
                  compactInputMode
                      ? Expanded(
                          child: _buildInputField(
                            controller: _textOnImageController,
                            focusNode: _textOnImageFocus,
                            fieldKey: _textOnImageKey,
                            label: 'Надпись на изображении',
                            hint: 'Например: С днём рождения!',
                            icon: Icons.title_rounded,
                            required: false,
                            minLines: 1,
                            maxLines: 4,
                            expands: true,
                            theme: theme,
                            colors: colors,
                          ),
                        )
                      : _buildInputField(
                          controller: _textOnImageController,
                          focusNode: _textOnImageFocus,
                          fieldKey: _textOnImageKey,
                          label: 'Надпись на изображении',
                          hint: 'Например: С днём рождения!',
                          icon: Icons.title_rounded,
                          required: false,
                          theme: theme,
                          colors: colors,
                        ),
                if (_error != null && !compactInputMode) ...[
                  const SizedBox(height: 12),
                  _buildDescriptionErrorBox(colors),
                ],
              ],
            ),
          ),
        ),
        _buildDescriptionBottomBar(colors, compactMode: compactInputMode),
      ],
    );
  }

  Widget _buildDescriptionErrorBox(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                color: colors.onErrorContainer,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionBottomBar(
    ColorScheme colors, {
    required bool compactMode,
  }) {
    final palette = PhotosessionPalette.of(context);
    final isEditingDescription = compactMode;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        compactMode ? 8 : 12,
        20,
        (compactMode ? 12 : 20) + MediaQuery.of(context).padding.bottom,
      ),
      child: SizedBox(
        key: _descriptionButtonKey,
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          onPressed: isEditingDescription
              ? _dismissKeyboard
              : (_loading ? null : _generatePrompt),
          icon: _loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.background,
                  ),
                )
              : Icon(
                  isEditingDescription
                      ? Icons.check_rounded
                      : Icons.auto_awesome,
                  size: 24,
                ),
          label: Text(
            isEditingDescription
                ? 'Сохранить'
                : (_loading ? 'Придумываем детали...' : 'Собрать описание'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          style: _brownActionButtonStyle(palette),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required ThemeData theme,
    required ColorScheme colors,
    required FocusNode focusNode,
    GlobalKey? fieldKey,
    bool required = true,
    int minLines = 1,
    int maxLines = 1,
    bool expands = false,
    bool centerHintWhenEmpty = false,
  }) {
    assert(
      minLines >= 1 && maxLines >= minLines,
      'minLines/maxLines must be valid for TextField',
    );
    final multiline = maxLines > 1;
    final hintStyle = TextStyle(
      color: colors.onSurface.withOpacity(0.35),
      fontSize: 14,
    );
    final fieldStyle = theme.textTheme.bodyLarge?.copyWith(
          height: 1.4,
          color: colors.onSurface,
        ) ??
        TextStyle(
          fontSize: 16,
          height: 1.4,
          color: colors.onSurface,
        );
    final field = TextField(
      controller: controller,
      onChanged: (_) => _handleDescriptionInputChanged(),
      focusNode: focusNode,
      scrollPadding: const EdgeInsets.only(top: 24, bottom: 320),
      style: fieldStyle,
      keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
      textInputAction:
          multiline ? TextInputAction.newline : TextInputAction.done,
      textAlignVertical:
          multiline ? TextAlignVertical.top : TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: centerHintWhenEmpty ? null : hint,
        hintStyle: hintStyle,
        prefixIcon: Icon(icon, color: colors.primary),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          maxWidth: 48,
          minHeight: 48,
          maxHeight: 48,
        ),
        isDense: !multiline,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: multiline ? 14 : 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outline.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        filled: true,
        fillColor: colors.surface,
      ),
      textCapitalization: TextCapitalization.sentences,
      minLines: expands ? null : (multiline ? minLines : null),
      maxLines: expands ? null : (multiline ? maxLines : 1),
      expands: expands,
    );
    final fieldBody = expands && centerHintWhenEmpty
        ? Stack(
            children: [
              Positioned.fill(child: field),
              if (controller.text.trim().isEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(56, 12, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          hint,
                          textAlign: TextAlign.left,
                          style: hintStyle.copyWith(height: 1.45),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          )
        : field;
    final content = expands
        ? LayoutBuilder(
            builder: (context, constraints) {
              final maxHeight = constraints.maxHeight;
              final showTitle = maxHeight >= 90;
              final topSpacing = showTitle ? 8.0 : 0.0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.max,
                children: [
                  if (showTitle)
                    Text(
                      required ? label : '$label (опционально)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (showTitle) SizedBox(height: topSpacing),
                  Expanded(child: fieldBody),
                ],
              );
            },
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                required ? label : '$label (опционально)',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              fieldBody,
            ],
          );
    return fieldKey != null
        ? KeyedSubtree(key: fieldKey, child: content)
        : content;
  }

  static const String _ideaHint =
      'Хватит нескольких слов: «кот-астронавт на Марсе», '
      '«уютная кофейня под дождём», «логотип для пекарни»';

  Widget _buildProviderSelector(
    ColorScheme colors,
    PhotosessionPalette palette,
  ) {
    return OutlinedButton(
      key: _photoModelSelectorKey,
      onPressed: () => _showModelSelectionSheet(colors),
      style: _oliveOutlineButtonStyle(palette),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _providerIcon(_selectedProvider),
            size: 22,
            color: palette.accent,
          ),
          const SizedBox(width: 10),
          Text(
            _selectedProvider.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: palette.textSecondary,
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
      case PhotosessionProvider.piapi:
        return Icons.rocket_launch_rounded;
      case PhotosessionProvider.googleFlash:
        return Icons.bolt_rounded;
      case PhotosessionProvider.flash:
        return Icons.flash_on_rounded;
      case PhotosessionProvider.qwen:
        return Icons.grain_rounded;
      case PhotosessionProvider.gptImage15:
        return Icons.auto_awesome_rounded;
      case PhotosessionProvider.gptImage2:
        return Icons.diamond_rounded;
      case PhotosessionProvider.grokImage:
        return Icons.blur_on_rounded;
      case PhotosessionProvider.apibostPro:
        return Icons.workspace_premium_rounded;
      case PhotosessionProvider.apibostStandard:
        return Icons.speed_rounded;
      case PhotosessionProvider.apibostFlash:
        return Icons.electric_bolt_rounded;
    }
  }

  Widget _buildPromptTab(ThemeData theme, ColorScheme colors) {
    final palette = PhotosessionPalette.of(context);
    if (_generatedPrompt == null && !_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 50,
                  color: colors.onSurface.withOpacity(0.4),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Описание сцены ещё не создано',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Заполните данные на первом экране\nи нажмите «Создать описание»',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: colors.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.primary.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Генерируем описание сцены...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...List.generate(_shimmerSectionTitles.length, (_) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ShimmerSectionCard(colors: colors),
              );
            }),
            const SizedBox(height: 20),
          ],
        ),
      );
    }

    final sections = _parsePromptSections(_generatedPrompt!);
    final sectionList = sections.entries.toList();
    final visibleCount = _revealedSectionCount.clamp(0, sectionList.length);
    final showButton = visibleCount >= sectionList.length;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_editedSections.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: palette.warning.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit,
                            size: 14,
                            color: palette.warning,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Изменён',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: palette.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              ...List.generate(visibleCount, (index) {
                final entry = sectionList[index];
                final sectionName = entry.key;
                final sectionContent =
                    _editedSections[sectionName] ?? entry.value;
                final isEdited = _editedSections.containsKey(sectionName);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: KeyedSubtree(
                    key: index == 0 ? _promptCardKey : null,
                    child: _PromptSectionCard(
                      title: sectionName,
                      content: sectionContent,
                      isEdited: isEdited,
                      onTap: () => _editSection(sectionName, sectionContent),
                      colors: colors,
                    ),
                  ),
                );
              }),
              if (_editedSections.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _editedSections.clear();
                      });
                    },
                    icon: const Icon(Icons.restore),
                    label: const Text('Вернуть оригинал'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                ),
              ],
              if (showButton) const SizedBox(height: 170),
            ],
          ),
        ),
        if (showButton)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.background.withValues(alpha: 0.96),
                boxShadow: [
                  BoxShadow(
                    color: palette.depth.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: _buildPromptGenerationBar(colors),
            ),
          ),
      ],
    );
  }

  bool get _canGenerate => !_loading;
}

/// Горизонтальный ряд взаимоисключающих вариантов: стиль, формат, настроение.
class _OptionChipsRow<T> extends StatelessWidget {
  const _OptionChipsRow({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.onSurface.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final value = values[index];
              final isSelected = value == selected;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelected(value),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? colors.primary
                            : colors.outline.withOpacity(0.5),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      labelOf(value),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? colors.primary
                            : colors.onSurface.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ShimmerSectionCard extends StatefulWidget {
  const _ShimmerSectionCard({required this.colors});

  final ColorScheme colors;

  @override
  State<_ShimmerSectionCard> createState() => _ShimmerSectionCardState();
}

class _ShimmerSectionCardState extends State<_ShimmerSectionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.25, end: 0.75).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final opacity = _animation.value;
        final base = isDark
            ? colors.onSurface.withOpacity(0.05 + opacity * 0.15)
            : colors.onSurface.withOpacity(0.04 + opacity * 0.14);
        final line = isDark
            ? colors.onSurface.withOpacity(0.08 + opacity * 0.2)
            : colors.onSurface.withOpacity(0.06 + opacity * 0.18);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest
                .withOpacity(0.3 + opacity * 0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.outline.withOpacity(0.15 + opacity * 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 16,
                      decoration: BoxDecoration(
                        color: line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 10,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 10,
                width: 200,
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        );
      },
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: palette.depth.withValues(alpha: 0.26),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _getIconForSection(title),
                        size: 18,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
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
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      color: colors.onSurface.withOpacity(0.4),
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: colors.onSurface.withOpacity(0.7),
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
