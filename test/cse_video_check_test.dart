// Интеграционный тест: проверяет, что по заданной строке CSE возвращает нужный RuTube URL
// Запуск: flutter test test/cse_video_check_test.dart (или dart test)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('Google CSE returns expected RuTube video for butterfly query',
      () async {
    final apiKey = Platform.environment['GOOGLE_CSE_API_KEY'];
    final cseId = Platform.environment['GOOGLE_CSE_ID'];
    expect(apiKey != null && apiKey.isNotEmpty, true,
        reason: 'GOOGLE_CSE_API_KEY is required');
    expect(cseId != null && cseId.isNotEmpty, true,
        reason: 'GOOGLE_CSE_ID is required');

    const query = 'Сведение рук в тренажере Бабочка упражнение site:rutube.ru';
    const expectedId = '8c17891b490c37ea99c375c767bc6185';

    final uri = Uri.parse('https://customsearch.googleapis.com/customsearch/v1')
        .replace(queryParameters: <String, String>{
      'key': apiKey!,
      'cx': cseId!,
      'q': query,
      'num': '10',
      'hl': 'ru',
      'gl': 'ru',
      'lr': 'lang_ru',
      'safe': 'off',
    });

    final resp = await http.get(uri).timeout(const Duration(seconds: 20));
    expect(resp.statusCode, 200,
        reason: 'HTTP ${resp.statusCode}: ${resp.body}');

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    expect(items.isNotEmpty, true, reason: 'CSE returned empty items');

    final links = <String>[];
    for (final it in items) {
      final link = (it['link'] ?? '').toString();
      final formatted = (it['formattedUrl'] ?? '').toString();
      final url = link.isNotEmpty ? link : formatted;
      if (url.isEmpty) continue;
      links.add(url);
    }

    final hit = links.firstWhere(
        (u) =>
            u.contains('rutube.ru/video/$expectedId') ||
            u.contains('/play/embed/$expectedId'),
        orElse: () => '');

    expect(hit.isNotEmpty, true,
        reason:
            'Expected RuTube video not found in top links. Links: ${links.join('\n')}');
  });
}
