import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/credit_config.dart';
import '../models/credit_usage_model.dart';
import '../services/credit_service.dart';

final creditServiceProvider = Provider<CreditService>((ref) {
  return CreditService();
});

class CreditBalanceOverlayNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void show() {
    state = state + 1;
  }

  void hide() {
    if (state <= 0) {
      state = 0;
      return;
    }
    state = state - 1;
  }

  void reset() {
    state = 0;
  }
}

class CreditUsageNotifier extends AsyncNotifier<CreditUsageModel> {
  late CreditService _service;

  @override
  Future<CreditUsageModel> build() async {
    _service = ref.read(creditServiceProvider);
    return await _service.getCreditUsage();
  }

  Future<bool> useCredits(int amount) async {
    final success = await _service.useCredits(amount);
    if (success) ref.invalidateSelf();
    return success;
  }

  Future<bool> useGenerationCredits(AiModelTier tier) async {
    final success = await _service.useGenerationCredits(tier);
    if (success) ref.invalidateSelf();
    return success;
  }

  Future<bool> canGenerate(AiModelTier tier) async {
    return _service.canGenerate(tier);
  }

  Future<CreditUsageModel> refreshFromServer() async {
    final usage = await _service.refreshFromServer();
    ref.invalidateSelf();
    return usage;
  }

  Future<CreditReservationResult> reserveGenerationCredits(AiModelTier tier) async {
    final result = await _service.reserveGenerationCredits(tier);
    ref.invalidateSelf();
    return result;
  }

  Future<CreditReservationResult> reserveCredits(
    int amount, {
    bool countAsFreeGeneration = false,
  }) async {
    final result = await _service.reserveCredits(
      amount,
      countAsFreeGeneration: countAsFreeGeneration,
    );
    ref.invalidateSelf();
    return result;
  }

  Future<void> rollbackReservation(CreditReservation reservation) async {
    await _service.rollbackReservation(reservation);
    ref.invalidateSelf();
  }

  Future<void> addPurchasedCredits(int amount) async {
    await _service.addPurchasedCredits(amount);
    ref.invalidateSelf();
  }

  Future<void> grantPurchasedCredits(int amount) async {
    await _service.grantPurchasedCredits(amount);
    ref.invalidateSelf();
  }

  // backward-compat for messenger
  Future<bool> useTextCredits(String input, String output) async {
    final success = await _service.useTextCredits(input, output);
    if (success) ref.invalidateSelf();
    return success;
  }

  Future<bool> useImageCredits() async {
    final success = await _service.useImageCredits();
    if (success) ref.invalidateSelf();
    return success;
  }

  Future<bool> useVoiceCredits(String text) async {
    final success = await _service.useVoiceCredits(text);
    if (success) ref.invalidateSelf();
    return success;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

final creditUsageNotifierProvider =
    AsyncNotifierProvider<CreditUsageNotifier, CreditUsageModel>(() {
  return CreditUsageNotifier();
});

final creditBalanceOverlayProvider =
    NotifierProvider<CreditBalanceOverlayNotifier, int>(
  CreditBalanceOverlayNotifier.new,
);

final creditBalanceOverlayVisibleProvider = Provider<bool>((ref) {
  return ref.watch(creditBalanceOverlayProvider) > 0;
});

final creditUsageProvider = FutureProvider<CreditUsageModel>((ref) async {
  final service = ref.read(creditServiceProvider);
  return await service.getCreditUsage();
});
