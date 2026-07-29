import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:socks5_proxy/socks_client.dart';

class InstagramScraperService {
  InstagramScraperService();

  String? get _rapidApiKey => dotenv.env['RAPIDAPI_KEY'];
  String? get _proxyUrl => dotenv.env['PIAPI_IMAGE_PROXY']?.trim();

  http.Client _createClient() {
    final raw = _proxyUrl;
    if (raw == null || raw.isEmpty) return http.Client();

    var value = raw;
    if (!value.contains('://')) value = 'socks5://$value';
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || uri.port == 0) return http.Client();

    final address = InternetAddress.tryParse(uri.host);
    if (address == null) return http.Client();

    String? username;
    String? password;
    if (uri.userInfo.isNotEmpty) {
      final parts = uri.userInfo.split(':');
      username = parts.first.isEmpty ? null : parts.first;
      if (parts.length > 1) {
        password = parts.sublist(1).join(':');
        if (password.isEmpty) password = null;
      }
    }

    final httpClient = HttpClient();
    SocksTCPClient.assignToHttpClientWithSecureOptions(
      httpClient,
      [
        ProxySettings(
          address,
          uri.port,
          username: username,
          password: password,
        ),
      ],
    );
    return IOClient(httpClient);
  }

  Future<InstagramMediaResult?> getMediaFromPost(String inputUrl) async {
    final trimmed = inputUrl.trim();

    if (_isDirectImageUrl(trimmed)) {
      debugPrint('📥 Instagram: прямой URL изображения');
      return InstagramMediaResult(mediaUrl: trimmed);
    }

    final shortcode = _extractShortcode(trimmed);
    if (shortcode == null) {
      throw Exception('Неверный формат ссылки.\nПример: instagram.com/p/ABC123/');
    }

    final postUrl = 'https://www.instagram.com/p/$shortcode/';
    debugPrint('📥 Instagram: загрузка поста $shortcode');

    final key = _rapidApiKey;
    if (key != null && key.isNotEmpty) {
      final r1 = await _tryDownloader38(postUrl, key);
      if (r1 != null) return r1;

      final r2 = await _tryAioDownloader(postUrl, key);
      if (r2 != null) return r2;
    }

    throw Exception(
      'Не удалось загрузить фото из Instagram.\n\n'
      'Попробуйте:\n'
      '• Откройте пост в браузере\n'
      '• Нажмите и удерживайте фото\n'
      '• Выберите "Копировать адрес изображения"\n'
      '• Вставьте этот URL',
    );
  }

  Future<InstagramMediaResult?> _tryDownloader38(
      String postUrl, String key) async {
    const host = 'instagram-downloader38.p.rapidapi.com';
    final client = _createClient();
    try {
      debugPrint('🔄 Instagram: попытка через $host');
      final uri = Uri.https(host, '/download', {'url': postUrl});
      final response = await client.get(
        uri,
        headers: {
          'X-RapidAPI-Key': key,
          'X-RapidAPI-Host': host,
        },
      ).timeout(const Duration(seconds: 20));

      debugPrint('📊 $host статус: ${response.statusCode}');
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final url = _extractImageUrl(data);
      if (url != null) {
        debugPrint('✅ $host: найдено изображение');
        return InstagramMediaResult(mediaUrl: url);
      }
    } catch (e) {
      debugPrint('⚠️ $host ошибка: $e');
    } finally {
      client.close();
    }
    return null;
  }

  Future<InstagramMediaResult?> _tryAioDownloader(
      String postUrl, String key) async {
    const host = 'aio-instagram-downloader.p.rapidapi.com';
    final client = _createClient();
    try {
      debugPrint('🔄 Instagram: попытка через $host');
      final uri = Uri.https(host, '/api/download');
      final response = await client.post(
        uri,
        headers: {
          'X-RapidAPI-Key': key,
          'X-RapidAPI-Host': host,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'url': postUrl}),
      ).timeout(const Duration(seconds: 20));

      debugPrint('📊 $host статус: ${response.statusCode}');
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final url = _extractImageUrl(data);
      if (url != null) {
        debugPrint('✅ $host: найдено изображение');
        return InstagramMediaResult(mediaUrl: url);
      }
    } catch (e) {
      debugPrint('⚠️ $host ошибка: $e');
    } finally {
      client.close();
    }
    return null;
  }

  String? _extractImageUrl(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      for (final key in [
        'url', 'download_url', 'image_url', 'media_url', 'src',
        'thumbnail', 'image', 'link', 'display_url',
      ]) {
        final val = data[key];
        if (val is String && _looksLikeImageUrl(val)) return val;
      }
      for (final key in ['data', 'result', 'media', 'items']) {
        final nested = data[key];
        final r = _extractImageUrl(nested);
        if (r != null) return r;
      }
    }
    if (data is List && data.isNotEmpty) {
      return _extractImageUrl(data.first);
    }
    return null;
  }

  bool _looksLikeImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http') &&
        (lower.contains('.jpg') ||
            lower.contains('.jpeg') ||
            lower.contains('.png') ||
            lower.contains('.webp') ||
            lower.contains('cdninstagram') ||
            lower.contains('fbcdn') ||
            lower.contains('scontent'));
  }

  bool _isDirectImageUrl(String url) {
    final lower = url.toLowerCase();
    return (lower.startsWith('http://') || lower.startsWith('https://')) &&
        !lower.contains('instagram.com/p/') &&
        !lower.contains('instagram.com/reel/') &&
        !lower.contains('instagram.com/tv/') &&
        _looksLikeImageUrl(lower);
  }

  String? _extractShortcode(String url) {
    final pattern = RegExp(
      r'(?:https?://)?(?:www\.)?instagram\.com/(?:p|reel|tv)/([^/?#\s]+)',
    );
    return pattern.firstMatch(url.trim())?.group(1);
  }

  bool isValidInput(String url) {
    final trimmed = url.trim();
    return _isDirectImageUrl(trimmed) || _extractShortcode(trimmed) != null;
  }

  bool isValidInstagramUrl(String url) => isValidInput(url);
}

class InstagramMediaResult {
  final String mediaUrl;
  final String? caption;
  final int? likes;
  final int? comments;

  InstagramMediaResult({
    required this.mediaUrl,
    this.caption,
    this.likes,
    this.comments,
  });
}
