import 'package:flutter/material.dart';
import '../../subscription/purchase_routes.dart';
import '../../../services/localization/app_localization_service.dart';

/// Сообщение о нулевом балансе токенов + две быстрые кнопки действия
class NoTokensNoticeWidget extends StatelessWidget {
  final String
      subscriptionType; // trial, free, weekly, monthly, yearly, lifetime
  const NoTokensNoticeWidget({super.key, required this.subscriptionType});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE1E1E6), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('insufficient_tokens_notice'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActionChip(
                  icon: Icons.shopping_cart,
                  label: context.tr('buy_tokens'),
                  color: Colors.green,
                  onTap: () {
                    Navigator.of(context).push(tokenPurchaseRoute());
                  },
                ),
                if (subscriptionType != 'yearly' &&
                    subscriptionType != 'lifetime')
                  _ActionChip(
                    icon: Icons.star,
                    label: subscriptionType == 'weekly' ||
                            subscriptionType == 'monthly'
                        ? context.tr('change_subscription')
                        : context.tr('get_subscription'),
                    color: Colors.blue,
                    onTap: () {
                      Navigator.of(context).push(paywallRoute());
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
