import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/theme_service.dart';
import '../theme/photosession_palette.dart';

class PhotosessionThemeToggle extends ConsumerWidget {
  const PhotosessionThemeToggle({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = PhotosessionPalette.of(context);
    final isDark = palette.isDark;

    return Tooltip(
      message: isDark ? 'Светлая тема' : 'Тёмная тема',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(
                isDark ? ThemeMode.light : ThemeMode.dark,
              ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.surfaceHigh,
              border: Border.all(color: palette.outline),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => RotationTransition(
                turns: Tween<double>(begin: 0.6, end: 1).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                key: ValueKey<bool>(isDark),
                size: size * 0.5,
                color: palette.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
