import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../services/localization/app_localization_service.dart';
import '../../../widgets/app_bar_action_chip.dart';
import '../theme/photosession_palette.dart';
import '../theme/photosession_theme_scope.dart';

export 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

bool photosessionLifecycleAllowsSyncFrames() {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

Future<void> preparePhotosessionCoachMarkShow(BuildContext context) async {
  if (!context.mounted) return;
  if (!photosessionLifecycleAllowsSyncFrames()) return;
  await _awaitRouteTransition(context);
  if (!context.mounted) return;
  await Future<void>.delayed(const Duration(milliseconds: 150));
}

/// Пока маршрут едет в переходе, содержимое экрана нарисовано со сдвигом:
/// `localToGlobal` вернёт координаты промежуточного кадра анимации, и вырез
/// подсветки останется в этом месте после её завершения. Сдвиг каждый раз
/// разный, потому что момент показа приходится на случайную фазу перехода.
Future<void> _awaitRouteTransition(BuildContext context) async {
  final animation = ModalRoute.of(context)?.animation;
  if (animation == null || animation.isCompleted) return;

  final settled = Completer<void>();
  void onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      if (!settled.isCompleted) settled.complete();
    }
  }

  animation.addStatusListener(onStatus);
  try {
    await Future.any<void>([
      settled.future,
      Future<void>.delayed(const Duration(milliseconds: 900)),
    ]);
  } finally {
    animation.removeStatusListener(onStatus);
  }
}

Future<void> settleLayoutForPhotosessionTutorial({
  bool forFirstStep = false,
  bool hasImages = false,
}) async {
  if (!forFirstStep) return;
  if (!photosessionLifecycleAllowsSyncFrames()) return;

  final binding = WidgetsBinding.instance;
  Future<void> waitFrame({
    Duration timeout = const Duration(milliseconds: 320),
  }) async {
    if (!photosessionLifecycleAllowsSyncFrames()) return;
    final frame = Completer<void>();
    binding.addPostFrameCallback((_) {
      if (!frame.isCompleted) frame.complete();
    });
    await Future.any<void>([
      frame.future,
      Future<void>.delayed(timeout),
    ]);
  }

  if (hasImages) {
    for (var i = 0; i < 8; i++) {
      await waitFrame();
    }
    await Future<void>.delayed(const Duration(milliseconds: 160));
    await waitFrame();
  } else {
    await waitFrame();
    await waitFrame();
  }
}

Future<void> Function(TargetFocus) photosessionTutorialBeforeFocus(
  List<TargetFocus> targets, {
  bool hasImages = false,
}) {
  final firstId = targets.first.identify;
  return (TargetFocus t) => settleLayoutForPhotosessionTutorial(
        forFirstStep: t.identify == firstId,
        hasImages: hasImages,
      );
}

enum PhotosessionTutorialScenario {
  showcase,
  showcaseFeed,
  preset,
  customCreation,
  customCreationResult,
  faceSwap,
  generation,
  creationMode,
}

extension PhotosessionTutorialScenarioX on PhotosessionTutorialScenario {
  int get storageVersion {
    switch (this) {
      case PhotosessionTutorialScenario.showcase:
        return 3;
      case PhotosessionTutorialScenario.showcaseFeed:
      case PhotosessionTutorialScenario.preset:
      case PhotosessionTutorialScenario.customCreation:
      case PhotosessionTutorialScenario.customCreationResult:
      case PhotosessionTutorialScenario.faceSwap:
      case PhotosessionTutorialScenario.generation:
        return 2;
      case PhotosessionTutorialScenario.creationMode:
        return 1;
    }
  }

  String get storageKey => 'photosession_tutorial_${name}_v$storageVersion';
}

class PhotosessionTutorialStore {
  PhotosessionTutorialStore(this._prefs);

  final SharedPreferences _prefs;

  bool shouldAutoShow(PhotosessionTutorialScenario scenario) {
    return !(_prefs.getBool(scenario.storageKey) ?? false);
  }

  Future<void> markSeen(PhotosessionTutorialScenario scenario) {
    return _prefs.setBool(scenario.storageKey, true);
  }
}

final photosessionTutorialStoreProvider =
    Provider<PhotosessionTutorialStore>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PhotosessionTutorialStore(prefs);
});

bool photosessionShowcaseCoachMarkVisible = false;

