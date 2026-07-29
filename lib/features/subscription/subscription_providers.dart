import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/subscription_repository.dart';
import '../../models/subscription_model.dart';
import '../../services/subscription_service.dart';
import '../../services/trial_server_service.dart';

/// Провайдер репозитория подписок
final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  throw UnimplementedError('Должен быть переопределен в ProviderScope');
});

/// Провайдер сервиса подписок
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  final repository = ref.watch(subscriptionRepositoryProvider);
  return SubscriptionService(repository);
});

/// Провайдер состояния подписки пользователя
final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, AsyncValue<SubscriptionModel>>(
        (ref) {
  final repository = ref.watch(subscriptionRepositoryProvider);
  return SubscriptionNotifier(repository);
});

/// StateNotifier для управления состоянием подписки
class SubscriptionNotifier
    extends StateNotifier<AsyncValue<SubscriptionModel>> {
  final SubscriptionRepository _repository;

  SubscriptionNotifier(this._repository) : super(const AsyncValue.loading()) {
    _loadSubscription();
  }

  /// Загрузка текущей подписки
  Future<void> _loadSubscription() async {
    state = const AsyncValue.loading();
    try {
      final subscription = await _repository.getCurrentSubscription();
      state = AsyncValue.data(subscription);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Активация пробной подписки с серверной проверкой права на триал.
  ///
  /// Бросает [TrialAlreadyUsedException] если сервер подтвердил, что данное
  /// устройство уже использовало триал (reinstall-abuse). При недоступности
  /// сервера работает в режиме fail-open (разрешает триал).
  Future<void> activateTrial() async {
    final serverResult = await TrialServerService().checkEligibility();

    if (!serverResult.eligible) {
      throw TrialAlreadyUsedException(serverResult.reason);
    }

    state = const AsyncValue.loading();
    try {
      final subscription = await _repository.activateTrial();
      // Регистрируем факт использования триала на сервере
      await TrialServerService().claimTrial();
      state = AsyncValue.data(subscription);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Активация недельной подписки
  Future<void> activateWeekly() async {
    state = const AsyncValue.loading();
    try {
      final subscription = await _repository.activateWeekly();
      state = AsyncValue.data(subscription);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Активация месячной подписки
  Future<void> activateMonthly() async {
    state = const AsyncValue.loading();
    try {
      final subscription = await _repository.activateMonthly();
      state = AsyncValue.data(subscription);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Активация годовой подписки
  Future<void> activateYearly() async {
    state = const AsyncValue.loading();
    try {
      final subscription = await _repository.activateYearly();
      state = AsyncValue.data(subscription);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Активация бессрочной подписки
  Future<void> activateLifetime() async {
    state = const AsyncValue.loading();
    try {
      final subscription = await _repository.activateLifetime();
      state = AsyncValue.data(subscription);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Деактивация подписки (перевод на бесплатную)
  Future<void> activateFree() async {
    state = const AsyncValue.loading();
    try {
      final free = SubscriptionModel.free();
      await _repository.saveSubscription(free);
      state = AsyncValue.data(free);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Использование запроса
  Future<bool> useRequest() async {
    try {
      final currentState = state;
      if (currentState is AsyncData<SubscriptionModel> &&
          currentState.value.availableRequests > 0) {
        final updatedSubscription = await _repository.useRequest();
        state = AsyncValue.data(updatedSubscription);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Проверка наличия доступных запросов
  Future<bool> hasAvailableRequests() async {
    try {
      return await _repository.hasAvailableRequests();
    } catch (e) {
      return false;
    }
  }

  /// Обновление состояния подписки
  Future<void> refreshSubscription() async {
    await _loadSubscription();
  }
}

/// Исключение: данное устройство уже использовало триальный период.
class TrialAlreadyUsedException implements Exception {
  final String reason;
  const TrialAlreadyUsedException(this.reason);

  @override
  String toString() => 'TrialAlreadyUsedException: $reason';
}
