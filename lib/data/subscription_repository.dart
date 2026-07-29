import 'package:shared_preferences/shared_preferences.dart';
import '../models/subscription_model.dart';
import 'dart:convert';

/// Репозиторий для работы с подписками пользователя
/// Реализует паттерн Repository, для абстрагирования доступа к данным
class SubscriptionRepository {
  static const String _subscriptionKey = 'user_subscription';
  static const String _lastResetDateKey = 'last_quota_reset_date';
  static const String _freeQuotaStartDateKey = 'free_quota_start_date';
  final SharedPreferences _prefs;

  /// Конструктор, принимающий экземпляр SharedPreferences
  SubscriptionRepository(this._prefs);

  /// Получение текущей подписки пользователя
  /// Если подписка не найдена, возвращает бесплатную подписку
  Future<SubscriptionModel> getCurrentSubscription() async {
    try {
      final String? subscriptionJson = _prefs.getString(_subscriptionKey);
      final String? lastResetDateStr = _prefs.getString(_lastResetDateKey);

      print(
          "📂 REPOSITORY: getCurrentSubscription: Чтение подписки из хранилища");

      // Проверяем, нужно ли сбросить ежедневные лимиты
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      DateTime? lastResetDate;

      if (lastResetDateStr != null) {
        lastResetDate = DateTime.parse(lastResetDateStr);
        print("📅 REPOSITORY: Последний сброс лимитов: $lastResetDateStr");
      } else {
        print("⚠️ REPOSITORY: Дата последнего сброса не найдена");
      }

      // Если это первый запуск или наступил новый день
      final bool shouldResetDailyQuota = lastResetDate == null ||
          today.isAfter(DateTime(
              lastResetDate.year, lastResetDate.month, lastResetDate.day));

      print("🔄 REPOSITORY: Требуется сброс квоты: $shouldResetDailyQuota");

      // Инициализируем дату начала динамической бесплатной квоты 3→2→1
      final DateTime freeQuotaStartDate = await _getOrInitFreeQuotaStartDate();
      final int todayFreeMax = _computeFreeDailyMax(freeQuotaStartDate);

      if (subscriptionJson != null && subscriptionJson.isNotEmpty) {
        final Map<String, dynamic> json = jsonDecode(subscriptionJson);
        final SubscriptionModel subscription = _subscriptionFromJson(json);

        print(
            "📊 REPOSITORY: Загружена подписка: тип=${subscription.type}, доступно=${subscription.availableRequests}/${subscription.maxRequests}, активна=${subscription.isActive}");

        // Если нужно сбросить квоту для бесплатного пользователя
        if (shouldResetDailyQuota &&
            subscription.type == SubscriptionType.free) {
          print(
              "🔄 REPOSITORY: Сброс ежедневной квоты для бесплатного пользователя");

          // Сбрасываем до динамического лимита на сегодня (3 → 2 → 1)
          final SubscriptionModel resetSubscription = subscription.copyWith(
            availableRequests: todayFreeMax,
            maxRequests: todayFreeMax,
          );
          await saveSubscription(resetSubscription);

          // Сохраняем дату сброса
          await _prefs.setString(_lastResetDateKey, today.toIso8601String());

          print(
              "✅ REPOSITORY: Квота сброшена до ${resetSubscription.availableRequests}/${resetSubscription.maxRequests} (динамика free)");

          return resetSubscription;
        }

        // Сбрасываем квоту для платных пользователей
        if (shouldResetDailyQuota &&
            subscription.type != SubscriptionType.free &&
            subscription.availableRequests != subscription.maxRequests) {
          print(
              "🔄 REPOSITORY: Сброс ежедневной квоты для платного пользователя типа ${subscription.type}");

          // Создаем обновленную модель с полными лимитами на основе текущей
          SubscriptionModel resetSubscription;

          switch (subscription.type) {
            case SubscriptionType.weekly:
              resetSubscription = SubscriptionModel.weekly();
              print(
                  "🔄 REPOSITORY: Сброс недельной подписки до ${resetSubscription.availableRequests} запросов на сегодня");
              // Сохраняем оригинальные даты начала/конца подписки
              resetSubscription = resetSubscription.copyWith(
                startDate: subscription.startDate,
                endDate: subscription.endDate,
              );
              break;
            case SubscriptionType.monthly:
              resetSubscription = SubscriptionModel.monthly();
              print(
                  "🔄 REPOSITORY: Сброс месячной подписки до ${resetSubscription.availableRequests} запросов на сегодня");
              resetSubscription = resetSubscription.copyWith(
                startDate: subscription.startDate,
                endDate: subscription.endDate,
              );
              break;
            case SubscriptionType.yearly:
              resetSubscription = SubscriptionModel.yearly();
              print(
                  "🔄 REPOSITORY: Сброс годовой подписки до ${resetSubscription.availableRequests} запросов на сегодня");
              resetSubscription = resetSubscription.copyWith(
                startDate: subscription.startDate,
                endDate: subscription.endDate,
              );
              break;
            case SubscriptionType.lifetime:
              resetSubscription = SubscriptionModel.lifetime();
              print(
                  "🔄 REPOSITORY: Сброс пожизненной подписки до ${resetSubscription.availableRequests} запросов на сегодня");
              resetSubscription = resetSubscription.copyWith(
                startDate: subscription.startDate,
              );
              break;
            default:
              // Для других типов подписок (включая trial), просто сбрасываем счетчик
              resetSubscription = subscription.copyWith(
                availableRequests: subscription.maxRequests,
              );
              print(
                  "🔄 REPOSITORY: Сброс стандартной подписки до ${resetSubscription.availableRequests} запросов на сегодня");
          }

          // Сохраняем обновленную подписку
          await saveSubscription(resetSubscription);

          // Сохраняем дату сброса
          await _prefs.setString(_lastResetDateKey, today.toIso8601String());

          print(
              "✅ REPOSITORY: Сброшено до ${resetSubscription.availableRequests} запросов для пользователя с подпиской ${resetSubscription.type}");

          return resetSubscription;
        }

        // Если нет необходимости в сбросе, проверим актуальность динамического лимита free
        if (subscription.type == SubscriptionType.free) {
          // Пересчитываем остаток с учетом уже использованных запросов
          final int usedToday =
              subscription.maxRequests - subscription.availableRequests;
          final int recalculatedAvailable = todayFreeMax - usedToday;
          final int clampedAvailable =
              recalculatedAvailable < 0 ? 0 : recalculatedAvailable;

          final bool needsAdjustment =
              subscription.maxRequests != todayFreeMax ||
                  subscription.availableRequests != clampedAvailable;

          if (needsAdjustment) {
            final adjusted = subscription.copyWith(
              maxRequests: todayFreeMax,
              availableRequests: clampedAvailable,
            );

            await saveSubscription(adjusted);
            print(
                "♻️ REPOSITORY: Применили динамический лимит free без сброса дня: ${adjusted.availableRequests}/${adjusted.maxRequests} (использовано сегодня: $usedToday)");
            return adjusted;
          }
        }

        // Если нет необходимости в сбросе и корректировке, просто возвращаем подписку
        return subscription;
      }
    } catch (e) {
      print("❌ REPOSITORY: Ошибка при получении данных подписки: $e");
    }

    // Первый запуск - создаем бесплатную подписку
    // Устанавливаем/читаем дату начала динамической квоты
    final DateTime freeQuotaStartDate = await _getOrInitFreeQuotaStartDate();
    final int todayFreeMax = _computeFreeDailyMax(freeQuotaStartDate);

    // Создаем free-подписку и сразу применяем динамический дневной лимит
    final SubscriptionModel freeSubscription = SubscriptionModel.free()
        .copyWith(availableRequests: todayFreeMax, maxRequests: todayFreeMax);
    await saveSubscription(freeSubscription);

    // Сохраняем текущую дату сброса
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    await _prefs.setString(_lastResetDateKey, today.toIso8601String());

    print(
        "✅ REPOSITORY: Создана новая бесплатная подписка (динамика free): доступно=${freeSubscription.availableRequests}/${freeSubscription.maxRequests}");

    return freeSubscription;
  }

