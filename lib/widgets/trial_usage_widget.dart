import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/trial_protection_service.dart';
import '../services/localization/app_localization_service.dart';
import '../features/subscription/token_purchase_screen.dart';

/// Провайдер для статистики триального использования
final trialUsageStatsProvider = FutureProvider<TrialUsageStats>((ref) async {
  final trialService = TrialProtectionService();
  return await trialService.getTrialUsageStats();
});

/// Виджет отображения статистики использования триального периода
class TrialUsageWidget extends ConsumerWidget {
  final bool showDetailed;
  final bool showUpgradeButton;

  const TrialUsageWidget({
    super.key,
    this.showDetailed = false,
    this.showUpgradeButton = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(trialUsageStatsProvider);

    return statsAsync.when(
      data: (stats) => _buildTrialUsageCard(context, stats),
      loading: () => _buildLoadingCard(context),
      error: (error, stack) => _buildErrorCard(context),
    );
  }

  Widget _buildTrialUsageCard(BuildContext context, TrialUsageStats stats) {
    final theme = Theme.of(context);
    final isLowTokens = stats.tokensRemainingToday < 200;
    final isCriticalTokens = stats.tokensRemainingToday < 50;
    final isTrialAlmostOver = stats.totalTokensRemaining < 1000;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isCriticalTokens
                ? [Colors.red.shade400, Colors.red.shade600]
                : isLowTokens
                    ? [Colors.orange.shade400, Colors.orange.shade600]
                    : isTrialAlmostOver
                        ? [Colors.amber.shade400, Colors.amber.shade600]
                        : [Colors.blue.shade400, Colors.blue.shade600],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('trial_progress'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (isCriticalTokens || isTrialAlmostOver)
                    Icon(
                      Icons.warning,
                      color: Colors.white,
                      size: 20,
                    ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // Прогресс токенов на сегодня
              _buildProgressSection(
                context,
                title: context.tr('tokens_used_today'),
                used: stats.tokensUsedToday,
                total: stats.dailyLimit,
                icon: Icons.today,
              ),
              
              const SizedBox(height: 16),
              
              // Общий прогресс триала
              _buildProgressSection(
                context,
                title: context.tr('total_tokens_used'),
                used: stats.totalTokensUsed,
                total: stats.totalLimit,
                icon: Icons.timeline,
              ),
              
              if (showDetailed) ...[
                const SizedBox(height: 16),
                
                // Часовая статистика
                _buildHourlyStats(context, stats),
              ],
              
              if (isCriticalTokens || isTrialAlmostOver) ...[
                const SizedBox(height: 20),
                _buildWarningMessage(context, stats),
              ],
              
              if (showUpgradeButton) ...[
                const SizedBox(height: 20),
                _buildUpgradeButton(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection(
    BuildContext context, {
    required String title,
    required int used,
    required int total,
    required IconData icon,
  }) {
    final progress = total > 0 ? used / total : 0.0;
    final remaining = total - used;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Прогресс-бар
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: Colors.white.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(
              progress > 0.9 
                ? Colors.red.shade200
                : progress > 0.7
                    ? Colors.orange.shade200  
                    : Colors.green.shade200,
            ),
            minHeight: 8,
          ),
        ),
        
        const SizedBox(height: 4),
        
        // Текстовая информация
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_formatNumber(used)} ${context.tr('of')} ${_formatNumber(total)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
            Text(
              '${context.tr('tokens_remaining_today')}: ${_formatNumber(remaining)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHourlyStats(BuildContext context, TrialUsageStats stats) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('usage_statistics'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  title: context.tr('tokens_used_today'),
                  value: '${stats.tokensUsedThisHour}/${stats.hourlyTokenLimit}',
                  icon: Icons.schedule,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  context,
                  title: context.tr('requests_this_hour'),
                  value: '${stats.requestsThisHour}/${stats.hourlyRequestLimit}',
                  icon: Icons.send,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildWarningMessage(BuildContext context, TrialUsageStats stats) {
    String message;
    if (stats.tokensRemainingToday < 50) {
      message = context.tr('daily_tokens_exhausted');
    } else if (stats.totalTokensRemaining < 1000) {
      message = context.tr('trial_tokens_exhausted');
    } else {
      message = context.tr('upgrade_to_continue');
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _showUpgradeOptions(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.blue.shade600,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upgrade, size: 18),
            const SizedBox(width: 8),
            Text(
              context.tr('upgrade_to_continue'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Container(
        height: 150,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Container(
        height: 150,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(height: 8),
              Text(context.tr('error_loading_data')),
            ],
          ),
        ),
      ),
    );
  }

  void _showUpgradeOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        child: const PhotosessionThemeScope(
          child: TokenPurchaseScreen(),
        ),
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}k';
    } else {
      return number.toString();
    }
  }
}

/// Компактный виджет статистики триала для отображения в других экранах
class CompactTrialUsageWidget extends ConsumerWidget {
  const CompactTrialUsageWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(trialUsageStatsProvider);

    return statsAsync.when(
      data: (stats) => _buildCompactCard(context, stats),
      loading: () => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, stack) => Icon(Icons.error_outline, color: Colors.red),
    );
  }

  Widget _buildCompactCard(BuildContext context, TrialUsageStats stats) {
    final isLow = stats.tokensRemainingToday < 200;
    final isCritical = stats.tokensRemainingToday < 50;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCritical 
            ? Colors.red.withValues(alpha: 0.1)
            : isLow 
                ? Colors.orange.withValues(alpha: 0.1)
                : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCritical 
              ? Colors.red.withValues(alpha: 0.3)
              : isLow 
                  ? Colors.orange.withValues(alpha: 0.3)
                  : Colors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time,
            size: 14,
            color: isCritical 
                ? Colors.red
                : isLow 
                    ? Colors.orange
                    : Colors.green,
          ),
          const SizedBox(width: 4),
          Text(
            '${_formatNumber(stats.tokensRemainingToday)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isCritical 
                  ? Colors.red
                  : isLow 
                      ? Colors.orange
                      : Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}k';
    } else {
      return number.toString();
    }
  }
}
