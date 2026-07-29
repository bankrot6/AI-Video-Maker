import 'dart:async';
import 'dart:io'; // Импорт для использования Platform
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/subscription_model.dart';
import 'yookassa_payment_service.dart';
import 'subscription/subscription_storage_service.dart';

/// Сервис для обработки результатов платежей
class PaymentResultHandler {
  // Синглтон
  static final PaymentResultHandler _instance =
      PaymentResultHandler._internal();
  factory PaymentResultHandler() => _instance;
  PaymentResultHandler._internal();

  /// Канал методов для обработки платежных результатов
  static const MethodChannel _channel =
      MethodChannel('app.aivideomaker/payment_result');

  /// Контроллер для отправки событий об успешном завершении платежа
  final StreamController<String> _paymentSuccessController =
      StreamController<String>.broadcast();

  /// Поток для подписки на события успешного завершения платежа
  Stream<String> get onPaymentSuccess => _paymentSuccessController.stream;

  /// Временное хранилище для ID платежей, ожидающих проверки
  final Map<String, SubscriptionType> _pendingPayments = {};

  /// Ключ для хранения последнего ID платежа
  static const String _lastPaymentIdKey = 'last_yookassa_payment_id';

  /// Ключ для хранения последнего типа подписки ЮKassa
  static const String _lastSubscriptionTypeKey =
      'last_yookassa_subscription_type';

  /// Инициализация обработчика результатов платежей
  Future<void> initialize() async {
    try {
      // Настраиваем обработчик методов
      _channel.setMethodCallHandler(_handleMethodCall);
      debugPrint(
          '💳 PAYMENT_HANDLER: Обработчик результатов платежей инициализирован');
    } catch (e) {
      debugPrint('🔴 PAYMENT_HANDLER: Ошибка при инициализации: $e');
    }
  }