void runPhotosessionAutoTutorialChain({
  required BuildContext context,
  required WidgetRef ref,
  required bool force,
  required PhotosessionTutorialScenario scenario,
  required bool Function() schedulingGateOk,
  required List<TargetFocus> Function() buildTargets,
  required void Function(List<TargetFocus> targets) onShow,
  required bool Function() getDidTryAuto,
  required void Function(bool value) setDidTryAuto,
  required bool Function() getChainActive,
  required void Function(bool value) setChainActive,
  int maxLayoutRetries = 120,
}) {
  if (!context.mounted) return;
  if (!force) {
    final store = ref.read(photosessionTutorialStoreProvider);
    if (!store.shouldAutoShow(scenario)) return;
    if (getDidTryAuto() || getChainActive() || !schedulingGateOk()) return;
    setChainActive(true);
  } else {
    if (!schedulingGateOk()) return;
  }

  void step(int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(() async {
        if (!context.mounted) {
          if (!force) setChainActive(false);
          return;
        }
        if (!schedulingGateOk()) {
          if (!force) setChainActive(false);
          return;
        }

        final store = ref.read(photosessionTutorialStoreProvider);
        if (!force && !store.shouldAutoShow(scenario)) {
          setChainActive(false);
          return;
        }

        final targets = buildTargets();
        if (targets.isEmpty && !force && attempt < maxLayoutRetries) {
          step(attempt + 1);
          return;
        }
        if (targets.isEmpty) {
          if (!force) setChainActive(false);
          return;
        }

        if (!force) {
          setDidTryAuto(true);
          setChainActive(false);
        }

        await preparePhotosessionCoachMarkShow(context);
        if (!context.mounted) return;
        onShow(targets);
      }());
    });
  }

  step(0);
}

class PhotosessionTutorialHelpButton extends StatelessWidget {
  const PhotosessionTutorialHelpButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Показать подсказки',
    this.compact = false,
    this.plain = false,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final bool compact;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final double buttonSize = compact ? 36 : 36;
    final double iconSize = compact ? 16 : 16;

    if (plain) {
      return Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: 32,
            height: 32,
          ),
          icon: Icon(
            Icons.question_mark_rounded,
            color: colors.primary,
            size: 18,
          ),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: AppBarActionChip(
          onTap: onPressed,
          minWidth: buttonSize,
          padding: EdgeInsets.zero,
          backgroundColor: colors.surfaceContainerHighest.withOpacity(0.9),
          borderColor: colors.outlineVariant.withOpacity(0.45),
          child: Icon(
            Icons.question_mark_rounded,
            color: colors.primary,
            size: iconSize,
          ),
        ),
      ),
    );
  }
}

TargetFocus buildPhotosessionTutorialTarget({
  required BuildContext context,
  required GlobalKey key,
  required String id,
  required String title,
  required String description,
  required int step,
  required int total,
  required IconData icon,
  ContentAlign align = ContentAlign.bottom,
  double paddingFocus = 12,
  Offset contentOffset = Offset.zero,
  EdgeInsets contentPadding =
      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
}) {
  final colors = Theme.of(context).colorScheme;

  return TargetFocus(
    identify: id,
    keyTarget: key,
    shape: ShapeLightFocus.RRect,
    radius: 18,
    paddingFocus: paddingFocus,
    borderSide: BorderSide(
      color: colors.primary.withOpacity(0.7),
      width: 2,
    ),
    color: colors.primary.withOpacity(0.14),
    contents: [
      TargetContent(
        align: align,
        padding: contentPadding,
        builder: (overlayContext, controller) {
          Widget bubble = _PhotosessionTutorialBubble(
            icon: icon,
            title: title,
            description: description,
            step: step,
            total: total,
            onSkip: controller.skip,
            onNext: step == total ? controller.skip : controller.next,
          );
          if (contentOffset != Offset.zero) {
            bubble = Transform.translate(
              offset: contentOffset,
              child: bubble,
            );
          }
          // Coach mark живёт в root overlay — тема экрана туда не наследуется.
          return PhotosessionThemeScope(child: bubble);
        },
      ),
    ],
  );
}

class _PhotosessionTutorialBubble extends StatelessWidget {
  const _PhotosessionTutorialBubble({
    required this.icon,
    required this.title,
    required this.description,
    required this.step,
    required this.total,
    required this.onSkip,
    required this.onNext,
  });

  final IconData icon;
  final String title;
  final String description;
  final int step;
  final int total;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isLast = step == total;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: colors.primary.withOpacity(0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: PhotosessionPalette.of(context)
                    .depth
                    .withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.tertiary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$step/$total',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.tertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withOpacity(0.78),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: onSkip,
                    child: const Text('Пропустить'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(isLast ? 'Готово' : 'Дальше'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension PhotosessionTutorialCoachMarkX on TutorialCoachMark {
  void showForPhotosession(BuildContext context) {
    show(
      context: context,
      rootOverlay: true,
    );
  }
}
