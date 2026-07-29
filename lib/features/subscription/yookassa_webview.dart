import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/payment_result_handler.dart';
import '../../models/subscription_model.dart';
import '../../services/localization/app_localization_service.dart';
import '../../services/yookassa_payment_service.dart';

/// Экран WebView для отображения страницы оплаты ЮKassa
class YooKassaWebView extends StatefulWidget {
  /// URL страницы оплаты ЮKassa
  final String paymentUrl;

  /// ID платежа для проверки статуса
  final String paymentId;

  /// Тип подписки
  final SubscriptionType subscriptionType;

  /// Callback при успешной оплате
  final Function(SubscriptionType type) onSuccess;

  /// Callback при отмене оплаты
  final VoidCallback onCancel;

  const YooKassaWebView({
    super.key,
    required this.paymentUrl,
    required this.paymentId,
    required this.subscriptionType,
    required this.onSuccess,
    required this.onCancel,
  });

  @override
  State<YooKassaWebView> createState() => _YooKassaWebViewState();
}

class _YooKassaWebViewState extends State<YooKassaWebView> {
  /// Контроллер для WebView
  late final WebViewController _controller;

  /// Обработчик результатов платежей
  final PaymentResultHandler _paymentHandler = PaymentResultHandler();

  /// Статус загрузки страницы
  bool _isLoading = true;

  /// Флаг обработки платежа (для предотвращения повторных вызовов)
  bool _isPaymentHandled = false;

  /// Флаг проверки статуса платежа
  bool _isCheckingPayment = false;

  /// Флаг отображения кнопки ручной проверки
  bool _showCheckButton = false;

  /// Подписка на события успешных платежей
  StreamSubscription? _paymentSubscription;

  /// Текущий URL страницы
  String? _currentUrl;

  /// JavaScript для извлечения информации о ценах (для российских пользователей)
  final String _priceExtractionScript = '''
  (function() {
    // Ожидаем загрузку всего контента
    function extractPriceInfo() {
      try {
        // Проверяем наличие элементов с ценами
        const priceElements = document.querySelectorAll('.price-info, .amount, .shop-details__price, .ShopDetailsPrice, .Price');
        
        if (priceElements.length > 0) {
          const prices = Array.from(priceElements).map(el => ({
            text: el.textContent,
            value: el.textContent.replace(/[^0-9,.]/g, '').trim()
          }));
          
          // Возвращаем JSON с данными о ценах
          return JSON.stringify({
            prices: prices,
            currency: document.querySelector('.currency, .shop-details__currency') ? 
                    document.querySelector('.currency, .shop-details__currency').textContent : 'RUB',
            isRussianUser: document.documentElement.lang === 'ru' || 
                          navigator.language.startsWith('ru') ||
                          window.location.href.includes('.ru/') ||
                          document.body.innerHTML.includes('ЮKassa') ||
                          document.body.innerHTML.includes('Юкасса') ||
                          document.body.innerHTML.includes('ЮМани')
          });
        }
      } catch (e) {
        return JSON.stringify({ error: e.toString() });
      }
      return null;
    }
    
    // Выполняем с небольшой задержкой для полной загрузки страницы
    setTimeout(extractPriceInfo, 1500);
  })();
  ''';

