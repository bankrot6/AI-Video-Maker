import 'package:flutter/material.dart';

@immutable
class PhotosessionPalette extends ThemeExtension<PhotosessionPalette> {
  const PhotosessionPalette({
    required this.brightness,
    required this.background,
    required this.backgroundElevated,
    required this.surface,
    required this.surfaceHigh,
    required this.accent,
    required this.accentMuted,
    required this.onAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.depth,
    required this.outline,
    required this.backgroundScrim,
    required this.depthScrim,
    required this.danger,
    required this.success,
    required this.warning,
  });

  final Brightness brightness;

  final Color background;
  final Color backgroundElevated;

  final Color surface;
  final Color surfaceHigh;

  final Color accent;
  final Color accentMuted;

  /// Контрастная пара к [accent]: подписи и иконки поверх акцентных заливок.
  final Color onAccent;

  final Color textPrimary;
  final Color textSecondary;

  final Color depth;
  final Color outline;

  /// Затемнение поверх фотографий: фон и «глубокий» цвет с альфой.
  final Color backgroundScrim;
  final Color depthScrim;

  final Color danger;
  final Color success;
  final Color warning;

  bool get isDark => brightness == Brightness.dark;

  static const PhotosessionPalette dark = PhotosessionPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0F1520),
    backgroundElevated: Color(0xFF1A2333),
    surface: Color(0xFF1A2333),
    surfaceHigh: Color(0xFF243044),
    accent: Color(0xFF0077CC),
    accentMuted: Color(0xFF2E4058),
    onAccent: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFF4F7FC),
    textSecondary: Color(0xFF8A9BB0),
    depth: Color(0xFF060A12),
    outline: Color(0xFF2E4058),
    backgroundScrim: Color(0xCC0F1520),
    depthScrim: Color(0x8C060A12),
    danger: Color(0xFFFF453A),
    success: Color(0xFF34C759),
    warning: Color(0xFFF5A623),
  );

  static const PhotosessionPalette light = PhotosessionPalette(
    brightness: Brightness.light,
    background: Color(0xFFF4F7FC),
    backgroundElevated: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFE8EEF6),
    accent: Color(0xFF0077CC),
    accentMuted: Color(0xFF9FC4E4),
    onAccent: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF1A2333),
    textSecondary: Color(0xFF5A6B7C),
    depth: Color(0xFF1A2333),
    outline: Color(0xFFD0DAE8),
    backgroundScrim: Color(0xCCF4F7FC),
    depthScrim: Color(0x8C1A2333),
    danger: Color(0xFFFF3B30),
    success: Color(0xFF34C759),
    warning: Color(0xFFF5A623),
  );

  static PhotosessionPalette forBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  static PhotosessionPalette of(BuildContext context) {
    return Theme.of(context).extension<PhotosessionPalette>() ?? dark;
  }

  @override
  PhotosessionPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? backgroundElevated,
    Color? surface,
    Color? surfaceHigh,
    Color? accent,
    Color? accentMuted,
    Color? onAccent,
    Color? textPrimary,
    Color? textSecondary,
    Color? depth,
    Color? outline,
    Color? backgroundScrim,
    Color? depthScrim,
    Color? danger,
    Color? success,
    Color? warning,
  }) {
    return PhotosessionPalette(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      backgroundElevated: backgroundElevated ?? this.backgroundElevated,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      onAccent: onAccent ?? this.onAccent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      depth: depth ?? this.depth,
      outline: outline ?? this.outline,
      backgroundScrim: backgroundScrim ?? this.backgroundScrim,
      depthScrim: depthScrim ?? this.depthScrim,
      danger: danger ?? this.danger,
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  PhotosessionPalette lerp(
    covariant ThemeExtension<PhotosessionPalette>? other,
    double t,
  ) {
    if (other is! PhotosessionPalette) return this;
    return PhotosessionPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      backgroundElevated:
          Color.lerp(backgroundElevated, other.backgroundElevated, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      depth: Color.lerp(depth, other.depth, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      backgroundScrim: Color.lerp(backgroundScrim, other.backgroundScrim, t)!,
      depthScrim: Color.lerp(depthScrim, other.depthScrim, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}

extension PhotosessionPaletteX on BuildContext {
  PhotosessionPalette get psPalette => PhotosessionPalette.of(this);
}

const kPhotosessionWatermarkLabel = 'РепИИн';
