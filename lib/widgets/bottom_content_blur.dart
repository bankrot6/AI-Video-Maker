import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// Виджет для градиентного размытия нижней части контента под навигационным баром
/// Имитирует поведение iOS 26, где контент плавно размывается снизу
/// Использует многослойное размытие для создания плавного перехода
class BottomContentBlur extends StatelessWidget {
  /// Высота области размытия (по умолчанию 120px)
  final double blurHeight;

  /// Максимальная интенсивность размытия внизу (по умолчанию 8)
  final double maxBlurIntensity;

  /// Цвет наложения (опционально, для дополнительного затемнения)
  final Color? overlayColor;

  const BottomContentBlur({
    super.key,
    this.blurHeight = 120.0,
    this.maxBlurIntensity = 8.0,
    this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: blurHeight,
      child: IgnorePointer(
        child: Stack(
          children: [
            // Слой 1: Легкое размытие для всей области (20% от макс)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: maxBlurIntensity * 0.2,
                    sigmaY: maxBlurIntensity * 0.2,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Слой 2: Среднее размытие для нижних 70% (40% от макс)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: blurHeight * 0.7,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: maxBlurIntensity * 0.4,
                    sigmaY: maxBlurIntensity * 0.4,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          (overlayColor ?? Colors.white).withOpacity(0.01),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Слой 3: Сильное размытие для нижних 40% (100% от макс)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: blurHeight * 0.4,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: maxBlurIntensity,
                    sigmaY: maxBlurIntensity,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          (overlayColor ?? Colors.white).withOpacity(0.02),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Виджет-маска для создания fade-out эффекта контента снизу
/// Использует ShaderMask для плавного исчезновения контента
class BottomFadeMask extends StatelessWidget {
  final Widget child;

  /// Высота области затухания
  final double fadeHeight;

  /// Начало затухания (0.0 = начинается сверху, 1.0 = только внизу)
  final double fadeStart;

  /// Сила затухания (>1.0 — быстрее и сильнее, 1.0 — линейно)
  final double fadeStrength;

  /// Начальная непрозрачность в точке первичного провала (0..1)
  /// Меньше — сильнее первичное затухание. По умолчанию 0.25
  final double initialOpacity;

  const BottomFadeMask({
    super.key,
    required this.child,
    this.fadeHeight = 120.0,
    this.fadeStart = 0.85,
    this.fadeStrength = 1.0,
    this.initialOpacity = 0.25,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        final double totalHeight = bounds.height;
        if (totalHeight <= 0) {
          return const LinearGradient(colors: [Colors.white, Colors.white])
              .createShader(bounds);
        }

        // Привязываем начало затухания к нижней части экрана на высоте fadeHeight
        final double clampedFadeHeight = fadeHeight.clamp(0.0, totalHeight);
        final double topWhiteStop =
            ((totalHeight - clampedFadeHeight) / totalHeight).clamp(0.0, 1.0);
        final double zoneFrac = (clampedFadeHeight / totalHeight);
        final double fadeStartStop =
            (topWhiteStop + (fadeStart.clamp(0.0, 1.0) * zoneFrac))
                .clamp(0.0, 1.0);

        // Более резкое падение альфы: промежуточная точка с пониженной непрозрачностью
        final double midT = (0.25 / fadeStrength.clamp(0.5, 4.0))
            .clamp(0.02, 0.5); // чем больше сила, тем ближе к началу
        final double midStop =
            (fadeStartStop + zoneFrac * midT).clamp(0.0, 1.0);

        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white, // сохраняем контент
            Colors.white, // до начала затухания
            Colors.white.withOpacity(
                initialOpacity.clamp(0.0, 1.0)), // первичный провал
            Colors.transparent, // исчезновение к низу
          ],
          stops: [0.0, fadeStartStop, midStop, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}

/// Виджет-маска для создания fade-out эффекта контента сверху
/// Использует ShaderMask для плавного исчезновения контента
class TopFadeMask extends StatelessWidget {
  final Widget child;

  /// Высота области затухания
  final double fadeHeight;

  /// Начало затухания (0.0 = начинается снизу, 1.0 = только сверху)
  final double fadeStart;

  /// Сила затухания (>1.0 — быстрее и сильнее, 1.0 — линейно)
  final double fadeStrength;

  /// Начальная непрозрачность в точке первичного провала (0..1)
  final double initialOpacity;

  const TopFadeMask({
    super.key,
    required this.child,
    this.fadeHeight = 120.0,
    this.fadeStart = 0.85,
    this.fadeStrength = 1.0,
    this.initialOpacity = 0.25,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        final double totalHeight = bounds.height;
        if (totalHeight <= 0) {
          return const LinearGradient(colors: [Colors.white, Colors.white])
              .createShader(bounds);
        }

        // Привязываем начало затухания к верхней части экрана на высоте fadeHeight
        final double clampedFadeHeight = fadeHeight.clamp(0.0, totalHeight);
        final double bottomWhiteStop =
            (clampedFadeHeight / totalHeight).clamp(0.0, 1.0);
        final double zoneFrac = (clampedFadeHeight / totalHeight);
        final double fadeStartStop =
            ((1.0 - fadeStart.clamp(0.0, 1.0)) * zoneFrac)
                .clamp(0.0, 1.0);

        // Более резкое падение альфы: промежуточная точка с пониженной непрозрачностью
        final double midT = (0.25 / fadeStrength.clamp(0.5, 4.0))
            .clamp(0.02, 0.5);
        final double midStop =
            (fadeStartStop + zoneFrac * midT).clamp(0.0, bottomWhiteStop);

        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent, // исчезновение сверху
            Colors.white.withOpacity(
                initialOpacity.clamp(0.0, 1.0)), // первичный провал
            Colors.white, // до конца затухания
            Colors.white, // сохраняем контент
          ],
          stops: [0.0, midStop, fadeStartStop, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}

/// Комбинированный виджет: fade-out контента сверху и снизу
class TopBottomFadeMask extends StatelessWidget {
  final Widget child;
  
  /// Высота области затухания сверху
  final double topFadeHeight;
  
  /// Высота области затухания снизу
  final double bottomFadeHeight;
  
  /// Начало затухания сверху
  final double topFadeStart;
  
  /// Начало затухания снизу
  final double bottomFadeStart;
  
  /// Сила затухания
  final double fadeStrength;

  const TopBottomFadeMask({
    super.key,
    required this.child,
    this.topFadeHeight = 100.0,
    this.bottomFadeHeight = 180.0,
    this.topFadeStart = 0.85,
    this.bottomFadeStart = 0.40,
    this.fadeStrength = 3.2,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        final double totalHeight = bounds.height;
        if (totalHeight <= 0) {
          return const LinearGradient(colors: [Colors.white, Colors.white])
              .createShader(bounds);
        }

        // Верхняя зона затухания
        final double clampedTopFadeHeight = topFadeHeight.clamp(0.0, totalHeight);
        final double topZoneFrac = clampedTopFadeHeight / totalHeight;
        final double topFadeEnd = ((1.0 - topFadeStart.clamp(0.0, 1.0)) * topZoneFrac).clamp(0.0, 1.0);
        final double topMidT = (0.25 / fadeStrength.clamp(0.5, 4.0)).clamp(0.02, 0.5);
        final double topMidStop = (topFadeEnd * (1.0 - topMidT)).clamp(0.0, topZoneFrac);

        // Нижняя зона затухания
        final double clampedBottomFadeHeight = bottomFadeHeight.clamp(0.0, totalHeight);
        final double bottomTopWhiteStop = ((totalHeight - clampedBottomFadeHeight) / totalHeight).clamp(0.0, 1.0);
        final double bottomZoneFrac = clampedBottomFadeHeight / totalHeight;
        final double bottomFadeStartStop = (bottomTopWhiteStop + (bottomFadeStart.clamp(0.0, 1.0) * bottomZoneFrac)).clamp(0.0, 1.0);
        final double bottomMidT = (0.25 / fadeStrength.clamp(0.5, 4.0)).clamp(0.02, 0.5);
        final double bottomMidStop = (bottomFadeStartStop + bottomZoneFrac * bottomMidT).clamp(0.0, 1.0);

        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent, // исчезновение сверху
            Colors.white.withOpacity(0.25), // первичный провал сверху
            Colors.white, // полная видимость в середине
            Colors.white, // до начала затухания снизу
            Colors.white.withOpacity(0.25), // первичный провал снизу
            Colors.transparent, // исчезновение снизу
          ],
          stops: [
            0.0,
            topMidStop,
            topFadeEnd,
            bottomFadeStartStop,
            bottomMidStop,
            1.0,
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}

/// Комбинированный виджет: fade-out контента + размытие
/// Максимально приближен к эффекту iOS 26
class IOSStyleBottomBlur extends StatelessWidget {
  final Widget child;

  /// Высота области эффекта
  final double effectHeight;

  /// Максимальная интенсивность размытия
  final double maxBlurIntensity;

  /// С какого процента высоты начинается затухание контента
  final double fadeStart;

  /// Цвет наложения для размытия
  final Color? overlayColor;

  const IOSStyleBottomBlur({
    super.key,
    required this.child,
    this.effectHeight = 120.0,
    this.maxBlurIntensity = 8.0,
    this.fadeStart = 0.80,
    this.overlayColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Контент с fade-out маской
        BottomFadeMask(
          fadeHeight: effectHeight,
          fadeStart: fadeStart,
          child: child,
        ),
        // Размытие снизу
        BottomContentBlur(
          blurHeight: effectHeight,
          maxBlurIntensity: maxBlurIntensity,
          overlayColor: overlayColor,
        ),
      ],
    );
  }
}
