import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui' as ui;
import '../services/localization/app_localization_service.dart';

/// Виджет для отображения отладочной информации о языке
class LanguageDebugInfo extends ConsumerWidget {
  const LanguageDebugInfo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Получаем текущий язык из провайдера
    final currentLanguage = ref.watch(currentLanguageProvider);

    // Получаем информацию о языке системы
    final deviceLocale = ui.PlatformDispatcher.instance.locale;
    final availableLocales = ui.PlatformDispatcher.instance.locales;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "🔍 Отладка локализации",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.blue.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
              context.trParams('current_app_language', [currentLanguage.name])),
          Text(context.trParams('device_language', [deviceLocale.toString()])),
          Text(context.trParams('language_code', [deviceLocale.languageCode])),
          Text(context.trParams('country',
              [deviceLocale.countryCode ?? context.tr('not_specified')])),
          const SizedBox(height: 8),
          Text(context.tr('available_locales')),
          ...availableLocales.map((locale) => Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Text("- $locale"),
              )),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () {
              // Перезагружаем язык
              final localizationService =
                  ref.read(appLocalizationServiceProvider);
              localizationService.loadSavedLanguage();

              // Показываем сообщение
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.tr('language_reloaded')),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: Text(context.tr('reload_language')),
          ),
        ],
      ),
    );
  }
}
