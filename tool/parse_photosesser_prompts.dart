// Парсинг промптов с photosesser.ru (или любого URL/API).
//
// Как найти источник данных на photosesser.ru:
// 1. Открой https://photosesser.ru/ в браузере.
// 2. F12 → Network → фильтр XHR/Fetch.
// 3. Обнови страницу, походи по разделам (Категории, Сгенерировать).
// 4. Найди запрос, в ответе которого приходит JSON с пресетами/промптами.
// 5. Скопируй полный URL этого запроса и передай скрипту.
//
// Использование:
//   dart run tool/parse_photosesser_prompts.dart
//     — загружает главную страницу и ищет встроенный JSON в HTML.
//   dart run tool/parse_photosesser_prompts.dart "https://photosesser.ru/..."
//     — загружает указанный URL (страница или API) и извлекает промпты.
//   dart run tool/parse_photosesser_prompts.dart "https://..." --out presets.json
//     — сохраняет результат в JSON-файл в формате пресетов (id, prompt, previewImageUrl, title).
//
// Промпты на странице — в div с классами rounded-lg, max-h-40, overflow-y-auto (см. скриншот).
//
// Чтение из файла (после сбора через скрипт в консоли браузера):
//   dart run tool/parse_photosesser_prompts.dart --file presets.json --out presets_out.json
//   dart run tool/parse_photosesser_prompts.dart --file saved_page.html --out presets_out.json

import 'dart:convert';
import 'dart:io';

const String defaultUrl = 'https://photosesser.ru/';

void main(List<String> args) async {
  String? url;
  String? filePath;
  String? outPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) {
      outPath = args[++i];
    } else if (args[i] == '--file' && i + 1 < args.length) {
      filePath = args[++i];
    } else if (!args[i].startsWith('--')) {
      final arg = args[i].trim();
      if (arg.startsWith('http://') || arg.startsWith('https://')) {
        url = arg;
      } else if (filePath == null && (arg.contains('/') || arg.contains('.') || File(arg).existsSync())) {
        filePath = arg;
      } else {
        url = arg;
      }
    }
  }
  url ??= defaultUrl;

  String? body;
  if (filePath != null) {
    final file = File(filePath);
    if (!file.existsSync()) {
      print('Файл не найден: $filePath');
      exit(1);
    }
    print('Чтение файла: $filePath');
    body = file.readAsStringSync();
  } else {
    print('Загрузка: $url');
    body = await _fetchUrl(url);
  }
  if (body == null || body.isEmpty) {
    print('Пустой контент.');
    exit(1);
  }
  final content = body;

  final presets = <Map<String, dynamic>>[];

  if (content.trimLeft().startsWith('{') || content.trimLeft().startsWith('[')) {
    final parsed = _parseJsonResponse(content);
    if (parsed != null) presets.addAll(_extractPresetsFromJson(parsed));
  } else {
    presets.addAll(_extractPresetsFromHtml(content));
    final embedded = _findEmbeddedJsonInHtml(content);
    for (final j in embedded) {
      presets.addAll(_extractPresetsFromJson(j));
    }
  }

  _normalizePresets(presets);
  if (presets.isEmpty) {
    print('Промпты не найдены. Используй скрипт из tool/scrape_photosesser_console.js в консоли на photosesser.ru, сохрани JSON и передай --file.');
    exit(1);
  }

  print('Найдено пресетов: ${presets.length}');
  for (var i = 0; i < presets.length && i < 5; i++) {
    final p = presets[i];
    final prompt = (p['prompt'] as String? ?? '').replaceAll('\n', ' ');
    print('  ${i + 1}. ${p['title'] ?? p['id'] ?? ''}: ${prompt.length > 60 ? '${prompt.substring(0, 60)}...' : prompt}');
  }
  if (presets.length > 5) print('  ...');

  if (outPath != null) {
    File(outPath).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(presets));
    print('Сохранено: $outPath');
  } else {
    print('--- JSON ---');
    print(const JsonEncoder.withIndent('  ').convert(presets));
  }
}

Future<String?> _fetchUrl(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'Mozilla/5.0 (compatible; AIVideoMaker/1)');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();
    return res.statusCode == 200 ? body : null;
  } catch (e) {
    print('Ошибка запроса: $e');
    client.close();
    return null;
  }
}

