import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../../services/payment_providers.dart';
import '../../services/app_store_detection_service.dart';
import '../../services/rustore_billing_service.dart';
import '../../services/yookassa_payment_service.dart';
import '../../utils/app_logger.dart';
import '../../models/subscription_model.dart';
import '../../services/localization/app_localization_service.dart';

class PaymentProviderDebugScreen extends ConsumerStatefulWidget {
  const PaymentProviderDebugScreen({super.key});

  @override
  ConsumerState<PaymentProviderDebugScreen> createState() =>
      _PaymentProviderDebugScreenState();
}

class _PaymentProviderDebugScreenState
    extends ConsumerState<PaymentProviderDebugScreen> {
  String _diagnosticInfo = '...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDiagnosticInfo();
  }

  Future<void> _loadDiagnosticInfo() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Получаем информацию о источнике установки
      final storeDetectionService = AppStoreDetectionService();
      final installationSource =
          await storeDetectionService.getInstallationSource();

      // Получаем тип платежного провайдера
      final paymentProviderType =
          await ref.read(paymentProviderTypeProvider.future);

      // Получаем цены для разных провайдеров
      final rustoreService = RuStoreBillingService();
      String rustoreWeeklyPrice = '${rustoreService.getWeeklyPrice()}₽';
      String rustoreMonthlyPrice = '${rustoreService.getMonthlyPrice()}₽';
      String rustoreYearlyPrice = '${rustoreService.getYearlyPrice()}₽';

      String yookassaWeeklyPrice =
          '${YooKassaPaymentService.getPriceForSubscriptionType(SubscriptionType.weekly)}₽';
      String yookassaMonthlyPrice =
          '${YooKassaPaymentService.getPriceForSubscriptionType(SubscriptionType.monthly)}₽';
      String yookassaYearlyPrice =
          '${YooKassaPaymentService.getPriceForSubscriptionType(SubscriptionType.yearly)}₽';

      // Получаем информацию о локали
      final locale = PlatformDispatcher.instance.locale;

      // Проверяем каждое условие отдельно
      bool isRuStore = installationSource == AppStoreType.ruStore;
      bool isGooglePlayRu = installationSource == AppStoreType.googlePlay &&
          locale.countryCode == 'RU';
      bool isAppStore = installationSource == AppStoreType.appStore;
      bool isUnknown = installationSource == AppStoreType.unknown;

      String diagnosticInfo = '''
${ref.read(appLocalizationServiceProvider).translate('payment_diag_title')}

${ref.read(appLocalizationServiceProvider).translateWithParams('payment_diag_source', [
            storeDetectionService.getSourceDisplayName(installationSource)
          ])}
${ref.read(appLocalizationServiceProvider).translateWithParams('payment_diag_provider', [
            paymentProviderType.name
          ])}
${ref.read(appLocalizationServiceProvider).translateWithParams('payment_diag_locale', [
            '${locale.languageCode}_${locale.countryCode}'
          ])}

${ref.read(appLocalizationServiceProvider).translate('payment_diag_rustore_prices')}
${ref.read(appLocalizationServiceProvider).translateWithParams('payment_diag_weekly', [
            rustoreWeeklyPrice
          ])}
${ref.read(appLocalizationServiceProvider).translateWithParams('payment_diag_monthly', [
            rustoreMonthlyPrice
          ])}
${ref.read(appLocalizationServiceProvider).translateWithParams('payment_diag_yearly', [
            rustoreYearlyPrice
          ])}

${ref.read(appLocalizationServiceProvider).translate('payment_diag_yookassa_prices')}
${ref.read(appLocalizationServiceProvider).translateWithParams('payment_diag_weekly', [
            yookassaWeeklyPrice
          ])}
${ref.read(appLocalizationServiceProvider).translateWithParams('payment_diag_monthly', [
            yookassaMonthlyPrice
          ])}
${ref.read(appLocalizationServiceProvider).translateWithParams('payment_diag_yearly', [
            yookassaYearlyPrice
          ])}

${ref.read(appLocalizationServiceProvider).translate('payment_diag_rustore_products')}
${ref.read(appLocalizationServiceProvider).translate('payment_diag_rustore_weekly')}
${ref.read(appLocalizationServiceProvider).translate('payment_diag_rustore_monthly')}
${ref.read(appLocalizationServiceProvider).translate('payment_diag_rustore_yearly')}

${ref.read(appLocalizationServiceProvider).translate('payment_diag_selection_logic')}
${isRuStore ? '✅' : '❌'} ${ref.read(appLocalizationServiceProvider).translate('payment_diag_rustore_logic')}
${isGooglePlayRu ? '✅' : '❌'} ${ref.read(appLocalizationServiceProvider).translate('payment_diag_yookassa_logic')}
${isAppStore ? '✅' : '❌'} ${ref.read(appLocalizationServiceProvider).translate('payment_diag_standard_iap_logic')}
${isUnknown ? '⚠️' : '❌'} ${ref.read(appLocalizationServiceProvider).translate('payment_diag_fallback_logic')}

${ref.read(appLocalizationServiceProvider).translate('payment_diag_debug_details')}
• installationSource: $installationSource
• locale.countryCode: ${locale.countryCode}
• paymentProviderType: $paymentProviderType
• isRuStore: $isRuStore
• isGooglePlayRu: $isGooglePlayRu

${ref.read(appLocalizationServiceProvider).translate('payment_diag_problems')}
${paymentProviderType != PaymentProvider.rustore && isRuStore ? '🔴 ${ref.read(appLocalizationServiceProvider).translate('payment_diag_problem_rustore_mismatch')}' : ''}
${paymentProviderType == PaymentProvider.rustore && !isRuStore ? '🔴 ${ref.read(appLocalizationServiceProvider).translate('payment_diag_problem_rustore_source')}' : ''}
${paymentProviderType == PaymentProvider.yookassa && !isGooglePlayRu ? '🔴 ${ref.read(appLocalizationServiceProvider).translate('payment_diag_problem_yookassa_not_ru')}' : ''}
      ''';

      setState(() {
        _diagnosticInfo = diagnosticInfo;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.log('Payment diagnostic load error: $e', level: LogLevel.error);
      setState(() {
        _diagnosticInfo = ref
            .read(appLocalizationServiceProvider)
            .translateWithParams('payment_diag_load_error', ['$e']);
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _diagnosticInfo));
    final l10n = ref.read(appLocalizationServiceProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.translate('copied_to_clipboard'))),
    );
  }

  void _testStoreDetection() async {
    try {
      final storeDetectionService = AppStoreDetectionService();

      // Очищаем кэш для повторного тестирования
      storeDetectionService.clearCache();

      // Получаем источник установки заново
      final installationSource =
          await storeDetectionService.getInstallationSource();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(ref
              .read(appLocalizationServiceProvider)
              .translate('store_detection_test_title')),
          content: FutureBuilder<Map<String, dynamic>>(
            future: _getStoreDetectionDetails(
                storeDetectionService, installationSource),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }

              final data = snapshot.data ?? {};
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ref
                      .read(appLocalizationServiceProvider)
                      .translateWithParams('store_detection_source', [
                    storeDetectionService
                        .getSourceDisplayName(installationSource)
                  ])),
                  const SizedBox(height: 8),
                  Text('Enum: $installationSource'),
                  const SizedBox(height: 8),
                  Text('isInstalledFromRuStore: ${data['isRuStore'] ?? '...'}'),
                  Text(
                      'isInstalledFromGooglePlay: ${data['isGooglePlay'] ?? '...'}'),
                  Text(
                      'canUseStandardIAP: ${data['canUseStandardIAP'] ?? '...'}'),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                  ref.read(appLocalizationServiceProvider).translate('close')),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(ref
                .read(appLocalizationServiceProvider)
                .translateWithParams('testing_error', ['$e']))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(ref
            .read(appLocalizationServiceProvider)
            .translate('payment_diag_title_appbar')),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDiagnosticInfo,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyToClipboard,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Диагностическая информация
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: SelectableText(
                      _diagnosticInfo,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Кнопки для тестирования
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _testStoreDetection,
                          child: Text(ref
                              .read(appLocalizationServiceProvider)
                              .translate('store_detection_test_title')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _loadDiagnosticInfo,
                          child: Text(ref
                              .read(appLocalizationServiceProvider)
                              .translate('refresh_data')),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Кнопки для принудительного тестирования провайдеров
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: () => _testProvider(AppStoreType.ruStore),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange),
                        child: Text(ref
                            .read(appLocalizationServiceProvider)
                            .translate('test_rustore')),
                      ),
                      ElevatedButton(
                        onPressed: () => _testProvider(AppStoreType.googlePlay),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                        child: Text(ref
                            .read(appLocalizationServiceProvider)
                            .translate('test_google_play')),
                      ),
                      ElevatedButton(
                        onPressed: () => _testProvider(AppStoreType.appStore),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue),
                        child: Text(ref
                            .read(appLocalizationServiceProvider)
                            .translate('test_app_store')),
                      ),
                      ElevatedButton(
                        onPressed: () => _testProvider(null),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey),
                        child: Text(ref
                            .read(appLocalizationServiceProvider)
                            .translate('reset')),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Информация о провайдерах
                  _buildProviderInfo(),
                ],
              ),
            ),
    );
  }

  Widget _buildProviderInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ref
                  .read(appLocalizationServiceProvider)
                  .translate('providers_info_title'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
                '${ref.read(appLocalizationServiceProvider).translate('rustore_title')}:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
                '• ${ref.read(appLocalizationServiceProvider).translate('rustore_bullet_1')}'),
            Text(
                '• ${ref.read(appLocalizationServiceProvider).translate('rustore_bullet_2')}'),
            Text(
                '• ${ref.read(appLocalizationServiceProvider).translate('rustore_bullet_3')}'),
            const SizedBox(height: 8),
            Text(
                '${ref.read(appLocalizationServiceProvider).translate('yookassa_title')}:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
                '• ${ref.read(appLocalizationServiceProvider).translate('yookassa_bullet_1')}'),
            Text(
                '• ${ref.read(appLocalizationServiceProvider).translate('yookassa_bullet_2')}'),
            Text(
                '• ${ref.read(appLocalizationServiceProvider).translate('yookassa_bullet_3')}'),
            const SizedBox(height: 8),
            Text(
                '${ref.read(appLocalizationServiceProvider).translate('standard_iap_title')}:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
                '• ${ref.read(appLocalizationServiceProvider).translate('standard_iap_bullet_1')}'),
            Text(
                '• ${ref.read(appLocalizationServiceProvider).translate('standard_iap_bullet_2')}'),
            Text(
                '• ${ref.read(appLocalizationServiceProvider).translate('standard_iap_bullet_3')}'),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _getStoreDetectionDetails(
      AppStoreDetectionService storeDetectionService,
      AppStoreType installationSource) async {
    try {
      final isRuStore = await storeDetectionService.isInstalledFromRuStore();
      final isGooglePlay =
          await storeDetectionService.isInstalledFromGooglePlay();
      final canUseStandardIAP = await storeDetectionService.canUseStandardIAP();

      return {
        'isRuStore': isRuStore,
        'isGooglePlay': isGooglePlay,
        'canUseStandardIAP': canUseStandardIAP,
      };
    } catch (e) {
      return {
        'isRuStore': 'ошибка: $e',
        'isGooglePlay': 'ошибка: $e',
        'canUseStandardIAP': 'ошибка: $e',
      };
    }
  }

  void _testProvider(AppStoreType? sourceType) async {
    try {
      final storeDetectionService = AppStoreDetectionService();

      // Устанавливаем принудительный источник для тестирования
      storeDetectionService.setForcedSourceForTesting(sourceType);

      // Обновляем диагностическую информацию
      await _loadDiagnosticInfo();

      String message;
      if (sourceType == null) {
        message =
            'Принудительный источник сброшен. Используется реальное определение.';
      } else {
        message =
            'Принудительно установлен источник: ${storeDetectionService.getSourceDisplayName(sourceType)}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при установке провайдера: $e')),
      );
    }
  }
}