  /// JavaScript для скрытия технических сообщений на странице
  final String _hideMessageScript = '''
  (function() {
    // Функция для удаления технических сообщений
    function hideMessages() {
      try {
        // Скрываем любые окна с технической информацией
        const messageElements = document.querySelectorAll('.payment-message, .result-message, .system-message');
        messageElements.forEach(el => {
          if (el.textContent.includes('payment_processed_successfully')) {
            el.style.display = 'none';
          }
        });
        
        // Ищем все элементы, содержащие текст payment_processed_successfully
        const allElements = document.querySelectorAll('*');
        allElements.forEach(el => {
          if (el.childNodes.length === 1 && el.childNodes[0].nodeType === Node.TEXT_NODE) {
            const text = el.textContent.trim();
            if (text === 'payment_processed_successfully') {
              el.style.display = 'none';
            }
          }
        });

        // Найти и заменить текстовые узлы с технической информацией
        const walker = document.createTreeWalker(
          document.body, 
          NodeFilter.SHOW_TEXT,
          null,
          false
        );

        let node;
        const nodesToRemove = [];
        while(node = walker.nextNode()) {
          if (node.nodeValue && node.nodeValue.trim() === 'payment_processed_successfully') {
            nodesToRemove.push(node);
          }
        }

        nodesToRemove.forEach(node => {
          if (node.parentNode) {
            node.parentNode.removeChild(node);
          }
        });

        // Удаляем все сообщения и окна об успешной оплате от ЮКассы
        // если мы находимся на успешной странице
        if (window.location.href.includes('success')) {
          const successMessages = document.querySelectorAll('.message-success, .payment-success');
          successMessages.forEach(el => {
            // Если родительский элемент похож на окно, скрываем его
            if (el.parentElement && 
                (el.parentElement.classList.contains('modal') || 
                 el.parentElement.classList.contains('window') || 
                 el.parentElement.classList.contains('popup'))) {
              el.parentElement.style.display = 'none';
            }
            // Скрываем сам элемент
            el.style.display = 'none';
          });

          // Скрываем все модальные окна на странице успеха
          const modals = document.querySelectorAll('.modal, .popup, .dialog');
          modals.forEach(modal => {
            modal.style.display = 'none';
          });
        }
        
        // Исправляем заголовок страницы
        if (document.title === 'subscription_payment' || document.querySelector('header h1')?.textContent === 'subscription_payment') {
          document.title = 'Оплата подписки';
          
          // Пытаемся найти и изменить заголовок в разных местах страницы
          const headers = document.querySelectorAll('h1, h2, .header-title, .title, .payment-title');
          headers.forEach(header => {
            if (header.textContent.includes('subscription_payment')) {
              header.textContent = 'Оплата подписки';
            }
          });
        }
      } catch (e) {
        console.error('Error hiding messages:', e);
      }
    }
    
    // Сначала выполняем сразу, затем повторно через некоторое время
    // для обработки асинхронно загружаемых сообщений
    hideMessages();
    setTimeout(hideMessages, 300);
    setTimeout(hideMessages, 800);
    setTimeout(hideMessages, 1500);
    setTimeout(hideMessages, 3000);
  })();
  ''';

  /// JavaScript для изменения заголовка страницы
  final String _changePageTitleScript = '''
  (function() {
    // Функция для замены заголовка страницы
    function replacePageTitle() {
      try {
        // Заменяем текст subscription_payment в заголовке страницы
        if (document.title === 'subscription_payment') {
          document.title = 'Оплата подписки';
        }
        
        // Ищем элементы с текстом subscription_payment и заменяем их
        const elements = document.querySelectorAll('*');
        elements.forEach(el => {
          if (el.textContent === 'subscription_payment') {
            el.textContent = 'Оплата подписки';
          }
        });
        
        // Специально для заголовка страницы ЮКассы
        const headerElements = document.querySelectorAll('.header-title, .title-text, h1, h2, .page-title');
        headerElements.forEach(el => {
          if (el.textContent === 'subscription_payment') {
            el.textContent = 'Оплата подписки';
          }
        });
      } catch (e) {
        console.error('Error replacing page title:', e);
      }
    }
    
    // Запускаем замену сразу и с задержкой для загружаемых элементов
    replacePageTitle();
    setTimeout(replacePageTitle, 500);
    setTimeout(replacePageTitle, 1500);
    
    // Запускаем наблюдателя за изменениями DOM для динамических элементов
    const observer = new MutationObserver(function(mutations) {
      replacePageTitle();
    });
    
    observer.observe(document.body, { 
      childList: true, 
      subtree: true 
    });
  })();
  ''';

  @override
  void initState() {
    super.initState();
    _subscribeToPaymentEvents();
    _initWebView();
  }

  @override
  void dispose() {
    _paymentSubscription?.cancel();
    super.dispose();
  }

  /// Подписка на события успешных платежей
  void _subscribeToPaymentEvents() {
    _paymentSubscription = _paymentHandler.onPaymentSuccess.listen((paymentId) {
      if (paymentId == widget.paymentId) {
        _handleSuccessfulPayment();
      }
    });
  }

