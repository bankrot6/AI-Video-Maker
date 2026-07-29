// Простая CLI-проверка Google CSE по сырому запросу
// Запуск: dart run scripts/cse_video_check.dart
// Требуются переменные окружения: GOOGLE_CSE_API_KEY, GOOGLE_CSE_ID

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final apiKey = Platform.environment['GOOGLE_CSE_API_KEY'];
  final cseId = Platform.environment['GOOGLE_CSE_ID'];
  if (apiKey == null || apiKey.isEmpty || cseId == null || cseId.isEmpty) {
    stderr.writeln('ERROR: GOOGLE_CSE_API_KEY/GOOGLE_CSE_ID не заданы.');
    exitCode = 2;
    return;
  }

  final rawQuery = args.isNotEmpty
      ? args.join(' ')
      : 'Сведение рук в тренажере Бабочка упражнение site:rutube.ru';
  final expectedId = '8c17891b490c37ea99c375c767bc6185';

  stdout.writeln('🔎 CSE CHECK: q="$rawQuery"');

  final uri = Uri.parse('https://customsearch.googleapis.com/customsearch/v1')
      .replace(queryParameters: <String, String>{
    'key': apiKey,
    'cx': cseId,
    'q': rawQuery,
    'num': '10',
    'hl': 'ru',
    'gl': 'ru',
    'lr': 'lang_ru',
    'safe': 'off',
  });

  final resp = await http.get(uri).timeout(const Duration(seconds: 20));
  stdout.writeln('HTTP ${resp.statusCode}');
  if (resp.statusCode != 200) {
    stderr.writeln('Body: ${resp.body}');
    exitCode = 1;
    return;
  }

  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ??
      const <Map<String, dynamic>>[];

  final links = <String>[];
  for (final it in items) {
    final link = (it['link'] ?? '').toString();
    final formatted = (it['formattedUrl'] ?? '').toString();
    final url = link.isNotEmpty ? link : formatted;
    if (url.isEmpty) continue;
    links.add(url);
  }

  stdout.writeln('TOP LINKS:');
  for (final l in links) {
    stdout.writeln(' - $l');
  }

  final hit = links.firstWhere(
      (u) =>
          u.contains('rutube.ru/video/$expectedId') ||
          u.contains('/play/embed/$expectedId'),
      orElse: () => '');

  if (hit.isEmpty) {
    stderr.writeln('❌ Ожидаемая ссылка не найдена в топ-результатах.');
    exitCode = 1;
    return;
  }

  stdout.writeln('✅ Найдена ожидаемая ссылка: $hit');
}
