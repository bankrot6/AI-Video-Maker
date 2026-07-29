import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/providers.dart' as services;
import '../services/localization/app_localization_service.dart';
import '../config/feature_flags.dart'; // FEATURE_FLAG: NOTIFICATIONS

/// Виджет для настройки умных уведомлений о приемах пищи
class SmartMealNotificationsSettings extends ConsumerStatefulWidget {
  const SmartMealNotificationsSettings({super.key});

  @override
  ConsumerState<SmartMealNotificationsSettings> createState() =>
      _SmartMealNotificationsSettingsState();
}

class _SmartMealNotificationsSettingsState
    extends ConsumerState<SmartMealNotificationsSettings> {
  bool _areNotificationsEnabled = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkNotificationsStatus();
  }

  Future<void> _checkNotificationsStatus() async {
    try {
      final smartService =
          ref.read(services.smartMealNotificationsServiceProvider);
      final isEnabled = smartService.isEnabled;
      final hasPermissions = await smartService.checkNotificationPermissions();

      setState(() {
        _areNotificationsEnabled = isEnabled && hasPermissions;
      });
    } catch (e) {
      debugPrint('Smart notifications status check error: $e');
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final smartService =
          ref.read(services.smartMealNotificationsServiceProvider);
      final localizationService = ref.read(appLocalizationServiceProvider);

      if (value) {
        // Включаем умные уведомления
        final hasPermissions =
            await smartService.requestNotificationPermissions();

        if (hasPermissions) {
          final setupSuccess = await smartService.setupSmartNotifications(
            localizationService: localizationService,
          );

          if (setupSuccess && mounted) {
            setState(() {
              _areNotificationsEnabled = true;
            });

            _showSnackBar(
                context.tr('smart_notif_enabled_success'), Colors.green);
          } else if (mounted) {
            _showSnackBar(context.tr('smart_notif_setup_error'), Colors.red);
          }
        } else if (mounted) {
          _showSnackBar(
              context.tr('notification_permissions_denied'), Colors.orange);
        }
      } else {
        // Отключаем умные уведомления
        await smartService.disableNotifications();

        if (mounted) {
          setState(() {
            _areNotificationsEnabled = false;
          });

          _showSnackBar(context.tr('smart_notif_disabled'), Colors.blue);
        }
      }
    } catch (e) {
      debugPrint('Smart notifications toggle error: $e');
      if (mounted) {
        _showSnackBar(context.trParams('error_occurred', ['$e']), Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    try {
      final smartService =
          ref.read(services.smartMealNotificationsServiceProvider);
      await smartService.sendTestNotification();

      if (mounted) {
        _showSnackBar(context.tr('test_notification_sent'), Colors.blue);
      }
    } catch (e) {
      debugPrint('Smart notifications test error: $e');
      if (mounted) {
        _showSnackBar(
            context.trParams('notification_send_error', ['$e']), Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // FEATURE_FLAG: NOTIFICATIONS - Не показываем виджет если уведомления отключены
    if (!FeatureFlags.enableNotifications) {
      return const SizedBox.shrink();
    }
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок
            Row(
              children: [
                Icon(
                  Icons.smart_display,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('smart_notifications_title'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Описание умной логики
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).primaryColor.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('smart_notifications_logic_title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('smart_notifications_logic_bullets'),
                    style: const TextStyle(height: 1.4),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Стандартные времена
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('smart_notifications_std_times_title'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[700],
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.wb_sunny,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text(context.tr('smart_notif_breakfast_time'),
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.wb_sunny_outlined,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text(context.tr('smart_notif_lunch_time'),
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.nightlight_round,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text(context.tr('smart_notif_dinner_time'),
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Основной переключатель
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('smart_notifications_enable'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: _areNotificationsEnabled,
                    onChanged: _toggleNotifications,
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Кнопка тестового уведомления
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sendTestNotification,
                icon: const Icon(Icons.send),
                label: Text(context.tr('send_test_notification')),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Информационное сообщение
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.blue[700],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('notifications_help_text'),
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Информация о badge count (iOS)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.phone_iphone,
                    color: Colors.green[700],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('ios_badge_info_text'),
                      style: TextStyle(
                        color: Colors.green[700],
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
