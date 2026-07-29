import 'package:flutter/material.dart';

import '../models/preset_earnings.dart';

class PresetEarningsCard extends StatelessWidget {
  const PresetEarningsCard({
    super.key,
    required this.earnings,
    required this.presetTitle,
    this.presetImageUrl,
    this.onTap,
  });

  final PresetEarnings earnings;
  final String? presetTitle;
  final String? presetImageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final progress = earnings.creditsEarned / PresetEarnings.maxCreditsPerPreset;
    final isMaxed = earnings.hasReachedMaxReward;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (presetImageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    presetImageUrl!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 60,
                      height: 60,
                      color: colors.surfaceContainerHighest,
                      child: Icon(
                        Icons.image_outlined,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      presetTitle ?? 'Пресет #${earnings.presetId.substring(0, 8)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.favorite_rounded,
                          size: 14,
                          color: Colors.pink.shade300,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${earnings.totalLikes} ${_pluralLikes(earnings.totalLikes)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.stars_rounded,
                          size: 14,
                          color: Colors.amber.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '+${earnings.creditsEarned}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: colors.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(
                          isMaxed ? Colors.amber.shade600 : Colors.green.shade600,
                        ),
                        minHeight: 4,
                      ),
                    ),
                    if (isMaxed)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Достигнут максимум',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.amber.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _pluralLikes(int count) {
    if (count % 10 == 1 && count % 100 != 11) {
      return 'лайк';
    } else if ([2, 3, 4].contains(count % 10) &&
        ![12, 13, 14].contains(count % 100)) {
      return 'лайка';
    } else {
      return 'лайков';
    }
  }
}
