import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import 'token_store_config.dart';

/// Модель токенной покупки YooKassa
class YooKassaTokenPurchase {
  final String paymentId;
  final String productId;
  final int tokenCount;
  final DateTime purchaseDate;
  final double amount;
  final bool isRestored;

  const YooKassaTokenPurchase({
    required this.paymentId,
    required this.productId,
    required this.tokenCount,
    required this.purchaseDate,
    required this.amount,
    this.isRestored = false,
  });

  Map<String, dynamic> toJson() => {
        'paymentId': paymentId,
        'productId': productId,
        'tokenCount': tokenCount,
        'purchaseDate': purchaseDate.millisecondsSinceEpoch,
        'amount': amount,
        'isRestored': isRestored,
      };

  factory YooKassaTokenPurchase.fromJson(Map<String, dynamic> json) =>
      YooKassaTokenPurchase(
        paymentId: json['paymentId'],
        productId: json['productId'],
        tokenCount: json['tokenCount'],
        purchaseDate: DateTime.fromMillisecondsSinceEpoch(json['purchaseDate']),
        amount: json['amount'].toDouble(),
        isRestored: json['isRestored'] ?? false,
      );
}

/// Сервис для восстановления токенных покупок YooKassa
class YooKassaTokenService {
  static const String _logPrefix = '💳 YOOKASSA_TOKENS';
  static const String _tokenPurchasesKey = 'yookassa_token_purchases';

  // Синглтон
  static final YooKassaTokenService _instance =
      YooKassaTokenService._internal();
  factory YooKassaTokenService() => _instance;
  YooKassaTokenService._internal();

  /// Сохранение токенной покупки YooKassa
  Future<void> saveTokenPurchase({
    required String paymentId,
    required String productId,
    required int tokenCount,
    required double amount,
  }) async {
    try {
      AppLogger.log(
          '$_logPrefix Сохранение токенной покупки: $productId ($tokenCount токенов)');

      final prefs = await SharedPreferences.getInstance();
      final purchase = YooKassaTokenPurchase(
        paymentId: paymentId,
        productId: productId,
        tokenCount: tokenCount,
        purchaseDate: DateTime.now(),
        amount: amount,
      );

      // Получаем существующие покупки
      final existingPurchases = await _getStoredPurchases();

      // Проверяем, не дублируется ли покупка
      final isDuplicate =
          existingPurchases.any((p) => p.paymentId == paymentId);
      if (isDuplicate) {
        AppLogger.log('$_logPrefix Покупка уже существует: $paymentId');
        return;
      }

      // Добавляем новую покупку
      existingPurchases.add(purchase);

      // Сохраняем в SharedPreferences
      final purchasesJson = existingPurchases.map((p) => p.toJson()).toList();
      await prefs.setString(_tokenPurchasesKey, jsonEncode(purchasesJson));

      AppLogger.log('$_logPrefix ✅ Токенная покупка сохранена: $paymentId');
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка сохранения токенной покупки: $e');
    }
  }

  /// Восстановление токенных покупок YooKassa
  Future<List<YooKassaTokenPurchase>> restoreTokenPurchases() async {
    try {
      AppLogger.log(
          '$_logPrefix 🔄 Восстановление токенных покупок YooKassa...');

      final purchases = await _getStoredPurchases();

      // Фильтруем неразработанные покупки
      final unrestoredPurchases =
          purchases.where((p) => !p.isRestored).toList();

      if (unrestoredPurchases.isNotEmpty) {
        // Помечаем покупки как восстановленные
        await _markPurchasesAsRestored(
            unrestoredPurchases.map((p) => p.paymentId).toList());

        AppLogger.log(
            '$_logPrefix ✅ Восстановлено токенных покупок: ${unrestoredPurchases.length}');
        for (final purchase in unrestoredPurchases) {
          AppLogger.log(
              '$_logPrefix - ${purchase.productId}: ${purchase.tokenCount} токенов');
        }
      } else {
        AppLogger.log(
            '$_logPrefix Новых токенных покупок для восстановления не найдено');
      }

      return unrestoredPurchases;
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка восстановления токенов: $e');
      return [];
    }
  }

  /// Получение количества токенов по product ID
  int getTokenCountFromProductId(String productId) {
    return TokenStoreConfig.getTokenCountFromProductId(productId) ?? 0;
  }

  /// Получение всех сохраненных покупок
  Future<List<YooKassaTokenPurchase>> _getStoredPurchases() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final purchasesJson = prefs.getString(_tokenPurchasesKey);

      if (purchasesJson == null || purchasesJson.isEmpty) {
        return [];
      }

      final List<dynamic> purchasesList = jsonDecode(purchasesJson);
      return purchasesList
          .map((json) => YooKassaTokenPurchase.fromJson(json))
          .toList();
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка получения сохраненных покупок: $e');
      return [];
    }
  }

  /// Пометить покупки как восстановленные
  Future<void> _markPurchasesAsRestored(List<String> paymentIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final purchases = await _getStoredPurchases();

      // Обновляем статус восстановления
      for (int i = 0; i < purchases.length; i++) {
        if (paymentIds.contains(purchases[i].paymentId)) {
          purchases[i] = YooKassaTokenPurchase(
            paymentId: purchases[i].paymentId,
            productId: purchases[i].productId,
            tokenCount: purchases[i].tokenCount,
            purchaseDate: purchases[i].purchaseDate,
            amount: purchases[i].amount,
            isRestored: true,
          );
        }
      }

      // Сохраняем обновленный список
      final purchasesJson = purchases.map((p) => p.toJson()).toList();
      await prefs.setString(_tokenPurchasesKey, jsonEncode(purchasesJson));
    } catch (e) {
      AppLogger.log(
          '$_logPrefix Ошибка пометки покупок как восстановленных: $e');
    }
  }

  /// Получение общего количества невосстановленных токенов
  Future<int> getUnrestoredTokenCount() async {
    try {
      final purchases = await _getStoredPurchases();
      final unrestoredPurchases = purchases.where((p) => !p.isRestored);

      int totalTokens = 0;
      for (final purchase in unrestoredPurchases) {
        totalTokens += purchase.tokenCount;
      }

      return totalTokens;
    } catch (e) {
      AppLogger.log(
          '$_logPrefix Ошибка подсчета невосстановленных токенов: $e');
      return 0;
    }
  }

  /// Очистка старых покупок (старше 30 дней и восстановленных)
  Future<void> cleanupOldPurchases() async {
    try {
      final purchases = await _getStoredPurchases();
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));

      final filteredPurchases = purchases.where((purchase) {
        // Сохраняем невосстановленные или новые покупки
        return !purchase.isRestored ||
            purchase.purchaseDate.isAfter(cutoffDate);
      }).toList();

      if (filteredPurchases.length != purchases.length) {
        final prefs = await SharedPreferences.getInstance();
        final purchasesJson = filteredPurchases.map((p) => p.toJson()).toList();
        await prefs.setString(_tokenPurchasesKey, jsonEncode(purchasesJson));

        final removedCount = purchases.length - filteredPurchases.length;
        AppLogger.log('$_logPrefix Очищено старых покупок: $removedCount');
      }
    } catch (e) {
      AppLogger.log('$_logPrefix Ошибка очистки старых покупок: $e');
    }
  }
}
