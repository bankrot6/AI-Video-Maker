import 'dart:convert';
import 'dart:io';

import 'package:translator/translator.dart';

/// Simple script to update the value of the 'ai_consultation_title' key
/// across all localization files using Google Translate.
///
/// Usage:
///   dart run scripts/update_ai_consultation_title.dart
///
/// It will search in `lib/services/localization/*_strings.dart` and replace
/// the value for 'ai_consultation_title'.
Future<void> main(List<String> args) async {
  final newRussianPhrase = 'Анализ недели с ИИ-Диетологом';

  final localizationDir = Directory(
    'lib/services/localization',
  );
  if (!await localizationDir.exists()) {
    stderr.writeln('Localization directory not found: ${localizationDir.path}');
    exit(1);
  }

  final translator = GoogleTranslator();

  // Build mapping from filename prefix to translator language code
  String toTranslatorCode(String filePrefix) {
    // Normalize common variants
    final lower = filePrefix.toLowerCase();
    switch (lower) {
      case 'zh':
        return 'zh-cn';
      case 'zhtw':
        return 'zh-tw';
      case 'pt':
        return 'pt';
      case 'ptbr':
        return 'pt';
      case 'fr':
        return 'fr';
      case 'frca':
        return 'fr';
      case 'es':
        return 'es';
      case 'esmx':
        return 'es';
      case 'fil':
        // Google uses 'tl' for Tagalog/Filipino
        return 'tl';
      case 'he':
        // Some translators expect 'iw' for Hebrew
        return 'iw';
      default:
        // For most: ru, en, de, it, pl, sv, tr, th, uk, vi, ja, ko, cs, sk, ro, nl, no, ms, hr, fi, da, el, hu, id, ar
        return lower;
    }
  }

  // Escape single quotes for Dart single-quoted strings
  String escapeForDartSingleQuotes(String value) {
    return value.replaceAll("'", r"\'");
  }

  final files = localizationDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('_strings.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (files.isEmpty) {
    stderr.writeln('No *_strings.dart files found in ${localizationDir.path}');
    exit(1);
  }

  final results = <String, String>{};

  for (final file in files) {
    final filename = file.uri.pathSegments.last;
    final prefix = filename.substring(0, filename.indexOf('_strings.dart'));
    final langCode = toTranslatorCode(prefix);

    String translated;
    if (langCode == 'ru') {
      translated = newRussianPhrase; // keep source phrase for RU
    } else {
      try {
        final Translation t = await translator.translate(newRussianPhrase,
            from: 'ru', to: langCode);
        translated = t.text;
      } catch (e) {
        stderr.writeln('Failed to translate for $prefix ($langCode): $e');
        // Fallback: use English if translation fails (translate to en),
        // or default to Russian if even that fails
        try {
          final Translation t = await translator.translate(newRussianPhrase,
              from: 'ru', to: 'en');
          translated = t.text;
        } catch (_) {
          translated = newRussianPhrase;
        }
      }
    }

    final original = await file.readAsString();

    // Regex to find the line like: 'ai_consultation_title': '...', possibly with spaces
    // The value can contain escaped single quotes, so allow \\'.
    final regex = RegExp(
      r"('ai_consultation_title'\s*:\s*')((?:[^'\\]|\\.)*)(')",
      multiLine: true,
    );

    if (!regex.hasMatch(original)) {
      stdout.writeln(
          "Key 'ai_consultation_title' not found in ${file.path} - skipping");
      continue;
    }

    final escaped = escapeForDartSingleQuotes(translated);
    final updated = original.replaceAllMapped(regex, (m) {
      return "${m.group(1)}$escaped${m.group(3)}";
    });

    if (updated != original) {
      await file.writeAsString(updated);
      results[prefix] = translated;
      stdout.writeln('Updated ${file.path} -> $translated');
    } else {
      stdout.writeln('No change for ${file.path}');
    }
  }

  // Write a small report for visibility
  final reportPath = 'scripts/update_ai_consultation_title_report.json';
  final reportFile = File(reportPath);
  await reportFile
      .writeAsString(const JsonEncoder.withIndent('  ').convert(results));
  stdout.writeln('Report saved to $reportPath');
}
