import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/providers.dart';
import '../services/notification/local_notification_service.dart';
import '../services/localization/app_localization_service.dart';
import '../config/feature_flags.dart'; // FEATURE_FLAG: NOTIFICATIONS

/// Виджет для настройки уведомлений о приемах пищи
class MealNotificationsSettings extends ConsumerStatefulWidget {
  const MealNotificationsSettings({super.key});

  @override
  ConsumerState<MealNotificationsSettings> createState() =>
      _MealNotificationsSettingsState();
}

class _MealNotificationsSettingsState
    extends ConsumerState<MealNotificationsSettings> {
  bool _areNotificationsEnabled = false;
  late TimeOfDay _breakfastTime;
  late TimeOfDay _lunchTime;
  late TimeOfDay _dinnerTime;

  @override
  void initState() {
    super.initState();
    _breakfastTime = const TimeOfDay(hour: 8, minute: 0);
    _lunchTime = const TimeOfDay(hour: 13, minute: 0);
    _dinnerTime = const TimeOfDay(hour: 19, minute: 0);
    _checkNotificationsStatus();
  }

  Future<void> _checkNotificationsStatus() async {
    // Получаем сервис напоминаний о приемах пищи
    final mealRemindersService = ref.read(mealRemindersServiceProvider);

    // Проверяем, настроены ли напоминания
    final areRemindersSet = mealRemindersService.areRemindersSet();

    setState(() {
      _areNotificationsEnabled = areRemindersSet;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() {
      _areNotificationsEnabled = value;
    });

    // Получаем сервис напоминаний о приемах пищи
    final mealRemindersService = ref.read(mealRemindersServiceProvider);

    if (value) {
      // Включаем напоминания
      await mealRemindersService.setupBreakfastReminder(
          hour: _breakfastTime.hour, minute: _breakfastTime.minute);
      await mealRemindersService.setupLunchReminder(
          hour: _lunchTime.hour, minute: _lunchTime.minute);
      await mealRemindersService.setupDinnerReminder(
          hour: _dinnerTime.hour, minute: _dinnerTime.minute);

      // Отправляем тестовое уведомление
      await mealRemindersService.sendTestNotification();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('reminders_enabled')),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      // Отключаем напоминания
      await mealRemindersService.cancelAllMealReminders();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('notifications_disabled')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _selectBreakfastTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _breakfastTime,
      helpText: context.tr('select_breakfast_time'),
    );

    if (picked != null && picked != _breakfastTime) {
      setState(() {
        _breakfastTime = picked;
      });

      if (_areNotificationsEnabled) {
        // Обновляем напоминание
        final mealRemindersService = ref.read(mealRemindersServiceProvider);
        await mealRemindersService.setupBreakfastReminder(
            hour: _breakfastTime.hour, minute: _breakfastTime.minute);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('breakfast_time_updated')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _selectLunchTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _lunchTime,
      helpText: context.tr('select_lunch_time'),
    );

    if (picked != null && picked != _lunchTime) {
      setState(() {
        _lunchTime = picked;
      });

      if (_areNotificationsEnabled) {
        // Обновляем напоминание
        final mealRemindersService = ref.read(mealRemindersServiceProvider);
        await mealRemindersService.setupLunchReminder(
            hour: _lunchTime.hour, minute: _lunchTime.minute);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('lunch_time_updated')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _selectDinnerTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _dinnerTime,
      helpText: context.tr('select_dinner_time'),
    );

    if (picked != null && picked != _dinnerTime) {
      setState(() {
        _dinnerTime = picked;
      });

      if (_areNotificationsEnabled) {
        // Обновляем напоминание
        final mealRemindersService = ref.read(mealRemindersServiceProvider);
        await mealRemindersService.setupDinnerReminder(
            hour: _dinnerTime.hour, minute: _dinnerTime.minute);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('dinner_time_updated')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    final hour = tod.hour.toString().padLeft(2, '0');
    final minute = tod.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    // FEATURE_FLAG: NOTIFICATIONS - Не показываем виджет если уведомления отключены
    if (!FeatureFlags.enableNotifications) {
      return const SizedBox.shrink();
    }
    
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('meal_reminders'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Switch(
                  value: _areNotificationsEnabled,
                  onChanged: _toggleNotifications,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('reminders_description'),
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading:
                  const Icon(Icons.wb_sunny_outlined, color: Colors.orange),
              title: Text(context.tr('breakfast')),
              subtitle: Text(_formatTimeOfDay(_breakfastTime)),
              trailing: IconButton(
                icon: const Icon(Icons.access_time),
                onPressed:
                    _areNotificationsEnabled ? _selectBreakfastTime : null,
              ),
              enabled: _areNotificationsEnabled,
            ),
            const Divider(),
            ListTile(
              leading:
                  const Icon(Icons.lunch_dining_outlined, color: Colors.green),
              title: Text(context.tr('lunch')),
              subtitle: Text(_formatTimeOfDay(_lunchTime)),
              trailing: IconButton(
                icon: const Icon(Icons.access_time),
                onPressed: _areNotificationsEnabled ? _selectLunchTime : null,
              ),
              enabled: _areNotificationsEnabled,
            ),
            const Divider(),
            ListTile(
              leading:
                  const Icon(Icons.dinner_dining_outlined, color: Colors.blue),
              title: Text(context.tr('dinner')),
              subtitle: Text(_formatTimeOfDay(_dinnerTime)),
              trailing: IconButton(
                icon: const Icon(Icons.access_time),
                onPressed: _areNotificationsEnabled ? _selectDinnerTime : null,
              ),
              enabled: _areNotificationsEnabled,
            ),
            const SizedBox(height: 16),
            if (_areNotificationsEnabled)
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    final mealRemindersService =
                        ref.read(mealRemindersServiceProvider);
                    await mealRemindersService.sendTestNotification();

                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr('test_notification_sent')),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                  icon: const Icon(Icons.notifications_active),
                  label: Text(context.tr('send_test_notification')),
                ),
              ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  // Используем прямое обращение к локальному сервису уведомлений для отладки
                  final debugService = LocalNotificationService();
                  await debugService.sendDebugNotification();

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('debug_notification_sent')),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                icon: const Icon(Icons.bug_report, color: Colors.red),
                label: Text(context.tr('send_debug_notification'),
                    style: const TextStyle(color: Colors.red)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  final mealRemindersService =
                      ref.read(mealRemindersServiceProvider);

                  final hasPermission = await mealRemindersService
                      .requestNotificationPermissions();

                  if (!mounted) return;
                  if (hasPermission) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr('notifications_granted')),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text(context.tr('notification_permissions_denied')),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.settings),
                label: Text(context.tr('check_permissions')),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  final mealRemindersService =
                      ref.read(mealRemindersServiceProvider);
                  final statusReport =
                      await mealRemindersService.checkNotificationStatus();

                  if (!mounted) return;
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
                },
                icon: const Icon(Icons.info_outline, color: Colors.blue),
                label: Text(context.tr('check_notifications_status'),
                    style: const TextStyle(color: Colors.blue)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  // Показываем диалог подтверждения
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(context.tr('reset_all_notifications_title')),
                      content:
                          Text(context.tr('reset_all_notifications_message')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(context.tr('cancel')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: Text(context.tr('reset')),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    final mealRemindersService =
                        ref.read(mealRemindersServiceProvider);

                    try {
                      await mealRemindersService.resetAllNotifications();

                      // Обновляем состояние UI
                      setState(() {
                        _areNotificationsEnabled = false;
                      });

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text(context.tr('notifications_reset_success')),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context
                              .trParams('notifications_reset_error', ['$e'])),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.refresh, color: Colors.red),
                label: const Text(
                  'Сбросить все уведомления',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ),

            // Добавляем информацию в случае проблем
            if (!_areNotificationsEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: ExpansionTile(
                  title: Text(
                    context.tr('notifications_troubleshooting'),
                    style:
                        const TextStyle(fontSize: 14, color: Colors.deepOrange),
                  ),
                  leading: const Icon(
                    Icons.help_outline,
                    color: Colors.deepOrange,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('if_notifications_dont_appear'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(context.tr('check_notification_instructions1')),
                          Text(context.tr('notifications_check_dnd_mode')),
                          Text(context.tr('restart_app')),
                          Text(context.tr('notifications_check_focus_mode')),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('on_ios'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(context.tr('check_notification_instructions2')),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('on_android'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(context.tr('check_notification_instructions2')),
                        ],
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
