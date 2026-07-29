import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'analytics/mytracker_analytics_service.dart';
import 'device_id_service.dart';

class RustorePendingPurchase {
  const RustorePendingPurchase({
    required this.purchaseId,
    required this.invoiceId,
    required this.productId,
    this.orderId,
    this.sandbox = false,
  });

  final String purchaseId;
  final String invoiceId;
  final String productId;
  final String? orderId;
  final bool sandbox;

  Map<String, dynamic> toJson() => {
        'purchaseId': purchaseId,
        'invoiceId': invoiceId,
        'productId': productId,
        if (orderId != null && orderId!.isNotEmpty) 'orderId': orderId,
        'sandbox': sandbox,
      };
}

class RustorePurchaseVerificationResult {
  const RustorePurchaseVerificationResult({
    required this.success,
    required this.alreadyProcessed,
    required this.purchaseId,
    required this.invoiceId,
    required this.productId,
    required this.creditsGranted,
    required this.purchasedCredits,
    required this.currentBalance,
    required this.ledgerStatus,
    required this.invoiceStatus,
    required this.acknowledgementState,
    this.orderId,
    this.reason = '',
    this.autoConfirmed = false,
  });

  final bool success;
  final bool alreadyProcessed;
  final String purchaseId;
  final String invoiceId;
  final String productId;
  final String? orderId;
  final int creditsGranted;
  final int purchasedCredits;
  final int currentBalance;
  final String ledgerStatus;
  final String invoiceStatus;
  final String acknowledgementState;
  final String reason;
  final bool autoConfirmed;

  bool get needsClientConfirm =>
      success &&
      ledgerStatus == 'confirm_pending' &&
      acknowledgementState != 'ACKNOWLEDGED' &&
      !autoConfirmed;

