import 'package:flutter/material.dart';

import '../theme/photosession_palette.dart';

class PhotosessionSegmentedTabs extends StatelessWidget {
  PhotosessionSegmentedTabs({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.segments,
    List<bool>? enabled,
  }) : enabled = enabled ?? List.filled(segments.length, true);

  final int selected;
  final ValueChanged<int> onChanged;
  final List<String> segments;
  final List<bool> enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = PhotosessionPalette.of(context);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(segments.length, (index) {
          final isSelected = index == selected;
          final isEnabled = index < enabled.length ? enabled[index] : true;
          return Expanded(
            child: GestureDetector(
              onTap: isEnabled ? () => onChanged(index) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? palette.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: palette.depth.withValues(alpha: 0.38),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Opacity(
                  opacity: isEnabled ? 1 : 0.4,
                  child: Text(
                    segments[index],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? palette.background
                          : colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
