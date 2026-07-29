import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'subscription_service.dart';
import '../models/subscription_model.dart';

class ExerciseLimitService {
  static const String _exerciseCountKey = 'exercise_interactions_count';
  static const String _lastResetDateKey = 'exercise_interactions_last_reset';
  static const String _firstLaunchDateKey = 'app_first_launch_date';
  
  // Лимиты для бесплатных пользователей
  static const int _week1Limit = 15; // Первая неделя
  static const int _week2Limit = 10; // Вторая неделя
  static const int _week3PlusLimit = 5; // Третья неделя и далее
  
  // Лимиты для платных пользователей (защита от спама)
  static const int _trialUserLimit = 30; // Триал
  static const int _paidUserLimit = 50; // Платная подписка

  final SubscriptionService _subscriptionService;

  ExerciseLimitService(this._subscriptionService);

  Future<bool> canPerformExerciseAction() async {
    await _initializeFirstLaunchDate();
    await _resetCounterIfNeeded();
    
    final subscription = await _subscriptionService.getCurrentSubscription();
    final dailyLimit = await _getDailyLimit(subscription);
    
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_exerciseCountKey) ?? 0;
    
    final canPerform = count < dailyLimit;
    
    if (subscription?.isPaidUser == true || subscription?.isTrialUser == true) {
      debugPrint('💪 EXERCISE_LIMIT: Платный/триал пользователь, использовано $count из $dailyLimit (защита от спама)');
    } else {
      debugPrint('💪 EXERCISE_LIMIT: Бесплатный пользователь, использовано $count из $dailyLimit');
    }
    
    return canPerform;
  }

  Future<void> incrementExerciseCount() async {
    await _resetCounterIfNeeded();
    
    final prefs = await SharedPreferences.getInstance();
    final currentCount = prefs.getInt(_exerciseCountKey) ?? 0;
    await prefs.setInt(_exerciseCountKey, currentCount + 1);
    
    final subscription = await _subscriptionService.getCurrentSubscription();
    if (subscription?.isPaidUser == true || subscription?.isTrialUser == true) {
      debugPrint('💪 EXERCISE_LIMIT: Счетчик увеличен до ${currentCount + 1} (платный/триал пользователь)');
    } else {
      debugPrint('💪 EXERCISE_LIMIT: Счетчик увеличен до ${currentCount + 1} (бесплатный пользователь)');
    }
  }

  Future<int> getRemainingCount() async {
    await _initializeFirstLaunchDate();
    await _resetCounterIfNeeded();
    
    final subscription = await _subscriptionService.getCurrentSubscription();
    final dailyLimit = await _getDailyLimit(subscription);
    
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_exerciseCountKey) ?? 0;
    final remaining = dailyLimit - count;
    
    return remaining > 0 ? remaining : 0;
  }
  
  /// Определяет, нужно ли показывать уведомление о лимите
  /// Не показываем для платных и триал пользователей
  Future<bool> shouldShowLimitNotification() async {
    final subscription = await _subscriptionService.getCurrentSubscription();
    
    // Не показываем уведомление для платных и триал пользователей
    if (subscription?.isPaidUser == true || subscription?.isTrialUser == true) {
      return false;
    }
    
    return true;
  }
  
  /// Получает дневной лимит в зависимости от типа пользователя и времени использования
  Future<int> _getDailyLimit(SubscriptionModel? subscription) async {
    // Платные пользователи - высокий лимит для защиты от спама
    if (subscription?.isPaidUser == true) {
      return _paidUserLimit;
    }
    
    // Триал пользователи - средний лимит
    if (subscription?.isTrialUser == true) {
      return _trialUserLimit;
    }
    
    // Бесплатные пользователи - прогрессивный лимит
    final weekNumber = await _getWeekNumberSinceFirstLaunch();
    
    if (weekNumber == 1) {
      debugPrint('💪 EXERCISE_LIMIT: Неделя $weekNumber - лимит $_week1Limit запросов');
      return _week1Limit;
    } else if (weekNumber == 2) {
      debugPrint('💪 EXERCISE_LIMIT: Неделя $weekNumber - лимит $_week2Limit запросов');
      return _week2Limit;
    } else {
      debugPrint('💪 EXERCISE_LIMIT: Неделя $weekNumber - лимит $_week3PlusLimit запросов');
      return _week3PlusLimit;
    }
  }
  
  /// Инициализирует дату первого запуска приложения
  Future<void> _initializeFirstLaunchDate() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (!prefs.containsKey(_firstLaunchDateKey)) {
      final now = DateTime.now();
      await prefs.setString(_firstLaunchDateKey, now.toIso8601String());
      debugPrint('💪 EXERCISE_LIMIT: Первый запуск приложения: $now');
    }
  }
  
  /// Получает номер недели с момента первого запуска приложения
  Future<int> _getWeekNumberSinceFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final firstLaunchStr = prefs.getString(_firstLaunchDateKey);
    
    if (firstLaunchStr == null) {
      return 1; // По умолчанию первая неделя
    }
    
    final firstLaunch = DateTime.parse(firstLaunchStr);
    final now = DateTime.now();
    final daysSinceLaunch = now.difference(firstLaunch).inDays;
    final weekNumber = (daysSinceLaunch ~/ 7) + 1;
    
    return weekNumber;
  }

  Future<void> _resetCounterIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastResetStr = prefs.getString(_lastResetDateKey);
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (lastResetStr == null) {
      await prefs.setString(_lastResetDateKey, today.toIso8601String());
      await prefs.setInt(_exerciseCountKey, 0);
      debugPrint('💪 EXERCISE_LIMIT: Счетчик инициализирован');
      return;
    }
    
    final lastReset = DateTime.parse(lastResetStr);
    final lastResetDay = DateTime(lastReset.year, lastReset.month, lastReset.day);
    
    if (today.isAfter(lastResetDay)) {
      await prefs.setInt(_exerciseCountKey, 0);
      await prefs.setString(_lastResetDateKey, today.toIso8601String());
      debugPrint('💪 EXERCISE_LIMIT: Счетчик сброшен на новый день');
    }
  }

  Future<void> resetForDebug() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_exerciseCountKey);
    await prefs.remove(_lastResetDateKey);
    debugPrint('💪 EXERCISE_LIMIT: Счетчик сброшен (debug)');
  }
}

