import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/payment_providers.dart';
import '../../models/subscription_model.dart';
import '../../services/subscription/subscription_renewal_service.dart';
import '../../services/providers.dart' as services;
import '../../services/localization/app_localization_service.dart';

/// Виджет для настройки напоминаний о продлении подписки
class SubscriptionReminderSettings extends ConsumerStatefulWidget {
  const SubscriptionReminderSettings({super.key});

  @override
  ConsumerState<SubscriptionReminderSettings> createState() =>
      _SubscriptionReminderSettingsState();
}

class _SubscriptionReminderSettingsState
    extends ConsumerState<SubscriptionReminderSettings> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    // Получаем текущее состояние напоминаний
    final renewalEnabledAsyncValue = ref.watch(renewalRemindersEnabledProvider);
    final daysLeftAsyncValue = ref.watch(daysLeftProvider);
    final subscriptionInfoAsyncValue = ref.watch(subscriptionInfoProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Информация о подписке
        subscriptionInfoAsyncValue.when(
          data: (subscriptionInfo) {
            if (subscriptionInfo == null) {
              return ListTile(
                title: Text(context.tr('subscription_reminder_settings')),
                subtitle: Text(context.tr('no_active_subscription')),
                enabled: false,
              );
            }

            // Проверяем тип подписки - если бесплатная или пожизненная, не показываем настройки
            if (subscriptionInfo.type == SubscriptionType.free ||
                subscriptionInfo.type == SubscriptionType.lifetime) {
              return ListTile(
                title: Text(context.tr('subscription_reminder_settings')),
                subtitle: Text(context.tr('reminders_not_needed')),
                enabled: false,
              );
            }

            // В противном случае показываем настройки
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Отображаем информацию о днях до окончания подписки
                daysLeftAsyncValue.when(
                  data: (daysLeft) {
                    if (daysLeft <= 0) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          context.tr('subscription_expired'),
                          style: TextStyle(color: Colors.red),
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: Text(
                        '${context.tr('days_left')}: $daysLeft',
                        style: TextStyle(
                          color: daysLeft <= 7 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                // Переключатель для включения/отключения напоминаний
                renewalEnabledAsyncValue.when(
                  data: (isEnabled) {
                    return SwitchListTile(
                      title: Text(context.tr('subscription_reminders')),
                      subtitle: Text(
                          context.tr('subscription_reminders_description')),
                      value: isEnabled,
                      onChanged: _isLoading
                          ? null
                          : (value) => _updateRemindersSetting(value),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// Обновляет настройку напоминаний о продлении подписки
  Future<void> _updateRemindersSetting(bool value) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Обновляем настройку в сервисе напоминаний
      final renewalService = ref.read(subscriptionRenewalServiceProvider);
      await renewalService.setReminderEnabled(value);

      // Обновляем настройку в общих настройках приложения
      final settingsRepository = ref.read(services.settingsRepositoryProvider);
      await settingsRepository.setEnableRenewalReminders(value);

      // Обновляем состояние в провайдере настроек
      ref.read(services.appSettingsProvider.notifier).state = ref
          .read(services.appSettingsProvider)
          .copyWith(enableRenewalReminders: value);

      if (mounted) {
        final message = value
            ? context.tr('reminders_enabled_message')
            : context.tr('reminders_disabled_message');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: value ? Colors.green : Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.tr('settings_update_error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
