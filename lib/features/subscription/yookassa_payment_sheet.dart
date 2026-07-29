import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/subscription_model.dart';
import '../../services/payment_providers.dart';
import '../../services/localization/app_localization_service.dart';
import '../../widgets/loading/loading_screen.dart';
import '../../widgets/loading/loading_manager.dart';
import 'yookassa_webview.dart'; // Импортируем виджет WebView

/// Сервис для обработки платежей через ЮKassa без промежуточного экрана
class YooKassaPaymentService {
  /// Создает платеж и сразу открывает WebView для его оплаты
  static Future<void> startPayment({
    required BuildContext context,
    required SubscriptionType subscriptionType,
    required Function(SubscriptionType) onSuccess,
    required VoidCallback onCancel,
    required WidgetRef ref,
  }) async {
    try {
      // Получаем сервис ЮKassa
      final yookassaService = ref.read(yookassaServiceProvider);

      // Получаем обработчик платежей
      final paymentHandler = ref.read(paymentResultHandlerProvider);

      // Подготавливаем описание подписки
      String description;
      switch (subscriptionType) {
        case SubscriptionType.weekly:
          description = context.tr('weekly_subscription');
          break;
        case SubscriptionType.monthly:
          description = context.tr('monthly_subscription');
          break;
        case SubscriptionType.yearly:
          description = context.tr('yearly_subscription');
          break;
        default:
          description = context.tr('subscription');
      }

      // Показываем простой индикатор загрузки при создании платежа
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              Text(context.tr('connecting_to_payment')),
            ],
          ),
          duration: const Duration(
              seconds:
                  30), // будет закрыт автоматически при успешном создании платежа
        ),
      );

      // Создаем платеж с автоматически сгенерированным email
      final generatedEmail =
          'user${DateTime.now().millisecondsSinceEpoch}@aivideomaker.app';
      final result = await yookassaService.createPayment(
        subscriptionType: subscriptionType,
        userEmail: generatedEmail,
        description: description,
      );

      // Скрываем сообщение с индикатором загрузки
      scaffoldMessenger.hideCurrentSnackBar();

      // Проверяем результат
      if (result != null && result.confirmationUrl != null) {
        // Открываем WebView для оплаты
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => YooKassaWebView(
              paymentUrl: result.confirmationUrl!,
              paymentId: result.token,
              subscriptionType: subscriptionType,
              onSuccess: (type) {
                // Показываем экран загрузки только ПОСЛЕ успешной оплаты
                LoadingManager().showLoadingScreen(
                  context,
                  text: context.tr('purchase_processing'),
                  animationPath: 'assets/animations/loading.json',
                  backgroundColor: Colors.white,
                  processingStepText: context.tr('do_not_close_app'),
                  progressValue: 0.5,
                  animationHeight: MediaQuery.of(context).size.height * 0.4,
                );

                // Вызываем колбэк после успешной оплаты
                onSuccess(type);
              },
              onCancel: onCancel,
            ),
          ),
        );
      } else {
        // Показываем ошибку, если не удалось создать платеж
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(context.tr('payment_creation_error')),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: context.tr('retry'),
              textColor: Colors.white,
              onPressed: () => startPayment(
                context: context,
                subscriptionType: subscriptionType,
                onSuccess: onSuccess,
                onCancel: onCancel,
                ref: ref,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      // Обработка других ошибок
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.tr('payment_error')}: $e'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: context.tr('retry'),
            textColor: Colors.white,
            onPressed: () => startPayment(
              context: context,
              subscriptionType: subscriptionType,
              onSuccess: onSuccess,
              onCancel: onCancel,
              ref: ref,
            ),
          ),
        ),
      );
    }
  }
}

/// Экран оплаты через ЮKassa (используется только как совместимый интерфейс)
class YooKassaPaymentSheet extends ConsumerStatefulWidget {
  /// Тип подписки для оформления
  final SubscriptionType subscriptionType;

  /// Колбэк при успешной оплате
  final Function(SubscriptionType type) onSuccess;

  /// Колбэк при отмене оплаты
  final VoidCallback onCancel;

  /// Название подписки для отображения
  final String title;

  const YooKassaPaymentSheet({
    super.key,
    required this.subscriptionType,
    required this.onSuccess,
    required this.onCancel,
    required this.title,
  });

  @override
  ConsumerState<YooKassaPaymentSheet> createState() =>
      _YooKassaPaymentSheetState();
}

class _YooKassaPaymentSheetState extends ConsumerState<YooKassaPaymentSheet> {
  /// Подписка на события платежей
  StreamSubscription? _paymentSubscription;

  @override
  void initState() {
    super.initState();
    // Подписываемся на события успешных платежей для обратной совместимости
    _subscribeToPaymentEvents();

    // Инициируем оплату сразу при создании виджета
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Сразу закрываем нижний sheet, он больше не нужен
      Navigator.of(context).pop();

      // Запускаем процесс оплаты напрямую через сервис
      YooKassaPaymentService.startPayment(
        context: context,
        subscriptionType: widget.subscriptionType,
        onSuccess: widget.onSuccess,
        onCancel: widget.onCancel,
        ref: ref,
      );
    });
  }

  @override
  void dispose() {
    _paymentSubscription?.cancel();
    super.dispose();
  }

  /// Подписываемся на события успешных платежей
  void _subscribeToPaymentEvents() {
    final paymentHandler = ref.read(paymentResultHandlerProvider);

    _paymentSubscription = paymentHandler.onPaymentSuccess.listen((paymentId) {
      if (mounted) {
        debugPrint(
            '✅ YOOKASSA_SHEET: Получено событие успешной оплаты: $paymentId');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Показываем индикатор загрузки напрямую, но он будет быстро закрыт
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