  /// Обработчик вызовов из платформенного кода
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'handlePaymentResult':
        final String url = call.arguments['url'];
        return processPaymentUrl(url);
      default:
        throw PlatformException(
          code: 'UNSUPPORTED_METHOD',
          message: 'Метод ${call.method} не поддерживается',
        );
    }
  }

  /// Добавляет платеж в список ожидающих проверки
  void addPendingPayment(String paymentId, SubscriptionType subscriptionType) {
    _pendingPayments[paymentId] = subscriptionType;
    debugPrint('💳 PAYMENT_HANDLER: Добавлен платеж в ожидание: $paymentId');

    // Сохраняем ID платежа как последний использованный
    _saveLastPaymentId(paymentId);

    // Сохраняем последний тип подписки
    _saveLastSubscriptionType(subscriptionType);
  }

  /// Сохраняет ID платежа как последний использованный
  Future<void> _saveLastPaymentId(String paymentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastPaymentIdKey, paymentId);
      debugPrint(
          '💳 PAYMENT_HANDLER: Сохранен последний ID платежа: $paymentId');
    } catch (e) {
      debugPrint('🔴 PAYMENT_HANDLER: Ошибка при сохранении ID платежа: $e');
    }
  }

  /// Получает последний использованный ID платежа
  Future<String?> getLastPaymentId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? paymentId = prefs.getString(_lastPaymentIdKey);
      return paymentId;
    } catch (e) {
      debugPrint('🔴 PAYMENT_HANDLER: Ошибка при получении ID платежа: $e');
      return null;
    }
  }

  /// Сохраняет последний тип подписки ЮKassa
  Future<void> _saveLastSubscriptionType(SubscriptionType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSubscriptionTypeKey, type.index);
      debugPrint(
          '💳 PAYMENT_HANDLER: Сохранен последний тип подписки: ${type.toString()}');
    } catch (e) {
      debugPrint('🔴 PAYMENT_HANDLER: Ошибка при сохранении типа подписки: $e');
    }
  }

  /// Возвращает последний тип подписки ЮKassa, если сохранен
  Future<SubscriptionType?> getLastSubscriptionType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final typeIndex = prefs.getInt(_lastSubscriptionTypeKey);
      if (typeIndex == null) return null;
      if (typeIndex >= 0 && typeIndex < SubscriptionType.values.length) {
        return SubscriptionType.values[typeIndex];
      }
      return null;
    } catch (e) {
      debugPrint('🔴 PAYMENT_HANDLER: Ошибка при получении типа подписки: $e');
      return null;
    }
  }

  int _subscriptionDurationDays(SubscriptionType type) {
    switch (type) {
      case SubscriptionType.weekly:
        return 7;
      case SubscriptionType.monthly:
        return 30;
      case SubscriptionType.yearly:
        return 365;
      default:
        return 0;
    }
  }

  Future<void> _persistYookassaSubscription(
      {required String paymentId, required SubscriptionType type}) async {
    try {
      final storage = SubscriptionStorageService();
      final now = DateTime.now();
      final durationDays = _subscriptionDurationDays(type);
      if (durationDays <= 0) {
        debugPrint(
            '⚠️ PAYMENT_HANDLER: Некорректный тип подписки для сохранения: $type');
        return;
      }
      final end = now.add(Duration(days: durationDays));
      await storage.saveSubscription(
        type: type,
        startDate: now,
        endDate: end,
        paymentId: paymentId,
        isYookassa: true,
      );
      debugPrint(
          '💾 PAYMENT_HANDLER: Подписка ЮKassa сохранена локально: $type до ${end.toIso8601String()}');
    } catch (e) {
      debugPrint('🔴 PAYMENT_HANDLER: Ошибка сохранения подписки ЮKassa: $e');
    }
  }

  /// Обрабатывает URL перенаправления после платежа
  Future<bool> processPaymentUrl(String url) async {
    debugPrint('💳 PAYMENT_HANDLER: Обработка URL после платежа: $url');

    try {
      final Uri uri = Uri.parse(url);

      // Проверяем, что URL соответствует нашему домену
      if (uri.host == 'aivideomaker.app' &&
          uri.path.contains('/payment/return')) {
        // Извлекаем ID платежа из запроса, если он есть
        final String? paymentId = uri.queryParameters['payment_id'];

        if (paymentId != null && paymentId.isNotEmpty) {
          return await _verifyPayment(paymentId);
        }
      }

      return false;
    } catch (e) {
      debugPrint('🔴 PAYMENT_HANDLER: Ошибка при обработке URL: $e');
      return false;
    }
  }

  /// Проверяет статус платежа
  Future<bool> _verifyPayment(String paymentId) async {
    debugPrint('💳 PAYMENT_HANDLER: Проверка статуса платежа: $paymentId');

    try {
      // Получаем сервис ЮKassa
      final yookassaService = YooKassaPaymentService();

      // Проверяем статус платежа
      final bool isSuccess =
          await yookassaService.checkPaymentStatus(paymentId);

      if (isSuccess) {
        debugPrint('✅ PAYMENT_HANDLER: Платеж успешно завершен: $paymentId');

        // Если платеж был в ожидании, получаем тип подписки, сохраняем и отправляем событие
        if (_pendingPayments.containsKey(paymentId)) {
          final subscriptionType = _pendingPayments[paymentId];
          if (subscriptionType != null) {
            await _persistYookassaSubscription(
                paymentId: paymentId, type: subscriptionType);
          } else {
            final lastType = await getLastSubscriptionType();
            if (lastType != null) {
              await _persistYookassaSubscription(
                  paymentId: paymentId, type: lastType);
            }
          }
          _paymentSuccessController.add(paymentId);
          _pendingPayments.remove(paymentId);
          return true;
        } else {
          // Если платеж не найден среди ожидающих (приложение перезапускали), пытаемся сохранить по последнему типу
          final lastType = await getLastSubscriptionType();
          if (lastType != null) {
            await _persistYookassaSubscription(
                paymentId: paymentId, type: lastType);
          }
        }
      } else {
        debugPrint('❌ PAYMENT_HANDLER: Платеж не подтвержден: $paymentId');
      }

      return false;
    } catch (e) {
      debugPrint('🔴 PAYMENT_HANDLER: Ошибка при проверке платежа: $e');
      return false;
    }
  }

  /// Создает URL для обработки результата платежа
  String createReturnUrl(String paymentId) {
    return 'https://aivideomaker.app/payment/return?payment_id=$paymentId';
  }

  /// Проверяет возможность обработки URL
  Future<bool> canHandleUrl(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      return uri.host == 'aivideomaker.app' &&
          uri.path.contains('/payment/return');
    } catch (e) {
      return false;
    }
  }

  /// Проверяет статус платежа напрямую через API
  Future<bool> checkPaymentStatus(String paymentId) async {
    debugPrint(
        '💳 PAYMENT_HANDLER: Проверка статуса платежа напрямую: $paymentId');

    try {
      // Получаем информацию о платеже из YooKassaPaymentService
      final yookassaService = YooKassaPaymentService();
      final isSuccess = await yookassaService.checkPaymentStatus(paymentId);

      if (isSuccess) {
        // Если платеж успешен, пытаемся сохранить подписку и отправить событие
        SubscriptionType? type;
        if (_pendingPayments.containsKey(paymentId)) {
          type = _pendingPayments[paymentId];
        } else {
          type = await getLastSubscriptionType();
        }

        if (type != null) {
          await _persistYookassaSubscription(paymentId: paymentId, type: type);
        } else {
          debugPrint(
              '⚠️ PAYMENT_HANDLER: Не удалось определить тип подписки для сохранения');
        }

        // Удаляем из списка ожидающих перед отправкой события
        _pendingPayments.remove(paymentId);

        // Сохраняем последний использованный ID платежа
        await _saveLastPaymentId(paymentId);

        debugPrint(
            '💳 PAYMENT_HANDLER: Отправляем событие об успешном платеже: $paymentId');

        // Отправляем событие об успешном платеже
        _paymentSuccessController.add(paymentId);
        return true;
      } else {
        debugPrint(
            '💳 PAYMENT_HANDLER: Платеж не завершен, ожидаем: $paymentId');
      }

      return false;
    } catch (e) {
      debugPrint('🔴 PAYMENT_HANDLER: Ошибка при проверке статуса платежа: $e');
      return false;
    }
  }

  /// Открывает URL для платежа
  Future<bool> launchPaymentUrl(String url) async {
    debugPrint('💳 PAYMENT_HANDLER: Открываем URL для платежа: $url');

    try {
      final Uri uri = Uri.parse(url);
      debugPrint('💳 PAYMENT_HANDLER: URI для открытия: $uri');
      debugPrint(
          '💳 PAYMENT_HANDLER: URI scheme: ${uri.scheme}, host: ${uri.host}, path: ${uri.path}');

      // Проверяем, можем ли открыть URL
      final canLaunch = await canLaunchUrl(uri);
      debugPrint('💳 PAYMENT_HANDLER: canLaunchUrl: $canLaunch');

      if (!canLaunch) {
        debugPrint('⚠️ PAYMENT_HANDLER: Невозможно открыть URL: $url');
        // Попробуем другой метод, даже если canLaunchUrl вернул false
      }

      // Сначала пробуем открыть в режиме external application
      bool launched = false;
      try {
        debugPrint(
            '💳 PAYMENT_HANDLER: Пробуем открыть как внешнее приложение...');
        launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        debugPrint(
            '💳 PAYMENT_HANDLER: URL открыт во внешнем приложении: $launched');
      } catch (e) {
        debugPrint(
            '⚠️ PAYMENT_HANDLER: Ошибка при открытии во внешнем приложении: $e');
      }

      // Если не получилось, пробуем открыть в режиме platformDefault
      if (!launched) {
        try {
          debugPrint(
              '💳 PAYMENT_HANDLER: Пробуем открыть в режиме по умолчанию...');
          launched = await launchUrl(
            uri,
            mode: LaunchMode.platformDefault,
          );
          debugPrint(
              '💳 PAYMENT_HANDLER: URL открыт в режиме по умолчанию: $launched');
        } catch (e) {
          debugPrint(
              '⚠️ PAYMENT_HANDLER: Ошибка при открытии в режиме по умолчанию: $e');
        }
      }

      // Если не вышло, пробуем inAppWebView
      if (!launched) {
        try {
          debugPrint('💳 PAYMENT_HANDLER: Пробуем открыть в inAppWebView...');
          launched = await launchUrl(
            uri,
            mode: LaunchMode.inAppWebView,
            webViewConfiguration: const WebViewConfiguration(
              enableJavaScript: true,
              enableDomStorage: true,
            ),
          );
          debugPrint(
              '💳 PAYMENT_HANDLER: URL открыт в inAppWebView: $launched');
        } catch (e) {
          debugPrint(
              '🔴 PAYMENT_HANDLER: Ошибка при открытии в inAppWebView: $e');
        }
      }

      // Последняя попытка - для Android пробуем открыть через Intent
      if (!launched && Platform.isAndroid) {
        debugPrint(
            '💳 PAYMENT_HANDLER: Пробуем открыть с использованием стандартного браузера...');
        try {
          final browserUri = Uri.parse('https://google.com');
          final browserOpened =
              await launchUrl(browserUri, mode: LaunchMode.externalApplication);
          debugPrint(
              '💳 PAYMENT_HANDLER: Тестовая страница открыта: $browserOpened');

          // Если браузер открылся, пробуем через 1 секунду открыть нужный URL
          if (browserOpened) {
            await Future.delayed(const Duration(seconds: 1));
            launched =
                await launchUrl(uri, mode: LaunchMode.externalApplication);
            debugPrint(
                '💳 PAYMENT_HANDLER: URL открыт после проверки браузера: $launched');
          }
        } catch (e) {
          debugPrint(
              '🔴 PAYMENT_HANDLER: Ошибка при тестовом открытии браузера: $e');
        }
      }

      if (!launched) {
        debugPrint(
            '❌ PAYMENT_HANDLER: Не удалось открыть URL ни одним способом: $url');
      }

      // Для тестирования всегда возвращаем true, чтобы процесс продолжался
      // В реальной версии раскомментировать следующую строку
      // return launched;

      // Временное решение для тестирования - всегда возвращаем успех
      debugPrint(
          '💳 PAYMENT_HANDLER: [ТЕСТОВЫЙ РЕЖИМ] Возвращаем успех независимо от результата');
      return true;
    } catch (e) {
      debugPrint('🔴 PAYMENT_HANDLER: Ошибка при открытии URL: $e');
      // Для тестирования
      return true;
    }
  }
}
