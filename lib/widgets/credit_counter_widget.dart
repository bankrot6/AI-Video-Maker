import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/subscription/purchase_routes.dart';
import '../models/credit_usage_model.dart';
import '../providers/credit_providers.dart';
import '../theme/semantic_colors.dart';
import 'app_bar_action_chip.dart';

enum CreditCounterStyle {
  standard,
  toolbar,
}

class CreditCounterWidget extends ConsumerWidget {
  const CreditCounterWidget({
    super.key,
    this.style = CreditCounterStyle.standard,
  });

  final CreditCounterStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditAsync = ref.watch(creditUsageNotifierProvider);

    return creditAsync.when(
      data: (usage) => _buildCounter(context, usage),
      loading: () => _buildLoading(context),
      error: (_, __) => _buildError(context),
    );
  }

  Widget _buildCounter(BuildContext context, CreditUsageModel usage) {
    final colors = Theme.of(context).colorScheme;
    final remaining = usage.remainingCredits;
    final lowThreshold = usage.isFreeUser ? 10 : 20;
    final criticalThreshold = usage.isFreeUser ? 5 : 8;
    final isLow = remaining <= lowThreshold;
    final isCritical = remaining < criticalThreshold;

    final accentColor = isCritical
        ? colors.error
        : isLow
            ? context.semanticColors.warning
            : colors.onSurface.withOpacity(0.8);

    if (style == CreditCounterStyle.toolbar) {
      return AppBarActionChip(
        onTap: () => _onTap(context, usage),
        minHeight: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stars_rounded, size: 18, color: accentColor),
            const SizedBox(width: 4),
            Text(
              remaining.toString(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _onTap(context, usage),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stars_rounded, size: 20, color: accentColor),
            const SizedBox(width: 4),
            Text(
              remaining.toString(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    if (style == CreditCounterStyle.toolbar) {
      return const AppBarActionChip(
        minHeight: 36,
        minWidth: 36,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    if (style == CreditCounterStyle.toolbar) {
      return AppBarActionChip(
        minHeight: 36,
        minWidth: 36,
        padding: EdgeInsets.zero,
        child: Icon(Icons.error_outline, size: 18, color: errorColor),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Icon(Icons.error_outline, size: 20, color: errorColor),
    );
  }

  void _onTap(BuildContext context, CreditUsageModel usage) {
    if (usage.isFreeUser) {
      Navigator.of(context).push(paywallRoute());
    } else {
      Navigator.of(context).push(tokenPurchaseRoute());
    }
  }
}

class CompactCreditCounterWidget extends ConsumerWidget {
  const CompactCreditCounterWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditAsync = ref.watch(creditUsageNotifierProvider);

    return creditAsync.when(
      data: (usage) => _buildCompact(context, usage),
      loading: () => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) =>
          const Icon(Icons.error_outline, size: 20, color: Colors.red),
    );
  }

  Widget _buildCompact(BuildContext context, CreditUsageModel usage) {
    final remaining = usage.remainingCredits;
    final lowThreshold = usage.isFreeUser ? 10 : 20;
    final criticalThreshold = usage.isFreeUser ? 5 : 8;
    final isLow = remaining <= lowThreshold;
    final isCritical = remaining < criticalThreshold;

    final color = isCritical
        ? Colors.red
        : isLow
            ? Colors.orange
            : Colors.white;

    return InkWell(
      onTap: () {
        if (usage.isFreeUser) {
          Navigator.of(context).push(
            paywallRoute(),
          );
        } else {
          Navigator.of(context).push(
            tokenPurchaseRoute(),
          );
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.stars_rounded, size: 18, color: color),
            const SizedBox(width: 4),
            Text(
              remaining.toString(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FreeUserBanner extends ConsumerWidget {
  const FreeUserBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditAsync = ref.watch(creditUsageNotifierProvider);

    return creditAsync.when(
      data: (usage) {
        if (!usage.isFreeUser) return const SizedBox.shrink();
        return _buildBanner(context, usage);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildBanner(BuildContext context, CreditUsageModel usage) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            paywallRoute(),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        const Color(0xFF1A237E),
                        const Color(0xFF4A148C),
                      ]
                    : [
                        const Color(0xFF42A5F5),
                        const Color(0xFF7E57C2),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Бесплатная версия',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.stars_rounded,
                              size: 13,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${usage.remainingCredits} кредитов',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Улучшить',
                      style: TextStyle(
                        color: Color(0xFF4A148C),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
