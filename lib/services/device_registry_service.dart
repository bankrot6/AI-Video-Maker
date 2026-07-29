import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'device_id_service.dart';

/// Данные об устройстве, полученные с сервера.
class DeviceRegistryResult {
  /// Дата первой установки приложения на этом устройстве.
  /// При переустановке — оригинальная дата, не текущая.
  final DateTime firstSeenAt;

  /// true — устройство регистрируется впервые (не переустановка).
  final bool isNewDevice;

  /// true — данные получены от сервера успешно и им можно доверять
  /// как источнику истины.
  final bool isServerTrusted;

  /// Использованных кредитов из бесплатного пула (free-пользователи).
  final int freeCreditsUsed;

  /// Использованных бесплатных генераций (free-пользователи).
  final int freeGenerationsUsed;

  /// Купленных кредитов (все типы пользователей).
  /// Эти кредиты не сбрасываются при смене/отмене подписки.
  final int purchasedCredits;

  /// Заработанных кредитов (все типы пользователей).
  /// Эти кредиты не сбрасываются при смене/отмене подписки.
  final int earnedCredits;

  /// Последний известный текущий баланс кредитов.
  final int currentBalance;

  /// Последний известный тип подписки.
  final String subscriptionType;

  const DeviceRegistryResult({
    required this.firstSeenAt,
    required this.isNewDevice,
    required this.isServerTrusted,
    required this.freeCreditsUsed,
    required this.freeGenerationsUsed,
    required this.purchasedCredits,
    required this.earnedCredits,
    required this.currentBalance,
    this.subscriptionType = '',
  });
}

/// Ошибка вызова функции `verify-trial` с сохранённым HTTP-статусом,
/// чтобы вызывающий код мог отличить «нет кредитов» от «сервер недоступен».
class DeviceRegistryFunctionException implements Exception {
  const DeviceRegistryFunctionException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() =>
      'DeviceRegistryFunctionException($statusCode): $body';
}

/// Результат резервирования кредитов на сервере.
class DeviceRegistryReserveResult {
  const DeviceRegistryReserveResult._(this.reason, this.state);

  const DeviceRegistryReserveResult.success(DeviceRegistryResult state)
      : this._('reserved', state);

  const DeviceRegistryReserveResult.failure(String reason)
      : this._(reason, null);

  /// `reserved` | `insufficient_credits` | `device_not_registered` |
  /// `server_unconfigured` | `server_unavailable`.
  final String reason;
  final DeviceRegistryResult? state;

  bool get isSuccess => state != null;
}

class ReviewBonusClaimResult {
  const ReviewBonusClaimResult({
    required this.awardedCredits,
    required this.reason,
    required this.totalEarnedCredits,
  });

  final int awardedCredits;
  final String reason;
  final int totalEarnedCredits;
}

/// Синхронизирует состояние кредитов устройства с сервером для ВСЕХ типов
/// пользователей: free, trial, paid.
///
/// Что защищается:
/// - `purchasedCredits` / `earnedCredits` — никогда не теряются при переустановке
///   или смене/отмене подписки.
/// - `freeCreditsUsed` / `freeGenerationsUsed` — free-пользователи не могут
///   сбросить счётчики переустановкой.
///
/// Стратегия fail-open: при недоступности сервера возвращаются безопасные
/// значения — приложение не блокируется.
class DeviceRegistryService {
  static final DeviceRegistryService _instance = DeviceRegistryService._();
  factory DeviceRegistryService() => _instance;
  DeviceRegistryService._();

  static const String _functionId = 'verify-trial';
  static const String _logPrefix = '📱 DEVICE_REGISTRY';

  Client _buildClient() {
    final endpoint = dotenv.env['APPWRITE_ENDPOINT']?.trim() ?? '';
    final projectId = dotenv.env['APPWRITE_PROJECT_ID']?.trim() ?? '';
    return Client().setEndpoint(endpoint).setProject(projectId);
  }