  /// Инициализация WebView
  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });

            // Проверяем URL перенаправления
            _checkRedirectUrl(url);

            // Пытаемся изменить заголовок страницы как можно раньше
            Future.delayed(const Duration(milliseconds: 300), () {
              _changePageTitle();
            });
          },
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;

              // Показываем кнопку проверки на страницах успеха или 3D-Secure
              _showCheckButton = url.contains('/success') ||
                  url.contains('finish-3ds') ||
                  url.contains('/processing/3ds');
            });

            // Проверяем URL перенаправления
            _checkRedirectUrl(url);

            // Запускаем извлечение информации о ценах
            _extractPriceInformation();

            // Скрываем технические сообщения
            _hideMessages();

            // Изменяем заголовок страницы
            _changePageTitle();

            // Однократно проверяем статус на странице успеха
            if (url.contains('/success') &&
                !_isPaymentHandled &&
                !_isCheckingPayment) {
              _checkPaymentStatus();
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            // Проверяем URL перенаправления
            if (_checkRedirectUrl(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  /// Извлекает информацию о ценах из веб-интерфейса ЮKassa
  Future<void> _extractPriceInformation() async {
    try {
      // Запускаем JavaScript для извлечения информации о ценах
      final result = await _controller
          .runJavaScriptReturningResult(_priceExtractionScript);

      // Результат будет в виде строки, его можно распарсить и использовать
      debugPrint('Извлеченная информация о ценах: $result');

      if (result != 'null') {
        try {
          // Преобразуем результат в строку (если это не строка)
          final String resultStr =
              result is String ? result : result.toString();

          // Удаляем кавычки, если они есть
          final String cleanResult =
              resultStr.startsWith('"') && resultStr.endsWith('"')
                  ? resultStr
                      .substring(1, resultStr.length - 1)
                      .replaceAll('\\"', '"')
                  : resultStr;

          // Преобразуем JSON в Map
          final Map<String, dynamic> priceData = json.decode(cleanResult);

          // Проверяем, что данные действительно для российского пользователя
          if (priceData['isRussianUser'] == true &&
              priceData['prices'] is List) {
            final List<dynamic> prices = priceData['prices'];
            debugPrint('Найдены цены для российского пользователя: $prices');

            // Извлекаем цены и обновляем данные в сервисе
            final Map<SubscriptionType, double> extractedPrices = {};

            // Извлекаем все числовые значения из цен
            for (final priceInfo in prices) {
              if (priceInfo['value'] != null) {
                final String valueStr = priceInfo['value'].toString();
                final double? value = double.tryParse(
                    valueStr.replaceAll(',', '.').replaceAll(' ', ''));

                if (value != null && value > 0) {
                  debugPrint('Найдена цена: $value рублей');

                  // Сопоставляем цены с типами подписок на основе диапазонов
                  if (value >= 900 && value <= 1500) {
                    extractedPrices[SubscriptionType.yearly] = value;
                    debugPrint('Определена годовая подписка: $value рублей');
                  } else if (value >= 250 && value <= 500) {
                    extractedPrices[SubscriptionType.monthly] = value;
                    debugPrint('Определена месячная подписка: $value рублей');
                  } else if (value >= 100 && value <= 200) {
                    extractedPrices[SubscriptionType.weekly] = value;
                    debugPrint('Определена недельная подписка: $value рублей');
                  }
                }
              }
            }

            // Обновляем цены в сервисе только если нашли хотя бы одну цену
            if (extractedPrices.isNotEmpty) {
              YooKassaPaymentService.updatePricesFromWebView(extractedPrices);
              debugPrint(
                  '✅ YOOKASSA_WEBVIEW: Цены успешно извлечены и обновлены: $extractedPrices');
            } else {
              debugPrint(
                  '⚠️ YOOKASSA_WEBVIEW: Не удалось извлечь цены из интерфейса');
            }
          } else {
            debugPrint(
                '⚠️ YOOKASSA_WEBVIEW: Данные не для российского пользователя или нет цен');
          }
        } catch (e) {
          debugPrint(
              '🔴 YOOKASSA_WEBVIEW: Ошибка при обработке данных о ценах: $e');
        }
      } else {
        debugPrint('⚠️ YOOKASSA_WEBVIEW: Скрипт извлечения цен вернул null');
      }
    } catch (e) {
      debugPrint(
          '🔴 YOOKASSA_WEBVIEW: Ошибка при извлечении информации о ценах: $e');
    }
  }

  /// Проверяет URL перенаправления
  bool _checkRedirectUrl(String url) {
    debugPrint('🌐 YOOKASSA_WEBVIEW: Проверка URL: $url');

    if (url.contains('aivideomaker.app/payment/return')) {
      _processReturnUrl(url);
      return true;
    }
    return false;
  }

  /// Обрабатывает URL перенаправления после оплаты
  Future<void> _processReturnUrl(String url) async {
    debugPrint('🌐 YOOKASSA_WEBVIEW: Обрабатываем URL возврата: $url');

    final bool result = await _paymentHandler.processPaymentUrl(url);

    if (result) {
      _handleSuccessfulPayment();
    }
  }

  /// Проверяет статус платежа напрямую через API
  Future<void> _checkPaymentStatus() async {
    // Предотвращаем повторные проверки
    if (_isCheckingPayment || _isPaymentHandled) {
      return;
    }

    setState(() {
      _isCheckingPayment = true;
    });

    // Сначала скрываем технические сообщения
    _hideMessages();

    try {
      debugPrint(
          '🌐 YOOKASSA_WEBVIEW: Проверка статуса платежа: ${widget.paymentId}');

      final bool isSuccess =
          await _paymentHandler.checkPaymentStatus(widget.paymentId);

      if (isSuccess) {
        _handleSuccessfulPayment();
      } else {
        // Показываем уведомление, что платеж еще не завершен
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('payment_pending')),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingPayment = false;
        });
      }
    }
  }

  /// Скрывает технические сообщения на странице
  Future<void> _hideMessages() async {
    try {
      // Запускаем скрипт для скрытия сообщений
      await _controller.runJavaScript(_hideMessageScript);
      debugPrint(
          '✅ YOOKASSA_WEBVIEW: Запущен скрипт скрытия технических сообщений');

      // Если мы на странице успеха, проверяем еще несколько раз с задержкой
      // для обработки динамически добавляемых элементов
      if (_currentUrl != null &&
          (_currentUrl!.contains('/success') ||
              _currentUrl!.contains('finish-3ds'))) {
        // Повторяем скрытие сообщений через 1 и 3 секунды для уверенности
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _controller.runJavaScript(_hideMessageScript);
          }
        });

        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _controller.runJavaScript(_hideMessageScript);
          }
        });
      }
    } catch (e) {
      debugPrint(
          '🔴 YOOKASSA_WEBVIEW: Ошибка при запуске скрипта скрытия сообщений: $e');
    }
  }

  /// Обрабатывает успешный платеж
  void _handleSuccessfulPayment() {
    // Предотвращаем повторные вызовы
    if (_isPaymentHandled) {
      debugPrint(
          '🌐 YOOKASSA_WEBVIEW: Платеж уже обработан, пропускаем повторную обработку');
      return;
    }

    debugPrint('🌐 YOOKASSA_WEBVIEW: Платеж успешен: ${widget.paymentId}');

    // Сразу завершаем платеж, без показа диалога
    _completePayment();
  }

  /// Завершает процесс оплаты и возвращает успешный результат
  void _completePayment() {
    // Устанавливаем флаг, что платеж обработан
    _isPaymentHandled = true;

    // Вызываем callback успешной оплаты
    widget.onSuccess(widget.subscriptionType);

    // Закрываем экран только если контекст все еще действителен
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Изменяет заголовок страницы
  void _changePageTitle() {
    try {
      // Запускаем скрипт для изменения заголовка страницы
      _controller.runJavaScript(_changePageTitleScript);
      debugPrint(
          '✅ YOOKASSA_WEBVIEW: Запущен скрипт изменения заголовка страницы');
    } catch (e) {
      debugPrint(
          '🔴 YOOKASSA_WEBVIEW: Ошибка при запуске скрипта изменения заголовка страницы: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        widget.onCancel();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('subscription_payment_title')),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              widget.onCancel();
              Navigator.of(context).pop();
            },
          ),
          actions: [
            if (_showCheckButton)
              IconButton(
                icon: const Icon(Icons.check_circle),
                tooltip: context.tr('check_payment_status'),
                onPressed: _isCheckingPayment ? null : _checkPaymentStatus,
              ),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              Center(
                child: CircularProgressIndicator(
                  color: Theme.of(context).primaryColor,
                ),
              ),
            if (_isCheckingPayment)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: Theme.of(context).primaryColor,
                ),
              ),
          ],
        ),
        bottomNavigationBar: _currentUrl != null &&
                (_currentUrl!.contains('/success') ||
                    _currentUrl!.contains('finish-3ds'))
            ? SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: _isCheckingPayment ? null : _checkPaymentStatus,
                    child: _isCheckingPayment
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(context.tr('checking'))
                            ],
                          )
                        : Text(context.tr('check_payment_status')),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
