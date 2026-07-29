import 'package:flutter/material.dart';

/// Цвета, которых нет в [ColorScheme], но которые нужны общим виджетам:
/// статусы «успех/предупреждение» и контрастная пара поверх фотографии.
/// Значения задаёт активная тема; при её отсутствии берётся [fallback].
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.success,
    required this.warning,
    required this.onImage,
    required this.imageScrim,
  });

  final Color success;
  final Color warning;
  final Color onImage;
  final Color imageScrim;

  static const SemanticColors fallback = SemanticColors(
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9500),
    onImage: Colors.white,
    imageScrim: Color(0x8A000000),
  );

  @override
  SemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? onImage,
    Color? imageScrim,
  }) {
    return SemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      onImage: onImage ?? this.onImage,
      imageScrim: imageScrim ?? this.imageScrim,
    );
  }

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onImage: Color.lerp(onImage, other.onImage, t)!,
      imageScrim: Color.lerp(imageScrim, other.imageScrim, t)!,
    );
  }
}

extension SemanticColorsX on BuildContext {
  SemanticColors get semanticColors =>
      Theme.of(this).extension<SemanticColors>() ?? SemanticColors.fallback;
}