  factory RustorePurchaseVerificationResult.fromJson(
      Map<String, dynamic> json) {
    return RustorePurchaseVerificationResult(
      success: json['success'] as bool? ?? false,
      alreadyProcessed: json['alreadyProcessed'] as bool? ?? false,
      purchaseId: json['purchaseId'] as String? ?? '',
      invoiceId: json['invoiceId'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      orderId: json['orderId'] as String?,
      creditsGranted: (json['creditsGranted'] as num?)?.toInt() ?? 0,
      purchasedCredits: (json['purchasedCredits'] as num?)?.toInt() ?? 0,
      currentBalance: (json['currentBalance'] as num?)?.toInt() ?? 0,
      ledgerStatus: json['ledgerStatus'] as String? ?? '',
      invoiceStatus: json['invoiceStatus'] as String? ?? '',
      acknowledgementState: json['acknowledgementState'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      autoConfirmed: json['autoConfirmed'] as bool? ?? false,
    );
  }
}

class RustoreReconcileResult {
  const RustoreReconcileResult({
    required this.success,
    required this.items,
  });

  final bool success;
  final List<RustorePurchaseVerificationResult> items;
}

class RustorePurchaseVerificationService {
  RustorePurchaseVerificationService._();

  static final RustorePurchaseVerificationService instance =
      RustorePurchaseVerificationService._();

  static const String _functionId = 'verify-rustore-purchase';
  static const String _logPrefix = '🛒 RUSTORE_VERIFY';

  Client _buildClient() {
    final endpoint = dotenv.env['APPWRITE_ENDPOINT']?.trim() ?? '';
    final projectId = dotenv.env['APPWRITE_PROJECT_ID']?.trim() ?? '';
    return Client().setEndpoint(endpoint).setProject(projectId);
  }

  Future<RustorePurchaseVerificationResult> verifyPurchase({
    required String purchaseId,
    required String invoiceId,
    required String productId,
    String? orderId,
    bool sandbox = false,
    bool autoConfirm = false,
    String sdkSource = 'pay',
  }) async {
    final fingerprint = await DeviceIdService.instance.getDeviceId();
    final instanceId = await MyTrackerAnalyticsService.instance.getInstanceId();
    final response = await _invoke({
      'action': 'verify_purchase',
      'fingerprint': fingerprint,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'purchaseId': purchaseId,
      'invoiceId': invoiceId,
      'productId': productId,
      if (orderId != null && orderId.isNotEmpty) 'orderId': orderId,
      if (instanceId != null && instanceId.isNotEmpty)
        'mytrackerInstanceId': instanceId,
      'sandbox': sandbox,
      'autoConfirm': autoConfirm,
      'sdkSource': sdkSource,
    });
    debugPrint(
      '$_logPrefix verify purchaseId=$purchaseId invoiceId=$invoiceId '
      'success=${response['success']} status=${response['ledgerStatus']}',
    );
    return RustorePurchaseVerificationResult.fromJson(response);
  }

  /// Dual-SDK: валидация подписки по purchaseId через Public API v4
  /// (без invoiceId — используется, когда покупка сделана через Pay SDK).
  Future<RustorePurchaseVerificationResult> verifyPaySubscription({
    required String purchaseId,
    required String productId,
    String? orderId,
    String? expirationDate,
    bool sandbox = false,
  }) async {
    final fingerprint = await DeviceIdService.instance.getDeviceId();
    final response = await _invoke({
      'action': 'verify_purchase',
      'fingerprint': fingerprint,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'purchaseId': purchaseId,
      'productId': productId,
      if (orderId != null && orderId.isNotEmpty) 'orderId': orderId,
      if (expirationDate != null && expirationDate.isNotEmpty)
        'expirationDate': expirationDate,
      'sandbox': sandbox,
      'sdkSource': 'pay_subscription',
    });
    return RustorePurchaseVerificationResult.fromJson(response);
  }

  /// Dual-SDK: привязать BillingClient-подписку к fingerprint на сервере.
  Future<bool> linkLegacySubscription({
    required String purchaseId,
    required String productId,
    String? invoiceId,
    String purchaseState = 'CONFIRMED',
    String? expirationDate,
  }) async {
    final fingerprint = await DeviceIdService.instance.getDeviceId();
    final response = await _invoke({
      'action': 'link_legacy_subscription',
      'fingerprint': fingerprint,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      'purchaseId': purchaseId,
      'productId': productId,
      if (invoiceId != null && invoiceId.isNotEmpty) 'invoiceId': invoiceId,
      'purchaseState': purchaseState,
      if (expirationDate != null && expirationDate.isNotEmpty)
        'expirationDate': expirationDate,
    });
    return response['success'] as bool? ?? false;
  }

  Future<RustoreReconcileResult> reconcilePurchases(
    List<RustorePendingPurchase> purchases,
  ) async {
    if (purchases.isEmpty) {
      return const RustoreReconcileResult(success: true, items: []);
    }
    final fingerprint = await DeviceIdService.instance.getDeviceId();
    final instanceId = await MyTrackerAnalyticsService.instance.getInstanceId();
    final response = await _invoke({
      'action': 'reconcile_purchases',
      'fingerprint': fingerprint,
      'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      if (instanceId != null && instanceId.isNotEmpty)
        'mytrackerInstanceId': instanceId,
      'purchases': purchases.map((purchase) => purchase.toJson()).toList(),
    });
    final items = ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => RustorePurchaseVerificationResult.fromJson(
              item.cast<String, dynamic>(),
            ))
        .toList();
    return RustoreReconcileResult(
      success: response['success'] as bool? ?? false,
      items: items,
    );
  }

  Future<void> markConfirmed(String purchaseId) async {
    await _invoke({
      'action': 'mark_confirmed',
      'purchaseId': purchaseId,
    });
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final functions = Functions(_buildClient());
    final execution = await functions.createExecution(
      functionId: _functionId,
      body: jsonEncode(body),
      xasync: false,
    );
    if (execution.responseStatusCode >= 400) {
      throw Exception(
        '$_logPrefix function returned ${execution.responseStatusCode}: '
        '${execution.responseBody}',
      );
    }
    return jsonDecode(execution.responseBody) as Map<String, dynamic>;
  }
}
