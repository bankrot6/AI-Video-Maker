import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/notification/local_notification_service.dart';
import '../../services/providers.dart';
import '../../services/localization/app_localization_service.dart';

/// Экран для отладки уведомлений
class NotificationDebugScreen extends ConsumerWidget {
  const NotificationDebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('notification_debug_title')),
        backgroundColor: Colors.red.shade200,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const _DebugInfoCard(),
          const SizedBox(height: 16),

          // Кнопка для отправки простого критического уведомления
          _buildDebugButton(
            context,
            context.tr('send_simple_notification'),
            context.tr('simple_notification_desc'),
            Icons.notifications_active,
            Colors.orange,
            () async {
              try {
                final debugService = LocalNotificationService();
                await debugService.sendDebugNotification();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('notification_sent')),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          context.trParams('notification_send_error', ['$e'])),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
          ),

          const SizedBox(height: 12),

          // Кнопка для отправки уведомления на переднем плане
          _buildDebugButton(
            context,
            context.tr('send_foreground_notification'),
            context.tr('foreground_notification_desc'),
            Icons.phonelink_ring,
            Colors.deepPurple,
            () async {
              try {
                final mealService = ref.read(mealRemindersServiceProvider);
                await mealService.sendImmediateNotification();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('foreground_notification_sent')),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          context.trParams('notification_send_error', ['$e'])),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
          ),

          const SizedBox(height: 12),

          // Кнопка для отправки отложенного уведомления через 5 секунд
          _buildDebugButton(
            context,
            context.tr('send_delayed_notification'),
            context.tr('delayed_notification_desc'),
            Icons.timer,
            Colors.blue,
            () async {
              try {
                final mealService = ref.read(mealRemindersServiceProvider);
                await mealService.sendTestNotification();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('scheduled_notification')),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          context.trParams('notification_send_error', ['$e'])),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
          ),

          const SizedBox(height: 12),

          // Кнопка для проверки разрешений
          _buildDebugButton(
            context,
            context.tr('request_permissions'),
            context.tr('permissions_request_desc'),
            Icons.security,
            Colors.green,
            () async {
              try {
                final mealService = ref.read(mealRemindersServiceProvider);
                final hasPermissions =
                    await mealService.requestNotificationPermissions();

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        hasPermissions
                            ? context.tr('permissions_granted')
                            : context.tr('permissions_denied'),
                      ),
                      backgroundColor:
                          hasPermissions ? Colors.green : Colors.red,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context
                          .trParams('permissions_request_error', ['$e'])),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
          ),

          const SizedBox(height: 12),

          // Кнопка для проверки статуса
          _buildDebugButton(
            context,
            context.tr('debug_check_notifications_status'),
            context.tr('debug_notification_status_desc'),
            Icons.info_outline,
            Colors.purple,
            () async {
              try {
                final mealService = ref.read(mealRemindersServiceProvider);
                final statusReport =
                    await mealService.checkNotificationStatus();

                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(context.tr('notifications_status')),
                      content: SingleChildScrollView(
                        child: Text(statusReport),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(context.tr('close')),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text(context.trParams('status_check_error', ['$e'])),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
          ),

          const SizedBox(height: 16),

          // Карточка с советами по устранению проблем
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('troubleshooting_tips'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(context.tr('check_ios_settings')),
                  Text(context.tr('debug_check_dnd_mode')),
                  Text(context.tr('debug_restart_device')),
                  Text(context.tr('debug_check_focus_mode')),
                  Text(context.tr('check_sound')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugButton(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.8),
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

/// Виджет с информацией об отладке
class _DebugInfoCard extends StatelessWidget {
  const _DebugInfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('debug_warning'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('debug_description'),
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