  bool get _isConfigured {
    final endpoint = dotenv.env['APPWRITE_ENDPOINT']?.trim() ?? '';
    final projectId = dotenv.env['APPWRITE_PROJECT_ID']?.trim() ?? '';
    return endpoint.isNotEmpty && projectId.isNotEmpty;
  }

  static DeviceRegistryResult get _failOpenResult => DeviceRegistryResult(
        firstSeenAt: DateTime.now(),
        isNewDevice: true,
        isServerTrusted: false,
        freeCreditsUsed: 0,
        freeGenerationsUsed: 0,
        purchasedCredits: 0,
        earnedCredits: 0,
        currentBalance: 0,
      );

  /// Регистрирует устройство и возвращает всё сохранённое на сервере состояние.
  ///
  /// Первая установка → нулевые счётчики + FREE_STARTING_CREDITS.
  /// Переустановка → оригинальная дата + накопленные кредиты.
  Future<DeviceRegistryResult> registerAndGetFirstSeen() async {
    if (!_isConfigured) {
      debugPrint('$_logPrefix: Appwrite не сконфигурирован');
      return _failOpenResult;
    }

    try {
      final fingerprint = await DeviceIdService.instance.getDeviceId();
      final platform = Platform.isAndroid ? 'android' : 'ios';

      final r = await _invoke({
        'action': 'register_device',
        'fingerprint': fingerprint,
        'platform': platform,
      });

      final result = DeviceRegistryResult(
        firstSeenAt: _parseDate(r['firstSeenAt']),
        isNewDevice: r['isNewDevice'] as bool? ?? true,
        isServerTrusted: true,
        freeCreditsUsed: _int(r['freeCreditsUsed']),
        freeGenerationsUsed: _int(r['freeGenerationsUsed']),
        purchasedCredits: _int(r['purchasedCredits']),
        earnedCredits: _int(r['earnedCredits']),
        currentBalance: _int(r['currentBalance']),
        subscriptionType: r['subscriptionType'] as String? ?? '',
      );

      debugPrint('$_logPrefix registerAndGetFirstSeen: '
          'isNew=${result.isNewDevice} '
          'trusted=${result.isServerTrusted} '
          'purchased=${result.purchasedCredits} '
          'earned=${result.earnedCredits} '
          'balance=${result.currentBalance} '
          'freeCr=${result.freeCreditsUsed} '
          'freeGens=${result.freeGenerationsUsed}');

      return result;
    } on SocketException {
      debugPrint('$_logPrefix: нет сети — fail-open');
      return _failOpenResult;
    } catch (e) {
      debugPrint('$_logPrefix: ошибка: $e — fail-open');
      return _failOpenResult;
    }
  }

  /// Синхронизирует текущее состояние кредитов устройства с сервером.
  ///
  /// Вызывается fire-and-forget после каждого изменения кредитов.
  /// Сервер применяет MAX(текущее, входящее) — значения только растут.
  ///
  /// [subscriptionType] — текущий тип подписки: "free", "trial", "weekly" и т.д.
  Future<void> syncCredits({
    required int freeCreditsUsed,
    required int freeGenerationsUsed,
    required int purchasedCredits,
    required int earnedCredits,
    required int currentBalance,
    required String subscriptionType,
  }) async {
    if (!_isConfigured) return;

    try {
      final fingerprint = await DeviceIdService.instance.getDeviceId();
      final platform = Platform.isAndroid ? 'android' : 'ios';

      await _invoke({
        'action': 'sync_credits',
        'fingerprint': fingerprint,
        'platform': platform,
        'freeCreditsUsed': freeCreditsUsed,
        'freeGenerationsUsed': freeGenerationsUsed,
        'purchasedCredits': purchasedCredits,
        'earnedCredits': earnedCredits,
        'currentBalance': currentBalance,
        'subscriptionType': subscriptionType,
      });

      debugPrint('$_logPrefix syncCredits: '
          'sub=$subscriptionType '
          'purchased=$purchasedCredits earned=$earnedCredits balance=$currentBalance '
          'freeCr=$freeCreditsUsed freeGens=$freeGenerationsUsed');
    } catch (e) {
      debugPrint('$_logPrefix syncCredits error (ignored): $e');
    }
  }