Object? _parseJsonResponse(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

List<Object?> _findEmbeddedJsonInHtml(String html) {
  final out = <Object?>[];
  final scriptRegex = RegExp(
    '<script[^>]*type\\s*=\\s*["\']application/json["\'][^>]*>([\\s\\S]*?)</script>',
    caseSensitive: false,
    dotAll: true,
  );
  for (final m in scriptRegex.allMatches(html)) {
    final raw = m.group(1)?.trim();
    if (raw == null || raw.isEmpty) continue;
    final decoded = _parseJsonResponse(raw);
    if (decoded != null) out.add(decoded);
  }
  final nextDataRegex = RegExp(
    '<script[^>]*id\\s*=\\s*["\']__NEXT_DATA__["\'][^>]*>([\\s\\S]*?)</script>',
    caseSensitive: false,
    dotAll: true,
  );
  for (final m in nextDataRegex.allMatches(html)) {
    final raw = m.group(1)?.trim();
    if (raw == null || raw.isEmpty) continue;
    final decoded = _parseJsonResponse(raw);
    if (decoded != null) out.add(decoded);
  }
  final assignRegex = RegExp(
    r'window\.__(?:DATA|INITIAL|PRELOAD)__\s*=\s*(\{[\s\S]*?\});',
    dotAll: true,
  );
  for (final m in assignRegex.allMatches(html)) {
    final raw = m.group(1)?.trim();
    if (raw == null) continue;
    final decoded = _parseJsonResponse(raw);
    if (decoded != null) out.add(decoded);
  }
  return out;
}

List<Map<String, dynamic>> _extractPresetsFromHtml(String html) {
  final list = <Map<String, dynamic>>[];
  final blockRegex = RegExp(
    '<div[^>]*class="[^"]*(?:rounded-lg|max-h-40|overflow-y-auto)[^"]*"[^>]*>'
    r'([\s\S]*?)'
    r'</div>',
    caseSensitive: false,
  );
  var index = 0;
  for (final m in blockRegex.allMatches(html)) {
    var raw = m.group(1) ?? '';
    raw = _stripHtmlTags(raw).trim();
    if (raw.length < 50) continue;
    if (raw.contains('</script>') || raw.contains('</style>')) continue;
    list.add({
      'id': 'preset_${++index}',
      'prompt': raw,
      'previewImageUrl': '',
      'title': null,
    });
  }
  return list;
}

String _stripHtmlTags(String html) {
  return html
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .trim();
}

List<Map<String, dynamic>> _extractPresetsFromJson(Object? json) {
  final list = <Map<String, dynamic>>[];
  if (json is Map<String, dynamic>) {
    if (json['presets'] is List) {
      for (final e in json['presets'] as List) {
        if (e is Map<String, dynamic>) list.add(Map<String, dynamic>.from(e));
      }
    }
    if (json['prompts'] is List) {
      for (final e in json['prompts'] as List) {
        if (e is Map<String, dynamic>) list.add(Map<String, dynamic>.from(e));
        if (e is String) list.add({'prompt': e});
      }
    }
    if (json['data'] is List) {
      for (final e in json['data'] as List) {
        if (e is Map<String, dynamic>) list.add(Map<String, dynamic>.from(e));
      }
    }
    if (json['documents'] is List) {
      for (final e in json['documents'] as List) {
        if (e is Map<String, dynamic>) list.add(Map<String, dynamic>.from(e));
      }
    }
    if (list.isEmpty && (json['prompt'] is String || json['title'] is String)) {
      list.add(Map<String, dynamic>.from(json));
    }
  }
  if (json is List) {
    for (final e in json) {
      if (e is Map<String, dynamic>) list.add(Map<String, dynamic>.from(e));
      if (e is String) list.add({'prompt': e});
    }
  }
  return list;
}

void _normalizePresets(List<Map<String, dynamic>> presets) {
  for (var i = 0; i < presets.length; i++) {
    final p = presets[i];
    final prompt = p['prompt'] ?? p['text'] ?? p['content'] ?? '';
    final title = p['title'] ?? p['name'] ?? p['label'];
    final imageUrl = p['previewImageUrl'] ?? p['preview_image_url'] ?? p['imageUrl'] ?? p['image_url'] ?? p['thumbnail'] ?? p['preview'] ?? '';
    final id = p['id'] ?? p['\$id'] ?? 'preset_${i + 1}';
    presets[i] = {
      'id': id is String ? id : id.toString(),
      'prompt': prompt is String ? prompt : prompt.toString(),
      'previewImageUrl': imageUrl is String ? imageUrl : '',
      'title': title?.toString(),
    };
  }
}
