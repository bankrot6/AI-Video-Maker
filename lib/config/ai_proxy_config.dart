import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'photosession_backend.dart';

/// Возвращает конфигурацию nginx AI-прокси (нидерландский сервер).
/// Прокси активен только при [useAppwriteBackend] == true и заполненных полях .env.
class AiProxyConfig {
  AiProxyConfig._();

  static String? _relayBaseUrl() {
    final value = dotenv.env['YANDEX_AI_RELAY_BASE_URL']?.trim() ?? '';
    return value.isEmpty ? null : _trimTrailingSlashes(value);
  }

  static String _trimTrailingSlashes(String value) {
    var result = value;
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String _trimLeadingSlashes(String value) {
    var result = value;
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    return result;
  }

  static String? _base() {
    if (!useAppwriteBackend()) return null;
    final host = dotenv.env['NL_SERVER_HOST']?.trim() ?? '';
    if (host.isEmpty) return null;
    return 'http://$host';
  }

  static String? _nlBase() {
    final host = dotenv.env['NL_SERVER_HOST']?.trim() ?? '';
    if (host.isEmpty) return null;
    return 'http://$host';
  }

  static String? get token {
    final t = dotenv.env['NL_PROXY_TOKEN']?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  static int get _piApiPort {
    final p = int.tryParse(dotenv.env['AI_PROXY_PIAPI_PORT']?.trim() ?? '');
    return p ?? 8080;
  }

  static int get _deepSeekPort {
    final p = int.tryParse(dotenv.env['AI_PROXY_DEEPSEEK_PORT']?.trim() ?? '');
    return p ?? 8001;
  }

  static String? _buildRelayUrl(int port, String path) {
    final relayBaseUrl = _relayBaseUrl();
    if (relayBaseUrl == null) return null;
    return '$relayBaseUrl/$port/${_trimLeadingSlashes(path)}';
  }

  static String? _buildTokenizedRelayUrl(int port, String path) {
    final t = token;
    if (t == null) return null;
    return _buildRelayUrl(port, 'ai-$t/${_trimLeadingSlashes(path)}');
  }

  /// URL задач PiAPI: http://NL_HOST:8080/ai-{TOKEN}/piapi/api/v1/task
  /// Возвращает null → сервисы используют значение из PIAPI_TASK_URL / дефолт.
  static String? piApiTaskUrl() {
    final relay = _buildTokenizedRelayUrl(_piApiPort, '/piapi/api/v1/task');
    if (relay != null) return relay;
    final b = _base();
    final t = token;
    if (b == null || t == null) return null;
    return '$b:$_piApiPort/ai-$t/piapi/api/v1/task';
  }

  /// URL загрузки изображений PiAPI: http://NL_HOST:8080/ai-{TOKEN}/piapi-upload/api/ephemeral_resource
  static String? piApiUploadUrl() {
    final relay = _buildTokenizedRelayUrl(
        _piApiPort, '/piapi-upload/api/ephemeral_resource');
    if (relay != null) return relay;
    final b = _base();
    final t = token;
    if (b == null || t == null) return null;
    return '$b:$_piApiPort/ai-$t/piapi-upload/api/ephemeral_resource';
  }

  /// Базовый URL DeepSeek: http://NL_HOST:8001
  /// DeepSeek использует абсолютные пути (/chat/completions), поэтому выделен
  /// отдельный порт, чтобы nginx мог форвардить без префикса.
  static String? deepSeekBaseUrl() {
    final relay = _buildRelayUrl(_deepSeekPort, '/chat/completions');
    if (relay != null) {
      return _trimTrailingSlashes(
          relay.substring(0, relay.length - '/chat/completions'.length));
    }
    final b = _base();
    if (b == null) return null;
    return '$b:$_deepSeekPort';
  }

  /// Базовый URL для ElevenLabs TTS:
  /// http://NL_HOST:8080/ai-{TOKEN}/elevenlabs
  /// nginx проксирует на https://api.elevenlabs.io/
  static String? elevenLabsBaseUrl() {
    final relay = _buildTokenizedRelayUrl(_piApiPort, '/elevenlabs');
    if (relay != null) return relay;
    final b = _base();
    final t = token;
    if (b == null || t == null) return null;
    return '$b:$_piApiPort/ai-$t/elevenlabs';
  }

  static String? apiBostBaseUrl() {
    final relay = _buildTokenizedRelayUrl(_piApiPort, '/apibost');
    if (relay != null) return relay;
    final b = _base();
    final t = token;
    if (b == null || t == null) return null;
    return '$b:$_piApiPort/ai-$t/apibost';
  }

  /// Базовый URL image-прокси: http://NL_HOST:8080/ai-{TOKEN}/imgproxy
  /// Использование: GET `$base?url=...`
  /// nginx маршрутизирует на локальный Python-сервис (127.0.0.1:8002).
  /// Работает независимо от Appwrite — достаточно NL_SERVER_HOST + NL_PROXY_TOKEN.
  static String? imageProxyBaseUrl() {
    final relay = _buildTokenizedRelayUrl(_piApiPort, '/imgproxy');
    if (relay != null) return relay;
    final b = _nlBase();
    final t = token;
    if (b == null || t == null) return null;
    return '$b:$_piApiPort/ai-$t/imgproxy';
  }

  static String? googleCustomSearchV1Url() {
    final relay =
        _buildTokenizedRelayUrl(_piApiPort, '/google-cse/customsearch/v1');
    if (relay != null) return relay;
    final b = _base();
    final t = token;
    if (b == null || t == null) return null;
    return '$b:$_piApiPort/ai-$t/google-cse/customsearch/v1';
  }

  static bool get isEnabled => _base() != null && token != null;
}