  /// Сохранение информации о подписке
  Future<void> saveSubscription(SubscriptionModel subscription) async {
    final json = _subscriptionToJson(subscription);
    await _prefs.setString(_subscriptionKey, jsonEncode(json));
    print(
        "💾 REPOSITORY: Сохранена подписка: тип=${subscription.type}, доступно=${subscription.availableRequests}/${subscription.maxRequests}");
  }

  /// Активация пробной подписки
  Future<SubscriptionModel> activateTrial() async {
    final trial = SubscriptionModel.trial();
    await saveSubscription(trial);
    print(
        "🔔 REPOSITORY: Активирована пробная подписка: доступно=${trial.availableRequests}/${trial.maxRequests}");
    return trial;
  }

  /// Активация недельной подписки
  Future<SubscriptionModel> activateWeekly() async {
    final weekly = SubscriptionModel.weekly();
    await saveSubscription(weekly);
    print(
        "🔔 REPOSITORY: Активирована недельная подписка: доступно=${weekly.availableRequests}/${weekly.maxRequests}");
    return weekly;
  }

  /// Активация месячной подписки
  Future<SubscriptionModel> activateMonthly() async {
    final monthly = SubscriptionModel.monthly();
    await saveSubscription(monthly);
    print(
        "🔔 REPOSITORY: Активирована месячная подписка: доступно=${monthly.availableRequests}/${monthly.maxRequests}");
    return monthly;
  }

  /// Активация годовой подписки
  Future<SubscriptionModel> activateYearly() async {
    final yearly = SubscriptionModel.yearly();
    await saveSubscription(yearly);
    print(
        "🔔 REPOSITORY: Активирована годовая подписка: доступно=${yearly.availableRequests}/${yearly.maxRequests}");
    return yearly;
  }

  /// Активация бессрочной подписки
  Future<SubscriptionModel> activateLifetime() async {
    final lifetime = SubscriptionModel.lifetime();
    await saveSubscription(lifetime);
    print(
        "🔔 REPOSITORY: Активирована бессрочная подписка: доступно=${lifetime.availableRequests}/${lifetime.maxRequests}");
    return lifetime;
  }

