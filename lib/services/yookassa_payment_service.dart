import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/subscription_model.dart';
import 'payment_result_handler.dart';

/// Сервис для обработки платежей через ЮKassa
class YooKassaPaymentService {
  // Синглтон
  static final YooKassaPaymentService _instance =
      YooKassaPaymentService._internal();
  factory YooKassaPaymentService() => _instance;
  YooKassaPaymentService._internal();

  // Константы для цен в рублях
  static const double _weeklyPriceRub = 99.0;
  static const double _monthlyPriceRub = 299.0;
  static const double _yearlyPriceRub = 999.0;

  // Храним фактические цены из веб-интерфейса
  static Map<SubscriptionType, double> _actualPrices = {
    SubscriptionType.weekly: _weeklyPriceRub,
    SubscriptionType.monthly: _monthlyPriceRub,
    SubscriptionType.yearly: _yearlyPriceRub,
  };

  // API ЮKassa
  static const String _apiUrl = 'https://api.yookassa.ru/v3/payments';

  // Ключи для авторизации (должны храниться в безопасном месте)
  final String _shopId = '375359'; // Реальный ID магазина
  final String _secretKey =
      'live_D_bV7VLAuL5UzTAkB54GCH14UdRxla8fs9RVyBa41sg'; // Реальный секретный ключ

  // Статус инициализации
  bool _isInitialized = false;

  // Обработчик результатов платежей
  final PaymentResultHandler _paymentHandler = PaymentResultHandler();

  /// Инициализация сервиса ЮKassa
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Инициализируем обработчик результатов платежей
      await _paymentHandler.initialize();

