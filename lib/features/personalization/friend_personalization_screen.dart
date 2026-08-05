import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/android_system_ui_controller.dart';
import '../../services/localization/app_localization_service.dart';
import 'models/friend_persona.dart';
import 'personalization_providers.dart';
import 'services/friend_persona_defaults_builder.dart';
import 'widgets/friend_persona_fields.dart';

class FriendPersonalizationScreen extends ConsumerStatefulWidget {
  final String contactId;
  final String contactName;
  final String gender;

  const FriendPersonalizationScreen({
    super.key,
    required this.contactId,
    required this.contactName,
    this.gender = 'male',
  });

  @override
  ConsumerState<FriendPersonalizationScreen> createState() =>
      _FriendPersonalizationScreenState();
}

class _FriendPersonalizationScreenState
    extends ConsumerState<FriendPersonalizationScreen>
    with WidgetsBindingObserver {
  static const double _sectionSpacing = 16;
  final Random _random = Random();
  final _aboutController = TextEditingController();
  final _occupationController = TextEditingController();
  final _goodHabitsController = TextEditingController();
  final _badHabitsController = TextEditingController();
  final _hobbiesController = TextEditingController();
  final _bestMomentsController = TextEditingController();
  final _traitsController = TextEditingController();
  final _secretsController = TextEditingController();
  final _relationshipController = TextEditingController();

  late final FriendPersonaDefaults _personaDefaults;
  bool _initialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidSystemUiController.showNavigationBar();
    _personaDefaults = FriendPersonaDefaultsBuilder(random: _random)
        .build(gender: widget.gender);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AndroidSystemUiController.hideNavigationBar();
    _aboutController.dispose();
    _occupationController.dispose();
    _goodHabitsController.dispose();
    _badHabitsController.dispose();
    _hobbiesController.dispose();
    _bestMomentsController.dispose();
    _traitsController.dispose();
    _secretsController.dispose();
    _relationshipController.dispose();
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

  void _hydrateControllers(FriendPersona persona) {
    if (_initialized) return;
    _initialized = true;
    _aboutController.text = persona.about;
    _occupationController.text = persona.occupation;
    _goodHabitsController.text = persona.goodHabits;
    _badHabitsController.text = persona.badHabits;
    _hobbiesController.text = persona.hobbies;
    _bestMomentsController.text = persona.bestMoments;
    _traitsController.text = persona.characterTraits;
    _secretsController.text = persona.sharedSecrets;
    _relationshipController.text = persona.relationshipNotes;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
    });
    final persona = FriendPersona(
      about: _aboutController.text.trim(),
      occupation: _occupationController.text.trim(),
      goodHabits: _goodHabitsController.text.trim(),
      badHabits: _badHabitsController.text.trim(),
      hobbies: _hobbiesController.text.trim(),
      bestMoments: _bestMomentsController.text.trim(),
      characterTraits: _traitsController.text.trim(),
      sharedSecrets: _secretsController.text.trim(),
      relationshipNotes: _relationshipController.text.trim(),
    );
    final notifier = ref.read(friendPersonaProvider(widget.contactId).notifier);
    final success = await notifier.save(persona);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Сохранено' : 'Не удалось сохранить настройки',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final personaAsync = ref.watch(friendPersonaProvider(widget.contactId));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Персонализация ${widget.contactName}'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: personaAsync.when(
          data: (persona) {
            _hydrateControllers(persona);
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
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
                  text: context.tr('friend_about_title'),
                ),
                FriendPersonaMultiLineField(
                  controller: _aboutController,
                  hintText: _personaDefaults.about,
                ),
                const SizedBox(height: _sectionSpacing),
                FriendPersonaSectionTitle(
                  text: context.tr('friend_relationship_title'),
                ),
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
                const FriendPersonaSectionTitle(text: 'Лучшие моменты вместе'),
                FriendPersonaMultiLineField(
                  controller: _bestMomentsController,
                  hintText: 'Запоминающиеся события и истории',
                ),
                const SizedBox(height: _sectionSpacing),
                const FriendPersonaSectionTitle(text: 'Черты характера'),
                FriendPersonaMultiLineField(
                  controller: _traitsController,
                  hintText: _personaDefaults.traitsHint,
                ),
                const SizedBox(height: _sectionSpacing),
                const FriendPersonaSectionTitle(text: 'Общие секреты'),
                FriendPersonaMultiLineField(
                  controller: _secretsController,
                  hintText: 'То, что знаете только вы',
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (_, __) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Не удалось загрузить данные'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(friendPersonaProvider(widget.contactId));
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