  Future<DeviceRegistryResult?> syncCreditsAndFetch({
    required int freeCreditsUsed,
    required int freeGenerationsUsed,
    required int purchasedCredits,
    required int earnedCredits,
    required int currentBalance,
    required String subscriptionType,
  }) async {
    if (!_isConfigured) return null;

    try {
      final fingerprint = await DeviceIdService.instance.getDeviceId();
      final platform = Platform.isAndroid ? 'android' : 'ios';

      final r = await _invoke({
        'action': 'sync_credits',
        'fingerprint': fingerprint,
        'platform': platform,
        'freeCreditsUsed': freeCreditsUsed,
        'freeGenerationsUsed': freeGenerationsUsed,
        'purchasedCredits': purchasedCredits,
        'earnedCredits': earnedCredits,
        'currentBalance': currentBalance,
        'subscriptionType': subscriptionType,
      });

      return DeviceRegistryResult(
        firstSeenAt: DateTime.now(),
        isNewDevice: false,
        isServerTrusted: true,
        freeCreditsUsed: _int(r['freeCreditsUsed']),
        freeGenerationsUsed: _int(r['freeGenerationsUsed']),
        purchasedCredits: _int(r['purchasedCredits']),
        earnedCredits: _int(r['earnedCredits']),
        currentBalance: _int(r['currentBalance']),
        subscriptionType: r['subscriptionType'] as String? ?? subscriptionType,
      );
    } catch (e) {
      debugPrint('$_logPrefix syncCreditsAndFetch error: $e');
      return null;
    }
  }

  Future<DeviceRegistryReserveResult> reserveCredits({
    required int amount,
    bool countAsFreeGeneration = false,
  }) async {
    if (!_isConfigured) {
      debugPrint('$_logPrefix reserveCredits: Appwrite не сконфигурирован');
      return const DeviceRegistryReserveResult.failure('server_unconfigured');
    }

    try {
      return DeviceRegistryReserveResult.success(
        await _sendReserveCredits(
          amount: amount,
          countAsFreeGeneration: countAsFreeGeneration,
        ),
      );
    } on DeviceRegistryFunctionException catch (e) {
      // Регистрация на старте могла не пройти (таймаут, оффлайн) — устройства
      // на сервере нет. Регистрируем его и повторяем резерв один раз.
      if (e.statusCode == 404) {
        return _reserveAfterRegistration(
          amount: amount,
          countAsFreeGeneration: countAsFreeGeneration,
        );
      }
      if (e.statusCode == 402) {
        debugPrint('$_logPrefix reserveCredits: недостаточно кредитов '
            'на сервере (${e.body})');
        return const DeviceRegistryReserveResult.failure(
          'insufficient_credits',
        );
      }
      debugPrint('$_logPrefix reserveCredits error: $e');
      return const DeviceRegistryReserveResult.failure('server_unavailable');
    } catch (e) {
      debugPrint('$_logPrefix reserveCredits error: $e');
      return const DeviceRegistryReserveResult.failure('server_unavailable');
    }
  }

  Future<DeviceRegistryReserveResult> _reserveAfterRegistration({
    required int amount,
    required bool countAsFreeGeneration,
  }) async {
    debugPrint('$_logPrefix reserveCredits: устройство не зарегистрировано — '
        'регистрируем и повторяем');
    final registered = await registerAndGetFirstSeen();
    if (!registered.isServerTrusted) {
      return const DeviceRegistryReserveResult.failure('device_not_registered');
    }

    try {
      return DeviceRegistryReserveResult.success(
        await _sendReserveCredits(
          amount: amount,
          countAsFreeGeneration: countAsFreeGeneration,
        ),
      );
    } on DeviceRegistryFunctionException catch (e) {
      debugPrint('$_logPrefix reserveCredits retry error: $e');
      return DeviceRegistryReserveResult.failure(
        e.statusCode == 402 ? 'insufficient_credits' : 'server_unavailable',
      );
    } catch (e) {
      debugPrint('$_logPrefix reserveCredits retry error: $e');
      return const DeviceRegistryReserveResult.failure('server_unavailable');
    }
  }