      _isInitialized = true;
      debugPrint('🛒 YOOKASSA: Сервис ЮKassa успешно инициализирован');
    } catch (e) {
      debugPrint('🔴 YOOKASSA: Ошибка при инициализации сервиса ЮKassa: $e');
      rethrow;
    }
  }

  /// Создает платеж через API ЮKassa
  Future<PaymentData?> createPayment({
    required SubscriptionType subscriptionType,
    required String userEmail,
    required String description,
  }) async {
    if (!_isInitialized) await initialize();

    debugPrint('⚙️ YOOKASSA: Начинаем создание платежа через API');
    debugPrint('⚙️ YOOKASSA: Тип подписки: $subscriptionType');
    debugPrint('⚙️ YOOKASSA: Email: $userEmail');
    debugPrint('⚙️ YOOKASSA: Описание: $description');

    try {
      debugPrint(
          '⚙️ YOOKASSA: Начинаем процесс оплаты для типа: $subscriptionType');

      // Определяем сумму платежа на основе типа подписки
      final amount = _getAmountBySubscriptionType(subscriptionType);
      debugPrint('⚙️ YOOKASSA: Сумма платежа: $amount RUB');

      // Получаем идентификатор устройства пользователя
      final deviceId = await _getDeviceId();
      debugPrint('⚙️ YOOKASSA: ID устройства: $deviceId');

      // Генерируем уникальный идентификатор заказа
      final String orderId =
          '${DateTime.now().millisecondsSinceEpoch}-$deviceId';
      debugPrint('⚙️ YOOKASSA: ID заказа: $orderId');

      // Формируем данные для создания платежа
      final Map<String, dynamic> paymentData = {
        'amount': {
          'value': amount.toStringAsFixed(2),
          'currency': 'RUB',
        },
        'payment_method_data': {
          'type': 'bank_card',
        },
        'confirmation': {
          'type': 'redirect',
          'return_url':
              'https://aivideomaker.app/payment/return', // Базовый URL возврата
        },
        'description': 'AI Video Maker $description',
        'metadata': {
          'order_id': orderId,
          'subscription_type': subscriptionType.toString(),
          'email': userEmail,
        },
        'capture': true,
        'save_payment_method': true,
      };

      debugPrint('⚙️ YOOKASSA: Данные платежа: ${jsonEncode(paymentData)}');
      debugPrint('⚙️ YOOKASSA: URL API: $_apiUrl');
      debugPrint('⚙️ YOOKASSA: ShopID: $_shopId');

      // Базовый URL возврата
      final returnUrl = 'https://aivideomaker.app/payment/return';
      debugPrint('⚙️ YOOKASSA: URL возврата: $returnUrl');

      // Отправляем запрос на создание платежа
      debugPrint('⚙️ YOOKASSA: Отправляем запрос на создание платежа...');
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$_shopId:$_secretKey'))}',
          'Idempotence-Key': DateTime.now().millisecondsSinceEpoch.toString(),
        },
        body: jsonEncode(paymentData),
      );

      debugPrint('⚙️ YOOKASSA: Получен ответ, статус: ${response.statusCode}');
      debugPrint('⚙️ YOOKASSA: Тело ответа: ${response.body}');

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        debugPrint('✅ YOOKASSA: Платеж успешно создан: ${response.body}');

        // Получаем ID платежа
        final String paymentId = responseBody['id'];
        debugPrint('✅ YOOKASSA: ID платежа: $paymentId');

        // Получаем URL подтверждения
        final String confirmationUrl =
            responseBody['confirmation']['confirmation_url'];
        debugPrint('✅ YOOKASSA: URL подтверждения: $confirmationUrl');

        // Добавляем платеж в список ожидающих
        _paymentHandler.addPendingPayment(paymentId, subscriptionType);
        debugPrint('✅ YOOKASSA: Платеж добавлен в список ожидающих');

        // Возвращаем данные платежа
        return PaymentData(
          token: paymentId,
          paymentMethodType: 'bank_card',
          email: userEmail,
          subscriptionType: subscriptionType,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          confirmationUrl: responseBody['confirmation']['confirmation_url'],
        );
      } else {
        debugPrint(
            '🔴 YOOKASSA: Ошибка при создании платежа: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('🔴 YOOKASSA: Ошибка при процессе оплаты: $e');
      return null;
    }
  }

  /// Проверяет статус платежа по его ID
  Future<bool> checkPaymentStatus(String paymentId) async {
    if (!_isInitialized) await initialize();

    debugPrint('⚙️ YOOKASSA: Проверяем статус платежа: $paymentId');

    try {
      // URL для запроса статуса платежа
      final url = '$_apiUrl/$paymentId';
      debugPrint('⚙️ YOOKASSA: URL для проверки: $url');

      // Отправляем запрос на проверку статуса
      debugPrint('⚙️ YOOKASSA: Отправляем запрос на проверку статуса...');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Basic ${base64Encode(utf8.encode('$_shopId:$_secretKey'))}',
        },
      );

      debugPrint('⚙️ YOOKASSA: Получен ответ, статус: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        debugPrint('⚙️ YOOKASSA: Тело ответа: ${response.body}');

        // Получаем статус платежа
        final String status = responseBody['status'];
        debugPrint('⚙️ YOOKASSA: Статус платежа: $status');

        // Если статус "succeeded", то платеж успешен
        final bool isSucceeded = status == 'succeeded';
        debugPrint('⚙️ YOOKASSA: Платеж успешен: $isSucceeded');

        return isSucceeded;
      } else {
        debugPrint(
            '🔴 YOOKASSA: Ошибка при проверке статуса платежа: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('🔴 YOOKASSA: Ошибка при проверке статуса платежа: $e');
      return false;
    }
  }

  /// Обновляет цены из веб-интерфейса ЮKassa (для российских пользователей)
  static void updatePricesFromWebView(Map<SubscriptionType, double> prices) {
    if (prices.isNotEmpty) {
      _actualPrices = {..._actualPrices, ...prices};
      debugPrint(
          '✅ YOOKASSA: Цены обновлены из веб-интерфейса: $_actualPrices');
    }
  }

  /// Получает цену для указанного типа подписки
  static double getPriceForSubscriptionType(SubscriptionType type) {
    return _actualPrices[type] ?? _getDefaultPriceForType(type);
  }

  /// Получает дефолтную цену для типа подписки
  static double _getDefaultPriceForType(SubscriptionType type) {
    switch (type) {
      case SubscriptionType.weekly:
        return _weeklyPriceRub;
      case SubscriptionType.monthly:
        return _monthlyPriceRub;
      case SubscriptionType.yearly:
        return _yearlyPriceRub;
      default:
        return 0.0;
    }
  }

  /// Возвращает символ валюты, используемый для платежей
  static String getCurrencySymbol() {
    // Для ЮКассы всегда используется рубль
    return '₽';
  }

  /// Получает сумму платежа в зависимости от типа подписки
  double _getAmountBySubscriptionType(SubscriptionType subscriptionType) {
    return _actualPrices[subscriptionType] ??
        _getDefaultPriceForType(subscriptionType);
  }

  /// Получает идентификатор устройства
  Future<String> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('device_id');

      if (deviceId == null || deviceId.isEmpty) {
        // Генерируем новый ID устройства, если его еще нет
        deviceId = DateTime.now().millisecondsSinceEpoch.toString();
        await prefs.setString('device_id', deviceId);
      }

      return deviceId;
    } catch (e) {
      // Fallback, если не удалось получить ID из SharedPreferences
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }
}

/// Класс для хранения данных о платеже
class PaymentData {
  final String token;
  final String paymentMethodType;
  final String email;
  final SubscriptionType subscriptionType;
  final int timestamp;
  final String? confirmationUrl;

  PaymentData({
    required this.token,
    required this.paymentMethodType,
    required this.email,
    required this.subscriptionType,
    required this.timestamp,
    this.confirmationUrl,
  });
}
