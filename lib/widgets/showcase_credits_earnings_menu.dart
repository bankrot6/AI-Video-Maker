import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/credit_config.dart';
import '../models/credit_usage_model.dart';
import '../models/preset_earnings.dart';
import '../providers/credit_providers.dart';
import '../theme/semantic_colors.dart';

class ShowcaseCreditsEarningsMenu extends ConsumerWidget {
  const ShowcaseCreditsEarningsMenu({
    super.key,
    required this.expanded,
    required this.creditAsync,
    required this.earningsStats,
    required this.earningsStatsLoading,
    required this.likesPeekVisible,
    required this.newLikesSinceLastAck,
    required this.onExpand,
    required this.onCollapse,
    required this.onPurchase,
    required this.onEarningsDetails,
    required this.onHelp,
    required this.activeColor,
  });

  final bool expanded;
  final AsyncValue<CreditUsageModel> creditAsync;
  final Map<String, int>? earningsStats;
  final bool earningsStatsLoading;
  final bool likesPeekVisible;
  final int newLikesSinceLastAck;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;
  final VoidCallback onPurchase;
  final VoidCallback onEarningsDetails;
  final VoidCallback onHelp;
  final Color activeColor;

  int get _earnedCredits => earningsStats?['totalCreditsEarned'] ?? 0;
  int get _totalLikes => earningsStats?['totalLikes'] ?? 0;

  CreditUsageModel? get _usage => creditAsync.asData?.value;
  bool get _creditsLoading => creditAsync.isLoading;
  bool get _creditsError => creditAsync.hasError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showOverlay = ref.watch(creditBalanceOverlayVisibleProvider);
    return expanded
        ? _buildExpanded(context)
        : _buildCollapsed(context, showOverlay: showOverlay);
  }

  Widget _buildCollapsed(BuildContext context, {bool showOverlay = false}) {
    if (_creditsError) {
      return const SizedBox.shrink();
    }

    if (_creditsLoading || _usage == null) {
      return const SizedBox(width: 52, height: 36);
    }

    final colors = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;
    final u = _usage!;
    final remaining = u.remainingCredits;
    final isLow = remaining <= (u.isFreeUser ? 10 : 20);
    final isCritical = remaining < (u.isFreeUser ? 5 : 8);

    final Color starBg;
    final Color starFg;
    if (isCritical) {
      starBg = colors.error;
      starFg = colors.onError;
    } else if (isLow) {
      starBg = semantic.warning;
      starFg = colors.surfaceContainerLowest;
    } else {
      starBg = activeColor;
      starFg = colors.onPrimary;
    }

    final showLikesPeek = likesPeekVisible && !earningsStatsLoading;

    return Stack(
      alignment: Alignment.center,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: showOverlay ? null : onExpand,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    starBg,
                    starBg.withOpacity(0.88),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: starBg.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stars_rounded, size: 16, color: starFg),
                    const SizedBox(width: 6),
                    Text(
                      '$remaining',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: starFg,
                      ),
                    ),
                    if (showLikesPeek) ...[
                      Container(
                        width: 1,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: starFg.withOpacity(0.35),
                      ),
                      Icon(
                        Icons.favorite_rounded,
                        size: 14,
                        color: starFg.withOpacity(0.95),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$_totalLikes',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: starFg.withOpacity(0.95),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '+ $newLikesSinceLastAck',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: starFg.withOpacity(
                            newLikesSinceLastAck > 0 ? 0.95 : 0.65,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !showOverlay,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: showOverlay ? 1 : 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.scrim.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = context.semanticColors;

    if (_creditsError) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.primary.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onCollapse,
              splashRadius: 20,
              icon: Icon(
                Icons.arrow_back_rounded,
                color: colors.onSurface.withOpacity(0.72),
              ),
            ),
            Expanded(
              child: Text(
                'Не удалось загрузить баланс',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.onSurface.withOpacity(0.7),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final u = _usage;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.primary.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: onCollapse,
                  splashRadius: 20,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    color: colors.onSurface.withOpacity(0.72),
                  ),
                ),
                Expanded(
                  child: _creditsLoading || u == null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.primary,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Кредиты',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.onSurface.withOpacity(0.55),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              u.isTrialUser
                                  ? '${u.remainingCredits} кредитов + ${CreditPlan.yearly.totalCredits} (после истечения бесплатного периода)'
                                  : '${u.remainingCredits} кредитов',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurface,
                              ),
                            ),
                          ],
                        ),
                ),
                IconButton(
                  onPressed: onPurchase,
                  tooltip: 'Купить кредиты или подписку',
                  style: IconButton.styleFrom(
                    backgroundColor: activeColor.withOpacity(0.2),
                    foregroundColor: activeColor,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 22),
                ),
                IconButton(
                  onPressed: onHelp,
                  tooltip: 'Как работают лайки и кредиты',
                  splashRadius: 20,
                  icon: Icon(
                    Icons.help_outline_rounded,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onEarningsDetails,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.trending_up_rounded,
                        size: 20,
                        color: semantic.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: earningsStatsLoading
                            ? Text(
                                'Загрузка заработка…',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.onSurface.withOpacity(0.6),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Заработок за лайки',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: colors.onSurface.withOpacity(0.55),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '+$_earnedCredits кредитов · всего $_totalLikes лайков',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurface.withOpacity(0.88),
                                    ),
                                  ),
                                  if (newLikesSinceLastAck > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        'С прошлого визита: +$newLikesSinceLastAck',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: semantic.success,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    'От ${PresetEarnings.minLikesForReward} лайков на публичном пресете · до ${PresetEarnings.maxCreditsPerPreset} кредитов с пресета',
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.35,
                                      color: colors.onSurface.withOpacity(0.5),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: colors.onSurface.withOpacity(0.35),
                      ),
                    ],
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
