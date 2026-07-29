import 'package:flutter/material.dart';

import '../services/preset_reward_service.dart';

class EarnedCreditsBadge extends StatefulWidget {
  const EarnedCreditsBadge({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  State<EarnedCreditsBadge> createState() => _EarnedCreditsBadgeState();
}

class _EarnedCreditsBadgeState extends State<EarnedCreditsBadge> {
  int _earnedCredits = 0;
  int _totalLikes = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await PresetRewardService().getEarningsStats();
    if (mounted) {
      setState(() {
        _earnedCredits = stats['totalCreditsEarned'] ?? 0;
        _totalLikes = stats['totalLikes'] ?? 0;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _earnedCredits == 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.green.shade400.withOpacity(0.15),
                Colors.green.shade600.withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.green.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  size: 18,
                  color: Colors.green.shade700,
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Заработано',
                      style: TextStyle(
                        color: colors.onSurface.withOpacity(0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      '+$_earnedCredits',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
                if (_totalLikes > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 1,
                    height: 24,
                    color: Colors.green.withOpacity(0.2),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.favorite_rounded,
                    size: 14,
                    color: Colors.pink.shade300,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_totalLikes',
                    style: TextStyle(
                      color: colors.onSurface.withOpacity(0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
