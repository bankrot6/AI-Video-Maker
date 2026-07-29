import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/step_model.dart';
import '../../models/user_model.dart';
import '../../repositories/step_repository.dart';
import '../../services/step_tracker_service.dart';
import '../../services/localization/app_localization_service.dart';
import '../../services/providers.dart' as services;

final stepRepositoryProvider = Provider<StepRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return StepRepository(prefs);
});

final stepTrackerServiceProvider = Provider<StepTrackerService>((ref) {
  final repository = ref.watch(stepRepositoryProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  final service = StepTrackerService(repository, prefs);
  
  ref.onDispose(() {
    debugPrint('👟 Disposing StepTrackerService');
    service.dispose();
  });
  
  return service;
});

final stepTrackerInitProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(stepTrackerServiceProvider);
  await service.initialize();
  return service.isInitialized;
});

final stepGoalProvider = StateProvider<int>((ref) {
  final repository = ref.watch(stepRepositoryProvider);
  return repository.getStepGoal();
});

final liveStepEntryProvider = StreamProvider<StepEntry>((ref) {
  final service = ref.watch(stepTrackerServiceProvider);
  
  ref.watch(stepTrackerInitProvider);
  
  return service.stepEntryStream.map((entry) {
    debugPrint('👟 StreamProvider received: ${entry.steps} steps');
    return entry;
  });
});

final liveStepsCountProvider = StreamProvider<int>((ref) {
  final service = ref.watch(stepTrackerServiceProvider);
  ref.watch(stepTrackerInitProvider);
  return service.stepsStream;
});

final pedestrianStatusProvider = StreamProvider<String>((ref) {
  final service = ref.watch(stepTrackerServiceProvider);
  ref.watch(stepTrackerInitProvider);
  return service.statusStream;
});

final weeklyStepStatsProvider = FutureProvider<StepStats>((ref) async {
  final service = ref.watch(stepTrackerServiceProvider);
  await ref.watch(stepTrackerInitProvider.future);
  return service.getWeeklyStats();
});

final monthlyStepStatsProvider = FutureProvider<StepStats>((ref) async {
  final service = ref.watch(stepTrackerServiceProvider);
  await ref.watch(stepTrackerInitProvider.future);
  return service.getMonthlyStats();
});

class StepNotifier extends StateNotifier<StepEntry> {
  final StepTrackerService _service;
  final Ref _ref;
  StreamSubscription<StepEntry>? _subscription;
  bool _initialized = false;

  StepNotifier(this._service, this._ref) : super(StepEntry.empty(DateTime.now())) {
    _init();
  }

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    
    debugPrint('👟 StepNotifier: initializing...');
    
    await _service.initialize();
    
    state = _service.getTodayStepsSync();
    debugPrint('👟 StepNotifier: initial state = ${state.steps} steps');
    
    _subscription = _service.stepEntryStream.listen((entry) {
      debugPrint('👟 StepNotifier: stream update = ${entry.steps} steps');
      state = entry;
    });
  }

  Future<void> setGoal(int goal) async {
    await _service.setStepGoal(goal);
    state = state.copyWith(goal: goal, updatedAt: DateTime.now());
    _ref.read(stepGoalProvider.notifier).state = goal;
  }

  void refresh() {
    _service.forceRefresh();
    state = _service.getTodayStepsSync();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final stepNotifierProvider = StateNotifierProvider<StepNotifier, StepEntry>((ref) {
  final service = ref.watch(stepTrackerServiceProvider);
  return StepNotifier(service, ref);
});

final selectedPeriodProvider = StateProvider<StepPeriod>((ref) => StepPeriod.week);

final stepsForPeriodProvider = FutureProvider.family<List<StepEntry>, StepPeriod>((ref, period) async {
  final repository = ref.watch(stepRepositoryProvider);
  final now = DateTime.now();
  
  ref.watch(stepTrackerInitProvider);
  
  switch (period) {
    case StepPeriod.day:
      final entry = await repository.getOrCreateStepsForDate(now);
      return [entry];
    case StepPeriod.week:
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      return repository.getStepsForPeriod(startOfWeek, now);
    case StepPeriod.month:
      final startOfMonth = DateTime(now.year, now.month, 1);
      return repository.getStepsForPeriod(startOfMonth, now);
  }
});

final hasStepPermissionProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(stepTrackerServiceProvider);
  await service.initialize();
  return service.hasPermission;
});

/// Провайдер для расчёта персонализированной цели шагов через AI
final calculatePersonalizedStepGoalProvider =
    FutureProvider.family<int, UserModel>((ref, user) async {
  final calculatorService = ref.watch(services.stepGoalCalculatorServiceProvider);
  final repository = ref.watch(stepRepositoryProvider);
  
  try {
    final goal = await calculatorService.calculatePersonalizedStepGoal(user: user);
    
    await repository.setStepGoal(goal);
    
    ref.read(stepGoalProvider.notifier).state = goal;
    
    debugPrint('👟 STEP_PROVIDER: Персонализированная цель установлена: $goal шагов');
    return goal;
  } catch (e) {
    debugPrint('❌ STEP_PROVIDER: Ошибка расчёта цели: $e');
    return repository.getStepGoal();
  }
});

/// Функция для обновления цели шагов на основе параметров пользователя
Future<int> updateStepGoalForUser(WidgetRef ref, UserModel user) async {
  final calculatorService = ref.read(services.stepGoalCalculatorServiceProvider);
  final repository = ref.read(stepRepositoryProvider);
  
  try {
    final goal = await calculatorService.calculatePersonalizedStepGoal(user: user);
    
    await repository.setStepGoal(goal);
    
    ref.read(stepGoalProvider.notifier).state = goal;
    
    ref.invalidate(stepNotifierProvider);
    
    debugPrint('👟 STEP_GOAL_UPDATE: Цель обновлена до $goal шагов');
    return goal;
  } catch (e) {
    debugPrint('❌ STEP_GOAL_UPDATE: Ошибка: $e');
    return repository.getStepGoal();
  }
}
