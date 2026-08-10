import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:socks5_proxy/socks_client.dart';
import 'deepseek_config.dart';
import 'deepseek_exception.dart';

/// Тестовый API ключ DeepSeek для случаев, когда ключ отсутствует в .env
const String _testDeepSeekApiKey = 'sk-test-deepseek-key-12345';

/// Кэш для хранения результатов запросов к DeepSeek API
/// Ключ - хэш запроса, значение - результат запроса
class _RequestCache {
  final Map<String, String> _cache = {};
  final int _maxCacheSize;
  final Duration _cacheTtl;
  final Map<String, DateTime> _cacheTimestamps = {};

  _RequestCache({
    int maxCacheSize = 100,
    Duration? cacheTtl,
  })  : _maxCacheSize = maxCacheSize,
        _cacheTtl = cacheTtl ?? const Duration(minutes: 30);

  /// Генерирует хэш запроса
  String _generateRequestHash(dynamic data) {
    final String serialized;
    if (data is String) {
      serialized = data;
    } else {
      serialized = jsonEncode(data);
    }
    return serialized.hashCode.toString();
  }

  /// Добавляет результат в кэш
  void add(dynamic request, String response) {
    if (_maxCacheSize <= 0) return;
    _cleanStaleEntries();

    // Если кэш полон, удаляем самую старую запись
    if (_cache.length >= _maxCacheSize && _cacheTimestamps.isNotEmpty) {
      final oldestKey = _cacheTimestamps.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _cache.remove(oldestKey);
      _cacheTimestamps.remove(oldestKey);
    }

    final hash = _generateRequestHash(request);
    _cache[hash] = response;
    _cacheTimestamps[hash] = DateTime.now();
  }

  /// Получает результат из кэша
  String? get(dynamic request) {
    if (_maxCacheSize <= 0) return null;
    _cleanStaleEntries();

    final hash = _generateRequestHash(request);
    return _cache[hash];
  }

  /// Проверяет, есть ли результат в кэше
  bool contains(dynamic request) {
    if (_maxCacheSize <= 0) return false;
    _cleanStaleEntries();

    final hash = _generateRequestHash(request);
    return _cache.containsKey(hash);
  }

  /// Очищает устаревшие записи
  void _cleanStaleEntries() {
    final now = DateTime.now();
    final expiredKeys = _cacheTimestamps.entries
        .where((entry) => now.difference(entry.value) > _cacheTtl)
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  /// Очищает весь кэш
  void clear() {
    _cache.clear();
    _cacheTimestamps.clear();
  }
}

/// Клиент для работы с DeepSeek API
class DeepSeekClient {
  final DeepSeekConfig config;
  final Dio _dio;
  final bool _returnEmptyOnError;
  final _RequestCache _cache;
  final _ProxyConfig? _proxyConfig;
  Dio? _proxyDio;
  final Duration _connectTimeout;
  final Duration _receiveTimeout;
  final Duration _sendTimeout;

  // Управление параллельными запросами
  final Map<String, Future<String>> _ongoingRequests = {};

  DeepSeekClient({
    required this.config,
    bool returnEmptyOnError = false,
    bool enableCaching = true,
    Duration? cacheTtl,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  })  : _connectTimeout =
            connectTimeout ?? Duration(seconds: config.fastMode ? 5 : 10),
        _receiveTimeout =
            receiveTimeout ?? Duration(seconds: config.fastMode ? 20 : 45),
        _sendTimeout =
            sendTimeout ?? Duration(seconds: config.fastMode ? 10 : 30),
        _dio = Dio(BaseOptions(
          baseUrl: config.baseUrl,
          headers: {
            'Authorization': 'Bearer ${config.apiKey}',
            'Content-Type': 'application/json',
            if (config.proxyToken != null && config.proxyToken!.isNotEmpty)
              'X-Ai-Proxy-Token': config.proxyToken!,
          },
          connectTimeout:
              connectTimeout ?? Duration(seconds: config.fastMode ? 5 : 10),
          receiveTimeout:
              receiveTimeout ?? Duration(seconds: config.fastMode ? 20 : 45),
          sendTimeout:
              sendTimeout ?? Duration(seconds: config.fastMode ? 10 : 30),
        )),
        _returnEmptyOnError = returnEmptyOnError,
        _cache = enableCaching
            ? _RequestCache(cacheTtl: cacheTtl)
            : _RequestCache(maxCacheSize: 0),
        _proxyConfig = _ProxyConfig.tryParse(dotenv.env['PIAPI_IMAGE_PROXY']) {
    _addRetryInterceptor(_dio);
  }

