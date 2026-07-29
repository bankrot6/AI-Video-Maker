import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:socks5_proxy/socks_client.dart';

import '../utils/text_cleaner.dart';

class ElevenLabsVoice {
  final String id;
  final String voiceId;
  final String gender;
  final String ageGroup;
  final String languageCode;
  final String accent;

  const ElevenLabsVoice({
    required this.id,
    required this.voiceId,
    required this.gender,
    required this.ageGroup,
    required this.languageCode,
    this.accent = '',
  });

  factory ElevenLabsVoice.fromJson(Map<String, dynamic> json) {
    final voiceId = (json['voice_id'] ??
            json['voiceId'] ??
            json['id'] ??
            json['name'] ??
            '')
        .toString();
    return ElevenLabsVoice(
      id: (json['id'] ?? json['name'] ?? voiceId).toString(),
      voiceId: voiceId,
      gender: (json['gender'] ?? '').toString(),
      ageGroup: (json['age_group'] ?? json['ageGroup'] ?? json['age'] ?? '')
          .toString(),
      languageCode: (json['language'] ??
              json['languageCode'] ??
              json['locale'] ??
              'ru-RU')
          .toString(),
      accent: (json['accent'] ?? '').toString(),
    );
  }
}

class ElevenLabsTtsResult {
  final File? audioFile;
  final String? errorMessage;
  final ElevenLabsVoice? voice;

  const ElevenLabsTtsResult({this.audioFile, this.errorMessage, this.voice});

  bool get isSuccess => audioFile != null && errorMessage == null;
}

class ElevenLabsTtsService {
  static const int _maxTextChars = 1000;
  static const int _maxRedirects = 3;
  static const Duration _voicesTtl = Duration(minutes: 30);

  final String? _apiKey;
  final String _baseUrl;
  final String _modelId;
  final String _outputFormat;
  final Duration _timeout;
  final Map<String, dynamic>? _voiceSettings;
  final _ProxyConfig? _proxy;
  List<ElevenLabsVoice>? _cachedVoices;
  DateTime? _voicesFetchedAt;

  ElevenLabsTtsService({
    String? apiKey,
    String? baseUrl,
    String? modelId,
    String? outputFormat,
    Duration? timeout,
    Map<String, dynamic>? voiceSettings,
  })  : _apiKey = apiKey ?? dotenv.env['ELEVENLABS_API_KEY'],
        _baseUrl = baseUrl ??
            dotenv.env['ELEVENLABS_BASE_URL'] ??
            'https://api.elevenlabs.io',
        _modelId = modelId ??
            dotenv.env['ELEVENLABS_MODEL'] ??
            'eleven_multilingual_v2',
        _outputFormat = outputFormat ??
            dotenv.env['ELEVENLABS_OUTPUT_FORMAT'] ??
            'mp3_44100_128',
        _timeout = timeout ??
            Duration(
              seconds: _parseTimeoutSeconds(
                dotenv.env['ELEVENLABS_TIMEOUT_SEC'],
              ),
            ),
        _voiceSettings = voiceSettings ??
            _parseVoiceSettings(dotenv.env['ELEVENLABS_VOICE_SETTINGS']),
        _proxy = _ProxyConfig.tryParse(
          dotenv.env['PIAPI_IMAGE_PROXY']?.trim(),
        );

  Future<bool> isAvailable() async {
    final hasKey = (_apiKey ?? '').trim().isNotEmpty;
    final hasUrl = _baseUrl.trim().isNotEmpty;
    debugPrint('🟣 ELEVENLABS TTS: доступность key=$hasKey url=$hasUrl');
    return hasKey && hasUrl;
  }

