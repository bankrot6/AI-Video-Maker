import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../utils/app_logger.dart';
import 'token_store_config.dart';

/// Сервис для покупки и восстановления токенов через стандартные IAP
class TokenPurchaseService {
  static const String _logPrefix = '🪙 TOKEN_IAP';

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final StreamController<List<PurchaseDetails>> _purchaseController =
      StreamController<List<PurchaseDetails>>.broadcast();

  bool _isInitialized = false;

  /// Инициализация сервиса
  Future<bool> initialize() async {
    if (_isInitialized) {
      AppLogger.log('$_logPrefix Сервис уже инициализирован');
      return true;
    }

    try {
      AppLogger.log('$_logPrefix Инициализация сервиса токенов...');

      // Проверяем доступность магазина
      final available = await _inAppPurchase.isAvailable();
      if (!available) {
        AppLogger.log('$_logPrefix Магазин приложений недоступен');
        return false;
      }

      // Настраиваем слушатель покупок
      _subscription = _inAppPurchase.purchaseStream.listen(
        (purchases) {
          AppLogger.log(
              '$_logPrefix Получено событие покупки: ${purchases.length} элементов');
          _purchaseController.add(purchases);
          _handlePurchaseUpdates(purchases);
        },
        onError: (error) {
          AppLogger.log('$_logPrefix Ошибка в потоке покупок: $error');
        },
      );

      _isInitialized = true;
      AppLogger.log('$_logPrefix Сервис токенов успешно инициализирован');
      return true;
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка инициализации: $e');
      return false;
    }
  }

  /// Восстановление токенных покупок
  Future<List<PurchaseDetails>> restoreTokenPurchases() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        AppLogger.log(
            '$_logPrefix Не удалось инициализировать для восстановления');
        return [];
      }
    }

    try {
      AppLogger.log('$_logPrefix 🔄 Восстановление токенных покупок...');

      // Создаем completer для получения результатов
      final Completer<List<PurchaseDetails>> completer = Completer();
      final List<PurchaseDetails> tokenPurchases = [];

      // Устанавливаем таймаут
      final timer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          AppLogger.log('$_logPrefix Таймаут при восстановлении токенов');
          completer.complete(tokenPurchases);
        }
      });

      // Создаем временную подписку на события покупок
      StreamSubscription<List<PurchaseDetails>>? tempSubscription;
      tempSubscription = _inAppPurchase.purchaseStream.listen((purchases) {
        for (final purchase in purchases) {
          if (_isTokenProduct(purchase.productID) &&
              (purchase.status == PurchaseStatus.purchased ||
                  purchase.status == PurchaseStatus.restored)) {
            AppLogger.log(
                '$_logPrefix ✅ Найдена токенная покупка: ${purchase.productID}');
            tokenPurchases.add(purchase);
          }
        }

        if (!completer.isCompleted) {
          timer.cancel();
          tempSubscription?.cancel();
          completer.complete(tokenPurchases);
        }
      });

      // Выполняем восстановление покупок
      await _inAppPurchase.restorePurchases();

      // Ждем результатов
      final results = await completer.future;

      AppLogger.log(
          '$_logPrefix Восстановлено токенных покупок: ${results.length}');
      return results;
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка восстановления токенов: $e');
      return [];
    }
  }

  /// Получение количества токенов по product ID
  int getTokenCountFromProductId(String productId) {
    return TokenStoreConfig.getTokenCountFromProductId(productId) ?? 0;
  }

  /// Проверка, является ли продукт токенным
  bool _isTokenProduct(String productId) {
    return TokenStoreConfig.isTokenProduct(productId);
  }

  /// Обработка обновлений покупок
  Future<void> _handlePurchaseUpdates(
      List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchaseDetails in purchaseDetailsList) {
      AppLogger.log(
          '$_logPrefix Обработка покупки: ${purchaseDetails.productID}, статус: ${purchaseDetails.status}');

      if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        // Завершаем транзакцию для токенных продуктов (они consumable)
        if (_isTokenProduct(purchaseDetails.productID) &&
            purchaseDetails.pendingCompletePurchase) {
          AppLogger.log(
              '$_logPrefix Завершение токенной транзакции: ${purchaseDetails.productID}');
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  /// Поток покупок
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _purchaseController.stream;

  /// Освобождение ресурсов
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _purchaseController.close();
  }
}
