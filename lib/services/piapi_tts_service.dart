import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../utils/text_cleaner.dart';

class PiApiTtsVoice {
  final String id;
  final String gender;
  final String ageGroup;
  final String refAudioUrl;
  final String refText;
  final String languageCode;

  const PiApiTtsVoice({
    required this.id,
    required this.gender,
    required this.ageGroup,
    required this.refAudioUrl,
    required this.refText,
    required this.languageCode,
  });

  factory PiApiTtsVoice.fromJson(Map<String, dynamic> json) {
    return PiApiTtsVoice(
      id: (json['id'] ?? json['name'] ?? '').toString(),
      gender: (json['gender'] ?? '').toString(),
      ageGroup: (json['age_group'] ?? json['ageGroup'] ?? '').toString(),
      refAudioUrl: (json['ref_audio'] ??
              json['refAudio'] ??
              json['ref_audio_url'] ??
              json['refAudioUrl'] ??
              '')
          .toString(),
      refText: (json['ref_text'] ?? json['refText'] ?? '').toString().trim(),
      languageCode: (json['language'] ??
              json['languageCode'] ??
              json['locale'] ??
              'ru-RU')
          .toString(),
    );
  }
}

class PiApiTtsResult {
  final File? audioFile;
  final String? errorMessage;
  final PiApiTtsVoice? voice;

  const PiApiTtsResult({this.audioFile, this.errorMessage, this.voice});

  bool get isSuccess => audioFile != null && errorMessage == null;
}

class PiApiTtsService {
  static const int _maxTextChars = 600;
  static const int _maxRefAudioSeconds = 2;

  final String? _apiKey;
  final String _taskUrl;
  final String _model;
  final String _taskType;
  final String? _serviceMode;
  final Duration _timeout;
  final Duration _pollInterval;
  final Duration _pollTimeout;

  PiApiTtsService({
    String? apiKey,
    String? taskUrl,
    String? model,
    String? taskType,
    String? serviceMode,
    Duration? timeout,
    Duration? pollInterval,
    Duration? pollTimeout,
  })  : _apiKey = apiKey ?? dotenv.env['PIAPI_API_KEY'],
        _taskUrl = taskUrl ??
            dotenv.env['PIAPI_TASK_URL'] ??
            dotenv.env['PIAPI_BASE_URL'] ??
            'https://api.piapi.ai/api/v1/task',
        _model = model ?? dotenv.env['PIAPI_TTS_MODEL'] ?? 'Qubico/tts',
        _taskType =
            taskType ?? dotenv.env['PIAPI_TTS_TASK_TYPE'] ?? 'zero-shot',
        _serviceMode = serviceMode ??
            _normalizeServiceMode(dotenv.env['PIAPI_SERVICE_MODE']),
        _timeout = timeout ?? const Duration(seconds: 90),
        _pollInterval = pollInterval ?? const Duration(seconds: 2),
        _pollTimeout = pollTimeout ?? const Duration(minutes: 3);

  Future<bool> isAvailable() async {
    final hasKey = (_apiKey ?? '').trim().isNotEmpty;
    final hasUrl = _taskUrl.trim().isNotEmpty;
    debugPrint('🟣 PIAPI TTS: доступность key=$hasKey url=$hasUrl');
    return hasKey && hasUrl;
  }

