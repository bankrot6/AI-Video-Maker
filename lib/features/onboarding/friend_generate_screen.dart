import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loading_indicator/loading_indicator.dart';

import '../../services/android_system_ui_controller.dart';
import '../../services/localization/app_localization_service.dart';
import '../../services/ai_image_generation_service.dart';
import '../home/home_navigation_screen.dart';
import '../messenger/messenger_providers.dart';
import '../messenger/models/friend_profile.dart';
import '../messenger/services/friend_avatar_prompt_builder.dart';
import '../personalization/personalization_providers.dart';
import '../personalization/services/friend_persona_defaults_builder.dart';
import '../personalization/widgets/friend_persona_fields.dart';

class FriendGenerateScreen extends StatefulWidget {
  final String gender;
  final int age;
  final String hairColor;
  final String eyeColor;
  final String relationshipType;
  final String? prefetchSignature;
  final Future<FriendGeneratePrefetchData?>? prefetchFuture;

  const FriendGenerateScreen({
    super.key,
    required this.gender,
    required this.age,
    required this.hairColor,
    required this.eyeColor,
    required this.relationshipType,
    this.prefetchSignature,
    this.prefetchFuture,
  });

  @override
  State<FriendGenerateScreen> createState() => _FriendGenerateScreenState();
}

