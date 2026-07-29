import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

const _tagsKey = 'tags';
const _imageStyleKey = 'imageStyle';

/// Создаёт атрибут tags (массив строк) в коллекции presets через Appwrite API,
/// если его ещё нет. Вызывается при старте приложения, не блокирует UI.
Future<void> ensurePresetsTagsAttribute() async {
  final endpoint = dotenv.env['APPWRITE_ENDPOINT']?.trim();
  final projectId = dotenv.env['APPWRITE_PROJECT_ID']?.trim();
  final apiKey = dotenv.env['APPWRITE_API_KEY']?.trim();
  final databaseId = dotenv.env['APPWRITE_DATABASE_ID']?.trim();
  final collectionId = dotenv.env['APPWRITE_PRESETS_COLLECTION_ID']?.trim();

  if (endpoint == null ||
      endpoint.isEmpty ||
      projectId == null ||
      apiKey == null ||
      apiKey.isEmpty ||
      databaseId == null ||
      databaseId.isEmpty ||
      collectionId == null ||
      collectionId.isEmpty) {
    return;
  }

  final baseUrl = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final uri = Uri.parse(
    '${baseUrl}databases/$databaseId/collections/$collectionId/attributes/string',
  );

  try {
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'X-Appwrite-Project': projectId,
            'X-Appwrite-Key': apiKey,
          },
          body: jsonEncode({
            'key': _tagsKey,
            'size': 64,
            'required': false,
            'array': true,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      debugPrint('Appwrite: атрибут $_tagsKey создан в коллекции presets.');
      return;
    }
    final body = response.body;
    final err = body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic>? : null;
    final msg = err?['message']?.toString() ?? body;
    if (response.statusCode == 409 ||
        msg.toString().toLowerCase().contains('already')) {
      return;
    }
    debugPrint('Appwrite: создание атрибута $_tagsKey — ${response.statusCode} $msg');
  } catch (e) {
    debugPrint('Appwrite: ensurePresetsTagsAttribute — $e');
  }
}

/// Создаёт атрибут imageStyle (строка) в коллекции presets через Appwrite API,
/// если его ещё нет. Вызывается при старте приложения, не блокирует UI.
Future<void> ensurePresetsImageStyleAttribute() async {
  final endpoint = dotenv.env['APPWRITE_ENDPOINT']?.trim();
  final projectId = dotenv.env['APPWRITE_PROJECT_ID']?.trim();
  final apiKey = dotenv.env['APPWRITE_API_KEY']?.trim();
  final databaseId = dotenv.env['APPWRITE_DATABASE_ID']?.trim();
  final collectionId = dotenv.env['APPWRITE_PRESETS_COLLECTION_ID']?.trim();

  if (endpoint == null ||
      endpoint.isEmpty ||
      projectId == null ||
      apiKey == null ||
      apiKey.isEmpty ||
      databaseId == null ||
      databaseId.isEmpty ||
      collectionId == null ||
      collectionId.isEmpty) {
    return;
  }

  final baseUrl = endpoint.endsWith('/') ? endpoint : '$endpoint/';
  final uri = Uri.parse(
    '${baseUrl}databases/$databaseId/collections/$collectionId/attributes/string',
  );

  try {
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'X-Appwrite-Project': projectId,
            'X-Appwrite-Key': apiKey,
          },
          body: jsonEncode({
            'key': _imageStyleKey,
            'size': 32,
            'required': false,
            'array': false,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      debugPrint(
          'Appwrite: атрибут $_imageStyleKey создан в коллекции presets.');
      return;
    }
    final body = response.body;
    final err =
        body.isNotEmpty ? jsonDecode(body) as Map<String, dynamic>? : null;
    final msg = err?['message']?.toString() ?? body;
    if (response.statusCode == 409 ||
        msg.toString().toLowerCase().contains('already')) {
      return;
    }
    debugPrint(
        'Appwrite: создание атрибута $_imageStyleKey — ${response.statusCode} $msg');
  } catch (e) {
    debugPrint('Appwrite: ensurePresetsImageStyleAttribute — $e');
  }
}
