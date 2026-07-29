import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/localization/app_localization_service.dart';
import '../../services/theme_service.dart';
import '../../widgets/days_picker.dart';
import '../../services/ai_image_generation_service.dart';
import '../home/home_providers.dart' as home;
import '../messenger/messenger_providers.dart';
import 'friend_generate_screen.dart';
import '../messenger/services/friend_avatar_prompt_builder.dart';
import 'widgets/onboarding_simple_button.dart';
import 'widgets/typewriter_glitch_text.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _buttonAnimationController;

  int _currentPageIndex = 0;
  bool _isTypingComplete = false;

  String? _userGender;
  String? _relationshipType;
  String? _friendGender;
  int _friendAge = 25;
  String? _friendHairColor;
  String? _friendEyeColor;
  late final FriendAvatarPromptBuilder _avatarPromptBuilder =
      FriendAvatarPromptBuilder();
  AiImageGenerationService? _imageService;
  int _prefetchToken = 0;
  String? _prefetchSignature;
  Future<FriendGeneratePrefetchData?>? _prefetchFuture;

  final List<String> _progressTitles = const [
    'onboarding_friend_gender_question',
    'onboarding_friend_relationship_type_question',
    'onboarding_friend_age_question',
    'onboarding_friend_hair_question',
    'onboarding_friend_eyes_question',
    'onboarding_user_gender_question',
  ];

  static const int _minFriendAge = 18;
  static const int _maxFriendAge = 80;

  static const List<_OnboardingOption> _userGenderOptions = [
    _OnboardingOption('male', 'gender_male'),
    _OnboardingOption('female', 'gender_female'),
  ];

  static const List<_OnboardingOption> _genderOptions = [
    _OnboardingOption('female', 'gender_female'),
    _OnboardingOption('male', 'gender_male'),
  ];

  static const List<_OnboardingOption> _relationshipTypeOptions = [
    _OnboardingOption(
        'relationship', 'onboarding_friend_relationship_type_romance'),
    _OnboardingOption('friend', 'onboarding_friend_relationship_type_friend'),
  ];

  static const List<_OnboardingOption> _hairOptions = [
    _OnboardingOption('blonde', 'onboarding_friend_hair_blonde'),
    _OnboardingOption('brown', 'onboarding_friend_hair_brown'),
    _OnboardingOption('brunette', 'onboarding_friend_hair_brunette'),
    _OnboardingOption('red', 'onboarding_friend_hair_red'),
  ];

  static const List<_OnboardingOption> _eyeOptions = [
    _OnboardingOption('blue', 'onboarding_friend_eyes_blue'),
    _OnboardingOption('green', 'onboarding_friend_eyes_green'),
    _OnboardingOption('brown', 'onboarding_friend_eyes_brown'),
    _OnboardingOption('gray', 'onboarding_friend_eyes_gray'),
  ];

  @override
  void initState() {
    super.initState();
    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _imageService ??=
        ProviderScope.containerOf(context).read(avatarImageGenerationServiceProvider);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _buttonAnimationController.dispose();
    super.dispose();
  }

  /// Создаёт анимированную кнопку с задержкой появления
  Widget _buildAnimatedButton({
    required Widget child,
    required int index,
  }) {
    // Не показываем кнопки, пока не завершена печать заголовка
    if (!_isTypingComplete) {
      return Opacity(
        opacity: 0.0,
        child: child,
      );
    }

    // Создаём анимацию с задержкой для каждой кнопки
    final delay = index * 50; // 50ms задержка между кнопками
    final animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _buttonAnimationController,
        curve: Interval(
          (delay / 350).clamp(0.0, 1.0),
          1.0,
          curve: Curves.easeOut,
        ),
      ),
    );

    // Используем ScaleTransition для эффекта "разворачивания" как у FAB
    return ScaleTransition(
      scale: animation,
      child: child,
    );
  }

  /// Сбрасывает анимацию кнопок при смене страницы
  void _resetButtonAnimation() {
    setState(() {
      _isTypingComplete = false;
    });
    _buttonAnimationController.reset();
    // Не запускаем анимацию сразу - она запустится после печати заголовка
  }

  void _nextPage() {
    // Сбрасываем анимацию и блокируем контент ДО навигации, чтобы не было мерцаний
    _resetButtonAnimation();
    if (_currentPageIndex < _progressTitles.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      if (!mounted) return;
      unawaited(_markOnboardingCompleted());
      unawaited(_saveUserGender());
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FriendGenerateScreen(
            gender: _friendGender ?? 'male',
            age: _friendAge,
            hairColor: _friendHairColor ?? 'blonde',
            eyeColor: _friendEyeColor ?? 'blue',
            relationshipType: _relationshipType ?? 'friend',
            prefetchSignature: _buildFriendSignature(),
            prefetchFuture: _prefetchFuture,
          ),
        ),
      );
    }
  }

  bool _canContinueForPage(int index) {
    switch (index) {
      case 0:
        return _friendGender != null;
      case 1:
        return _relationshipType != null;
      case 2:
        return true;
      case 3:
        return _friendHairColor != null;
      case 4:
        return _friendEyeColor != null;
      case 5:
        return _userGender != null;
      default:
        return true;
    }
  }

  void _handleContinue() {
    if (!_canContinueForPage(_currentPageIndex)) return;
    _nextPage();
  }

  Future<void> _markOnboardingCompleted() async {
    try {
      final container = ProviderScope.containerOf(context);
      final repository = container.read(home.userRepositoryProvider);
      await repository.setOnboardingCompleted(true);
    } catch (_) {}
  }

  Future<void> _saveUserGender() async {
    if (_userGender == null) return;
    try {
      final container = ProviderScope.containerOf(context);
      final repository = container.read(home.userRepositoryProvider);
      await repository.setUserGender(_userGender!);
    } catch (_) {}
  }

  void _previousPage() {
    // Сбрасываем анимацию и блокируем контент ДО навигации, чтобы не было мерцаний
    _resetButtonAnimation();
    if (_currentPageIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Widget _buildTitledPage({
    required String titleKey,
    required Widget content,
    double titleTopFactor = 1 / 3.0,
    Widget? bottomAction,
    bool lockTopToFullHeight = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: SizedBox.expand(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final media = MediaQuery.of(context);
                  final baseHeight = lockTopToFullHeight
                      ? media.size.height + media.viewInsets.bottom
                      : media.size.height;
                  final double titleTop = (baseHeight * titleTopFactor) -
                      (media.padding.top + kToolbarHeight);
                  final double computedTop =
                      titleTop.clamp(0.0, constraints.maxHeight);
                  final double bottomSpacing =
                      bottomAction != null ? 24.0 : media.padding.bottom + 20;

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: computedTop),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TypewriterGlitchText(
                            key: ValueKey(titleKey),
                            text: context.tr(titleKey),
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface,
                              shadows: [
                                Shadow(
                                  color: theme.shadowColor.withOpacity(0.35),
                                  offset: Offset(0, 2),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            typingSpeed: const Duration(milliseconds: 50),
                            onTypingComplete: () {
                              if (!mounted) return;
                              setState(() => _isTypingComplete = true);
                              _buttonAnimationController.forward();
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_isTypingComplete) content,
                        SizedBox(height: bottomSpacing),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (bottomAction != null)
          SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final screenHeight = MediaQuery.of(context).size.height;
                final bottomPadding = screenHeight > 700 ? 16.0 : 12.0;
                return Padding(
                  padding: EdgeInsets.fromLTRB(24.0, 0.0, 24.0, bottomPadding),
                  child: SizedBox(width: double.infinity, child: bottomAction),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildContinueButton({required bool enabled}) {
    final continueButton = _buildAnimatedButton(
      index: 99,
      child: OnboardingSimpleButton(
        text: context.tr('continue_button'),
        isSelected: true,
        onPressed: _handleContinue,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    );
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.0,
        child: continueButton,
      ),
    );
  }

  Widget _buildOptionButton({
    required int index,
    required String labelKey,
    required bool isSelected,
    required VoidCallback onPressed,
  }) {
    return _buildAnimatedButton(
      index: index,
      child: OnboardingSimpleButton(
        text: context.tr(labelKey),
        isSelected: isSelected,
        emphasizeSelection: true,
        onPressed: onPressed,
      ),
    );
  }

  String _hairLabelKey(_OnboardingOption option) {
    final gender = _friendGender;
    if (gender == null) {
      return option.labelKey;
    }
    final suffix = gender == 'female' ? 'female' : 'male';
    return '${option.labelKey}_$suffix';
  }

  Widget _buildUserGenderPage() {
    return _buildTitledPage(
      titleKey: 'onboarding_user_gender_question',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _userGenderOptions.length; i++)
            _buildOptionButton(
              index: i,
              labelKey: _userGenderOptions[i].labelKey,
              isSelected: _userGenderOptions[i].value == _userGender,
              onPressed: () {
                setState(() => _userGender = _userGenderOptions[i].value);
                _nextPage();
              },
            ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildRelationshipTypePage() {
    return _buildTitledPage(
      titleKey: 'onboarding_friend_relationship_type_question',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _relationshipTypeOptions.length; i++)
            _buildOptionButton(
              index: i,
              labelKey: _relationshipTypeOptions[i].labelKey,
              isSelected:
                  _relationshipTypeOptions[i].value == _relationshipType,
              onPressed: () {
                _setRelationshipType(_relationshipTypeOptions[i].value);
                _nextPage();
              },
            ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildGenderPage() {
    return _buildTitledPage(
      titleKey: 'onboarding_friend_gender_question',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _genderOptions.length; i++)
            _buildOptionButton(
              index: i,
              labelKey: _genderOptions[i].labelKey,
              isSelected: _genderOptions[i].value == _friendGender,
              onPressed: () {
                _setFriendGender(_genderOptions[i].value);
                _nextPage();
              },
            ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildAgePage() {
    final colors = Theme.of(context).colorScheme;
    return _buildTitledPage(
      titleKey: 'onboarding_friend_age_question',
      bottomAction: _buildContinueButton(enabled: true),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAnimatedButton(
            index: 0,
            child: DaysPicker(
              initialDays: _friendAge,
              minValue: _minFriendAge,
              maxValue: _maxFriendAge,
              onChanged: (v) => _setFriendAge(v),
              backgroundColor: colors.surface,
              selectionColor: colors.surfaceContainerHighest,
              selectionBorderColor: colors.outline,
              useSelectionOverlay: false,
              showSelectionBackgroundBehind: true,
            ),
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildHairPage() {
    return _buildTitledPage(
      titleKey: 'onboarding_friend_hair_question',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _hairOptions.length; i++)
            _buildOptionButton(
              index: i,
              labelKey: _hairLabelKey(_hairOptions[i]),
              isSelected: _hairOptions[i].value == _friendHairColor,
              onPressed: () {
                _setFriendHairColor(_hairOptions[i].value);
                _nextPage();
              },
            ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildEyePage() {
    return _buildTitledPage(
      titleKey: 'onboarding_friend_eyes_question',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _eyeOptions.length; i++)
            _buildOptionButton(
              index: i,
              labelKey: _eyeOptions[i].labelKey,
              isSelected: _eyeOptions[i].value == _friendEyeColor,
              onPressed: () {
                _setFriendEyeColor(_eyeOptions[i].value);
                _startAvatarPrefetch();
                _nextPage();
              },
            ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: WillPopScope(
        onWillPop: () async {
          if (_currentPageIndex == 0) return false;
          _previousPage();
          return false;
        },
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            leading: _currentPageIndex > 0
                ? CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _previousPage,
                    child: Icon(
                      CupertinoIcons.back,
                      color: colors.onSurface,
                    ),
                  )
                : null,
          ),
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _ProgressLine(
                      progress:
                          (_currentPageIndex + 1) / _progressTitles.length,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _ThemeModeToggle(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (index) {
                        setState(() => _currentPageIndex = index);
                        _resetButtonAnimation();
                      },
                      itemCount: _progressTitles.length,
                      itemBuilder: (context, index) {
                        switch (index) {
                          case 0:
                            return _buildGenderPage();
                          case 1:
                            return _buildRelationshipTypePage();
                          case 2:
                            return _buildAgePage();
                          case 3:
                            return _buildHairPage();
                          case 4:
                            return _buildEyePage();
                          case 5:
                          default:
                            return _buildUserGenderPage();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setFriendGender(String value) {
    if (_friendGender == value) return;
    setState(() {
      _friendGender = value;
    });
    _invalidateAvatarPrefetch();
  }

  void _setRelationshipType(String value) {
    if (_relationshipType == value) return;
    setState(() {
      _relationshipType = value;
    });
    _invalidateAvatarPrefetch();
  }

  void _setFriendAge(int value) {
    if (_friendAge == value) return;
    setState(() {
      _friendAge = value;
    });
    _invalidateAvatarPrefetch();
  }

  void _setFriendHairColor(String value) {
    if (_friendHairColor == value) return;
    setState(() {
      _friendHairColor = value;
    });
    _invalidateAvatarPrefetch();
  }

  void _setFriendEyeColor(String value) {
    if (_friendEyeColor == value) return;
    setState(() {
      _friendEyeColor = value;
    });
    _invalidateAvatarPrefetch();
  }

  void _invalidateAvatarPrefetch() {
    _prefetchToken += 1;
    _prefetchSignature = null;
    _prefetchFuture = null;
  }

  String _buildFriendSignature() {
    final friendGender = _friendGender ?? 'male';
    final relationshipType = _relationshipType ?? 'friend';
    final hairColor = _friendHairColor ?? 'blonde';
    final eyeColor = _friendEyeColor ?? 'blue';
    return [
      friendGender,
      relationshipType,
      _friendAge.toString(),
      hairColor,
      eyeColor,
    ].join('|');
  }

  bool _isPrefetchReadyToStart() {
    return _friendGender != null &&
        _relationshipType != null &&
        _friendHairColor != null &&
        _friendEyeColor != null;
  }

  void _startAvatarPrefetch() {
    if (!_isPrefetchReadyToStart()) return;
    final service = _imageService;
    if (service == null) return;
    final signature = _buildFriendSignature();
    if (_prefetchSignature == signature && _prefetchFuture != null) return;
    _prefetchToken += 1;
    final token = _prefetchToken;
    _prefetchSignature = signature;
    _prefetchFuture = _runAvatarPrefetch(
      token: token,
      signature: signature,
      imageService: service,
    );
  }

  Future<FriendGeneratePrefetchData?> _runAvatarPrefetch({
    required int token,
    required String signature,
    required AiImageGenerationService imageService,
  }) async {
    Future<bool> isCurrent() async {
      return mounted &&
          token == _prefetchToken &&
          signature == _prefetchSignature &&
          _buildFriendSignature() == signature;
    }

    final prompts = List.generate(
      3,
      (_) => _avatarPromptBuilder.build(
        gender: _friendGender!,
        age: _friendAge,
        hairColor: _friendHairColor!,
        eyeColor: _friendEyeColor!,
        relationshipType: _relationshipType!,
      ),
    );

    final files = <File>[];
    final usedPrompts = <FriendAvatarPrompt>[];

    Future<void> generateAndStore(FriendAvatarPrompt prompt) async {
      final result = await imageService.generateImageFromPrompt(prompt.prompt);
      if (!await isCurrent()) return;
      final file = result.primaryFile;
      if (file == null) return;
      files.add(file);
      usedPrompts.add(prompt);
    }

    await generateAndStore(prompts[0]);
    if (!await isCurrent()) return null;

    await generateAndStore(prompts[1]);
    if (!await isCurrent()) return null;
    await generateAndStore(prompts[2]);
    if (!await isCurrent()) return null;

    return FriendGeneratePrefetchData(
      signature: signature,
      files: files,
      prompts: usedPrompts,
    );
  }
}

class _ProgressLine extends StatelessWidget {
  final double progress;

  const _ProgressLine({required this.progress});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: colors.outline.withOpacity(0.4)),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(color: colors.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingOption {
  final String value;
  final String labelKey;

  const _OnboardingOption(this.value, this.labelKey);
}

class _ThemeModeToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final currentMode = ref.watch(themeModeProvider);
    final selectedMode =
        currentMode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    final inactiveColor = colors.onSurface.withOpacity(0.6);
    final activeColor = colors.onSurface;
    final shadowColor = theme.shadowColor.withOpacity(isDark ? 0.35 : 0.12);
    final borderRadius = BorderRadius.circular(999);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: borderRadius,
          border: Border.all(color: colors.outline),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: CupertinoSlidingSegmentedControl<ThemeMode>(
            groupValue: selectedMode,
            backgroundColor: Colors.transparent,
            thumbColor: colors.outline.withOpacity(0.4),
            onValueChanged: (value) {
              if (value == null) return;
              ref.read(themeModeProvider.notifier).setThemeMode(value);
            },
            children: {
              ThemeMode.light: ClipRRect(
                borderRadius: borderRadius,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Icon(
                    CupertinoIcons.sun_max_fill,
                    size: 18,
                    color: selectedMode == ThemeMode.light
                        ? activeColor
                        : inactiveColor,
                  ),
                ),
              ),
              ThemeMode.dark: ClipRRect(
                borderRadius: borderRadius,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Icon(
                    CupertinoIcons.moon_stars_fill,
                    size: 18,
                    color: selectedMode == ThemeMode.dark
                        ? activeColor
                        : inactiveColor,
                  ),
                ),
              ),
            },
          ),
        ),
      ),
    );
  }
}