class _FriendGenerateScreenState extends State<FriendGenerateScreen>
    with WidgetsBindingObserver {
  static const double _sectionSpacing = 16;
  final Random _random = Random();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _aboutController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _goodHabitsController = TextEditingController();
  final TextEditingController _badHabitsController = TextEditingController();
  final TextEditingController _hobbiesController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  late final AiImageGenerationService _imageService;
  final FriendAvatarPromptBuilder _promptBuilder =
      FriendAvatarPromptBuilder(random: Random());
  late final FriendPersonaDefaults _personaDefaults;
  bool _imageServiceReady = false;


  static const List<int> _slotOrder = [1, 2, 0];

  bool _isGenerating = true;
  List<File?> _avatarFiles = [null, null, null];
  List<FriendAvatarPrompt?> _promptResults = [null, null, null];
  List<bool> _avatarLoading = [true, true, true];
  int _selectedAvatarIndex = 1;
  int _filledSlots = 0;
  String? _generationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidSystemUiController.hideNavigationBar();
    _personaDefaults = FriendPersonaDefaultsBuilder(random: _random).build(
      gender: widget.gender,
      relationshipType: widget.relationshipType,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocusNode.requestFocus();
      unawaited(() async {
        await _hydrateFromStorage();
        if (!mounted) return;
        await _generateAvatars();
      }());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_imageServiceReady) return;
    _imageServiceReady = true;
    _imageService =
        ProviderScope.containerOf(context).read(avatarImageGenerationServiceProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AndroidSystemUiController.hideNavigationBar();
    _nameFocusNode.dispose();
    _nameController.dispose();
    _aboutController.dispose();
    _relationshipController.dispose();
    _occupationController.dispose();
    _goodHabitsController.dispose();
    _badHabitsController.dispose();
    _hobbiesController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AndroidSystemUiController.refresh();
      });
    }
  }

  Future<void> _generateAvatars() async {
    setState(() {
      _isGenerating = true;
      _avatarFiles = [null, null, null];
      _promptResults = [null, null, null];
      _avatarLoading = [false, true, false];
      _selectedAvatarIndex = 1;
      _filledSlots = 0;
      _generationError = null;
    });
    final prefetched = await _consumePrefetchWithSoftTimeout();
    if (!mounted) return;
    if (prefetched != null &&
        prefetched.signature == _buildCurrentSignature() &&
        prefetched.files.isNotEmpty) {
      _applyPrefetch(prefetched);
      if (_filledSlots >= 1) {
        setState(() {
          _isGenerating = false;
          _generationError = null;
        });
        return;
      }
    }
    final firstPrompt = _buildPrompt();
    final firstSlot = _slotOrder[_filledSlots];
    setState(() {
      _filledSlots++;
    });
    await _generateSingleAvatar(firstPrompt, firstSlot);

    if (!mounted) return;
    final hasAtLeastOneAvatar = _avatarFiles.any((file) => file != null);
    setState(() {
      _isGenerating = false;
      if (!hasAtLeastOneAvatar) {
        _generationError = context.tr('friend_generate_error');
      } else {
        _generationError = null;
      }
    });
  }

  Future<FriendGeneratePrefetchData?> _consumePrefetchWithSoftTimeout() async {
    final future = widget.prefetchFuture;
    if (future == null) return null;
    final expectedSignature = widget.prefetchSignature;
    try {
      final data = await future.timeout(const Duration(milliseconds: 900));
      if (data == null) return null;
      if (expectedSignature == null || expectedSignature.isEmpty) return data;
      if (data.signature != expectedSignature) return null;
      return data;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  void _applyPrefetch(FriendGeneratePrefetchData data) {
    var assigned = 0;
    for (var i = 0; i < data.files.length && i < _slotOrder.length; i += 1) {
      final slot = _slotOrder[i];
      _avatarFiles[slot] = data.files[i];
      _promptResults[slot] = i < data.prompts.length ? data.prompts[i] : null;
      _avatarLoading[slot] = false;
      assigned += 1;
    }
    for (var i = assigned; i < _slotOrder.length; i += 1) {
      final slot = _slotOrder[i];
      _avatarLoading[slot] = false;
    }
    _filledSlots = assigned;
    if (assigned > 0) {
      _isGenerating = false;
      _generationError = null;
      final firstFilledSlot = _slotOrder.firstWhere(
        (slot) => _avatarFiles[slot] != null,
        orElse: () => 1,
      );
      _selectedAvatarIndex = firstFilledSlot;
    }
  }

  String _buildCurrentSignature() {
    return [
      widget.gender,
      widget.relationshipType,
      widget.age.toString(),
      widget.hairColor,
      widget.eyeColor,
    ].join('|');
  }

  Future<void> _generateSingleAvatar(FriendAvatarPrompt prompt, int targetSlot) async {
    var result = await _imageService.generateImageFromPrompt(prompt.prompt);
    if ((!result.isSuccess || result.file == null) &&
        _isRetryableGenerationError(result.errorMessage)) {
      await Future.delayed(const Duration(milliseconds: 450));
      result = await _imageService.generateImageFromPrompt(prompt.prompt);
    }
    if (!mounted) return;
    setState(() {
      _avatarLoading[targetSlot] = false;
      if (result.isSuccess && result.file != null) {
        _avatarFiles[targetSlot] = result.file;
        _promptResults[targetSlot] = prompt;
        if (_isGenerating) {
          _isGenerating = false;
          _selectedAvatarIndex = targetSlot;
        }
      }
      if (_filledSlots == 3 && !_avatarFiles.any((f) => f != null)) {
        _isGenerating = false;
        _generationError = context.tr('friend_generate_error');
      }
    });
  }

  bool _isRetryableGenerationError(String? message) {
    final text = message?.toLowerCase() ?? '';
    if (text.isEmpty) return false;
    return text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('истекло время') ||
        text.contains('ошибка создания задачи') ||
        text.contains('ошибка проверки статуса');
  }

  FriendAvatarPrompt _buildPrompt() {
    return _promptBuilder.build(
      gender: widget.gender,
      age: widget.age,
      hairColor: widget.hairColor,
      eyeColor: widget.eyeColor,
      relationshipType: widget.relationshipType,
      about: _aboutController.text.trim(),
      relationshipNotes: _relationshipController.text.trim(),
    );
  }

  Future<void> _generateAdditionalAvatar() async {
    if (_filledSlots >= 3) return;
    final nextSlotIndex = _slotOrder[_filledSlots];
    setState(() {
      _avatarLoading[nextSlotIndex] = true;
      _filledSlots++;
    });
    final prompt = _buildPrompt();
    await _generateSingleAvatar(prompt, nextSlotIndex);
  }

  Future<void> _hydrateFromStorage() async {
    final container = ProviderScope.containerOf(context);
    final profileRepo = container.read(friendProfileRepositoryProvider);
    final profile = profileRepo.load();
    if (profile != null && _nameController.text.trim().isEmpty) {
      _nameController.text = profile.name;
    }
    final personaRepo = container.read(friendPersonaRepositoryProvider);
    final persona = await personaRepo.load('friend');
    if (_aboutController.text.trim().isEmpty && persona.about.isNotEmpty) {
      _aboutController.text = persona.about;
    }
    if (_relationshipController.text.trim().isEmpty &&
        persona.relationshipNotes.isNotEmpty) {
      _relationshipController.text = persona.relationshipNotes;
    }
    if (_occupationController.text.trim().isEmpty &&
        persona.occupation.isNotEmpty) {
      _occupationController.text = persona.occupation;
    }
    if (_goodHabitsController.text.trim().isEmpty &&
        persona.goodHabits.isNotEmpty) {
      _goodHabitsController.text = persona.goodHabits;
    }
    if (_badHabitsController.text.trim().isEmpty &&
        persona.badHabits.isNotEmpty) {
      _badHabitsController.text = persona.badHabits;
    }
    if (_hobbiesController.text.trim().isEmpty && persona.hobbies.isNotEmpty) {
      _hobbiesController.text = persona.hobbies;
    }
  }

  void _openHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeNavigationScreen()),
      (_) => false,
    );
  }

  File? get _selectedAvatarFile {
    if (_selectedAvatarIndex < _avatarFiles.length) {
      return _avatarFiles[_selectedAvatarIndex];
    }
    return null;
  }

  FriendAvatarPrompt? get _selectedPromptResult {
    if (_selectedAvatarIndex < _promptResults.length) {
      return _promptResults[_selectedAvatarIndex];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final showContinue = _selectedAvatarFile != null;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AvatarGenerationHeader(
                      isGenerating: _isGenerating,
                      avatarFiles: _avatarFiles,
                      avatarLoading: _avatarLoading,
                      selectedIndex: _selectedAvatarIndex,
                      filledSlots: _filledSlots,
                      onAvatarSelected: (index) {
                        if (_avatarFiles[index] != null) {
                          setState(() => _selectedAvatarIndex = index);
                        }
                      },
                      onSelectedTap: () {
                        final file = _selectedAvatarFile;
                        if (file != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  _AvatarFullScreenViewer(file: file),
                            ),
                          );
                        }
                      },
                      onGenerateMore: _generateAdditionalAvatar,
                      error: _generationError,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    const FriendPersonaSectionTitle(text: 'Имя'),
                    _NameInputField(
                      controller: _nameController,
                      focusNode: _nameFocusNode,
                      placeholder: context.tr('friend_name_placeholder'),
                    ),
                    const SizedBox(height: _sectionSpacing),
                    const FriendPersonaSectionTitle(text: 'Кем работает'),
                    FriendPersonaSingleLineField(
                      hintText: _personaDefaults.occupation,
                      controller: _occupationController,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    const FriendPersonaSectionTitle(text: 'Хобби'),
                    FriendPersonaSingleLineField(
                      hintText: _personaDefaults.hobbies,
                      controller: _hobbiesController,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    FriendPersonaSectionTitle(
                      text: context.tr('friend_about_title'),
                    ),
                    FriendPersonaMultiLineField(
                      hintText: _personaDefaults.about,
                      controller: _aboutController,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    FriendPersonaSectionTitle(
                      text: context.tr('friend_relationship_title'),
                    ),
                    FriendPersonaMultiLineField(
                      hintText: _personaDefaults.relationshipNotes,
                      controller: _relationshipController,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    const FriendPersonaSectionTitle(
                      text: 'Полезные привычки',
                    ),
                    FriendPersonaMultiLineField(
                      hintText: _personaDefaults.goodHabits,
                      controller: _goodHabitsController,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    const FriendPersonaSectionTitle(
                      text: 'Вредные привычки',
                    ),
                    FriendPersonaMultiLineField(
                      hintText: _personaDefaults.badHabits,
                      controller: _badHabitsController,
                    ),
                    if (_generationError != null) ...[
                      const SizedBox(height: 16),
                      _ActionButton(
                        text: context.tr('retry'),
                        onPressed: _generateAvatars,
                        filled: false,
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (showContinue)
                      _ActionButton(
                        text: context.tr('continue_button'),
                        onPressed: () async {
                          await _persistFriendProfile();
                          _openHome();
                        },
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarGenerationHeader extends StatelessWidget {
  final bool isGenerating;
  final List<File?> avatarFiles;
  final List<bool> avatarLoading;
  final int selectedIndex;
  final int filledSlots;
  final ValueChanged<int> onAvatarSelected;
  final VoidCallback? onSelectedTap;
  final VoidCallback onGenerateMore;
  final String? error;

  const _AvatarGenerationHeader({
    required this.isGenerating,
    required this.avatarFiles,
    required this.avatarLoading,
    required this.selectedIndex,
    required this.filledSlots,
    required this.onAvatarSelected,
    required this.onGenerateMore,
    this.onSelectedTap,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 400),
      firstCurve: Curves.easeInOut,
      secondCurve: Curves.easeInOut,
      sizeCurve: Curves.easeInOut,
      crossFadeState:
          isGenerating ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      firstChild: _buildLoading(context),
      secondChild: error != null
          ? _buildError(context)
          : _buildAvatarSelection(context),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.tr('friend_generate_title'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            height: 36,
            child: LoadingIndicator(
              indicatorType: Indicator.ballScaleMultiple,
              colors: [
                colors.primary.withOpacity(0.55),
                colors.secondary.withOpacity(0.45),
                colors.onSurface.withOpacity(0.3),
              ],
              backgroundColor: Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        error!,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.error,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildAvatarSelection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(3, (index) {
          final isSelected = index == selectedIndex;
          final file = avatarFiles[index];
          final loading = avatarLoading[index];
          final canGenerate = filledSlots < 3 && file == null && !loading;
          return _AvatarCircle(
            file: file,
            isSelected: isSelected,
            isLoading: loading,
            showAddButton: canGenerate,
            onTap: file != null
                ? isSelected
                    ? onSelectedTap
                    : () => onAvatarSelected(index)
                : canGenerate
                    ? onGenerateMore
                    : null,
          );
        }),
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  static const double _selectedSize = 130.0;
  static const double _unselectedSize = 56.0;

  final File? file;
  final bool isSelected;
  final bool isLoading;
  final bool showAddButton;
  final VoidCallback? onTap;

  const _AvatarCircle({
    required this.file,
    required this.isSelected,
    this.isLoading = false,
    this.showAddButton = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = isSelected ? _selectedSize : _unselectedSize;
    final borderWidth = isSelected ? 3.0 : 1.5;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: size,
        height: size,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: EdgeInsets.all(borderWidth),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? colors.primary
                : colors.outline.withOpacity(0.3),
            width: borderWidth,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colors.primary.withOpacity(0.25),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: ClipOval(
          child: SizedBox.expand(
            child: isLoading
                ? _buildLoading(colors)
                : file != null
                    ? Image.file(
                        file!,
                        fit: BoxFit.cover,
                        alignment: const Alignment(0, -0.65),
                      )
                    : showAddButton
                        ? ColoredBox(
                            color: colors.onSurface.withOpacity(0.08),
                            child: Center(
                              child: Icon(
                                Icons.add,
                                size: isSelected ? 48 : 24,
                                color: colors.primary,
                              ),
                            ),
                          )
                        : ColoredBox(
                            color: colors.onSurface.withOpacity(0.08),
                            child: Center(
                              child: Icon(
                                Icons.person,
                                color: colors.onSurface.withOpacity(0.35),
                              ),
                            ),
                          ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(ColorScheme colors) {
    return ColoredBox(
      color: colors.onSurface.withOpacity(0.05),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: LoadingIndicator(
            indicatorType: Indicator.ballScaleMultiple,
            colors: [
              colors.primary.withOpacity(0.55),
              colors.secondary.withOpacity(0.45),
              colors.onSurface.withOpacity(0.3),
            ],
            backgroundColor: Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool filled;

  const _ActionButton({
    required this.text,
    required this.onPressed,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (filled) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.onSurface,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          side: BorderSide(color: colors.outline.withOpacity(0.4)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _AvatarFullScreenViewer extends StatelessWidget {
  final File file;

  const _AvatarFullScreenViewer({required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 3.0,
            child: Center(
              child: Image.file(
                file,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameInputField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;

  const _NameInputField({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        keyboardType: TextInputType.name,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: placeholder,
          hintStyle: const TextStyle(color: Colors.black45),
        ),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
      ),
    );
  }
}

extension _FriendProfilePersistence on _FriendGenerateScreenState {
  Future<void> _persistFriendProfile() async {
    if (!mounted) return;
    final rawName = _nameController.text.trim();
    final displayName =
        rawName.isEmpty ? context.tr('friend_default_name') : rawName;
    final selectedPrompt = _selectedPromptResult;
    final profile = FriendProfile(
      name: displayName,
      gender: widget.gender,
      age: widget.age,
      hairColor: widget.hairColor,
      eyeColor: widget.eyeColor,
      hairstyle: selectedPrompt?.hairstyle ?? '',
      ethnicity: selectedPrompt?.ethnicity ?? '',
      skinTone: selectedPrompt?.skinTone ?? '',
      bodyType: selectedPrompt?.bodyType ?? '',
      heightCategory: selectedPrompt?.heightCategory ?? '',
      relationshipType: widget.relationshipType,
      avatarPath: _selectedAvatarFile?.path,
      aiModel: FriendProfile.aiModelChat,
      avatarStatus: FriendProfile.avatarStatusReady,
    );
    final container = ProviderScope.containerOf(context);
    final profileRepo = container.read(friendProfileRepositoryProvider);
    await profileRepo.save('friend', profile);
    container.read(friendProfileProvider.notifier).state = profile;
    final avatarFile = _selectedAvatarFile;
    final appearanceService = container.read(friendAppearanceServiceProvider);

    final personaRepo = container.read(friendPersonaRepositoryProvider);
    final existing = await personaRepo.load('friend');
    final updated = existing.copyWith(
      about: _resolvePersonaValue(
        input: _aboutController.text,
        existing: existing.about,
        fallback: _personaDefaults.about,
      ),
      relationshipNotes: _resolvePersonaValue(
        input: _relationshipController.text,
        existing: existing.relationshipNotes,
        fallback: _personaDefaults.relationshipNotes,
      ),
      occupation: _resolvePersonaValue(
        input: _occupationController.text,
        existing: existing.occupation,
        fallback: _personaDefaults.occupation,
      ),
      goodHabits: _resolvePersonaValue(
        input: _goodHabitsController.text,
        existing: existing.goodHabits,
        fallback: _personaDefaults.goodHabits,
      ),
      badHabits: _resolvePersonaValue(
        input: _badHabitsController.text,
        existing: existing.badHabits,
        fallback: _personaDefaults.badHabits,
      ),
      hobbies: _resolvePersonaValue(
        input: _hobbiesController.text,
        existing: existing.hobbies,
        fallback: _personaDefaults.hobbies,
      ),
    );
    await container
        .read(friendPersonaProvider('friend').notifier)
        .save(updated);

    final messengerRepo = container.read(messengerStorageRepositoryProvider);
    await messengerRepo.clearThread('friend');

    final dailyStoryService =
        container.read(messengerDailyStoryServiceProvider);
    unawaited(() async {
      final updatedProfile =
          await appearanceService.ensureAppearanceDescription(
        profile: profile,
        avatarFile: avatarFile,
        contactId: 'friend',
      );
      if (!mounted) return;
      if (updatedProfile.appearanceDescription !=
          profile.appearanceDescription) {
        container.read(friendProfileProvider.notifier).state = updatedProfile;
      }
      await dailyStoryService.generateInitialStories(contactId: 'friend');
    }());
  }

  String _resolvePersonaValue({
    required String input,
    required String existing,
    required String fallback,
  }) {
    final trimmed = input.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final stored = existing.trim();
    if (stored.isNotEmpty) return stored;
    return fallback;
  }
}

class FriendGeneratePrefetchData {
  final String signature;
  final List<File> files;
  final List<FriendAvatarPrompt> prompts;

  const FriendGeneratePrefetchData({
    required this.signature,
    required this.files,
    required this.prompts,
  });
}
