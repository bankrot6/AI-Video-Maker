import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../services/android_system_ui_controller.dart';
import '../../services/localization/app_localization_service.dart';
import '../../widgets/days_picker.dart';
import '../onboarding/widgets/onboarding_simple_button.dart';
import '../personalization/models/friend_persona.dart';
import '../personalization/personalization_providers.dart';
import '../personalization/services/friend_persona_defaults_builder.dart';
import '../personalization/widgets/friend_persona_fields.dart';
import 'messenger_providers.dart';
import 'models/friend_profile.dart';

class MessengerCreateFriendScreen extends ConsumerStatefulWidget {
  const MessengerCreateFriendScreen({super.key});

  @override
  ConsumerState<MessengerCreateFriendScreen> createState() =>
      _MessengerCreateFriendScreenState();
}

class _MessengerCreateFriendScreenState
    extends ConsumerState<MessengerCreateFriendScreen>
    with WidgetsBindingObserver {
  static const double _sectionSpacing = 16;
  static const int _minAge = 18;
  static const int _maxAge = 80;
  static const List<_Option> _relationshipTypeOptions = [
    _Option('relationship', 'onboarding_friend_relationship_type_romance'),
    _Option('friend', 'onboarding_friend_relationship_type_friend'),
  ];
  static const List<_Option> _genderOptions = [
    _Option('male', 'gender_male'),
    _Option('female', 'gender_female'),
  ];
  static const List<_Option> _hairOptions = [
    _Option('blonde', 'onboarding_friend_hair_blonde'),
    _Option('brown', 'onboarding_friend_hair_brown'),
    _Option('brunette', 'onboarding_friend_hair_brunette'),
    _Option('red', 'onboarding_friend_hair_red'),
  ];
  static const List<_Option> _eyeOptions = [
    _Option('blue', 'onboarding_friend_eyes_blue'),
    _Option('green', 'onboarding_friend_eyes_green'),
    _Option('brown', 'onboarding_friend_eyes_brown'),
    _Option('gray', 'onboarding_friend_eyes_gray'),
  ];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _aboutController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _goodHabitsController = TextEditingController();
  final TextEditingController _badHabitsController = TextEditingController();
  final TextEditingController _hobbiesController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final Random _random = Random();
  final Uuid _uuid = const Uuid();
  FriendPersonaDefaults _personaDefaults =
      FriendPersonaDefaultsBuilder().build();

  String? _relationshipType;
  String? _gender;
  int _age = 25;
  String? _hairColor;
  String? _eyeColor;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidSystemUiController.showNavigationBar();
    _nameController.addListener(_handleInputChanged);
    _aboutController.addListener(_handleInputChanged);
    _relationshipController.addListener(_handleInputChanged);
    _occupationController.addListener(_handleInputChanged);
    _goodHabitsController.addListener(_handleInputChanged);
    _badHabitsController.addListener(_handleInputChanged);
    _hobbiesController.addListener(_handleInputChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AndroidSystemUiController.hideNavigationBar();
    _nameController.removeListener(_handleInputChanged);
    _aboutController.removeListener(_handleInputChanged);
    _relationshipController.removeListener(_handleInputChanged);
    _occupationController.removeListener(_handleInputChanged);
    _goodHabitsController.removeListener(_handleInputChanged);
    _badHabitsController.removeListener(_handleInputChanged);
    _hobbiesController.removeListener(_handleInputChanged);
    _nameController.dispose();
    _aboutController.dispose();
    _relationshipController.dispose();
    _occupationController.dispose();
    _goodHabitsController.dispose();
    _badHabitsController.dispose();
    _hobbiesController.dispose();
    _nameFocusNode.dispose();
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

  void _handleInputChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool get _canCreate {
    return _relationshipType != null &&
        _gender != null &&
        _hairColor != null &&
        _eyeColor != null &&
        _nameController.text.trim().isNotEmpty;
  }

  String _pickAiModel() {
    return FriendProfile.aiModelChat;
  }

  String _hairLabelKey(_Option option) {
    final gender = _gender;
    if (gender == null) return option.labelKey;
    final suffix = gender == 'female' ? 'female' : 'male';
    return '${option.labelKey}_$suffix';
  }

  String _resolvePersonaValue(
    TextEditingController controller,
    String fallback,
  ) {
    final trimmed = controller.text.trim();
    return trimmed.isNotEmpty ? trimmed : fallback;
  }

  Future<void> _createFriend() async {
    if (_isSaving || !_canCreate) return;
    setState(() => _isSaving = true);
    try {
      final contactId = 'friend_${_uuid.v4()}';
      final profile = FriendProfile(
        name: _nameController.text.trim(),
        gender: _gender ?? 'male',
        age: _age,
        hairColor: _hairColor ?? 'blonde',
        eyeColor: _eyeColor ?? 'blue',
        relationshipType: _relationshipType ?? FriendProfile.relationshipFriend,
        aiModel: _pickAiModel(),
        avatarStatus: FriendProfile.avatarStatusPending,
        avatarPath: null,
        appearanceDescription: '',
        appearanceCheckAvatarPath: null,
      );
      await ref.read(friendProfileRepositoryProvider).save(contactId, profile);
      final persona = FriendPersona(
        about: _resolvePersonaValue(_aboutController, _personaDefaults.about),
        relationshipNotes: _resolvePersonaValue(
          _relationshipController,
          _personaDefaults.relationshipNotes,
        ),
        occupation: _resolvePersonaValue(
            _occupationController, _personaDefaults.occupation),
        goodHabits: _resolvePersonaValue(
            _goodHabitsController, _personaDefaults.goodHabits),
        badHabits: _resolvePersonaValue(
            _badHabitsController, _personaDefaults.badHabits),
        hobbies:
            _resolvePersonaValue(_hobbiesController, _personaDefaults.hobbies),
      );
      await ref.read(friendPersonaProvider(contactId).notifier).save(persona);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось создать друга.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(context.tr('friend_create_title')),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    FriendPersonaSectionTitle(
                      text: context
                          .tr('onboarding_friend_relationship_type_question'),
                    ),
                    _OptionGroup(
                      options: _relationshipTypeOptions,
                      selected: _relationshipType,
                      onSelected: (value) => setState(() {
                        _relationshipType = value;
                        _personaDefaults =
                            FriendPersonaDefaultsBuilder(random: _random).build(
                          gender: _gender ?? 'male',
                          relationshipType: value,
                        );
                      }),
                    ),
                    const SizedBox(height: _sectionSpacing),
                    FriendPersonaSectionTitle(
                        text: context.tr('onboarding_friend_gender_question')),
                    _OptionGroup(
                      options: _genderOptions,
                      selected: _gender,
                      onSelected: (value) => setState(() {
                        _gender = value;
                        _personaDefaults =
                            FriendPersonaDefaultsBuilder(random: _random).build(
                          gender: value,
                          relationshipType: _relationshipType,
                        );
                      }),
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
                      controller: _occupationController,
                      hintText: _personaDefaults.occupation,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    const FriendPersonaSectionTitle(text: 'Хобби'),
                    FriendPersonaSingleLineField(
                      controller: _hobbiesController,
                      hintText: _personaDefaults.hobbies,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    FriendPersonaSectionTitle(
                        text: context.tr('friend_about_title')),
                    FriendPersonaMultiLineField(
                      controller: _aboutController,
                      hintText: _personaDefaults.about,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    FriendPersonaSectionTitle(
                        text: context.tr('friend_relationship_title')),
                    FriendPersonaMultiLineField(
                      controller: _relationshipController,
                      hintText: _personaDefaults.relationshipNotes,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    const FriendPersonaSectionTitle(text: 'Полезные привычки'),
                    FriendPersonaMultiLineField(
                      controller: _goodHabitsController,
                      hintText: _personaDefaults.goodHabits,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    const FriendPersonaSectionTitle(text: 'Вредные привычки'),
                    FriendPersonaMultiLineField(
                      controller: _badHabitsController,
                      hintText: _personaDefaults.badHabits,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    FriendPersonaSectionTitle(
                        text: context.tr('onboarding_friend_age_question')),
                    DaysPicker(
                      initialDays: _age,
                      minValue: _minAge,
                      maxValue: _maxAge,
                      onChanged: (v) => setState(() => _age = v),
                      backgroundColor: Colors.white,
                      selectionColor: const Color(0xFFF2F2F7),
                      selectionBorderColor: const Color(0xFFE1E1E6),
                      useSelectionOverlay: false,
                      showSelectionBackgroundBehind: true,
                    ),
                    const SizedBox(height: _sectionSpacing),
                    FriendPersonaSectionTitle(
                        text: context.tr('onboarding_friend_hair_question')),
                    _OptionGroup(
                      options: _hairOptions,
                      selected: _hairColor,
                      labelKeyBuilder: _hairLabelKey,
                      onSelected: (value) => setState(() => _hairColor = value),
                    ),
                    const SizedBox(height: _sectionSpacing),
                    FriendPersonaSectionTitle(
                        text: context.tr('onboarding_friend_eyes_question')),
                    _OptionGroup(
                      options: _eyeOptions,
                      selected: _eyeColor,
                      onSelected: (value) => setState(() => _eyeColor = value),
                    ),
                    const SizedBox(height: _sectionSpacing),
                    if (_canCreate)
                      OnboardingSimpleButton(
                        text: context.tr('friend_create_button'),
                        isSelected: true,
                        onPressed: _createFriend,
                        margin: EdgeInsets.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionGroup extends StatelessWidget {
  final List<_Option> options;
  final String? selected;
  final ValueChanged<String> onSelected;
  final String Function(_Option option)? labelKeyBuilder;

  const _OptionGroup({
    required this.options,
    required this.selected,
    required this.onSelected,
    this.labelKeyBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options)
          OnboardingSimpleButton(
            text: context.tr(labelKeyBuilder?.call(option) ?? option.labelKey),
            isSelected: option.value == selected,
            emphasizeSelection: true,
            onPressed: () => onSelected(option.value),
          ),
      ],
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
        textCapitalization: TextCapitalization.words,
        keyboardType: TextInputType.name,
        textInputAction: TextInputAction.next,
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

class _Option {
  final String value;
  final String labelKey;

  const _Option(this.value, this.labelKey);
}
