import 'package:flutter/material.dart';

import 'app_bar_action_chip.dart';
import '../theme/semantic_colors.dart';
import '../utils/like_count_format.dart';

enum PresetLikeChipStyle {
  onImage,
  toolbar,
  appBarPlain,
}

class PresetLikeChip extends StatelessWidget {
  const PresetLikeChip({
    super.key,
    required this.count,
    required this.isLiked,
    required this.onPressed,
    this.style = PresetLikeChipStyle.onImage,
    this.busy = false,
  });

  final int count;
  final bool isLiked;
  final VoidCallback? onPressed;
  final PresetLikeChipStyle style;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final semantic = context.semanticColors;
    final formatted = formatLikeCount(count);
    final showCount = count > 0 || isLiked;

    final icon = Icon(
      isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      size: switch (style) {
        PresetLikeChipStyle.toolbar => 22,
        PresetLikeChipStyle.appBarPlain => 20,
        PresetLikeChipStyle.onImage => 18,
      },
      color: _iconColor(colors, semantic),
    );

    final textStyle = TextStyle(
      color: _textColor(colors, semantic),
      fontSize: switch (style) {
        PresetLikeChipStyle.toolbar => 14,
        PresetLikeChipStyle.appBarPlain => 14,
        PresetLikeChipStyle.onImage => 12,
      },
      fontWeight: FontWeight.w600,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        busy
            ? SizedBox(
                width: switch (style) {
                  PresetLikeChipStyle.toolbar => 22,
                  PresetLikeChipStyle.appBarPlain => 20,
                  PresetLikeChipStyle.onImage => 18,
                },
                height: switch (style) {
                  PresetLikeChipStyle.toolbar => 22,
                  PresetLikeChipStyle.appBarPlain => 20,
                  PresetLikeChipStyle.onImage => 18,
                },
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _iconColor(colors, semantic),
                ),
              )
            : icon,
        if (showCount) ...[
          SizedBox(
            width: switch (style) {
              PresetLikeChipStyle.toolbar => 6,
              PresetLikeChipStyle.appBarPlain => 4,
              PresetLikeChipStyle.onImage => 5,
            },
          ),
          Text(formatted, style: textStyle),
        ],
      ],
    );

    switch (style) {
      case PresetLikeChipStyle.onImage:
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: busy ? null : onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: semantic.imageScrim,
                border: Border.all(
                  color: semantic.onImage.withValues(alpha: 0.14),
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: child,
              ),
            ),
          ),
        );
      case PresetLikeChipStyle.toolbar:
        return AppBarActionChip(
          onTap: busy ? null : onPressed,
          borderRadius: 18,
          minHeight: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: isLiked
              ? colors.primaryContainer.withOpacity(0.9)
              : colors.surfaceContainerHighest.withOpacity(0.9),
          borderColor: isLiked
              ? colors.primary.withOpacity(0.22)
              : colors.outlineVariant.withOpacity(0.45),
          child: child,
        );
      case PresetLikeChipStyle.appBarPlain:
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: busy ? null : onPressed,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: child,
            ),
          ),
        );
    }
  }

  Color _iconColor(ColorScheme colors, SemanticColors semantic) {
    switch (style) {
      case PresetLikeChipStyle.onImage:
        return isLiked ? colors.error : semantic.onImage;
      case PresetLikeChipStyle.toolbar:
        return isLiked ? colors.primary : colors.onSurfaceVariant;
      case PresetLikeChipStyle.appBarPlain:
        return isLiked ? colors.error : colors.onSurfaceVariant;
    }
  }

  Color _textColor(ColorScheme colors, SemanticColors semantic) {
    switch (style) {
      case PresetLikeChipStyle.onImage:
        return semantic.onImage;
      case PresetLikeChipStyle.toolbar:
        return isLiked ? colors.onPrimaryContainer : colors.onSurface;
      case PresetLikeChipStyle.appBarPlain:
        return colors.onSurface;
    }
  }
}