  Future<PiApiTtsResult> synthesize({
    required String text,
    required PiApiTtsVoice voice,
  }) async {
    final cleaned = TextCleaner.cleanForSpeechPreserveContent(text).trim();
    if (cleaned.isEmpty) {
      return const PiApiTtsResult(errorMessage: 'Пустой текст для озвучки.');
    }
    if (!await isAvailable()) {
      return const PiApiTtsResult(
        errorMessage: 'TTS сервис не настроен. Проверьте ключи .env.',
      );
    }
    final resolvedRefAudio = await _resolveRefAudio(voice.refAudioUrl);
    if (resolvedRefAudio == null ||
        resolvedRefAudio.isEmpty ||
        voice.refText.trim().isEmpty) {
      return const PiApiTtsResult(
        errorMessage: 'Не задан референс голоса для озвучки.',
      );
    }
    final safeText = _truncateText(cleaned, _maxTextChars);
    try {
      final createSnapshot = await _createTask(
        text: safeText,
        voice: voice,
        refAudioUrl: resolvedRefAudio,
      );
      if (createSnapshot.errorMessage != null) {
        return PiApiTtsResult(errorMessage: createSnapshot.errorMessage);
      }
      final firstResult = await _resolveAudio(createSnapshot, voice);
      if (firstResult != null) return firstResult;

      final taskId = createSnapshot.taskId;
      if (taskId == null || taskId.isEmpty) {
        return const PiApiTtsResult(
          errorMessage: 'Не удалось получить идентификатор задачи.',
        );
      }
      final polled = await _pollTask(taskId);
      return await _resolveAudio(polled, voice) ??
          const PiApiTtsResult(
            errorMessage: 'Модель не вернула аудио.',
          );
    } catch (e) {
      debugPrint('🟣 PIAPI TTS: ошибка синтеза: $e');
      return PiApiTtsResult(errorMessage: 'Ошибка синтеза: $e');
    }
  }

  Future<_PiApiTtsSnapshot> _createTask({
    required String text,
    required PiApiTtsVoice voice,
    required String refAudioUrl,
  }) async {
    final payload = _buildPayload(text, voice, refAudioUrl);
    final response = await http
        .post(
          Uri.parse(_taskUrl),
          headers: _buildHeaders(),
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    final json = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _extractErrorMessage(json) ??
          'Ошибка запроса: HTTP ${response.statusCode}';
      debugPrint('🟣 PIAPI TTS: HTTP ${response.statusCode} $error');
      return _PiApiTtsSnapshot(errorMessage: error);
    }
    return _PiApiTtsSnapshot.fromJson(json);
  }