  /// Использование запроса (уменьшение доступных запросов)
  Future<SubscriptionModel> useRequest() async {
    try {
      final currentSubscription = await getCurrentSubscription();
      print(
          "📝 REPOSITORY: useRequest: Текущее состояние подписки: type=${currentSubscription.type}, availableRequests=${currentSubscription.availableRequests}, maxRequests=${currentSubscription.maxRequests}");

      // Проверяем, есть ли доступные запросы
      if (currentSubscription.availableRequests <= 0) {
        print("❌ REPOSITORY: Невозможно использовать запрос: лимит исчерпан");
        return currentSubscription;
      }

      // Создаем обновленную подписку с уменьшенным числом доступных запросов
      final updatedSubscription = currentSubscription.copyWith(
        availableRequests: currentSubscription.availableRequests - 1,
      );

      print(
          "🔄 REPOSITORY: useRequest: Обновленная подписка: type=${updatedSubscription.type}, availableRequests=${updatedSubscription.availableRequests}, maxRequests=${updatedSubscription.maxRequests}");

      // Сохраняем обновленную подписку
      await saveSubscription(updatedSubscription);

      print(
          "✅ REPOSITORY: Использован запрос. Осталось: ${updatedSubscription.availableRequests}/${updatedSubscription.maxRequests}");

      return updatedSubscription;
    } catch (e) {
      print("❌ REPOSITORY: Ошибка при использовании запроса: $e");
      rethrow;
    }
  }

  /// Проверка доступности запросов
  Future<bool> hasAvailableRequests() async {
    try {
      final subscription = await getCurrentSubscription();
      final hasAvailable = subscription.availableRequests > 0;

      print(
          "🔢 REPOSITORY: hasAvailableRequests: $hasAvailable, осталось=${subscription.availableRequests}/${subscription.maxRequests}, тип=${subscription.type}");

      return hasAvailable;
    } catch (e) {
      print("❌ REPOSITORY: Ошибка при проверке доступных запросов: $e");
      return false;
    }
  }

  /// Сброс ежедневного лимита запросов для тестирования
  Future<SubscriptionModel> resetDailyQuota() async {
    final currentSubscription = await getCurrentSubscription();

    if (currentSubscription.type == SubscriptionType.free) {
      final resetSubscription = SubscriptionModel.free();
      await saveSubscription(resetSubscription);

      // Обновляем дату сброса
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      await _prefs.setString(_lastResetDateKey, today.toIso8601String());

      print("✅ REPOSITORY: Принудительный сброс ежедневной квоты");
      return resetSubscription;
    }

    return currentSubscription;
  }

  /// Сериализация модели подписки в Map
  Map<String, dynamic> _subscriptionToJson(SubscriptionModel subscription) {
    return {
      'type': subscription.type.index,
      'startDate': subscription.startDate.millisecondsSinceEpoch,
      'endDate': subscription.endDate?.millisecondsSinceEpoch,
      'availableRequests': subscription.availableRequests,
      'maxRequests': subscription.maxRequests,
    };
  }

  /// Десериализация модели подписки из Map
  SubscriptionModel _subscriptionFromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      type: SubscriptionType.values[json['type'] as int],
      startDate: DateTime.fromMillisecondsSinceEpoch(json['startDate'] as int),
      endDate: json['endDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['endDate'] as int)
          : null,
      availableRequests: json['availableRequests'] as int,
      maxRequests: json['maxRequests'] as int,
    );
  }

  /// Возвращает дату начала динамической бесплатной квоты, инициализируя при необходимости
  Future<DateTime> _getOrInitFreeQuotaStartDate() async {
    final String? stored = _prefs.getString(_freeQuotaStartDateKey);
    if (stored != null) {
      try {
        return DateTime.parse(stored);
      } catch (_) {
        // игнорируем инициализацию ниже
      }
    }

    // Попытка использовать ранее сохраненную метку первого запуска, если есть
    final int? firstLaunchMs = _prefs.getInt('first_app_launch');
    DateTime start = DateTime.now();
    if (firstLaunchMs != null) {
      try {
        start = DateTime.fromMillisecondsSinceEpoch(firstLaunchMs);
      } catch (_) {}
    }

    await _prefs.setString(_freeQuotaStartDateKey, start.toIso8601String());
    print(
        "🗓️ REPOSITORY: Инициализирована дата начала динамической квоты free: ${start.toIso8601String()}");
    return start;
  }

  /// Вычисляет дневной лимит бесплатного пользователя:
  /// 0–13 дней — 3/день; 14–27 — 2/день; ≥28 — 1/день.
  int _computeFreeDailyMax(DateTime startDate) {
    final DateTime today = DateTime.now();
    final DateTime start =
        DateTime(startDate.year, startDate.month, startDate.day);
    final int days = today.difference(start).inDays;
    if (days < 14) return 3;
    if (days < 28) return 2;
    return 1;
  }
}