  /// Создает экземпляр клиента из переменных окружения
  factory DeepSeekClient.fromEnvironment({
    bool returnEmptyOnError = false,
    bool enableCaching = true,
    Duration? cacheTtl,
    bool fastMode = false, // Добавляем параметр быстрого режима
    String? model,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) {
    // Получаем ключ из .env файла или используем дефолтный тестовый ключ
    var apiKey = dotenv.env['DEEPSEEK_API_KEY'] ?? '';

    // убрали шумный лог ключа (безопасность/шум в консоли)

    // Если ключ отсутствует или является плейсхолдером, используем тестовый ключ
    if (apiKey.isEmpty ||
        apiKey == 'YOUR_ACTUAL_DEEPSEEK_API_KEY' ||
        apiKey == 'your_deepseek_api_key_here') {
      apiKey = _testDeepSeekApiKey;
    }

    return DeepSeekClient(
      config: DeepSeekConfig.fromEnvironment(
        apiKey,
        fastMode: fastMode,
        model: model,
      ),
      returnEmptyOnError: returnEmptyOnError,
      enableCaching: enableCaching,
      cacheTtl: cacheTtl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
    );
  }

  /// Отправляет запрос к API модели DeepSeek с текстовым промптом
  /// [prompt] - текстовый запрос к модели
  /// [tools] - необязательный список функций для Function Calling (новая возможность R1-0528)
  Future<String> generateText(String prompt,
      {List<Map<String, dynamic>>? tools}) async {
    final requestData = {
      ...config.toJson(),
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        },
      ],
    };

    // Добавляем поддержку Function Calling (новая функция R1-0528)
    if (tools != null && tools.isNotEmpty && config.enableFunctionCalling) {
      requestData['tools'] = tools;
      requestData['tool_choice'] =
          'auto'; // Позволяем модели решать, использовать ли функции
      debugPrint(
          '🔧 DEEPSEEK_CLIENT: Включен Function Calling с ${tools.length} функциями');
    }

    final requestHash = jsonEncode(requestData).hashCode.toString();

    // Проверяем, есть ли результат в кэше
    final cachedResult = _cache.get(requestData);
    if (cachedResult != null) {
      debugPrint(
          '🔄 DEEPSEEK_CLIENT: Использую кэшированный ответ для запроса');
      return cachedResult;
    }

    // Проверяем, выполняется ли уже такой запрос
    if (_ongoingRequests.containsKey(requestHash)) {
      debugPrint(
          '🔄 DEEPSEEK_CLIENT: Ожидание аналогичного запроса $requestHash');
      return await _ongoingRequests[requestHash]!;
    }

    // Создаем новый запрос и добавляем его в список выполняющихся
    final completer = Completer<String>();
    _ongoingRequests[requestHash] = completer.future;

