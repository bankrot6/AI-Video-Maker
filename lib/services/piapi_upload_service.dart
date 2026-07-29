import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:socks5_proxy/socks_client.dart';

class PiApiUploadService {
  PiApiUploadService({
    String? apiKey,
    String? uploadUrl,
    Duration? timeout,
  })  : _apiKey = apiKey ?? dotenv.env['PIAPI_API_KEY'],
        _uploadUrl = uploadUrl ??
            dotenv.env['PIAPI_UPLOAD_URL'] ??
            'https://upload.theapi.app/api/ephemeral_resource',
        _timeout = timeout ?? const Duration(seconds: 60),
        _uploadProxy = _ProxyConfig.tryParse(dotenv.env['PIAPI_IMAGE_PROXY']?.trim());

  final String? _apiKey;
  final String _uploadUrl;
  final Duration _timeout;
  final _ProxyConfig? _uploadProxy;

  static const int maxBytes = 8 * 1024 * 1024;

  Future<String?> uploadImage(File file) async {
    debugPrint('PiApiUpload: начинаем загрузку ${file.path}');
    if (!file.existsSync()) {
      debugPrint('PiApiUpload: файл не существует');
      return null;
    }
    try {
      var bytes = await file.readAsBytes();
      final sizeMB = bytes.length / (1024 * 1024);
      debugPrint('PiApiUpload: размер файла ${sizeMB.toStringAsFixed(2)}MB');
      
      var fileName = path.basename(file.path);
      final ext = path.extension(fileName).toLowerCase();
      
      if (ext == '.heic' || ext == '.heif') {
        debugPrint('PiApiUpload: конвертируем HEIC в JPG...');
        final image = img.decodeImage(bytes);
        if (image == null) {
          debugPrint('PiApiUpload: не удалось декодировать HEIC');
          return null;
        }
        bytes = img.encodeJpg(image, quality: 85);
        fileName = fileName.replaceAll(RegExp(r'\.(heic|heif)$', caseSensitive: false), '.jpg');
        debugPrint('PiApiUpload: конвертировано в JPG, новый размер ${(bytes.length / (1024 * 1024)).toStringAsFixed(2)}MB');
      } else if (ext == '.png') {
        debugPrint('PiApiUpload: оптимизируем PNG → JPG...');
        final image = img.decodeImage(bytes);
        if (image == null) {
          debugPrint('PiApiUpload: не удалось декодировать PNG');
          return null;
        }
        bytes = img.encodeJpg(image, quality: 85);
        fileName = '${path.basenameWithoutExtension(fileName)}.jpg';
        debugPrint('PiApiUpload: PNG→JPG, новый размер ${(bytes.length / (1024 * 1024)).toStringAsFixed(2)}MB');
      } else if (ext != '.jpg' && ext != '.jpeg' && ext != '.webp') {
        debugPrint('PiApiUpload: неподдерживаемый формат $ext, конвертируем в JPG...');
        final image = img.decodeImage(bytes);
        if (image == null) {
          debugPrint('PiApiUpload: не удалось декодировать изображение');
          return null;
        }
        bytes = img.encodeJpg(image, quality: 85);
        fileName = '${path.basenameWithoutExtension(fileName)}.jpg';
        debugPrint('PiApiUpload: конвертировано в JPG');
      }
      
      if (bytes.length > maxBytes) {
        debugPrint('PiApiUpload: файл больше ${maxBytes ~/ (1024 * 1024)}MB после конвертации');
        return null;
      }
      
      debugPrint('PiApiUpload: имя файла $fileName');
      final payload = <String, dynamic>{
        'file_name': fileName,
        'file_data': base64Encode(bytes),
      };
      final headers = _headers();
      debugPrint('PiApiUpload: POST $_uploadUrl через ${_uploadProxy != null ? "SOCKS прокси" : "прямое соединение"}');
      
      final client = _createUploadClient();
      final response = await client
          .post(
            Uri.parse(_uploadUrl),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(_timeout);
      client.close();
      
      debugPrint('PiApiUpload: HTTP ${response.statusCode}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('PiApiUpload: ответ: ${response.body}');
        return null;
      }
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) {
        final data = json['data'];
        if (data is Map<String, dynamic>) {
          final url = data['url'];
          if (url is String && url.isNotEmpty) {
            debugPrint('PiApiUpload: успешно загружено, URL=$url');
            return url;
          }
        }
      }
      debugPrint('PiApiUpload: URL не найден в ответе: ${response.body}');
    } catch (e, st) {
      debugPrint('PiApiUpload: ошибка $e');
      debugPrint('PiApiUpload: $st');
    }
    return null;
  }

  Map<String, String> _headers() {
    final h = <String, String>{'Content-Type': 'application/json'};
    final key = _apiKey?.trim();
    if (key != null && key.isNotEmpty) h['x-api-key'] = key;
    return h;
  }

  http.Client _createUploadClient() {
    final proxy = _uploadProxy;
    if (proxy == null) {
      debugPrint('PiApiUpload: прокси не настроен, используем прямое соединение');
      return http.Client();
    }
    if (proxy.kind == _ProxyKind.socks5) {
      final address = InternetAddress.tryParse(proxy.host);
      if (address == null) {
        debugPrint('PiApiUpload: SOCKS прокси требует IP-адрес хоста');
        return http.Client();
      }
      debugPrint('PiApiUpload: используем SOCKS5 прокси ${proxy.host}:${proxy.port}');
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
    debugPrint('PiApiUpload: используем HTTP прокси ${proxy.host}:${proxy.port}');
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
}

enum _ProxyKind { socks5, http }

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
