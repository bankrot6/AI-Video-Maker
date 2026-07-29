import 'dart:convert';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../config/photosession_backend.dart';
import '../models/photo_session_preset.dart';

/// Вызывает серверную функцию generate-thumbnail для пресетов без обложки.
///
/// Singleton — хранит множество presetId в обработке, чтобы не дублировать
/// параллельные запросы для одного и того же пресета.
class PresetThumbnailService {
  static final PresetThumbnailService _instance = PresetThumbnailService._();
  factory PresetThumbnailService() => _instance;
  PresetThumbnailService._();

  static const _functionId = 'generate-thumbnail';

  final _inProgress = <String>{};

  Client _buildClient() {
    return Client()
        .setEndpoint(dotenv.env['APPWRITE_ENDPOINT']?.trim() ?? '')
        .setProject(dotenv.env['APPWRITE_PROJECT_ID']?.trim() ?? '');
  }

  /// Запрашивает генерацию thumbnail для пресета без [PhotoSessionPreset.thumbnailUrl].
  ///
  /// Возвращает URL сгенерированной обложки, либо `null` при ошибке или если:
  /// - бэкенд не Appwrite,
  /// - `previewImageUrl` пуст,
  /// - генерация уже идёт для этого presetId.
  Future<String?> generateForPreset(PhotoSessionPreset preset) async {
    if (!useAppwriteBackend()) return null;
    if (preset.previewImageUrl.isEmpty) return null;
    if (_inProgress.contains(preset.id)) return null;

    _inProgress.add(preset.id);
    try {
      final execution = await Functions(_buildClient()).createExecution(
        functionId: _functionId,
        body: jsonEncode({
          '\$id': preset.id,
          'previewImageUrl': preset.previewImageUrl,
          'thumbnailUrl': preset.thumbnailUrl,
          'thumbnailSourceUrl': null,
        }),
        xasync: false,
      );
      if (execution.responseStatusCode == 200) {
        final resp =
            jsonDecode(execution.responseBody) as Map<String, dynamic>;
        if (resp['ok'] == true) {
          final url = resp['thumbnailUrl'] as String?;
          debugPrint(
              'PresetThumbnailService: thumbnail готов для ${preset.id}: $url');
          return url;
        }
        debugPrint(
            'PresetThumbnailService: ok=false для ${preset.id}: ${resp['message']}');
      }
    } catch (e) {
      debugPrint('PresetThumbnailService: ошибка для ${preset.id}: $e');
    } finally {
      _inProgress.remove(preset.id);
    }
    return null;
  }
}
