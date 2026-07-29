enum RuStoreProductKind {
  subscription,
  consumable,
  nonConsumable,
  unknown,
}

enum RuStorePurchaseState {
  active,
  paused,
  confirmed,
  paid,
  cancelled,
  other,
}

class RuStorePurchaseInfo {
  final String purchaseId;
  final String productId;
  final String? invoiceId;
  final String? orderId;
  final RuStoreProductKind kind;
  final RuStorePurchaseState state;
  final String? expirationDate;
  final bool fromLegacySdk;

  const RuStorePurchaseInfo({
    required this.purchaseId,
    required this.productId,
    this.invoiceId,
    this.orderId,
    required this.kind,
    required this.state,
    this.expirationDate,
    this.fromLegacySdk = false,
  });

  bool get isActiveSubscription =>
      kind == RuStoreProductKind.subscription &&
      state == RuStorePurchaseState.active;

  bool get isPausedSubscription =>
      kind == RuStoreProductKind.subscription &&
      state == RuStorePurchaseState.paused;

  bool get isRestorableToken =>
      kind == RuStoreProductKind.consumable &&
      (state == RuStorePurchaseState.paid ||
          state == RuStorePurchaseState.confirmed);

  /// Совместимость со старым API flutter_rustore_billing (Purchase.productType).
  String get productType {
    switch (kind) {
      case RuStoreProductKind.subscription:
        return 'SUBSCRIPTION';
      case RuStoreProductKind.consumable:
        return 'CONSUMABLE';
      case RuStoreProductKind.nonConsumable:
        return 'NON_CONSUMABLE';
      case RuStoreProductKind.unknown:
        return 'UNKNOWN';
    }
  }

  /// Совместимость со старым API flutter_rustore_billing (Purchase.purchaseState).
  String get purchaseState {
    switch (state) {
      case RuStorePurchaseState.active:
        return 'CONFIRMED';
      case RuStorePurchaseState.paused:
        return 'PAUSED';
      case RuStorePurchaseState.confirmed:
        return 'CONFIRMED';
      case RuStorePurchaseState.paid:
        return 'PAID';
      case RuStorePurchaseState.cancelled:
        return 'CANCELLED';
      case RuStorePurchaseState.other:
        return 'OTHER';
    }
  }

  @override
  String toString() {
    return 'RuStorePurchaseInfo('
        'productId: $productId, '
        'purchaseId: $purchaseId, '
        'kind: $kind, '
        'state: $state, '
        'legacy: $fromLegacySdk'
        ')';
  }
}