  Future<DeviceRegistryResult> _sendReserveCredits({
    required int amount,
    required bool countAsFreeGeneration,
  }) async {
    final fingerprint = await DeviceIdService.instance.getDeviceId();
    final platform = Platform.isAndroid ? 'android' : 'ios';
    final r = await _invoke({
      'action': 'reserve_credits',
      'fingerprint': fingerprint,
      'platform': platform,
      'amount': amount,
      'countAsFreeGeneration': countAsFreeGeneration,
    });

    return DeviceRegistryResult(
      firstSeenAt: DateTime.now(),
      isNewDevice: false,
      isServerTrusted: true,
      freeCreditsUsed: _int(r['freeCreditsUsed']),
      freeGenerationsUsed: _int(r['freeGenerationsUsed']),
      purchasedCredits: _int(r['purchasedCredits']),
      earnedCredits: _int(r['earnedCredits']),
      currentBalance: _int(r['currentBalance']),
      subscriptionType: r['subscriptionType'] as String? ?? '',
    );
  }

  Future<DeviceRegistryResult?> rollbackCredits({
    required int amount,
    bool countAsFreeGeneration = false,
  }) async {
    if (!_isConfigured) return null;

    try {
      final fingerprint = await DeviceIdService.instance.getDeviceId();
      final platform = Platform.isAndroid ? 'android' : 'ios';
      final r = await _invoke({
        'action': 'rollback_credits',
        'fingerprint': fingerprint,
        'platform': platform,
        'amount': amount,
        'countAsFreeGeneration': countAsFreeGeneration,
      });

      return DeviceRegistryResult(
        firstSeenAt: DateTime.now(),
        isNewDevice: false,
        isServerTrusted: true,
        freeCreditsUsed: _int(r['freeCreditsUsed']),
        freeGenerationsUsed: _int(r['freeGenerationsUsed']),
        purchasedCredits: _int(r['purchasedCredits']),
        earnedCredits: _int(r['earnedCredits']),
        currentBalance: _int(r['currentBalance']),
        subscriptionType: r['subscriptionType'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('$_logPrefix rollbackCredits error: $e');
      return null;
    }
  }

  Future<ReviewBonusClaimResult> claimReviewBonus({
    required String store,
    required String appVersion,
    required String reviewOutcome,
  }) async {
    if (!_isConfigured) {
      return const ReviewBonusClaimResult(
        awardedCredits: 0,
        reason: 'server_unconfigured',
        totalEarnedCredits: 0,
      );
    }

    try {
      final fingerprint = await DeviceIdService.instance.getDeviceId();
      final platform = Platform.isAndroid ? 'android' : 'ios';
      final r = await _invoke({
        'action': 'claim_review_bonus',
        'fingerprint': fingerprint,
        'platform': platform,
        'store': store,
        'appVersion': appVersion,
        'reviewOutcome': reviewOutcome,
      });

      return ReviewBonusClaimResult(
        awardedCredits: _int(r['awardedCredits']),
        reason: r['reason'] as String? ?? '',
        totalEarnedCredits: _int(r['totalEarnedCredits']),
      );
    } catch (e) {
      debugPrint('$_logPrefix claimReviewBonus error: $e');
      return const ReviewBonusClaimResult(
        awardedCredits: 0,
        reason: 'server_error',
        totalEarnedCredits: 0,
      );
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    final functions = Functions(_buildClient());
    final execution = await functions.createExecution(
      functionId: _functionId,
      body: jsonEncode(body),
      xasync: false,
    );
    if (execution.responseStatusCode >= 400) {
      throw DeviceRegistryFunctionException(
        execution.responseStatusCode,
        execution.responseBody,
      );
    }
    return jsonDecode(execution.responseBody) as Map<String, dynamic>;
  }

  static int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    try {
      return DateTime.parse(v as String);
    } catch (_) {
      return DateTime.now();
    }
  }
}
