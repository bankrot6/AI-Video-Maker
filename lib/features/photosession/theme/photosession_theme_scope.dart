import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/theme_service.dart';
import 'photosession_palette.dart';
import 'photosession_theme.dart';

/// Применяет палитру флоу создания фотосессии к поддереву, выбирая светлый
/// или тёмный вариант по текущему [themeModeProvider].
/// Ставится и на уровне маршрута (чтобы диалоги и coach marks, создаваемые
/// из State, видели тему), и внутри `build` экранов — на случай входа
/// в обход [photosessionRoute]. Повторное применение — no-op.
class PhotosessionThemeScope extends ConsumerWidget {
  const PhotosessionThemeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context
            .dependOnInheritedWidgetOfExactType<_PhotosessionThemeMarker>() !=
        null) {
      return child;
    }

    final brightness =
        _resolveBrightness(context, ref.watch(themeModeProvider));
    final palette = PhotosessionPalette.forBrightness(brightness);

    return _PhotosessionThemeMarker(
      brightness: brightness,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: PhotosessionTheme.overlayStyleFor(palette),
        child: Theme(
          data: PhotosessionTheme.forBrightness(brightness),
          child: child,
        ),
      ),
    );
  }

  static Brightness _resolveBrightness(BuildContext context, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context);
    }
  }
}

class _PhotosessionThemeMarker extends InheritedWidget {
  const _PhotosessionThemeMarker({
    required this.brightness,
    required super.child,
  });

  final Brightness brightness;

  @override
  bool updateShouldNotify(_PhotosessionThemeMarker oldWidget) =>
      brightness != oldWidget.brightness;
}

Route<T> photosessionRoute<T>(Widget child) {
  return MaterialPageRoute<T>(
    builder: (_) => PhotosessionThemeScope(child: child),
  );
}