  Future<_PiApiTtsSnapshot> _fetchTask(String taskId) async {
    final url = _buildTaskStatusUrl(taskId);
    final response = await http
        .get(Uri.parse(url), headers: _buildHeaders())
        .timeout(_timeout);
    final json = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _extractErrorMessage(json) ??
          'Ошибка запроса: HTTP ${response.statusCode}';
      debugPrint('🟣 PIAPI TTS: HTTP ${response.statusCode} $error');
      return _PiApiTtsSnapshot(errorMessage: error);
    }
    return _PiApiTtsSnapshot.fromJson(json);
  }

  Future<_PiApiTtsSnapshot> _pollTask(String taskId) async {
    final startedAt = DateTime.now();
    while (DateTime.now().difference(startedAt) <= _pollTimeout) {
      final snapshot = await _fetchTask(taskId);
      if (snapshot.errorMessage != null) return snapshot;
      if (snapshot.isCompleted || snapshot.isFailed) return snapshot;
      await Future.delayed(_pollInterval);
    }
    return const _PiApiTtsSnapshot(
      errorMessage: 'Истекло время ожидания генерации.',
    );
  }

  Future<PiApiTtsResult?> _resolveAudio(
    _PiApiTtsSnapshot snapshot,
    PiApiTtsVoice voice,
  ) async {
    if (snapshot.errorMessage != null) {
      return PiApiTtsResult(errorMessage: snapshot.errorMessage);
    }
    if (snapshot.isFailed) {
      return PiApiTtsResult(
        errorMessage: snapshot.errorMessage ?? 'Генерация завершилась ошибкой.',
      );
    }
    if (!snapshot.isCompleted) return null;

    final audioUrl = snapshot.audioUrl;
    if (audioUrl == null || audioUrl.isEmpty) {
      return const PiApiTtsResult(
        errorMessage: 'Модель не вернула ссылку на аудио.',
      );
    }
    final bytes = await _downloadAudio(audioUrl);
    if (bytes == null || bytes.bytes.isEmpty) {
      return const PiApiTtsResult(
        errorMessage: 'Не удалось скачать аудио.',
      );
    }
    final file = await _saveAudioBytes(
      bytes.bytes,
      audioUrl,
      bytes.contentType,
    );
    return PiApiTtsResult(audioFile: file, voice: voice);
  }

  Map<String, dynamic> _buildPayload(
    String text,
    PiApiTtsVoice voice,
    String refAudioUrl,
  ) {
    final payload = <String, dynamic>{
      'model': _model,
      'task_type': _taskType,
      'input': {
        'gen_text': text,
        'ref_audio': refAudioUrl,
        'ref_text': voice.refText,
      },
    };
    final serviceMode = _serviceMode ?? 'public';
    payload['config'] = {'service_mode': serviceMode};
    return payload;
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final key = _apiKey?.trim();
    if (key != null && key.isNotEmpty) {
      headers['X-API-Key'] = key;
    }
    return headers;
  }

  String _buildTaskStatusUrl(String taskId) {
    var base = _taskUrl.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base/$taskId';
  }

  dynamic _decodeJson(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  String? _extractErrorMessage(dynamic json) {
    if (json is Map<String, dynamic>) {
      final error = json['error'];
      if (error is Map<String, dynamic>) {
        final message = error['message'];
        if (message is String && message.isNotEmpty) return message;
      }
      final message = json['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return null;
  }

  Future<_AudioBytes?> _downloadAudio(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      debugPrint('🟣 PIAPI TTS: некорректный URL аудио');
      return null;
    }
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        debugPrint('🟣 PIAPI TTS: ошибка скачивания ${response.statusCode}');
        return null;
      }
      return _AudioBytes(
        bytes: response.bodyBytes,
        contentType: response.headers['content-type'],
      );
    } catch (e) {
      debugPrint('🟣 PIAPI TTS: ошибка скачивания: $e');
      return null;
    }
  }

  Future<String?> _resolveRefAudio(String refAudio) async {
    final trimmed = refAudio.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final bytes = await _loadAudioBytes(trimmed);
    if (bytes == null || bytes.isEmpty) return null;
    final prepared = _trimWav(bytes, maxSeconds: _maxRefAudioSeconds);
    return base64Encode(prepared);
  }

  Future<Uint8List?> _loadAudioBytes(String ref) async {
    if (ref.startsWith('asset:')) {
      final assetPath = ref.substring('asset:'.length).trim();
      return _loadAssetBytes(assetPath);
    }
    if (ref.startsWith('assets/')) {
      return _loadAssetBytes(ref);
    }
    final file = File(ref);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  Future<Uint8List?> _loadAssetBytes(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return data.buffer.asUint8List();
    } catch (e) {
      debugPrint('🟣 PIAPI TTS: ассет не найден: $assetPath ($e)');
      return null;
    }
  }

  Uint8List _trimWav(Uint8List bytes, {required int maxSeconds}) {
    if (!_matchesFourCC(bytes, 0, 'RIFF') ||
        !_matchesFourCC(bytes, 8, 'WAVE')) {
      return bytes;
    }
    int offset = 12;
    int? dataOffset;
    int? dataSize;
    int? dataSizeOffset;
    int? byteRate;
    int? blockAlign;

    while (offset + 8 <= bytes.length) {
      final chunkId = _readFourCC(bytes, offset);
      final chunkSize = _readUint32LE(bytes, offset + 4);
      final chunkDataStart = offset + 8;
      if (chunkId == 'fmt ' &&
          chunkSize >= 16 &&
          chunkDataStart + 16 <= bytes.length) {
        byteRate = _readUint32LE(bytes, chunkDataStart + 8);
        blockAlign = _readUint16LE(bytes, chunkDataStart + 12);
      }
      if (chunkId == 'data') {
        dataOffset = chunkDataStart;
        dataSizeOffset = offset + 4;
        final available = bytes.length - dataOffset;
        dataSize = chunkSize <= available ? chunkSize : available;
        break;
      }
      offset = chunkDataStart + chunkSize;
      if (chunkSize.isOdd) {
        offset += 1;
      }
    }

    if (dataOffset == null ||
        dataSize == null ||
        dataSizeOffset == null ||
        byteRate == null ||
        blockAlign == null ||
        byteRate <= 0 ||
        blockAlign <= 0) {
      return bytes;
    }

    final maxDataBytes = byteRate * maxSeconds;
    if (maxDataBytes <= 0 || maxDataBytes >= dataSize) {
      return bytes;
    }
    final trimmedSize = (maxDataBytes ~/ blockAlign) * blockAlign;
    if (trimmedSize <= 0) return bytes;

    final newLength = dataOffset + trimmedSize;
    final trimmed = Uint8List(newLength);
    trimmed.setRange(0, dataOffset, bytes);
    trimmed.setRange(
      dataOffset,
      newLength,
      bytes.sublist(dataOffset, dataOffset + trimmedSize),
    );
    final header = ByteData.view(trimmed.buffer);
    header.setUint32(4, newLength - 8, Endian.little);
    header.setUint32(dataSizeOffset, trimmedSize, Endian.little);
    debugPrint('🟣 PIAPI TTS: референс WAV обрезан до $trimmedSize байт');
    return trimmed;
  }

  bool _matchesFourCC(Uint8List bytes, int offset, String value) {
    final units = value.codeUnits;
    if (offset + units.length > bytes.length) return false;
    for (var i = 0; i < units.length; i++) {
      if (bytes[offset + i] != units[i]) return false;
    }
    return true;
  }

  String _readFourCC(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return '';
    return String.fromCharCodes(bytes.sublist(offset, offset + 4));
  }

  int _readUint16LE(Uint8List bytes, int offset) {
    if (offset + 2 > bytes.length) return 0;
    return ByteData.sublistView(bytes, offset, offset + 2)
        .getUint16(0, Endian.little);
  }

  int _readUint32LE(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.little);
  }

  Future<File> _saveAudioBytes(
    Uint8List bytes,
    String url,
    String? contentType,
  ) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory(path.join(baseDir.path, 'voice_messages'));
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }
    final extension = _guessAudioExtension(url, contentType);
    final fileName =
        'voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final filePath = path.join(voiceDir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _guessAudioExtension(String url, String? contentType) {
    final lower = url.toLowerCase();
    if (lower.endsWith('.mp3')) return 'mp3';
    if (lower.endsWith('.wav')) return 'wav';
    if (lower.endsWith('.ogg') || lower.endsWith('.opus')) return 'ogg';
    final type = (contentType ?? '').toLowerCase();
    if (type.contains('audio/mpeg')) return 'mp3';
    if (type.contains('audio/wav') || type.contains('audio/x-wav')) {
      return 'wav';
    }
    if (type.contains('audio/ogg') || type.contains('opus')) return 'ogg';
    return 'mp3';
  }

  String _truncateText(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final sliced = text.substring(0, maxChars);
    final lastSpace = sliced.lastIndexOf(' ');
    if (lastSpace > maxChars * 0.6) {
      return sliced.substring(0, lastSpace).trim();
    }
    return sliced.trim();
  }

  static String? _normalizeServiceMode(String? value) {
    final raw = value?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (raw == 'public' || raw == 'private') return raw;
    return null;
  }
}

