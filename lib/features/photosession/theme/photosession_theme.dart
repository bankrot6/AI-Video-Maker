import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/semantic_colors.dart';
import 'photosession_palette.dart';

class PhotosessionTheme {
  const PhotosessionTheme._();

  static final ThemeData dark = _build(PhotosessionPalette.dark);
  static final ThemeData light = _build(PhotosessionPalette.light);

  static ThemeData forBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  static SystemUiOverlayStyle overlayStyleFor(PhotosessionPalette palette) {
    final iconBrightness = palette.isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness: palette.brightness,
      systemNavigationBarColor: palette.background,
      systemNavigationBarIconBrightness: iconBrightness,
    );
  }

  static SemanticColors semanticColorsFor(PhotosessionPalette palette) {
    return SemanticColors(
      success: palette.success,
      warning: palette.warning,
      onImage: palette.textPrimary,
      imageScrim: palette.backgroundScrim,
    );
  }

  static ThemeData _build(PhotosessionPalette palette) {
    final scheme = ColorScheme(
      brightness: palette.brightness,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      primaryContainer: palette.accentMuted,
      onPrimaryContainer: palette.textPrimary,
      secondary: palette.textPrimary,
      onSecondary: palette.background,
      tertiary: palette.warning,
      onTertiary: palette.depth,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      surfaceContainerLowest: palette.background,
      surfaceContainerLow: palette.backgroundElevated,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.surfaceHigh,
      surfaceContainerHighest: palette.surfaceHigh,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.outline,
      outlineVariant: palette.accentMuted,
      error: palette.danger,
      onError: Colors.white,
      errorContainer: palette.danger,
      onErrorContainer: Colors.white,
      shadow: palette.depth,
      scrim: palette.depth,
      inverseSurface: palette.textPrimary,
      onInverseSurface: palette.background,
    );

    final overlayStyle = overlayStyleFor(palette);

    return ThemeData(
      brightness: palette.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      fontFamily: 'Roboto',
      shadowColor: palette.depth,
      dividerColor: palette.outline,
      splashColor: palette.accent.withValues(alpha: 0.12),
      highlightColor: palette.accent.withValues(alpha: 0.08),
      extensions: [palette, semanticColorsFor(palette)],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        systemOverlayStyle: overlayStyle,
      ),
      iconTheme: IconThemeData(
        color: palette.textPrimary,
        size: 24,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.backgroundElevated,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.backgroundElevated,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: palette.backgroundElevated,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: palette.backgroundElevated,
        elevation: 8,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.surfaceHigh,
        contentTextStyle: TextStyle(color: palette.textPrimary),
        actionTextColor: palette.accent,
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
        linearTrackColor: palette.surfaceHigh,
        circularTrackColor: palette.surfaceHigh,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        hintStyle: TextStyle(color: palette.textSecondary),
        labelStyle: TextStyle(color: palette.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.accent, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          disabledBackgroundColor: palette.surfaceHigh,
          disabledForegroundColor: palette.textSecondary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          disabledBackgroundColor: palette.surfaceHigh,
          disabledForegroundColor: palette.textSecondary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accent,
          side: BorderSide(color: palette.outline),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accent
              : palette.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.accentMuted
              : palette.surfaceHigh,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: palette.accent,
        labelStyle: TextStyle(color: palette.textPrimary),
        side: BorderSide(color: palette.outline),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: palette.accent,
        unselectedLabelColor: palette.textSecondary,
        indicatorColor: palette.accent,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