  Future<ElevenLabsTtsResult> synthesize({
    required String text,
    required ElevenLabsVoice voice,
    Map<String, dynamic>? voiceSettings,
  }) async {
    final cleaned = TextCleaner.cleanForSpeechPreserveContent(text).trim();
    if (cleaned.isEmpty) {
      return const ElevenLabsTtsResult(
          errorMessage: 'Пустой текст для озвучки.');
    }
    if (!await isAvailable()) {
      return const ElevenLabsTtsResult(
        errorMessage: 'TTS сервис не настроен. Проверьте ключи .env.',
      );
    }
    final voiceId = voice.voiceId.trim();
    if (voiceId.isEmpty) {
      return const ElevenLabsTtsResult(errorMessage: 'Не задан voice_id.');
    }
    final safeText = _truncateText(cleaned, _maxTextChars);
    try {
      final response = await _postWithRedirect(
        _buildVoiceUrl(voiceId),
        headers: _buildHeaders(),
        body: jsonEncode(_buildPayload(safeText, voiceSettings: voiceSettings)),
      );
      final contentType = response.headers['content-type'] ?? '';
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = _extractErrorMessage(_decodeJson(response.body)) ??
            'Ошибка запроса: HTTP ${response.statusCode}';
        debugPrint('🟣 ELEVENLABS TTS: HTTP ${response.statusCode} $error');
        return ElevenLabsTtsResult(errorMessage: error);
      }
      if (contentType.contains('application/json')) {
        final error = _extractErrorMessage(_decodeJson(response.body));
        if (error != null && error.isNotEmpty) {
          return ElevenLabsTtsResult(errorMessage: error);
        }
      }
      if (response.bodyBytes.isEmpty) {
        return const ElevenLabsTtsResult(
          errorMessage: 'Модель не вернула аудио.',
        );
      }
      final file = await _saveAudioBytes(response.bodyBytes, contentType);
      return ElevenLabsTtsResult(audioFile: file, voice: voice);
    } catch (e) {
      debugPrint('🟣 ELEVENLABS TTS: ошибка синтеза: $e');
      return ElevenLabsTtsResult(errorMessage: 'Ошибка синтеза: $e');
    }
  }

  Uri _buildVoiceUrl(String voiceId) {
    var base = _baseUrl.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base/v1/text-to-speech/$voiceId');
  }

  Uri _buildVoicesUrl({String? pageToken, int pageSize = 100}) {
    var base = _baseUrl.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final params = <String, String>{
      'page_size': pageSize.toString(),
      'include_total_count': 'false',
    };
    if (pageToken != null && pageToken.isNotEmpty) {
      params['next_page_token'] = pageToken;
    }
    return Uri.parse('$base/v2/voices').replace(queryParameters: params);
  }

  Map<String, dynamic> _buildPayload(String text,
      {Map<String, dynamic>? voiceSettings}) {
    final payload = <String, dynamic>{
      'text': text,
      'model_id': _modelId,
      'output_format': _outputFormat,
    };
    final base = Map<String, dynamic>.from(_voiceSettings ?? {});
    if (voiceSettings != null && voiceSettings.isNotEmpty) {
      base.addAll(voiceSettings);
    }
    if (base.isNotEmpty) {
      payload['voice_settings'] = base;
    }
    return payload;
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': _acceptHeader(_outputFormat),
    };
    final key = _apiKey?.trim();
    if (key != null && key.isNotEmpty) {
      headers['xi-api-key'] = key;
    }
    return headers;
  }

  Future<List<ElevenLabsVoice>> fetchVoices({bool forceRefresh = false}) async {
    final now = DateTime.now();
    final cached = _cachedVoices;
    if (!forceRefresh &&
        cached != null &&
        _voicesFetchedAt != null &&
        now.difference(_voicesFetchedAt!) <= _voicesTtl) {
      return cached;
    }
    if (!await isAvailable()) return const [];
    try {
      final allVoices = <ElevenLabsVoice>[];
      String? pageToken;
      var hasMore = true;
      while (hasMore) {
        final response = await _getWithRedirect(
          _buildVoicesUrl(pageToken: pageToken),
          headers: _buildHeaders(),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final error = _extractErrorMessage(_decodeJson(response.body)) ??
              'Ошибка запроса: HTTP ${response.statusCode}';
          debugPrint('🟣 ELEVENLABS TTS: HTTP ${response.statusCode} $error');
          return cached ?? const [];
        }
        final json = _decodeJson(response.body);
        allVoices.addAll(_parseVoicesFromApi(json));
        if (json is Map<String, dynamic>) {
          hasMore = json['has_more'] == true;
          pageToken = json['next_page_token']?.toString();
          if (pageToken == null || pageToken.isEmpty) hasMore = false;
        } else {
          hasMore = false;
        }
      }
      _cachedVoices = allVoices;
      _voicesFetchedAt = DateTime.now();
      debugPrint(
        '🟣 ELEVENLABS TTS: v2 загружено ${allVoices.length} голосов',
      );
      for (final v in allVoices) {
        debugPrint(
          '🟣 ELEVENLABS TTS:   ${v.id} (${v.voiceId}) '
          'пол=${v.gender} возраст=${v.ageGroup} '
          'акцент=${v.accent} язык=${v.languageCode}',
        );
      }
      return allVoices;
    } catch (e) {
      debugPrint('🟣 ELEVENLABS TTS: ошибка загрузки голосов: $e');
      return cached ?? const [];
    }
  }

  Future<List<ElevenLabsVoice>> fetchSharedVoices({
    String? gender,
    String? age,
    String? language,
    String? accent,
    int pageSize = 30,
  }) async {
    if (!await isAvailable()) return const [];
    try {
      var base = _baseUrl.trim();
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);
      final params = <String, String>{
        'page_size': pageSize.toString(),
      };
      if (gender != null && gender.isNotEmpty) params['gender'] = gender;
      if (age != null && age.isNotEmpty) params['age'] = age;
      if (language != null && language.isNotEmpty) {
        params['language'] = language;
      }
      if (accent != null && accent.isNotEmpty) params['accent'] = accent;
      final url =
          Uri.parse('$base/v1/shared-voices').replace(queryParameters: params);
      debugPrint(
        '🟣 ELEVENLABS TTS: shared-voices запрос: '
        'gender=$gender age=$age language=$language',
      );
      final response = await _getWithRedirect(
        url,
        headers: _buildHeaders(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '🟣 ELEVENLABS TTS: shared-voices HTTP ${response.statusCode}',
        );
        return const [];
      }
      final json = _decodeJson(response.body);
      final voices = _parseSharedVoicesFromApi(json);
      debugPrint(
        '🟣 ELEVENLABS TTS: shared-voices найдено ${voices.length} голосов',
      );
      return voices;
    } catch (e) {
      debugPrint('🟣 ELEVENLABS TTS: shared-voices ошибка: $e');
      return const [];
    }
  }

  List<ElevenLabsVoice> _parseSharedVoicesFromApi(dynamic json) {
    if (json is! Map<String, dynamic>) return const [];
    final rawVoices = json['voices'];
    if (rawVoices is! List) return const [];
    final voices = <ElevenLabsVoice>[];
    for (final entry in rawVoices) {
      if (entry is! Map<String, dynamic>) continue;
      final voiceId = (entry['voice_id'] ?? '').toString();
      if (voiceId.isEmpty) continue;
      final gender = _normalizeGender(entry['gender']?.toString());
      final ageGroup = _normalizeAgeGroup(entry['age']?.toString());
      final accent = entry['accent']?.toString() ?? '';
      final language = _normalizeLanguage(entry['language']?.toString()) ??
          _normalizeLanguage(entry['locale']?.toString()) ??
          _normalizeLanguage(accent);
      voices.add(
        ElevenLabsVoice(
          id: (entry['name'] ?? voiceId).toString(),
          voiceId: voiceId,
          gender: gender ?? '',
          ageGroup: ageGroup ?? '',
          languageCode: language ?? '',
          accent: accent,
        ),
      );
    }
    return voices;
  }

  Future<ElevenLabsVoice?> fetchVoiceById(String voiceId) async {
    final id = voiceId.trim();
    if (id.isEmpty) return null;
    if (!await isAvailable()) return null;
    try {
      var base = _baseUrl.trim();
      if (base.endsWith('/')) base = base.substring(0, base.length - 1);
      final url = Uri.parse('$base/v1/voices/$id');
      final response = await _getWithRedirect(
        url,
        headers: _buildHeaders(),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '🟣 ELEVENLABS TTS: fetchVoiceById $id → '
          'HTTP ${response.statusCode}',
        );
        return null;
      }
      final json = _decodeJson(response.body);
      if (json is! Map<String, dynamic>) return null;
      final resolvedId = (json['voice_id'] ?? json['voiceId'] ?? id).toString();
      final labelsRaw = json['labels'];
      final labels = labelsRaw is Map
          ? Map<String, dynamic>.from(labelsRaw)
          : const <String, dynamic>{};
      final gender = _normalizeGender(labels['gender']?.toString());
      final ageGroup = _normalizeAgeGroup(
        labels['age_group']?.toString() ?? labels['age']?.toString(),
      );
      final accent = labels['accent']?.toString() ?? '';
      var language = _normalizeLanguage(labels['language']?.toString()) ??
          _normalizeLanguage(labels['locale']?.toString()) ??
          _normalizeLanguage(accent);
      if (language == null || language.isEmpty) {
        language = _extractLanguageFromVerified(json['verified_languages']);
      }
      debugPrint(
        '🟣 ELEVENLABS TTS: fetchVoiceById $id → '
        'пол=${gender ?? "?"} возраст=${ageGroup ?? "?"} '
        'акцент=$accent язык=${language ?? "?"}',
      );
      return ElevenLabsVoice(
        id: (json['name'] ?? id).toString(),
        voiceId: resolvedId,
        gender: gender ?? '',
        ageGroup: ageGroup ?? '',
        languageCode: language ?? '',
        accent: accent,
      );
    } catch (e) {
      debugPrint('🟣 ELEVENLABS TTS: fetchVoiceById $id ошибка: $e');
      return null;
    }
  }

  String _acceptHeader(String format) {
    final lower = format.toLowerCase();
    if (lower.contains('wav')) return 'audio/wav';
    if (lower.contains('ogg') || lower.contains('opus')) return 'audio/ogg';
    return 'audio/mpeg';
  }

  Future<http.Response> _postWithRedirect(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final client = _createHttpClient();
    try {
      var response = await client
          .post(url, headers: headers, body: body)
          .timeout(_timeout);
      var redirectCount = 0;
      while (
          _isRedirect(response.statusCode) && redirectCount < _maxRedirects) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) break;
        final next = Uri.parse(location);
        final resolved = next.isAbsolute ? next : url.resolveUri(next);
        debugPrint(
          '🟣 ELEVENLABS TTS: redirect ${response.statusCode} -> $resolved',
        );
        if (response.statusCode == 303) {
          response =
              await client.get(resolved, headers: headers).timeout(_timeout);
        } else {
          response = await client
              .post(resolved, headers: headers, body: body)
              .timeout(_timeout);
        }
        url = resolved;
        redirectCount++;
      }
      return response;
    } finally {
      client.close();
    }
  }

  Future<http.Response> _getWithRedirect(
    Uri url, {
    required Map<String, String> headers,
  }) async {
    final client = _createHttpClient();
    try {
      var response = await client.get(url, headers: headers).timeout(_timeout);
      var redirectCount = 0;
      while (
          _isRedirect(response.statusCode) && redirectCount < _maxRedirects) {
        final location = response.headers['location'];
        if (location == null || location.isEmpty) break;
        final next = Uri.parse(location);
        final resolved = next.isAbsolute ? next : url.resolveUri(next);
        debugPrint(
          '🟣 ELEVENLABS TTS: redirect ${response.statusCode} -> $resolved',
        );
        response =
            await client.get(resolved, headers: headers).timeout(_timeout);
        url = resolved;
        redirectCount++;
      }
      return response;
    } finally {
      client.close();
    }
  }

  http.Client _createHttpClient() {
    final proxy = _proxy;
    if (proxy == null) {
      return http.Client();
    }
    if (proxy.kind == _ProxyKind.socks5) {
      final address = InternetAddress.tryParse(proxy.host);
      if (address == null) {
        debugPrint(
          '🟣 ELEVENLABS TTS: SOCKS прокси требует IP-адрес хоста',
        );
        return http.Client();
      }
      final httpClient = HttpClient();
      SocksTCPClient.assignToHttpClientWithSecureOptions(
        httpClient,
        [
          ProxySettings(
            address,
            proxy.port,
            username: proxy.username,
            password: proxy.password,
          ),
        ],
      );
      return IOClient(httpClient);
    }
    final httpClient = HttpClient();
    httpClient.findProxy = (_) => proxy.proxyRule;
    final username = proxy.username;
    if (username != null && username.isNotEmpty) {
      httpClient.authenticateProxy = (host, port, scheme, realm) async {
        if (host != proxy.host || port != proxy.port) return false;
        final safeRealm = realm ?? '';
        httpClient.addProxyCredentials(
          host,
          port,
          safeRealm,
          HttpClientBasicCredentials(username, proxy.password ?? ''),
        );
        return true;
      };
    }
    return IOClient(httpClient);
  }

  bool _isRedirect(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
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
      final detail = json['detail'];
      if (detail is Map<String, dynamic>) {
        final message = detail['message'];
        if (message is String && message.isNotEmpty) return message;
      }
      final message = json['message'];
      if (message is String && message.isNotEmpty) return message;
      final error = json['error'];
      if (error is String && error.isNotEmpty) return error;
    }
    return null;
  }

  List<ElevenLabsVoice> _parseVoicesFromApi(dynamic json) {
    if (json is! Map<String, dynamic>) return const [];
    final rawVoices = json['voices'];
    if (rawVoices is! List) return const [];
    final voices = <ElevenLabsVoice>[];
    for (final entry in rawVoices) {
      if (entry is! Map<String, dynamic>) continue;
      final voiceId = (entry['voice_id'] ?? entry['voiceId'] ?? '').toString();
      if (voiceId.isEmpty) continue;
      final labelsRaw = entry['labels'];
      final labels = labelsRaw is Map
          ? Map<String, dynamic>.from(labelsRaw)
          : const <String, dynamic>{};
      final gender = _normalizeGender(labels['gender']?.toString());
      final ageGroup = _normalizeAgeGroup(
        labels['age_group']?.toString() ?? labels['age']?.toString(),
      );
      final accent = labels['accent']?.toString() ?? '';
      var language = _normalizeLanguage(labels['language']?.toString()) ??
          _normalizeLanguage(labels['locale']?.toString()) ??
          _normalizeLanguage(accent);
      if (language == null || language.isEmpty) {
        language = _extractLanguageFromVerified(entry['verified_languages']);
      }
      voices.add(
        ElevenLabsVoice(
          id: (entry['name'] ?? voiceId).toString(),
          voiceId: voiceId,
          gender: gender ?? '',
          ageGroup: ageGroup ?? '',
          languageCode: language ?? '',
          accent: accent,
        ),
      );
    }
    return voices;
  }

  String? _extractLanguageFromVerified(dynamic verifiedLanguages) {
    if (verifiedLanguages is! List) return null;
    for (final lang in verifiedLanguages) {
      if (lang is! Map<String, dynamic>) continue;
      final locale = lang['locale']?.toString();
      if (locale != null) {
        final normalized = _normalizeLanguage(locale);
        if (normalized != null) return normalized;
      }
      final language = lang['language']?.toString();
      if (language != null) {
        final normalized = _normalizeLanguage(language);
        if (normalized != null) return normalized;
      }
    }
    return null;
  }

  Future<File> _saveAudioBytes(Uint8List bytes, String? contentType) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final voiceDir = Directory(path.join(baseDir.path, 'voice_messages'));
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }
    final extension = _guessAudioExtension(_outputFormat, contentType);
    final fileName =
        'voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final filePath = path.join(voiceDir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _guessAudioExtension(String format, String? contentType) {
    final lower = format.toLowerCase();
    if (lower.contains('wav')) return 'wav';
    if (lower.contains('ogg') || lower.contains('opus')) return 'ogg';
    if (lower.contains('mp3')) return 'mp3';
    final type = (contentType ?? '').toLowerCase();
    if (type.contains('audio/wav') || type.contains('audio/x-wav')) {
      return 'wav';
    }
    if (type.contains('audio/ogg') || type.contains('opus')) return 'ogg';
    if (type.contains('audio/mpeg')) return 'mp3';
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

  String? _normalizeGender(String? value) {
    final raw = value?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('m')) return 'male';
    if (raw.startsWith('f')) return 'female';
    if (raw == 'man') return 'male';
    if (raw == 'woman') return 'female';
    return raw;
  }

  String? _normalizeAgeGroup(String? value) {
    final raw = value?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (raw.contains('teen') || raw.contains('youth')) return 'young';
    if (raw.contains('young')) return 'young';
    if (raw.contains('adult')) return 'adult';
    if (raw.contains('middle')) return 'adult';
    if (raw.contains('mature') ||
        raw.contains('senior') ||
        raw.contains('old')) {
      return 'mature';
    }
    return raw;
  }

  String? _normalizeLanguage(String? value) {
    final raw = value?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return null;
    if (raw == 'ru' || raw.startsWith('ru-') || raw.contains('russian')) {
      return 'ru-RU';
    }
    if (raw == 'en' || raw.startsWith('en-') || raw.contains('english')) {
      return 'en-US';
    }
    return raw;
  }

  static int _parseTimeoutSeconds(String? raw) {
    final parsed = int.tryParse((raw ?? '').trim());
    if (parsed != null && parsed > 0) return parsed;
    return 60;
  }

  static Map<String, dynamic>? _parseVoiceSettings(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (e) {
      debugPrint('🟣 ELEVENLABS TTS: ошибка настроек: $e');
    }
    return null;
  }
}

enum _ProxyKind { http, socks5 }

class _ProxyConfig {
  final _ProxyKind kind;
  final String host;
  final int port;
  final String? username;
  final String? password;

  _ProxyConfig({
    required this.kind,
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  String get proxyRule => 'PROXY $host:$port';

  static _ProxyConfig? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    var value = raw.trim();
    if (!value.contains('://')) {
      value = 'socks5://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || uri.port == 0) return null;
    final scheme = uri.scheme.toLowerCase();
    final kind = switch (scheme) {
      'socks5' || 'socks' => _ProxyKind.socks5,
      'http' || 'https' => _ProxyKind.http,
      _ => _ProxyKind.http,
    };
    String? username;
    String? password;
    if (uri.userInfo.isNotEmpty) {
      final parts = uri.userInfo.split(':');
      username = parts.first;
      if (parts.length > 1) {
        password = parts.sublist(1).join(':');
      }
    }
    return _ProxyConfig(
      kind: kind,
      host: uri.host,
      port: uri.port,
      username: username?.trim().isEmpty == true ? null : username,
      password: password?.trim().isEmpty == true ? null : password,
    );
  }
}
