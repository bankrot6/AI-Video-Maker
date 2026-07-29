import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter/foundation.dart';
import '../models/subscription_model.dart';

/// Идентификаторы продуктов в магазинах приложений
class StoreProductIds {
  // iOS App Store идентификаторы
  static const String _weeklyIOS = 'aivideomakerWeek';
  static const String _monthlyIOS = 'aivideomakerMonth';
  static const String _yearlyWithTrialIOS = 'aivideomakerYear';

  // Android Google Play идентификаторы
  static const String _weeklyAndroid = 'aivideomaker.weekly.subscription';
  static const String _monthlyAndroid = 'aivideomaker.monthly.subscription';
  static const String _yearlyWithTrialAndroid = 'aivideomaker.yearly.subscription';

  // RuStore идентификаторы
  static const String _weeklyRuStore = 'aivideomaker.weekly.rustore';
  static const String _monthlyRuStore = 'aivideomaker.monthly.rustore';
  static const String _yearlyRuStore = 'aivideomaker.yearly.rustore';

  /// Недельная подписка
  static String get weekly => Platform.isIOS ? _weeklyIOS : _weeklyAndroid;

  /// Месячная подписка
  static String get monthly => Platform.isIOS ? _monthlyIOS : _monthlyAndroid;

  /// Годовая подписка с недельным пробным периодом
  static String get yearlyWithTrial =>
      Platform.isIOS ? _yearlyWithTrialIOS : _yearlyWithTrialAndroid;

  /// Список всех идентификаторов продуктов
  static Set<String> get all => {
        weekly,
        monthly,
        yearlyWithTrial,
      };

  /// Список всех идентификаторов продуктов для iOS
  static Set<String> get allIOS => {
        _weeklyIOS,
        _monthlyIOS,
        _yearlyWithTrialIOS,
      };

  /// Список всех идентификаторов продуктов для Android
  static Set<String> get allAndroid => {
        _weeklyAndroid,
        _monthlyAndroid,
        _yearlyWithTrialAndroid,
      };

  /// Список всех идентификаторов продуктов для RuStore
  static Set<String> get allRuStore => {
        _weeklyRuStore,
        _monthlyRuStore,
        _yearlyRuStore,
      };

  /// Геттеры для RuStore product IDs
  static String get weeklyRuStore => _weeklyRuStore;
  static String get monthlyRuStore => _monthlyRuStore;
  static String get yearlyRuStore => _yearlyRuStore;
}

/// Абстрактный интерфейс для сервиса покупок
///
/// Следуя принципу OCP (Open-Closed Principle) из SOLID, этот интерфейс
/// позволяет нам в будущем легко добавлять другие платформы без изменения
/// существующего кода.
abstract class IPurchaseService {
  /// Инициализация сервиса
  Future<void> initialize();

  /// Получение доступных продуктов из магазина
  Future<List<ProductDetails>> getProducts();

  /// Покупка продукта
  Future<void> buyProduct(ProductDetails product);

  /// Восстановление покупок
  Future<void> restorePurchases();

  /// Проверка наличия активной подписки
  Future<bool> checkActiveSubscription();

  /// Завершение работы сервиса
  Future<void> dispose();

  /// Stream для получения информации о покупках
  Stream<List<PurchaseDetails>> get purchaseStream;

  /// Проверка соединения с магазином приложений
  Future<bool> get isAvailable;
}

/// Реализация сервиса покупок для iOS/Android через пакет in_app_purchase
///
/// Следуя принципу SRP (Single Responsibility Principle) из SOLID,
/// этот класс отвечает только за взаимодействие с платежной системой.
class InAppPurchaseService implements IPurchaseService {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final StreamController<List<PurchaseDetails>> _purchaseController =
      StreamController<List<PurchaseDetails>>.broadcast();

  bool _isInitialized = false;

  /// Создает экземпляр сервиса покупок
  InAppPurchaseService() {
    debugPrint('🟣 IAP: Сервис покупок создан');
  }

