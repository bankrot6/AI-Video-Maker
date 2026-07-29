import 'package:flutter/material.dart';

import '../../models/photo_session_preset.dart';
import '../../models/preset_tag.dart';

class PhotosessionDrawer extends StatelessWidget {
  const PhotosessionDrawer({
    super.key,
    required this.presets,
    required this.selectedTagId,
    required this.onTagSelected,
  });

  final List<PhotoSessionPreset> presets;
  final String? selectedTagId;
  final ValueChanged<String?> onTagSelected;

  static const _accentColor = Color(0xFF2196F3);

  int _countForTag(PresetTag tag) {
    if (tag.id == PresetTag.idAll || tag.id == PresetTag.idTrending) {
      return presets.length;
    }
    return presets.where((p) => p.tags.contains(tag.id)).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D0E11) : colors.surface;

    return Drawer(
      backgroundColor: bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text(
                'КАТЕГОРИИ',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurface.withOpacity(0.5),
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: PresetTag.all.length,
                itemBuilder: (context, index) {
                  final tag = PresetTag.all[index];
                  final count = _countForTag(tag);
                  final isSelected = _isSelected(tag.id);
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        onTagSelected(
                            tag.id == PresetTag.idAll ? null : tag.id);
                        Navigator.of(context).pop();
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? _accentColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              tag.icon,
                              size: 22,
                              color: isSelected
                                  ? Colors.white
                                  : colors.onSurface.withOpacity(0.8),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                tag.name,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isSelected
                                      ? Colors.white
                                      : colors.onSurface,
                                  fontWeight:
                                      isSelected ? FontWeight.w600 : null,
                                ),
                              ),
                            ),
                            Text(
                              '$count',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isSelected
                                    ? Colors.white.withOpacity(0.9)
                                    : colors.onSurface.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSelected(String tagId) {
    if (selectedTagId == null || selectedTagId!.isEmpty) {
      return tagId == PresetTag.idAll;
    }
    return selectedTagId == tagId;
  }
}