class _AudioBytes {
  final Uint8List bytes;
  final String? contentType;

  const _AudioBytes({required this.bytes, this.contentType});
}

class _PiApiTtsSnapshot {
  final String? taskId;
  final String? status;
  final String? audioUrl;
  final String? errorMessage;

  const _PiApiTtsSnapshot({
    this.taskId,
    this.status,
    this.audioUrl,
    this.errorMessage,
  });

  bool get isCompleted {
    final value = (status ?? '').toLowerCase();
    return value == 'completed' || value == 'success' || value == 'succeeded';
  }

  bool get isFailed {
    final value = (status ?? '').toLowerCase();
    return value == 'failed' || value == 'error';
  }

  factory _PiApiTtsSnapshot.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return const _PiApiTtsSnapshot(
        errorMessage: 'Некорректный ответ сервера.',
      );
    }
    final data = json['data'];
    final payload = data is Map<String, dynamic> ? data : json;
    final output = payload['output'];
    String? audioUrl;
    if (output is Map<String, dynamic>) {
      final directUrl = output['audio_url'] ?? output['audioUrl'];
      if (directUrl is String && directUrl.isNotEmpty) {
        audioUrl = directUrl;
      }
    }
    audioUrl ??= payload['audio_url'] as String?;
    audioUrl ??= payload['audioUrl'] as String?;
    String? errorMessage;
    final error = payload['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        errorMessage = message;
      }
    }
    return _PiApiTtsSnapshot(
      taskId: payload['task_id'] as String?,
      status: payload['status'] as String?,
      audioUrl: audioUrl,
      errorMessage: errorMessage,
    );
  }
}