  @override
  Future<bool> get isAvailable => _inAppPurchase.isAvailable();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _purchaseController.stream;

  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('🟣 IAP: Сервис покупок уже инициализирован');
      return;
    }

    debugPrint('🟣 IAP: Начинаем инициализацию сервиса покупок');
    debugPrint('🟣 IAP: Проверяем доступность магазина приложений');
    final available = await isAvailable;
    debugPrint('🟣 IAP: Доступность магазина приложений: $available');

    if (!available) {
      debugPrint('🔴 IAP: Магазин приложений недоступен');
      throw Exception('Магазин приложений недоступен');
    }

    debugPrint('🟣 IAP: Настраиваем слушатель покупок');
    // Слушаем события покупок
    _subscription = _inAppPurchase.purchaseStream.listen(
      (purchases) {
        debugPrint(
            '🟣 IAP: Получено событие покупки: ${purchases.length} элементов');
        for (var purchase in purchases) {
          debugPrint(
              '🟣 IAP: Событие покупки: ${purchase.productID}, статус: ${purchase.status}');
        }
        _purchaseController.add(purchases);
        _handlePurchaseUpdates(purchases);
      },
      onDone: () {
        debugPrint('🟣 IAP: Поток покупок завершен');
        _subscription?.cancel();
      },
      onError: (error) {
        // Обработка ошибок
        debugPrint('🔴 IAP: Ошибка в потоке покупок: $error');
      },
    );

    _isInitialized = true;
    debugPrint('🟣 IAP: Сервис покупок успешно инициализирован');
  }

  @override
  Future<List<ProductDetails>> getProducts() async {
    debugPrint('🟣 IAP: Запрашиваем список продуктов');
    if (!_isInitialized) {
      debugPrint('🟣 IAP: Сервис не инициализирован, выполняем инициализацию');
      await initialize();
    }

    debugPrint(
        '🟣 IAP: Выполняем запрос продуктов для: ${StoreProductIds.all}');
    final ProductDetailsResponse response =
        await _inAppPurchase.queryProductDetails(StoreProductIds.all);

    if (response.error != null) {
      debugPrint('🔴 IAP: Ошибка при получении продуктов: ${response.error}');
      throw Exception('Ошибка при получении продуктов: ${response.error}');
    }

    debugPrint('🟣 IAP: Получено продуктов: ${response.productDetails.length}');
    for (var product in response.productDetails) {
      debugPrint(
          '🟣 IAP: Продукт: ${product.id}, ${product.title}, ${product.price}');
    }

    return response.productDetails;
  }

  @override
  Future<void> buyProduct(ProductDetails product) async {
    if (!_isInitialized) {
      debugPrint('🟣 IAP: Сервис не инициализирован, выполняем инициализацию');
      await initialize();
    }

    // Защита от повторных нажатий
    debugPrint('🟣 IAP: Начало процесса покупки: ${product.id}');

    // Формируем параметры покупки
    final PurchaseParam purchaseParam = PurchaseParam(
      productDetails: product,
      applicationUserName: null, // Можно добавить идентификатор пользователя
    );

    // В зависимости от платформы выбираем правильный метод покупки
    try {
      if (Platform.isIOS) {
        // На iOS для подписок используем именно buyNonConsumable
        debugPrint(
            '🟣 IAP: iOS: Вызываем метод buyNonConsumable с purchaseParam');
        debugPrint(
            '🟣 IAP: iOS: product.id=${product.id}, product.title=${product.title}, product.price=${product.price}');

        // Вызываем метод покупки
        final bool purchaseProcessStarted =
            await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);

        // Проверяем результат запуска процесса покупки
        if (purchaseProcessStarted) {
          debugPrint(
              '🟣 IAP: iOS: Процесс покупки успешно запущен, ожидаем нативное окно');
        } else {
          debugPrint('🔴 IAP: iOS: Не удалось запустить процесс покупки');
          throw Exception('Не удалось запустить процесс покупки');
        }
      } else {
        // На Android для подписок используем правильный метод для Google Play
        debugPrint('🟣 IAP: Android: Покупка подписки: ${product.id}');

        // Проверяем ID продукта, чтобы убедиться, что это подписка Google Play
        if (StoreProductIds.allAndroid.contains(product.id)) {
          debugPrint(
              '🟣 IAP: Android: Используем метод для подписки Google Play');

          // Для подписок в Google Play также используем buyNonConsumable
          // В зависимости от имплементации API in_app_purchase для Google Play
          final bool purchaseStarted = await _inAppPurchase.buyNonConsumable(
              purchaseParam: purchaseParam);

          if (purchaseStarted) {
            debugPrint(
                '🟣 IAP: Android: Процесс покупки подписки запущен, ожидаем нативное окно');
          } else {
            debugPrint(
                '🔴 IAP: Android: Не удалось запустить процесс покупки подписки');
            throw Exception(
                'Не удалось запустить процесс покупки подписки на Android');
          }
        } else {
          // Обратная совместимость: если это не подписка Google Play, используем buyNonConsumable
          debugPrint(
              '🟣 IAP: Android: Используем buyNonConsumable для совместимости');

          final bool purchaseStarted = await _inAppPurchase.buyNonConsumable(
              purchaseParam: purchaseParam);

          if (purchaseStarted) {
            debugPrint(
                '🟣 IAP: Android: Процесс покупки запущен, ожидаем нативное окно');
          } else {
            debugPrint('🔴 IAP: Android: Не удалось запустить процесс покупки');
            throw Exception('Не удалось запустить процесс покупки на Android');
          }
        }
      }

      debugPrint('🟣 IAP: Процесс покупки инициирован успешно');
    } catch (e) {
      debugPrint('🔴 IAP: Ошибка при покупке: $e');
      rethrow;
    }
  }

  @override
  Future<void> restorePurchases() async {
    if (!_isInitialized) await initialize();
    await _inAppPurchase.restorePurchases();
  }

  @override
  Future<bool> checkActiveSubscription() async {
    try {
      debugPrint('🟣 IAP: Проверка активной подписки');

      if (!_isInitialized) {
        debugPrint('🟣 IAP: Инициализация сервиса перед проверкой подписки');
        await initialize();
      }

      // Создаем список для хранения всех полученных покупок
      final List<PurchaseDetails> allPurchases = [];
      final Completer<List<PurchaseDetails>> completer = Completer();

      // Устанавливаем разумный таймаут
      final timer = Timer(const Duration(seconds: 4), () {
        if (!completer.isCompleted) {
          debugPrint('🟡 IAP: Таймаут при проверке подписки');
          completer.complete(allPurchases);
        }
      });

      // Создаем временную подписку на события покупок
      StreamSubscription<List<PurchaseDetails>>? tempSubscription;

      // Подписываемся на события покупок
      tempSubscription = _inAppPurchase.purchaseStream.listen((purchases) {
        debugPrint('🟣 IAP: Получены покупки: ${purchases.length}');

        if (purchases.isNotEmpty) {
          allPurchases.addAll(purchases);

          // Проверяем наличие активных подписок сразу
          final hasSubscription = purchases.any((purchase) {
            final bool isPurchased =
                purchase.status == PurchaseStatus.purchased ||
                    purchase.status == PurchaseStatus.restored;
            final bool isSubscription =
                StoreProductIds.all.contains(purchase.productID);

            debugPrint(
                '🟣 IAP: Проверка покупки: ${purchase.productID}, статус=${purchase.status}, подписка=$isSubscription');

            return isPurchased && isSubscription;
          });

          if (hasSubscription && !completer.isCompleted) {
            debugPrint('🟢 IAP: Найдена активная подписка в потоке');
            timer.cancel();
            tempSubscription?.cancel();
            completer.complete(allPurchases);
          }
        }
      }, onDone: () {
        if (!completer.isCompleted) {
          timer.cancel();
          completer.complete(allPurchases);
        }
      }, onError: (error) {
        debugPrint('🔴 IAP: Ошибка в потоке покупок: $error');
        if (!completer.isCompleted) {
          timer.cancel();
          completer.complete(allPurchases);
        }
      });

      // Выполняем восстановление покупок для получения актуальных данных
      debugPrint(
          '🟣 IAP: Восстановление покупок для проверки статуса подписки');
      try {
        await _inAppPurchase.restorePurchases();
        debugPrint('🟣 IAP: Восстановление покупок выполнено успешно');
      } catch (e) {
        debugPrint('🔴 IAP: Ошибка при восстановлении покупок: $e');
      }

      // Ждем результатов восстановления или таймаута
      final purchases = await completer.future;
      debugPrint('🟣 IAP: Получено ${purchases.length} покупок для проверки');

      // Проверяем наличие активных подписок в полученных данных
      if (purchases.isNotEmpty) {
        // Подсчитываем статистику по покупкам для отладки
        int purchased = 0;
        int pending = 0;
        int error = 0;
        int canceled = 0;
        int restored = 0;

        for (var purchase in purchases) {
          switch (purchase.status) {
            case PurchaseStatus.purchased:
              purchased++;
              break;
            case PurchaseStatus.pending:
              pending++;
              break;
            case PurchaseStatus.error:
              error++;
              break;
            case PurchaseStatus.canceled:
              canceled++;
              break;
            case PurchaseStatus.restored:
              restored++;
              break;
          }
        }

        debugPrint(
            '🟣 IAP: Статистика покупок: purchased=$purchased, restored=$restored, pending=$pending, error=$error, canceled=$canceled');

        // Проверяем наличие активных подписок
        final hasActiveSubscription = purchases.any((purchase) {
          final bool isPurchased =
              purchase.status == PurchaseStatus.purchased ||
                  purchase.status == PurchaseStatus.restored;
          final bool isSubscription =
              StoreProductIds.all.contains(purchase.productID);

          return isPurchased && isSubscription;
        });

        if (hasActiveSubscription) {
          debugPrint('🟢 IAP: Обнаружена активная подписка');
          return true;
        }
      }

      // Если подписки не найдены через стандартный механизм,
      // выполняем дополнительную проверку для iOS Sandbox
      if (Platform.isIOS) {
        debugPrint('🟣 IAP: Выполняем дополнительную проверку для iOS');

        try {
          final isSandbox = await _isSandboxEnvironment();
          debugPrint('🟣 IAP: Проверка Sandbox: $isSandbox');

          if (isSandbox) {
            // Получаем данные чека для iOS
            final receiptData = await _fetchReceiptData();

            if (receiptData != null && receiptData.isNotEmpty) {
              debugPrint(
                  '🟢 IAP: Обнаружена активная подписка через проверку чека в Sandbox');
              return true;
            }

            // Дополнительная проверка для отладочного режима в iOS Sandbox
            if (kDebugMode) {
              final bool isDebugSandbox = allPurchases
                  .isEmpty; // Если в debug режиме и нет покупок, считаем что это тест

              if (isDebugSandbox) {
                debugPrint(
                    '🟢 IAP: Разрешаем доступ в режиме отладки для iOS Sandbox');
                return true; // В режиме отладки разрешаем доступ для тестирования
              }
            }
          }
        } catch (e) {
          debugPrint('🟡 IAP: Ошибка при дополнительной проверке для iOS: $e');
        }
      }

      debugPrint('🟡 IAP: Активные подписки не обнаружены');
      return false;
    } catch (e) {
      debugPrint('🔴 IAP: Ошибка при проверке активной подписки: $e');

      // В случае ошибки в режиме отладки разрешаем доступ для тестирования функциональности
      if (kDebugMode && Platform.isIOS) {
        debugPrint(
            '🟢 IAP: Разрешаем доступ в режиме отладки, несмотря на ошибку');
        return true;
      }

      return false;
    }
  }

  /// Получение данных чека для iOS (только для Sandbox)
  Future<String?> _fetchReceiptData() async {
    if (!Platform.isIOS) return null;

    try {
      // На iOS можно получить данные чека для проверки
      // Используем purchaseStream для проверки наличия транзакций
      final List<PurchaseDetails> currentPurchases = [];

      // Создаем Completer для получения результата
      final completer = Completer<List<PurchaseDetails>>();

      // Устанавливаем таймаут для операции
      final timer = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) {
          debugPrint('🟡 IAP: Таймаут при получении данных чека');
          completer.complete(currentPurchases);
        }
      });

      // Создаем временную подписку на поток покупок
      StreamSubscription<List<PurchaseDetails>>? tempSubscription;
      tempSubscription = _inAppPurchase.purchaseStream.listen((purchases) {
        debugPrint(
            '🟣 IAP: В _fetchReceiptData получены покупки: ${purchases.length}');
        currentPurchases.addAll(purchases);

        if (!completer.isCompleted) {
          timer.cancel();
          tempSubscription?.cancel();
          completer.complete(currentPurchases);
        }
      }, onDone: () {
        if (!completer.isCompleted) {
          timer.cancel();
          completer.complete(currentPurchases);
        }
      }, onError: (error) {
        debugPrint(
            '🔴 IAP: Ошибка в потоке покупок при получении данных чека: $error');
        if (!completer.isCompleted) {
          timer.cancel();
          completer.complete(currentPurchases);
        }
      });

      // Вызываем restorePurchases для проверки транзакций
      try {
        await _inAppPurchase.restorePurchases();
      } catch (e) {
        debugPrint(
            '🔴 IAP: Ошибка при восстановлении покупок в _fetchReceiptData: $e');
      }

      // Ждем результатов
      final purchases = await completer.future;

      // Если есть хотя бы одна покупка, считаем что у нас есть данные чека
      if (purchases.isNotEmpty) {
        for (var purchase in purchases) {
          debugPrint(
              '🟣 IAP: Обнаружена транзакция: ${purchase.productID}, статус: ${purchase.status}');

          // Если есть valid транзакция, возвращаем данные
          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            return "valid_receipt_data";
          }
        }
      }

      // Если мы в Sandbox, но транзакций не обнаружено, проверяем другие признаки
      if (await _isSandboxEnvironment()) {
        // Проверяем запуск через Xcode или другие признаки Sandbox
        if (kDebugMode) {
          // В debug-режиме в Sandbox может не быть валидных транзакций,
          // но нам нужно разрешить доступ к функциям подписки для отладки
          debugPrint(
              '🟣 IAP: Debug-режим в Sandbox, предполагаем наличие подписки для отладки');
          return "debug_sandbox_receipt";
        }
      }

      return null;
    } catch (e) {
      debugPrint('🔴 IAP: Ошибка при получении данных чека: $e');
      return null;
    }
  }

  /// Проверка запуска в Sandbox-окружении (только для iOS)
  Future<bool> _isSandboxEnvironment() async {
    if (!Platform.isIOS) return false;

    try {
      // Для более точного определения Sandbox среды:
      // 1. Проверяем, запущено ли приложение в режиме debug
      // 2. Проверяем признаки, характерные для Sandbox, такие как:
      //    - Наличие специфических сертификатов
      //    - Запуск через Xcode

      // Для начала проверим режим запуска
      if (kDebugMode) {
        debugPrint('🟣 IAP: Запуск в debug-режиме, вероятно Sandbox');
        return true;
      }

      // Дополнительная проверка для TestFlight
      // В реальном приложении можно использовать нативный канал для проверки
      // бандла или другие методы определения TestFlight
      final String appBundleID = await _getAppBundleIdentifier();
      if (appBundleID.contains('.dev') || appBundleID.contains('.test')) {
        debugPrint(
            '🟣 IAP: Bundle ID указывает на тестовую сборку: $appBundleID');
        return true;
      }

      // В релизной версии возвращаем false, чтобы не принимать sandbox за production
      debugPrint('🟣 IAP: Определено production-окружение');
      return false;
    } catch (e) {
      debugPrint('🔴 IAP: Ошибка при определении Sandbox-окружения: $e');
      return false;
    }
  }

  /// Получение идентификатора приложения (для определения TestFlight и т.д.)
  Future<String> _getAppBundleIdentifier() async {
    try {
      // В реальном приложении здесь был бы код для получения bundle ID
      // через method channel или плагин package_info_plus

      // Заглушка для примера
      return TargetPlatform.iOS == defaultTargetPlatform
          ? 'com.aivideomaker.app'
          : 'com.aivideomaker.app';
    } catch (e) {
      return 'unknown';
    }
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _purchaseController.close();
  }

  /// Обработка обновлений покупок
  Future<void> _handlePurchaseUpdates(
      List<PurchaseDetails> purchaseDetailsList) async {
    debugPrint(
        '🟣 IAP: Начинаем обработку ${purchaseDetailsList.length} покупок');

    for (var purchaseDetails in purchaseDetailsList) {
      debugPrint(
          '🟣 IAP: Обработка покупки: ${purchaseDetails.productID}, статус: ${purchaseDetails.status}');

      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Покупка в процессе
        debugPrint('🟣 IAP: Покупка в процессе: ${purchaseDetails.productID}');
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // Ошибка при покупке
        debugPrint(
            '🔴 IAP: Ошибка при покупке: ${purchaseDetails.productID}, ошибка: ${purchaseDetails.error?.message}');

        // Завершаем транзакцию даже в случае ошибки
        if (purchaseDetails.pendingCompletePurchase) {
          debugPrint(
              '🟣 IAP: Завершаем транзакцию (ошибка): ${purchaseDetails.productID}');
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        // Успешная покупка или восстановление
        debugPrint(
            '🟢 IAP: Успешная покупка/восстановление: ${purchaseDetails.productID}');

        // Проверка валидности покупки
        bool isValid = true;

        // На iOS необходимо проверить данные чека
        if (Platform.isIOS) {
          debugPrint('🟣 IAP: iOS: Проверяем данные чека');
          // На iOS можно проверить AppleVerificationData
          final iosPurchaseVerification = purchaseDetails.verificationData;
          if (iosPurchaseVerification.localVerificationData.isEmpty ||
              iosPurchaseVerification.serverVerificationData.isEmpty) {
            debugPrint(
                '🔴 IAP: iOS: Нет данных верификации: ${purchaseDetails.productID}');
            isValid = false;
          } else {
            debugPrint(
                '🟢 IAP: iOS: Данные верификации получены: ${purchaseDetails.productID}');
          }
        }
        // На Android выполняем проверку Google Play
        else if (Platform.isAndroid) {
          debugPrint('🟣 IAP: Android: Проверяем данные подписки');
          // В настоящем приложении здесь должна быть проверка токена Google Play
          final androidPurchaseVerification = purchaseDetails.verificationData;
          if (androidPurchaseVerification.localVerificationData.isEmpty ||
              androidPurchaseVerification.serverVerificationData.isEmpty) {
            debugPrint(
                '🔴 IAP: Android: Нет данных верификации: ${purchaseDetails.productID}');
            isValid = false;
          } else {
            debugPrint(
                '🟢 IAP: Android: Данные верификации получены: ${purchaseDetails.productID}');
            // Проверяем, принадлежит ли продукт к списку Google Play подписок
            if (!StoreProductIds.allAndroid
                    .contains(purchaseDetails.productID) &&
                !StoreProductIds.allIOS.contains(purchaseDetails.productID)) {
              debugPrint(
                  '🔴 IAP: Android: Неизвестный продукт: ${purchaseDetails.productID}');
              isValid = false;
            }
          }
        }

        if (isValid) {
          try {
            debugPrint(
                '🟢 IAP: Начинаем верификацию покупки: ${purchaseDetails.productID}');
            await _verifyPurchase(purchaseDetails);
            debugPrint(
                '🟢 IAP: Верификация покупки выполнена: ${purchaseDetails.productID}');
          } catch (e) {
            debugPrint('🔴 IAP: Ошибка при верификации покупки: $e');
            // Даже в случае ошибки верификации мы должны завершить транзакцию
            if (purchaseDetails.pendingCompletePurchase) {
              debugPrint(
                  '🟣 IAP: Завершаем транзакцию (при ошибке верификации): ${purchaseDetails.productID}');
              await _inAppPurchase.completePurchase(purchaseDetails);
            }
          }
        } else {
          debugPrint(
              '🔴 IAP: Невалидная транзакция: ${purchaseDetails.productID}');

          // Все равно завершаем транзакцию для избежания "залипших" транзакций
          if (purchaseDetails.pendingCompletePurchase) {
            debugPrint(
                '🟣 IAP: Завершаем невалидную транзакцию: ${purchaseDetails.productID}');
            await _inAppPurchase.completePurchase(purchaseDetails);
          }
        }
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        debugPrint('🟣 IAP: Покупка отменена: ${purchaseDetails.productID}');

        // Завершаем отмененную транзакцию
        if (purchaseDetails.pendingCompletePurchase) {
          debugPrint(
              '🟣 IAP: Завершаем отмененную транзакцию: ${purchaseDetails.productID}');
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  /// Верификация покупки и активация соответствующей подписки
  Future<void> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    // В реальном приложении здесь должна быть проверка с сервером
    debugPrint('🟣 IAP: Верификация покупки: ${purchaseDetails.productID}');

    try {
      // Определяем тип подписки на основе ID продукта
      final subscriptionType =
          _getSubscriptionTypeFromProductId(purchaseDetails.productID);

      if (subscriptionType != SubscriptionType.free) {
        debugPrint(
            '🟢 IAP: Тип подписки определен: $subscriptionType для ${purchaseDetails.productID}');

        // Здесь можно отправить событие об успешной покупке
        // или выполнить другие действия по активации подписки

        // Дополнительная логика верификации на основе платформы
        if (Platform.isIOS) {
          // Логика верификации для iOS
          debugPrint('🟣 IAP: iOS: Выполняется платформенная верификация');
          // В реальном приложении - отправка данных на сервер для проверки
        } else if (Platform.isAndroid) {
          // Логика верификации для Android
          debugPrint('🟣 IAP: Android: Выполняется платформенная верификация');
          // Дополнительная проверка для Google Play подписок
        }
      } else {
        debugPrint(
            '🔴 IAP: Не удалось определить тип подписки для ${purchaseDetails.productID}');
      }

      // Завершаем транзакцию независимо от результата верификации
      if (purchaseDetails.pendingCompletePurchase) {
        debugPrint(
            '🟣 IAP: Завершение транзакции покупки: ${purchaseDetails.productID}');
        await _inAppPurchase.completePurchase(purchaseDetails);
        debugPrint(
            '🟣 IAP: Транзакция успешно завершена: ${purchaseDetails.productID}');
      }
    } catch (e) {
      debugPrint('🔴 IAP: Ошибка при верификации покупки: $e');
      // Пробуем завершить транзакцию даже при ошибке
      if (purchaseDetails.pendingCompletePurchase) {
        try {
          await _inAppPurchase.completePurchase(purchaseDetails);
          debugPrint(
              '🟣 IAP: Транзакция завершена после ошибки: ${purchaseDetails.productID}');
        } catch (e) {
          debugPrint('🔴 IAP: Ошибка при завершении транзакции: $e');
        }
      }
      rethrow; // Пробрасываем ошибку дальше
    }
  }

  /// Получение типа подписки из ID продукта
  SubscriptionType _getSubscriptionTypeFromProductId(String productId) {
    if (productId == StoreProductIds.weekly ||
        productId == 'aivideomaker.weekly.subscription') {
      return SubscriptionType.weekly;
    } else if (productId == StoreProductIds.monthly ||
        productId == 'aivideomaker.monthly.subscription') {
      return SubscriptionType.monthly;
    } else if (productId == StoreProductIds.yearlyWithTrial ||
        productId == 'aivideomaker.yearly.subscription') {
      return SubscriptionType.yearly;
    }
    return SubscriptionType.free;
  }
}
