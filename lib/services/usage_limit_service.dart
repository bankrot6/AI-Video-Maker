import 'package:flutter/material.dart';
import '../data/usage_limit_repository.dart';
import 'subscription_service.dart';
import 'dart:developer' as developer;
import 'localization/app_localization_service.dart';
import 'dart:async';

/// Интерфейс сервиса ограничений использования
/// Реализует паттерн Strategy для возможности изменения реализации
abstract class IUsageLimitService {
  /// Проверяет, может ли пользователь использовать функцию
  Future<bool> canUseFeature();

  /// Регистрирует использование функции
  Future<bool> registerUsage();

  /// Показывает предупреждение о лимите использований
  Future<void> showUsageLimitWarning(BuildContext context);

  /// Получает количество оставшихся использований
  Future<int> getRemainingUsages();
}

/// Реализация сервиса ограничений использования
class UsageLimitService implements IUsageLimitService {
  final UsageLimitRepository _repository;
  final SubscriptionService _subscriptionService;

  /// Конструктор, принимающий репозиторий ограничений и сервис подписок
  UsageLimitService(this._repository, this._subscriptionService) {
    // При инициализации проверяем, нужно ли сбросить лимиты
    checkAndResetLimitsIfNeeded().then((wasReset) {
      if (wasReset) {
        developer.log('Лимиты использования сброшены при инициализации сервиса',
            name: 'UsageLimitService');
      }
    });
  }

  @override
  Future<bool> canUseFeature() async {
    try {
      // Проверяем, нужно ли сбросить лимиты на новый день
      await checkAndResetLimitsIfNeeded();

      // Проверяем, имеет ли пользователь подписку
      final hasPaidSubscription =
          await _subscriptionService.hasPaidSubscription();
      developer.log('Проверка наличия подписки: $hasPaidSubscription',
          name: 'UsageLimitService');

      // Если у пользователя есть подписка, проверяем лимит для платных пользователей
      if (hasPaidSubscription) {
        final remainingUsages = await _repository.getRemainingTotalUsages();
        return remainingUsages > 0;
      }

      // Если нет подписки, проверяем лимит для бесплатных пользователей
      final remainingUsages = await _repository.getRemainingFreeUsages();
      developer.log(
          'Оставшиеся использования для бесплатных пользователей: $remainingUsages',
          name: 'UsageLimitService');
      return remainingUsages > 0;
    } catch (e) {
      developer.log('Ошибка при проверке возможности использования: $e',
          name: 'UsageLimitService');
      return false;
    }
  }

  @override
  Future<bool> registerUsage() async {
    try {
      final hasPaidSubscription =
          await _subscriptionService.hasPaidSubscription();

      // В зависимости от типа пользователя увеличиваем соответствующий счетчик
      if (hasPaidSubscription) {
        final updatedUsage = await _repository.incrementTotalUsage();
        return updatedUsage.totalUsagesCount <= updatedUsage.maxTotalUsages;
      } else {
        final updatedUsage = await _repository.incrementFreeUsage();
        return updatedUsage.freeUsagesCount <= updatedUsage.maxFreeUsages;
      }
    } catch (e) {
      developer.log('Ошибка при регистрации использования: $e',
          name: 'UsageLimitService');
      return false;
    }
  }

  @override
  Future<void> showUsageLimitWarning(BuildContext context) async {
    try {
      final hasPaidSubscription =
          await _subscriptionService.hasPaidSubscription();
      int remainingUsages;

      if (hasPaidSubscription) {
        remainingUsages = await _repository.getRemainingTotalUsages();
      } else {
        remainingUsages = await _repository.getRemainingFreeUsages();
      }

      if (remainingUsages <= 1 && remainingUsages > 0) {
        // Проверяем, что контекст все еще смонтирован
        if (!context.mounted) return;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr('few_usages_left')),
            content: Text(
              context.trParams('usages_left_message', [
                '$remainingUsages',
                _getUsagesString(context, remainingUsages),
                !hasPaidSubscription ? context.tr('subscribe_for_more') : '',
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('understand')),
              ),
              if (!hasPaidSubscription)
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _subscriptionService.showPaywall(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6A44E0),
                  ),
                  child: Text(context.tr('subscribe')),
                ),
            ],
          ),
        );
      }
    } catch (e) {
      developer.log('Ошибка при показе предупреждения: $e',
          name: 'UsageLimitService');
    }
  }

  @override
  Future<int> getRemainingUsages() async {
    try {
      final hasPaidSubscription =
          await _subscriptionService.hasPaidSubscription();

      if (hasPaidSubscription) {
        return await _repository.getRemainingTotalUsages();
      } else {
        return await _repository.getRemainingFreeUsages();
      }
    } catch (e) {
      developer.log('Ошибка при получении оставшихся использований: $e',
          name: 'UsageLimitService');
      return 0;
    }
  }

  /// Получение правильного склонения слова "использование" с учетом локализации
  String _getUsagesString(BuildContext context, int count) {
    // Используем контекст для определения текущего языка
    if (context.tr('russian') == 'Русский') {
      // Для русского языка используем правила склонения
      if (count % 10 == 1 && count % 100 != 11) {
        return context.tr('usage_singular');
      } else if (count % 10 >= 2 &&
          count % 10 <= 4 &&
          (count % 100 < 10 || count % 100 >= 20)) {
        return context.tr('usage_few');
      } else {
        return context.tr('usage_many');
      }
    } else {
      // Для английского и других языков используем простое правило
      return count == 1
          ? context.tr('usage_singular')
          : context.tr('usage_many');
    }
  }

  /// Проверяет, нужно ли сбросить ограничения использования
  Future<bool> checkAndResetLimitsIfNeeded() async {
    try {
      // Получаем последнюю дату сброса из репозитория
      final lastResetDateStr = await _repository.getLastResetDateString();
      final today = DateTime.now();
      final todayString = "${today.year}-${today.month}-${today.day}";

      developer.log(
          'Проверка необходимости сброса лимитов. Последний сброс: $lastResetDateStr, сегодня: $todayString',
          name: 'UsageLimitService');

      // Если дата последнего сброса не сегодня, сбрасываем ограничения
      if (lastResetDateStr == null || lastResetDateStr != todayString) {
        final resetUsage = await _repository.resetUsageLimits();
        await _repository.saveLastResetDateString(todayString);
        developer.log(
            'Лимиты использования сброшены на новый день. '
            'Новые лимиты: для платных=${resetUsage.maxTotalUsages}, '
            'для бесплатных=${resetUsage.maxFreeUsages}',
            name: 'UsageLimitService');
        return true;
      } else {
        developer.log('Сброс лимитов не требуется (уже был выполнен сегодня)',
            name: 'UsageLimitService');
      }

      return false;
    } catch (e) {
      developer.log('Ошибка при проверке необходимости сброса лимитов: $e',
          name: 'UsageLimitService');
      return false;
    }
  }
}
