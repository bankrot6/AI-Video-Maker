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
    background: Color(0xFF3A0F13),
    backgroundElevated: Color(0xFF4A171C),
    surface: Color(0xFF4C4A3A),
    surfaceHigh: Color(0xFF5A5845),
    accent: Color(0xFFB8976A),
    accentMuted: Color(0xFF8C7150),
    textPrimary: Color(0xFFE8DCC4),
    textSecondary: Color(0xFFC4B79C),
    depth: Color(0xFF1A1A1A),
    outline: Color(0xFF7A6A55),
    backgroundScrim: Color(0xCC3A0F13),
    depthScrim: Color(0x8C1A1A1A),
    danger: Color(0xFFC25A45),
    success: Color(0xFF8A9A6B),
    warning: Color(0xFFD6A75C),
  );

  static const PhotosessionPalette light = PhotosessionPalette(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    backgroundElevated: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F2EE),
    surfaceHigh: Color(0xFFEAE5DE),
    accent: Color(0xFF5A5A3C),
    accentMuted: Color(0xFF7C7C5A),
    textPrimary: Color(0xFF2C2C2C),
    textSecondary: Color(0xFF6B6B6B),
    depth: Color(0xFF2C2C2C),
    outline: Color(0xFFD9D3CA),
    backgroundScrim: Color(0xCCFFFFFF),
    depthScrim: Color(0x8C2C2C2C),
    danger: Color(0xFF9E3B3B),
    success: Color(0xFF5A5A3C),
    warning: Color(0xFFB07D2B),
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
