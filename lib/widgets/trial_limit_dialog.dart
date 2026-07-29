import 'package:flutter/material.dart';
import '../services/trial_protection_service.dart';
import '../services/localization/app_localization_service.dart';
import '../features/subscription/purchase_routes.dart';

/// Диалог уведомления о превышении лимитов триального периода
class TrialLimitDialog extends StatefulWidget {
  final TokenUsageResult usageResult;
  final VoidCallback? onDismiss;

  const TrialLimitDialog({
    super.key,
    required this.usageResult,
    this.onDismiss,
  });

  @override
  State<TrialLimitDialog> createState() => _TrialLimitDialogState();
}

class _TrialLimitDialogState extends State<TrialLimitDialog>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  AnimationController? _countdownController;
  int? _countdownSeconds;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _animationController.forward();

    // Настройка обратного отсчета если есть время ожидания
    if (widget.usageResult.waitTimeSeconds != null) {
      _countdownSeconds = widget.usageResult.waitTimeSeconds!;
      _countdownController = AnimationController(
        duration: Duration(seconds: _countdownSeconds!),
        vsync: this,
      );

      _countdownController?.addListener(() {
        if (mounted) {
          setState(() {
            _countdownSeconds = widget.usageResult.waitTimeSeconds! -
                ((_countdownController?.value ?? 0) *
                        widget.usageResult.waitTimeSeconds!)
                    .floor();
          });
        }
      });

      _countdownController?.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          Navigator.of(context).pop();
          widget.onDismiss?.call();
        }
      });

      _countdownController?.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _countdownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: _buildDialogContent(),
          );
        },
      ),
    );
  }

  Widget _buildDialogContent() {
    final limitType = _getLimitType();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Иконка и заголовок
          _buildHeader(limitType),

          const SizedBox(height: 16),

          // Описание ограничения
          _buildDescription(limitType),

          if (_countdownSeconds != null) ...[
            const SizedBox(height: 16),
            _buildCountdown(),
          ],

          const SizedBox(height: 24),

          // Действия
          _buildActions(limitType),
        ],
      ),
    );
  }

  Widget _buildHeader(LimitType limitType) {
    IconData icon;
    Color iconColor;
    String title;

    switch (limitType) {
      case LimitType.dailyLimit:
        icon = Icons.today;
        iconColor = Colors.orange;
        title = context.tr('daily_limit_exceeded');
        break;
      case LimitType.hourlyLimit:
        icon = Icons.schedule;
        iconColor = Colors.amber;
        title = context.tr('hourly_limit_exceeded');
        break;
      case LimitType.requestLimit:
        icon = Icons.send;
        iconColor = Colors.blue;
        title = context.tr('hourly_requests_exceeded');
        break;
      case LimitType.frequency:
        icon = Icons.timer;
        iconColor = Colors.red;
        title = context.tr('requests_too_frequent');
        break;
      case LimitType.trialTotal:
        icon = Icons.flag;
        iconColor = Colors.purple;
        title = context.tr('trial_total_limit_exceeded');
        break;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 40,
            color: iconColor,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDescription(LimitType limitType) {
    String description = _getDescriptionForLimitType(limitType);

    return Text(
      description,
      style: TextStyle(
        fontSize: 14,
        color: Colors.grey[600],
        height: 1.4,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildCountdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer,
            size: 16,
            color: Colors.blue,
          ),
          const SizedBox(width: 8),
          Text(
            context
                .tr('wait_seconds')
                .replaceAll('{0}', _countdownSeconds.toString()),
            style: TextStyle(
              fontSize: 13,
              color: Colors.blue[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(LimitType limitType) {
    List<Widget> actions = [];

    if (limitType == LimitType.trialTotal ||
        limitType == LimitType.dailyLimit) {
      // Для серьезных лимитов предлагаем покупку
      actions.addAll([
        _buildActionButton(
          text: context.tr('buy_tokens'),
          onPressed: () {
            Navigator.of(context).pop();
            _showTokenPurchase();
          },
          isPrimary: true,
          icon: Icons.shopping_cart,
        ),
        const SizedBox(height: 8),
        _buildActionButton(
          text: context.tr('get_subscription'),
          onPressed: () {
            Navigator.of(context).pop();
            _showSubscriptionPaywall();
          },
          isPrimary: false,
          icon: Icons.star,
        ),
      ]);
    } else {
      // Для временных лимитов - просто ждать или покупать
      if (_countdownSeconds == null) {
        actions.add(
          _buildActionButton(
            text: context.tr('buy_tokens'),
            onPressed: () {
              Navigator.of(context).pop();
              _showTokenPurchase();
            },
            isPrimary: true,
            icon: Icons.shopping_cart,
          ),
        );
      }
    }

    // Кнопка закрытия всегда есть
    actions.addAll([
      const SizedBox(height: 8),
      _buildActionButton(
        text: context.tr('understood'),
        onPressed: () {
          Navigator.of(context).pop();
          widget.onDismiss?.call();
        },
        isPrimary: false,
        icon: Icons.check,
      ),
    ]);

    return Column(
      children: actions,
    );
  }

  Widget _buildActionButton({
    required String text,
    required VoidCallback onPressed,
    required bool isPrimary,
    required IconData icon,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(text),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Colors.blue : Colors.grey[100],
          foregroundColor: isPrimary ? Colors.white : Colors.grey[700],
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: isPrimary ? 2 : 0,
        ),
      ),
    );
  }

  LimitType _getLimitType() {
    switch (widget.usageResult.reason) {
      case 'daily_limit_exceeded':
        return LimitType.dailyLimit;
      case 'hourly_limit_exceeded':
        return LimitType.hourlyLimit;
      case 'hourly_requests_exceeded':
        return LimitType.requestLimit;
      case 'requests_too_frequent':
        return LimitType.frequency;
      case 'trial_total_limit_exceeded':
      case 'insufficient_tokens':
        return LimitType.trialTotal;
      default:
        return LimitType.dailyLimit;
    }
  }

  String _getDescriptionForLimitType(LimitType limitType) {
    switch (limitType) {
      case LimitType.dailyLimit:
        final remaining = widget.usageResult.remainingTokensToday ?? 0;
        return context.trParams('trial_daily_limit_exceeded',
            [widget.usageResult.limitValue.toString(), remaining.toString()]);

      case LimitType.hourlyLimit:
        return context.trParams('trial_hourly_limit_exceeded',
            [widget.usageResult.limitValue.toString()]);

      case LimitType.requestLimit:
        return context.trParams('trial_request_limit_exceeded',
            [widget.usageResult.limitValue.toString()]);

      case LimitType.frequency:
        final waitTime = widget.usageResult.waitTimeSeconds ?? 30;
        return context
            .trParams('trial_request_too_frequent', [waitTime.toString()]);

      case LimitType.trialTotal:
        return context.trParams('trial_all_tokens_exhausted',
            [widget.usageResult.limitValue.toString()]);
    }
  }

  void _showTokenPurchase() {
    Navigator.of(context).push(tokenPurchaseRoute());
  }

  void _showSubscriptionPaywall() {
    Navigator.of(context).push(paywallRoute());
  }
}

enum LimitType {
  dailyLimit,
  hourlyLimit,
  requestLimit,
  frequency,
  trialTotal,
}

/// Функция для показа диалога лимита
void showTrialLimitDialog(
  BuildContext context,
  TokenUsageResult usageResult, {
  VoidCallback? onDismiss,
}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => TrialLimitDialog(
      usageResult: usageResult,
      onDismiss: onDismiss,
    ),
  );
}
