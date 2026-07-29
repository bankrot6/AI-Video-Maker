import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'device_id_service.dart';

/// Результат серверной проверки права на триал
class TrialServerResult {
  final bool eligible;
  final String reason;

  const TrialServerResult({required this.eligible, required this.reason});

  bool get isServerError =>
      reason == 'server_error_allow' || reason == 'server_unavailable';
}

/// Связывается с Appwrite-функцией `verify-trial` для проверки и регистрации
/// триального периода на уровне сервера.
///
/// Стратегия fail-open: при недоступности сервера триал разрешается — это
/// защита от ложных блокировок при проблемах с сетью.
class TrialServerService {
  static final TrialServerService _instance = TrialServerService._();
  factory TrialServerService() => _instance;
  TrialServerService._();

  static const String _functionId = 'verify-trial';
  static const String _logPrefix = '🔐 TRIAL_SERVER';

  Client _buildClient() {
    final endpoint = dotenv.env['APPWRITE_ENDPOINT']?.trim() ?? '';
    final projectId = dotenv.env['APPWRITE_PROJECT_ID']?.trim() ?? '';
    return Client().setEndpoint(endpoint).setProject(projectId);
  }

  /// Проверяет, имеет ли устройство право на триал.
  ///
  /// Возвращает [TrialServerResult.eligible] == true, если:
  ///  - устройство ещё не использовало триал, или
  ///  - сервер недоступен (fail-open).
  Future<TrialServerResult> checkEligibility() async {
    if (kDebugMode) {
      debugPrint('$_logPrefix checkEligibility: debug-режим, пропускаем');
      return const TrialServerResult(eligible: true, reason: 'debug_mode');
    }

    try {
      final fingerprint = await _getFingerprint();
      final response = await _invoke({'action': 'check', 'fingerprint': fingerprint});

      final eligible = response['eligible'] as bool? ?? true;
      final reason = response['reason'] as String? ?? 'unknown';
      debugPrint('$_logPrefix check: eligible=$eligible reason=$reason');
      return TrialServerResult(eligible: eligible, reason: reason);
    } on SocketException {
      debugPrint('$_logPrefix check: нет сети — fail-open');
      return const TrialServerResult(eligible: true, reason: 'server_unavailable');
    } catch (e) {
      debugPrint('$_logPrefix check error: $e — fail-open');
      return const TrialServerResult(eligible: true, reason: 'server_error_allow');
    }
  }

  /// Регистрирует факт начала триала на сервере.
  ///
  /// Идемпотентен: повторный вызов для того же устройства не возвращает ошибку.
  Future<void> claimTrial() async {
    if (kDebugMode) return;

    try {
      final fingerprint = await _getFingerprint();
      final platform = Platform.isAndroid ? 'android' : 'ios';
      final response = await _invoke({
        'action': 'claim',
        'fingerprint': fingerprint,
        'platform': platform,
      });
      debugPrint('$_logPrefix claim: ${response['success']} '
          'alreadyClaimed=${response['alreadyClaimed']}');
    } catch (e) {
      // Fail-open: не блокируем локальную активацию при ошибке сети
      debugPrint('$_logPrefix claim error (ignored): $e');
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
      throw Exception(
          '$_logPrefix function returned ${execution.responseStatusCode}: '
          '${execution.responseBody}');
    }

    return jsonDecode(execution.responseBody) as Map<String, dynamic>;
  }

  Future<String> _getFingerprint() async {
    // Используем тот же SHA-256 fingerprint что и TrialProtectionService
    final deviceId = await DeviceIdService.instance.getDeviceId();
    return deviceId;
  }
}