    try {
      // debugPrint: убрали шумные логи сети

      final content = await _executeRequest(
        requestData,
        dio: _dio,
      );

      // debugPrint: убрали шумные логи сети
      if (content.startsWith('Function calling detected:')) {
        _cache.add(requestData, content);
        completer.complete(content);
        _ongoingRequests.remove(requestHash);
        return content;
      }

      // debugPrint: убрали шумные логи сети

      // Кэшируем результат
      _cache.add(requestData, content);

      // Завершаем и удаляем запрос из списка выполняющихся
      completer.complete(content);
      _ongoingRequests.remove(requestHash);

      return content;
    } on DioException catch (e) {
      debugPrint(
          '🔴 DEEPSEEK_CLIENT: Ошибка запроса к DeepSeek API: ${e.message}');
      final proxyDio = _maybeUseProxy(e);
      DioException finalError = e;
      if (proxyDio != null) {
        try {
          debugPrint(
              '🟣 DEEPSEEK_CLIENT: Повтор запроса через прокси после ошибки');
          final content = await _executeRequest(
            requestData,
            dio: proxyDio,
          );
          _cache.add(requestData, content);
          completer.complete(content);
          _ongoingRequests.remove(requestHash);
          return content;
        } on DioException catch (proxyError) {
          debugPrint(
              '🔴 DEEPSEEK_CLIENT: Ошибка через прокси: ${proxyError.message}');
          finalError = proxyError;
        } catch (proxyError) {
          debugPrint(
              '🔴 DEEPSEEK_CLIENT: Ошибка через прокси: ${proxyError.toString()}');
        }
      }

      String errorContent = '';

      if (_returnEmptyOnError) {
        debugPrint('🔴 DEEPSEEK_CLIENT: Возвращаем пустую строку из-за ошибки');
        errorContent = '';
      } else if (finalError.response != null) {
        throw DeepSeekException.fromJson(finalError.response!.data);
      } else {
        throw DeepSeekException(message: finalError.message ?? 'Unknown error');
      }

      // Завершаем и удаляем запрос из списка выполняющихся
      completer.complete(errorContent);
      _ongoingRequests.remove(requestHash);

      return errorContent;
    } catch (e) {
      debugPrint('🔴 DEEPSEEK_CLIENT: Неизвестная ошибка: ${e.toString()}');

      String errorContent = '';

      if (_returnEmptyOnError) {
        debugPrint('🔴 DEEPSEEK_CLIENT: Возвращаем пустую строку из-за ошибки');
        errorContent = '';
      } else {
        throw DeepSeekException(message: e.toString());
      }

      // Завершаем и удаляем запрос из списка выполняющихся
      completer.complete(errorContent);
      _ongoingRequests.remove(requestHash);

      return errorContent;
    }
  }

