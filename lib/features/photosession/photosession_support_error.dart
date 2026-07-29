import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String photosessionSupportEmail = 'bankr0t.studio@gmail.com';

String normalizePhotosessionErrorMessage(String? errorMessage) {
  final raw = (errorMessage ?? '').trim();
  if (raw.isEmpty) {
    return 'Не удалось выполнить действие.';
  }

  final lower = raw.toLowerCase();
  if (_isBalanceError(lower)) {
    return 'Недостаточно кредитов для генерации.';
  }
  if (_isUpstreamTimeoutError(lower)) {
    return 'Сервер генерации не успел ответить. Попробуйте ещё раз.';
  }
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection reset') ||
      lower.contains('network is unreachable') ||
      lower.contains('network') ||
      lower.contains('handshake') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('истекло время ожидания') ||
      lower.contains('http 502') ||
      lower.contains('http 503') ||
      lower.contains('http 504')) {
    return 'Не удалось подключиться к серверу.';
  }
  return 'Что-то пошло не так. Попробуйте ещё раз.';
}

String buildPhotosessionSupportAdvice() {
  return 'Попробуйте ещё раз, используя другую сеть или Wi-Fi. '
      'Если ошибка повторится, напишите нам на почту '
      '$photosessionSupportEmail и приложите скриншот.';
}

bool isPhotosessionBalanceError(String? errorMessage) {
  final lower = (errorMessage ?? '').toLowerCase();
  return _isBalanceError(lower);
}

/// Статусы CDN-контура ApiBost (520-527): запрос дошёл до провайдера, но ответ
/// не пришёл в отведённое время. Повтор обычно помогает.
bool _isUpstreamTimeoutError(String lower) {
  for (var status = 520; status <= 527; status++) {
    if (lower.contains('http $status')) return true;
  }
  return false;
}

bool _isBalanceError(String lower) {
  return lower.contains('余额不足') ||
      lower.contains('剩余额度') ||
      lower.contains('额度不足') ||
      lower.contains('insufficient balance') ||
      lower.contains('remaining balance') ||
      lower.contains('remaining credit') ||
      lower.contains('user quota is not enough') ||
      lower.contains('quota is not enough');
}

Future<void> contactPhotosessionSupport(
  BuildContext context, {
  String? rawError,
}) async {
  final subject = Uri.encodeComponent('AI Video Maker: ошибка');
  final body = Uri.encodeComponent(
    'Здравствуйте!\n\n'
    'Столкнулся(лась) с ошибкой в AI Video Maker.\n'
    'Попробовал(а) повторить через другую сеть или Wi-Fi.\n'
    'Прикладываю скриншот.\n\n'
    'Текст ошибки:\n${rawError?.trim().isNotEmpty == true ? rawError!.trim() : 'Не указан'}\n',
  );
  final uri = Uri.parse(
    'mailto:$photosessionSupportEmail?subject=$subject&body=$body',
  );

  if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    return;
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Не удалось открыть почтовое приложение'),
      backgroundColor: Colors.red,
    ),
  );
}
