import 'dart:math' as math;

import 'package:flutter/material.dart';

class MagicShimmer extends StatefulWidget {
  const MagicShimmer({
    super.key,
    this.borderRadius = 0,
    this.showIcon = false,
    this.iconSize = 32,
  });

  final double borderRadius;
  final bool showIcon;
  final double iconSize;

  @override
  State<MagicShimmer> createState() => _MagicShimmerState();
}

class _MagicShimmerState extends State<MagicShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final sweep = t * 3 - 1;
        final pulse = math.sin(t * 2 * math.pi);

        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: colors.surfaceContainerHighest),
              ShaderMask(
                shaderCallback: (bounds) {
                  return LinearGradient(
                    begin: Alignment(sweep, -0.5),
                    end: Alignment(sweep + 1.5, 0.5),
                    colors: [
                      Colors.transparent,
                      colors.primary.withValues(alpha: 0.12),
                      colors.onSurface.withValues(alpha: 0.22),
                      colors.tertiary.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.srcATop,
                child: ColoredBox(color: colors.surfaceContainerHighest),
              ),
              if (widget.showIcon)
                Center(
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: widget.iconSize,
                    color: colors.primary.withValues(
                      alpha: 0.1 + 0.06 * pulse.clamp(0.0, 1.0),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