  /// Отправляет запрос к API модели DeepSeek с текстовым промптом и возвращает поток ответов
  /// [prompt] - текстовый запрос к модели
  /// [tools] - необязательный список функций для Function Calling
  /// Возвращает поток строк, которые можно отображать в реальном времени
  Stream<String> generateTextStream(String prompt,
      {List<Map<String, dynamic>>? tools}) async* {
    final requestData = {
      ...config.toJson(),
      'stream': true, // Включаем потоковый режим
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        },
      ],
    };

    // Добавляем поддержку Function Calling если нужно
    if (tools != null && tools.isNotEmpty && config.enableFunctionCalling) {
      requestData['tools'] = tools;
      requestData['tool_choice'] = 'auto';
      debugPrint(
          '🔧 DEEPSEEK_CLIENT: Включен Function Calling с ${tools.length} функциями для streaming');
    }

    try {
      yield* _executeStream(
        requestData,
        dio: _dio,
      );
    } on DioException catch (e) {
      debugPrint('🔴 DEEPSEEK_CLIENT: Ошибка streaming запроса: ${e.message}');
      final proxyDio = _maybeUseProxy(e);
      DioException finalError = e;
      if (proxyDio != null) {
        try {
          debugPrint(
              '🟣 DEEPSEEK_CLIENT: Повтор streaming через прокси после ошибки');
          yield* _executeStream(
            requestData,
            dio: proxyDio,
          );
          return;
        } on DioException catch (proxyError) {
          debugPrint(
              '🔴 DEEPSEEK_CLIENT: Ошибка streaming через прокси: ${proxyError.message}');
          finalError = proxyError;
        } catch (proxyError) {
          debugPrint(
              '🔴 DEEPSEEK_CLIENT: Ошибка streaming через прокси: ${proxyError.toString()}');
        }
      }

      if (!_returnEmptyOnError) {
        if (finalError.response != null) {
          throw DeepSeekException.fromJson(finalError.response!.data);
        } else {
          throw DeepSeekException(
              message: finalError.message ?? 'Streaming request failed');
        }
      }
    } catch (e) {
      debugPrint(
          '🔴 DEEPSEEK_CLIENT: Неизвестная ошибка в streaming: ${e.toString()}');

      if (!_returnEmptyOnError) {
        throw DeepSeekException(message: e.toString());
      }
    }
  }

  /// Парсит поток Server-Sent Events от DeepSeek API
  Stream<String> _parseSSEStream(Stream<dynamic> stream,
      {DateTime? requestStart}) async* {
    try {
      String buffer = '';
      bool firstContentSeen = false;

      final textStream = stream.map<List<int>>((chunk) {
        if (chunk is List<int>) return chunk;
        throw FormatException(
          'Unexpected SSE chunk type: ${chunk.runtimeType}',
        );
      }).transform(utf8.decoder);

      await for (final chunkString in textStream) {
        buffer += chunkString;

        // Обрабатываем все полные строки в буфере
        while (buffer.contains('\n')) {
          final lineEnd = buffer.indexOf('\n');
          final line = buffer.substring(0, lineEnd).trim();
          buffer = buffer.substring(lineEnd + 1);

          if (line.isEmpty) continue;

          if (line.startsWith('data:')) {
            final data = line.substring(5).trimLeft();

            // Проверяем на окончание потока
            if (data == '[DONE]') {
              debugPrint('🔴 DEEPSEEK_CLIENT: Streaming завершен');
              return;
            }

            try {
              if (data.isEmpty) {
                continue;
              }
              final json = jsonDecode(data) as Map<String, dynamic>;
              final choices = json['choices'] as List<dynamic>?;

              if (choices != null && choices.isNotEmpty) {
                final choice = choices[0] as Map<String, dynamic>;
                final delta = choice['delta'] as Map<String, dynamic>?;

                if (delta != null) {
                  final content = delta['content'] as String?;
                  if (content != null && content.isNotEmpty) {
                    if (!firstContentSeen) {
                      firstContentSeen = true;
                      if (requestStart != null) {
                        final ttfbMs = DateTime.now()
                            .difference(requestStart)
                            .inMilliseconds;
                        debugPrint(
                            '⏱️ DEEPSEEK_CLIENT: TTFB ${ttfbMs}ms до первого чанка');
                      }
                    }
                    yield content;
                  }

                  // Проверяем функции если включены
                  if (delta.containsKey('tool_calls')) {
                    debugPrint(
                        '🔧 DEEPSEEK_CLIENT: Обнаружены streaming tool calls');
                    // В будущем можно обработать streaming function calls
                  }
                }

                // Проверяем причину завершения
                final finishReason = choice['finish_reason'] as String?;
                if (finishReason != null) {
                  debugPrint(
                      '🔴 DEEPSEEK_CLIENT: Streaming завершен по причине: $finishReason');
                  return;
                }
              }
            } catch (e) {
              debugPrint('⚠️ DEEPSEEK_CLIENT: Ошибка парсинга SSE chunk: $e');
              // Игнорируем ошибки парсинга отдельных chunk'ов
            }
          }
        }
      }
    } catch (e) {
      debugPrint('❌ DEEPSEEK_CLIENT: Ошибка в SSE stream: $e');
      if (!_returnEmptyOnError) {
        throw DeepSeekException(message: 'SSE stream error: $e');
      }
    }
  }

  /// Очищает кэш результатов
  void clearCache() {
    _cache.clear();
    debugPrint('🔴 DEEPSEEK_CLIENT: Кэш очищен');
  }

  Dio? _maybeUseProxy(DioException error) {
    if (_proxyConfig == null) return null;
    if (!_shouldTryProxy(error)) return null;
    return _ensureProxyDio();
  }

  void _addRetryInterceptor(Dio dio) {
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        logPrint: (message) => debugPrint('🔁 RETRY: $message'),
        retries: config.fastMode ? 1 : 2,
        retryDelays: config.fastMode
            ? [Duration(milliseconds: 500)]
            : [
                Duration(seconds: 1),
                Duration(seconds: 3),
              ],
      ),
    );
  }

  Dio? _ensureProxyDio() {
    final proxy = _proxyConfig;
    if (proxy == null) return null;
    if (_proxyDio != null) return _proxyDio;
    final dio = Dio(BaseOptions(
      baseUrl: config.baseUrl,
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
        if (config.proxyToken != null && config.proxyToken!.isNotEmpty)
          'X-Ai-Proxy-Token': config.proxyToken!,
      },
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
      sendTimeout: _sendTimeout,
    ));
    _configureProxy(dio, proxy);
    _addRetryInterceptor(dio);
    _proxyDio = dio;
    return dio;
  }

  void _configureProxy(Dio dio, _ProxyConfig proxy) {
    final httpClient = HttpClient();
    if (proxy.kind == _ProxyKind.socks5) {
      final address = InternetAddress.tryParse(proxy.host);
      if (address == null) {
        debugPrint('🔴 DEEPSEEK_CLIENT: SOCKS прокси требует IP-адрес хоста');
        return;
      }
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
    } else {
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
    }
    dio.httpClientAdapter =
        IOHttpClientAdapter(createHttpClient: () => httpClient);
    debugPrint('🔵 DEEPSEEK_CLIENT: Прокси активирован (${proxy.kind.name})');
  }

  bool _shouldTryProxy(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.badResponse &&
            (err.response?.statusCode == 429 ||
                err.response?.statusCode == 500 ||
                err.response?.statusCode == 502 ||
                err.response?.statusCode == 503 ||
                err.response?.statusCode == 504);
  }

  Future<String> _executeRequest(
    Map<String, dynamic> requestData, {
    required Dio dio,
  }) async {
    final response = await dio.post(
      '/chat/completions',
      data: requestData,
    );
    final responseData = response.data as Map<String, dynamic>;
    final choices = responseData['choices'] as List<dynamic>;
    if (choices.isEmpty) {
      if (_returnEmptyOnError) {
        return '';
      }
      throw DeepSeekException(message: 'Empty response from DeepSeek');
    }
    final message = choices[0]['message'] as Map<String, dynamic>;
    if (message.containsKey('tool_calls')) {
      debugPrint('🔧 DEEPSEEK_CLIENT: Обнаружены вызовы функций');
      final toolCalls = message['tool_calls'] as List<dynamic>;
      return 'Function calling detected: ${toolCalls.length} functions called. '
          'Обратитесь к разработчикам для полной интеграции Function Calling.';
    }
    final content = message['content'] as String? ?? '';
    if (content.isEmpty) {
      debugPrint('🔴 DEEPSEEK_CLIENT: Получен пустой контент от модели');
      if (_returnEmptyOnError) {
        return '';
      }
      throw DeepSeekException(message: 'Empty content from DeepSeek model');
    }
    return content;
  }

  Stream<String> _executeStream(
    Map<String, dynamic> requestData, {
    required Dio dio,
  }) async* {
    final DateTime requestStart = DateTime.now();
    final response = await dio.post(
      '/chat/completions',
      data: requestData,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
        },
      ),
    );
    yield* _parseSSEStream(response.data.stream, requestStart: requestStart);
  }
}

