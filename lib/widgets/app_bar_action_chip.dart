import 'package:flutter/material.dart';

class AppBarActionChip extends StatelessWidget {
  const AppBarActionChip({
    super.key,
    required this.child,
    this.onTap,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 18,
    this.minHeight = 36,
    this.minWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: 10),
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final double minHeight;
  final double? minWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: backgroundColor ?? colors.surfaceContainerHighest.withOpacity(0.9),
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color:
                  borderColor ?? colors.outlineVariant.withOpacity(0.45),
            ),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: minHeight,
              minWidth: minWidth ?? 0,
            ),
            child: Padding(
              padding: padding,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
