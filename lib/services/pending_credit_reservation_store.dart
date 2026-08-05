import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credit_service.dart';

/// Резерв кредитов, переживающий перезапуск приложения.
///
/// Вместе с резервом хранится всё, что нужно, чтобы забрать уже оплаченный
/// результат: идентификатор задачи у провайдера и адресаты записи в историю.
class PendingCreditReservation {
  const PendingCreditReservation({
    required this.taskId,
    required this.reservation,
    this.providerTaskId,
    this.providerName,
    this.presetId,
    this.userPhotoPath,
  });

  final String taskId;
  final CreditReservation reservation;

  /// Идентификатор задачи на стороне провайдера. Появляется не сразу: сначала
  /// резервируются кредиты, и только потом сервис ставит задачу.
  final String? providerTaskId;
  final String? providerName;
  final String? presetId;
  final String? userPhotoPath;

  PendingCreditReservation withProviderTask(String providerTaskId) =>
      PendingCreditReservation(
        taskId: taskId,
        reservation: reservation,
        providerTaskId: providerTaskId,
        providerName: providerName,
        presetId: presetId,
        userPhotoPath: userPhotoPath,
      );

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        'amount': reservation.amount,
        'free': reservation.countAsFreeGeneration,
        if (providerTaskId != null) 'providerTaskId': providerTaskId,
        if (providerName != null) 'providerName': providerName,
        if (presetId != null) 'presetId': presetId,
        if (userPhotoPath != null) 'userPhotoPath': userPhotoPath,
      };

  static PendingCreditReservation? fromJson(Map<String, dynamic> json) {
    final taskId = json['taskId'];
    final amount = json['amount'];
    if (taskId is! String || amount is! int) return null;
    return PendingCreditReservation(
      taskId: taskId,
      reservation: CreditReservation(
        amount: amount,
        countAsFreeGeneration: json['free'] == true,
      ),
      providerTaskId: json['providerTaskId'] as String?,
      providerName: json['providerName'] as String?,
      presetId: json['presetId'] as String?,
      userPhotoPath: json['userPhotoPath'] as String?,
    );
  }
}

/// Хранит незавершённые резервы кредитов на диске.
///
/// Задачи генерации живут только в памяти, поэтому смерть процесса во время
/// рендера или скачивания видео раньше означала списанные кредиты без
/// результата и без возврата. Записанный здесь резерв позволяет при следующем
/// запуске сначала забрать оплаченное видео и вернуть кредиты только тогда,
/// когда результата действительно нет.
class PendingCreditReservationStore {
  static const String _key = 'pending_credit_reservations';
  static const String _logPrefix = '💳 PENDING_RESERVATIONS:';

  Future<void> add(PendingCreditReservation pending) async {
    final items = await _read();
    items.removeWhere((item) => item.taskId == pending.taskId);
    items.add(pending);
    await _write(items);
  }

  /// Дописывает идентификатор задачи провайдера к уже сохранённому резерву.
  Future<void> attachProviderTask(String taskId, String providerTaskId) async {
    final items = await _read();
    final index = items.indexWhere((item) => item.taskId == taskId);
    if (index < 0) return;
    items[index] = items[index].withProviderTask(providerTaskId);
    await _write(items);
  }

  Future<void> remove(String taskId) async {
    final items = await _read();
    final before = items.length;
    items.removeWhere((item) => item.taskId == taskId);
    if (items.length == before) return;
    await _write(items);
  }

  /// Забирает все записи и очищает хранилище: вызывающий код обязан вернуть
  /// кредиты, а повторная выдача тех же резервов удвоила бы баланс.
  Future<List<PendingCreditReservation>> drain() async {
    final items = await _read();
    if (items.isEmpty) return const [];
    await _write(const []);
    return items;
  }

  Future<List<PendingCreditReservation>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? const [];
      return raw
          .map((entry) {
            final decoded = jsonDecode(entry);
            return decoded is Map<String, dynamic>
                ? PendingCreditReservation.fromJson(decoded)
                : null;
          })
          .whereType<PendingCreditReservation>()
          .toList();
    } catch (e) {
      debugPrint('$_logPrefix чтение не удалось: $e');
      return [];
    }
  }

  Future<void> _write(List<PendingCreditReservation> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _key,
        items.map((item) => jsonEncode(item.toJson())).toList(),
      );
    } catch (e) {
      debugPrint('$_logPrefix запись не удалась: $e');
    }
  }
}