// Удалена неиспользуемая функция _readFileBytes

/// Интерцептор для повторных попыток запросов при ошибках
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final Function(String message) logPrint;
  final int retries;
  final List<Duration> retryDelays;

  RetryInterceptor({
    required this.dio,
    required this.logPrint,
    this.retries = 3,
    required this.retryDelays,
  });

  @override
  Future onError(DioException err, ErrorInterceptorHandler handler) async {
    var extraInfo = err.requestOptions.extra;
    var retryCount = extraInfo['retryCount'] ?? 0;

    // Проверяем, что еще есть попытки и ошибка подходит для повторного запроса
    if (retryCount < retries && _shouldRetry(err)) {
      // Увеличиваем счетчик попыток
      extraInfo['retryCount'] = retryCount + 1;

      // Ждем перед повторной попыткой
      Duration delay = retryCount < retryDelays.length
          ? retryDelays[retryCount]
          : retryDelays.last;

      logPrint(
          '🔄 Повторная попытка ${retryCount + 1}/$retries через ${delay.inSeconds} сек...');
      await Future.delayed(delay);

      // Создаем новые опции запроса
      final options = Options(
        method: err.requestOptions.method,
        headers: err.requestOptions.headers,
        extra: extraInfo,
      );

      // Повторяем запрос
      try {
        logPrint('🔄 Отправка повторного запроса...');
        final response = await dio.request(
          err.requestOptions.path,
          data: err.requestOptions.data,
          queryParameters: err.requestOptions.queryParameters,
          options: options,
        );
        logPrint('✅ Повторный запрос успешен');
        handler.resolve(response);
        return;
      } catch (e) {
        // Если повторный запрос снова не удался, просто продолжаем с исходной ошибкой
        logPrint('❌ Повторный запрос не удался: $e');
      }
    }

    // Если не выполнили повторный запрос, продолжаем с исходной ошибкой
    return super.onError(err, handler);
  }

  /// Определяет, нужно ли повторять запрос для данной ошибки
  bool _shouldRetry(DioException err) {
    // Повторяем запрос при ошибках сети, тайм-аутах и некоторых HTTP-ошибках
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.badResponse &&
            (err.response?.statusCode == 429 || // Too Many Requests
                err.response?.statusCode == 500 || // Internal Server Error
                err.response?.statusCode == 502 || // Bad Gateway
                err.response?.statusCode == 503 || // Service Unavailable
                err.response?.statusCode == 504); // Gateway Timeout
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
