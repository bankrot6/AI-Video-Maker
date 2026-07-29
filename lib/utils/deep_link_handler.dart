import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uni_links/uni_links.dart';
import 'package:flutter/material.dart';
import '../services/payment_result_handler.dart';

/// Обработчик Deep Links для приложения
class DeepLinkHandler {
  // Синглтон
  static final DeepLinkHandler _instance = DeepLinkHandler._internal();
  factory DeepLinkHandler() => _instance;
  DeepLinkHandler._internal();

  /// Обработчик платежей
  final PaymentResultHandler _paymentHandler = PaymentResultHandler();

  /// Флаг инициализации
  bool _isInitialized = false;

  /// Подписка на Deep Links
  StreamSubscription? _linkSubscription;

  /// Отложенная ссылка, если навигация недоступна до построения UI
  Uri? _pendingUri;

  /// Инициализация обработчика Deep Links
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Инициализируем обработчик платежей
      await _paymentHandler.initialize();

      // Проверяем, не открыто ли приложение по ссылке
      await _handleInitialLink();

      // Подписываемся на будущие ссылки
      _linkSubscription = linkStream.listen((String? link) {
        if (link != null) {
          _handleIncomingLink(link);
        }
      }, onError: (e) {
        debugPrint('🔴 DEEP_LINK: Ошибка при получении ссылки: $e');
      });

      _isInitialized = true;
      debugPrint('🔗 DEEP_LINK: Обработчик Deep Links инициализирован');
    } catch (e) {
      debugPrint('🔴 DEEP_LINK: Ошибка при инициализации: $e');
    }
  }

  /// Обработка начальной ссылки, если приложение было запущено по Deep Link
  Future<void> _handleInitialLink() async {
    try {
      final initialLink = await getInitialUri();
      if (initialLink != null) {
        debugPrint('🔗 DEEP_LINK: Получена начальная ссылка: $initialLink');
        _handleLink(initialLink);
      }
    } on PlatformException catch (e) {
      debugPrint('🔴 DEEP_LINK: Ошибка при получении начальной ссылки: $e');
    }
  }

  /// Обработка входящей ссылки в виде строки
  Future<void> _handleIncomingLink(String link) async {
    try {
      final uri = Uri.parse(link);
      _handleLink(uri);
    } catch (e) {
      debugPrint('🔴 DEEP_LINK: Ошибка при разборе ссылки: $e');
    }
  }

  /// Обработка входящей ссылки
  Future<void> _handleLink(Uri uri) async {
    debugPrint('🔗 DEEP_LINK: Обработка ссылки: $uri');

    if (await _paymentHandler.canHandleUrl(uri.toString())) {
      // Обрабатываем ссылку как результат платежа
      final success = await _paymentHandler.processPaymentUrl(uri.toString());
      debugPrint('🔗 DEEP_LINK: Результат обработки платежа: $success');
    }

    // Обработка внутренних действий приложения
    try {
      if (uri.scheme == 'aivideomaker' && uri.host == 'action') {
        final action =
            uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
        final context = appNavigatorKey.currentContext;
        if (context == null) {
          // Откладываем до появления контекста
          _pendingUri = uri;
          debugPrint('⏳ DEEP_LINK: Навигация отложена до инициализации UI');
          return;
        }
        _navigateAction(action, context);
      }
    } catch (e) {
      debugPrint('🔴 DEEP_LINK: Ошибка обработки внутреннего действия: $e');
    }
  }

  /// Выполнить отложенное действие, если есть и UI готов
  void processPending() {
    if (_pendingUri == null) return;
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    final uri = _pendingUri!;
    _pendingUri = null;
    try {
      if (uri.scheme == 'aivideomaker' && uri.host == 'action') {
        final action =
            uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
        _navigateAction(action, context);
      }
    } catch (e) {
      debugPrint('🔴 DEEP_LINK: Ошибка выполнения отложенного действия: $e');
    }
  }

  void _navigateAction(String action, BuildContext context) {
    // Передаем действие на HomeScreen, где есть WidgetRef
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/home',
      (route) => false,
      arguments: {'widget_action': action},
    );
  }

  /// Освобождаем ресурсы
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _isInitialized = false;
    debugPrint('🔗 DEEP_LINK: Обработчик Deep Links отключен');
  }
}

// Глобальный ключ навигатора для навигации из DeepLinkHandler
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

// Глобальный наблюдатель маршрутов (для RouteAware-виджетов)
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
