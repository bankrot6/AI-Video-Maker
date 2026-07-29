import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/subscription_model.dart';
import '../../services/payment_providers.dart';
import '../../services/localization/app_localization_service.dart';

/// Виджет для отображения информации о подписке
class SubscriptionStatusWidget extends ConsumerWidget {
  const SubscriptionStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Получаем данные о подписке
    final subscriptionInfoAsync = ref.watch(subscriptionInfoProvider);
    final daysLeftAsync = ref.watch(daysLeftProvider);
    final typeAsync = ref.watch(activeSubscriptionTypeProvider);

    // Показываем информацию о подписке в зависимости от статуса
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Заголовок
            Text(
              context.tr('subscription'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Тип подписки
            typeAsync.when(
              data: (type) => _buildSubscriptionTypeInfo(context, type),
              loading: () => const CircularProgressIndicator(),
              error: (error, stack) => Text(
                '${context.tr('error')}: $error',
                style: const TextStyle(color: Colors.red),
              ),
            ),

            const SizedBox(height: 8),

            // Дни до окончания
            daysLeftAsync.when(
              data: (days) => days > 0
                  ? Text(
                      '${context.tr('days_left')}: $days',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 16),

            // Детальная информация
            subscriptionInfoAsync.when(
              data: (info) => info != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (info.isYookassa)
                          Text(
                            context.tr('payment_with_yookassa'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        Text(
                          '${context.tr('start_date')}: ${_formatDate(info.startDate, context)}',
                        ),
                        Text(
                          '${context.tr('end_date')}: ${_formatDate(info.endDate, context)}',
                        ),
                      ],
                    )
                  : Text(context.tr('no_active_subscription')),
              loading: () => const CircularProgressIndicator(),
              error: (error, stack) => Text(
                '${context.tr('error')}: $error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Формирует виджет с информацией о типе подписки
  Widget _buildSubscriptionTypeInfo(
      BuildContext context, SubscriptionType type) {
    String typeText;
    Color color;

    switch (type) {
      case SubscriptionType.free:
        typeText = context.tr('free_subscription');
        color = Colors.grey;
        break;
      case SubscriptionType.trial:
        typeText = context.tr('trial_subscription');
        color = Colors.orange;
        break;
      case SubscriptionType.weekly:
        typeText = context.tr('weekly_subscription');
        color = Colors.blue;
        break;
      case SubscriptionType.monthly:
        typeText = context.tr('monthly_subscription');
        color = Colors.green;
        break;
      case SubscriptionType.yearly:
        typeText = context.tr('yearly_subscription');
        color = Colors.purple;
        break;
      case SubscriptionType.lifetime:
        typeText = context.tr('lifetime_subscription');
        color = Colors.deepPurple;
        break;
      default:
        typeText = context.tr('unknown_subscription');
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        typeText,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Форматирует дату для отображения
  String _formatDate(DateTime date, BuildContext context) {
    // Для демонстрации используем простой формат, можно заменить на интернационализированный
    return '${date.day}.${date.month}.${date.year}';
  }
}
