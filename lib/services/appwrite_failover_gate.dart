import 'dart:async';
import 'dart:io';

import 'package:appwrite/appwrite.dart';

bool appwriteFailureLooksUnreachable(Object e) {
  if (e is TimeoutException) return true;
  if (e is SocketException) return true;
  if (e is HandshakeException) return true;
  if (e is HttpException) return true;
  if (e is AppwriteException) {
    final c = e.code;
    if (c == null || c >= 500) return true;
    if (c == 0) return true;
  }
  final s = e.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('connection timed out') ||
      s.contains('network is unreachable') ||
      s.contains('clientexception') ||
      s.contains('network error');
}

class AppwriteFailoverGate {
  AppwriteFailoverGate._();
  static final instance = AppwriteFailoverGate._();

  static const readTimeout = Duration(seconds: 12);
  static const cooldownAfterUnreachable = Duration(minutes: 2);

  DateTime? _blockedUntil;

  bool get shouldPreferFirebase =>
      _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  void noteSuccess() {
    _blockedUntil = null;
  }

  void noteUnreachableFailure() {
    _blockedUntil = DateTime.now().add(cooldownAfterUnreachable);
  }

  bool noteFailureIfUnreachable(Object e) {
    if (appwriteFailureLooksUnreachable(e)) {
      noteUnreachableFailure();
      return true;
    }
    return false;
  }
}
