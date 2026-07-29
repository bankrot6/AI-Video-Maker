import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/providers.dart' as services;
import '../notification_debug/notification_debug_screen.dart';
import '../../utils/navigation.dart';
import '../subscription/purchase_routes.dart';
import '../../services/localization/app_localization_service.dart';
import 'subscription_reminder_settings.dart';
import 'payment_provider_debug_screen.dart';
import 'package:flutter/foundation.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Получаем текущие настройки из провайдера
    final settings = ref.watch(services.appSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('settings')),
      ),
      body: ListView(
        children: [
          _buildSectionHeader(context, context.tr('subscription')),

          // Добавляем пункт подписки
          ListTile(
            title: Text(context.tr('manage_subscription')),
            subtitle: Text(context.tr('manage_subscription_subtitle')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            tileColor: Colors.blue.shade50,
            onTap: () {
              Navigator.of(context).push(paywallRoute());
            },
          ),

          // Добавляем пункт меню для просмотра оставшихся запросов
          FutureBuilder(
            future: ref
                .read(services.subscriptionRepositoryProvider)
                .getCurrentSubscription(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final subscription = snapshot.data!;
                return ListTile(
                  title: Text(context.tr('available_requests')),
                  subtitle: Text(context.trParams('requests_count', [
                    '${subscription.availableRequests}',
                    '${subscription.maxRequests}'
                  ])),
                  trailing: SizedBox(
                    width: 100,
                    child: LinearProgressIndicator(
                      value: subscription.requestsPercentage,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        subscription.requestsPercentage > 0.2
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                  ),
                );
              }
              return ListTile(
                title: Text(context.tr('loading_subscription_info')),
              );
            },
          ),

          // Настройки напоминаний о продлении подписки
          const SubscriptionReminderSettings(),

          const Divider(),

          _buildSectionHeader(context, context.tr('general_settings')),

          // Переключатель для включения/отключения Google Cloud Vision
          SwitchListTile(
            title: Text(context.tr('use_google_vision')),
            subtitle: Text(context.tr('use_google_vision_subtitle')),
            value: settings.useGoogleVision,
            onChanged: (value) {
              // Обновляем настройки в репозитории
              _updateGoogleVisionSetting(ref, value);
            },
          ),

          // Переключатель для включения/отключения загрузки изображений блюд
          SwitchListTile(
            title: Text(context.tr('upload_food_images')),
            subtitle: Text(context.tr('upload_food_images_subtitle')),
            value: settings.loadDishImages,
            onChanged: (value) {
              // Обновляем настройки в репозитории
              _updateLoadDishImagesSetting(ref, value);
            },
          ),

          // Добавляем кнопку для отладки уведомлений
          ListTile(
            title: Text(context.tr('settings_notification_debug')),
            subtitle: Text(context.tr('notification_debug_tools')),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            tileColor: Colors.red.shade50,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const NotificationDebugScreen(),
                ),
              );
            },
          ),

          // Добавляем кнопку для диагностики платежного провайдера (только в debug)
          if (kDebugMode)
            ListTile(
              title: Text(context.tr('payment_diag_title_appbar')),
              subtitle: Text(context.tr('payment_diag_subtitle')),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              tileColor: Colors.orange.shade50,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const PaymentProviderDebugScreen(),
                  ),
                );
              },
            ),

          const Divider(),

          // Информационный блок для Google Vision
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('google_vision_info'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('google_vision_desc1'),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('google_vision_desc2'),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Информационный блок для загрузки изображений
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('image_upload_info'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('image_upload_desc1'),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('image_upload_desc2'),
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          // Используем общий сервис для добавления еды
          final foodInputService =
              ref.read(services.foodInputServiceProvider)(ref, context);
          foodInputService.showAddFoodOptions();
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// Обновляет настройку использования Google Cloud Vision
  Future<void> _updateGoogleVisionSetting(WidgetRef ref, bool value) async {
    // Получаем репозиторий настроек
    final settingsRepository = ref.read(services.settingsRepositoryProvider);

    // Обновляем настройку в репозитории
    await settingsRepository.setUseGoogleVision(value);

    // Обновляем состояние в провайдере
    ref.read(services.appSettingsProvider.notifier).state =
        ref.read(services.appSettingsProvider).copyWith(useGoogleVision: value);
  }

  /// Обновляет настройку загрузки изображений блюд
  Future<void> _updateLoadDishImagesSetting(WidgetRef ref, bool value) async {
    // Получаем репозиторий настроек
    final settingsRepository = ref.read(services.settingsRepositoryProvider);

    // Обновляем настройку в репозитории
    await settingsRepository.setLoadDishImages(value);

    // Обновляем состояние в провайдере
    ref.read(services.appSettingsProvider.notifier).state =
        ref.read(services.appSettingsProvider).copyWith(loadDishImages: value);
  }

  /// Создает заголовок секции настроек
  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
