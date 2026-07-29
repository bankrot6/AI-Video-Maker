import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Состояние баннера с лимитом
class BannerLimitState {
  final bool showingLimit;
  final int remainingCount;

  const BannerLimitState({
    this.showingLimit = false,
    this.remainingCount = 0,
  });

  BannerLimitState copyWith({
    bool? showingLimit,
    int? remainingCount,
  }) {
    return BannerLimitState(
      showingLimit: showingLimit ?? this.showingLimit,
      remainingCount: remainingCount ?? this.remainingCount,
    );
  }
}

/// Контроллер для управления показом лимита на баннере
class BannerLimitController extends StateNotifier<BannerLimitState> {
  BannerLimitController() : super(const BannerLimitState());

  void showLimit(int remainingCount) {
    debugPrint('🎯 BANNER_LIMIT: showLimit вызван с remainingCount=$remainingCount');
    state = state.copyWith(showingLimit: true, remainingCount: remainingCount);
  }

  void hideLimit() {
    state = state.copyWith(showingLimit: false);
  }
}

/// Провайдер для управления состоянием баннера
final bannerLimitProvider = StateNotifierProvider<BannerLimitController, BannerLimitState>((ref) {
  return BannerLimitController();
});

/// Счётчик, инкрементируемый каждый раз, когда HomeScreen возвращается в фокус.
/// PremiumTrialBanner слушает этот провайдер и запускает анимацию.
final homeScreenResumeCountProvider = StateProvider<int>((ref) => 0);

