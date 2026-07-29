import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/token_usage_model.dart';

import '../features/subscription/purchase_routes.dart';
import '../services/payment_providers.dart';
import '../models/subscription_model.dart';
import '../services/localization/app_localization_service.dart';
import '../providers/token_providers.dart' as token_providers;

/// Виджет счетчика токенов для отображения в меню чата
class TokenCounterWidget extends ConsumerWidget {
  const TokenCounterWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenUsageAsync =
        ref.watch(token_providers.tokenUsageNotifierProvider);
    final subTypeAsync = ref.watch(activeSubscriptionTypeProvider);

    final isTrialSubscription = subTypeAsync.maybeWhen(
      data: (t) => t == SubscriptionType.trial,
      orElse: () => false,
    );

    return tokenUsageAsync.when(
      data: (tokenUsage) =>
          _buildTokenCounter(context, tokenUsage, isTrialSubscription),
      loading: () => _buildLoadingCounter(context),
      error: (error, stack) => _buildErrorCounter(context),
    );
  }

  Widget _buildTokenCounter(
      BuildContext context, TokenUsageModel tokenUsage, bool isTrialSub) {
    final theme = Theme.of(context);
    final isLowTokens = tokenUsage.remainingTokens < 5000; // Меньше 5k токенов
    final isCriticalTokens =
        tokenUsage.remainingTokens < 1000; // Меньше 1k токенов

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openTokenPurchaseScreen(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isCriticalTokens
                ? Colors.red.withValues(alpha: 0.1)
                : isLowTokens
                    ? Colors.orange.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCriticalTokens
                  ? Colors.red.withValues(alpha: 0.3)
                  : isLowTokens
                      ? Colors.orange.withValues(alpha: 0.3)
                      : Colors.green.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bolt,
                size: 16,
                color: isCriticalTokens
                    ? Colors.red
                    : isLowTokens
                        ? Colors.orange
                        : Colors.green,
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTokenCount(tokenUsage.remainingTokens),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isCriticalTokens
                          ? Colors.red
                          : isLowTokens
                              ? Colors.orange
                              : Colors.green,
                    ),
                  ),
                  Text(
                    '${context.tr('of')} ${_formatTokenCount(tokenUsage.totalTokens)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.add_circle_outline,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCounter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            context.tr('loading'),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCounter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.red),
          const SizedBox(width: 4),
          Text(
            context.tr('error'),
            style: const TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
      ),
    );
  }

  /// Форматирует количество токенов для отображения
  String _formatTokenCount(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(0)}k';
    } else {
      return tokens.toString();
    }
  }

  /// Открывает экран покупки токенов
  void _openTokenPurchaseScreen(BuildContext context) {
    Navigator.of(context).push(tokenPurchaseRoute());
  }
}

/// Компактная версия счетчика токенов для AppBar
class CompactTokenCounterWidget extends ConsumerWidget {
  const CompactTokenCounterWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenUsageAsync =
        ref.watch(token_providers.tokenUsageNotifierProvider);

    return tokenUsageAsync.when(
      data: (tokenUsage) => _buildCompactCounter(context, tokenUsage),
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, stack) => const Icon(
        Icons.error_outline,
        size: 16,
        color: Colors.red,
      ),
    );
  }

  Widget _buildCompactCounter(
      BuildContext context, TokenUsageModel tokenUsage) {
    // Показываем триальный компактный виджет, если в модели токенов установлен флаг триала
    if (tokenUsage.isTrialUser) {
      return _buildCompactTrialCounters(context, tokenUsage);
    }

    final isLowTokens = tokenUsage.remainingTokens < 5000;
    final isCriticalTokens = tokenUsage.remainingTokens < 1000;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openTokenPurchaseScreen(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bolt,
                size: 18,
                color: isCriticalTokens
                    ? Colors.red
                    : isLowTokens
                        ? Colors.orange
                        : Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                _formatTokenCount(tokenUsage.remainingTokens),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isCriticalTokens
                      ? Colors.red
                      : isLowTokens
                          ? Colors.orange
                          : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Компактное представление для триала: два старых компактных индикатора рядом
  Widget _buildCompactTrialCounters(
      BuildContext context, TokenUsageModel tokenUsage) {
    const int yearlyTokens = 365000; // общий лимит для годовой подписки

    // Первый: ровно старый компактный вид — молния + число (tap → покупка)
    final Widget first = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openTokenPurchaseScreen(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 18, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                _formatTokenCount(tokenUsage.remainingTokens),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Второй: тот же вид, но замок вместо молнии и тусклее
    final Widget second = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(context.tr('yearly_limit_locked_title')),
              content: Text(context.tr('yearly_limit_locked_message')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(context.tr('ok')),
                ),
              ],
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 18, color: Colors.white70),
              const SizedBox(width: 4),
              Text(
                _formatTokenCount(yearlyTokens),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Немного уменьшим общий масштаб, чтобы не перекрывать заголовок (без дополнительных визуальных элементов)
    return Transform.scale(
      scale: 0.92,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          first,
          const SizedBox(width: 6),
          second,
        ],
      ),
    );
  }

  String _formatTokenCount(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(0)}k';
    } else {
      return tokens.toString();
    }
  }

  void _openTokenPurchaseScreen(BuildContext context) {
    Navigator.of(context).push(tokenPurchaseRoute());
  }
}
