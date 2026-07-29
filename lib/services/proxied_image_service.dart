import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class _ImageMemoryCache {
  _ImageMemoryCache();

  static const int maxSizeBytes = 100 * 1024 * 1024;
  final _cache = <String, Uint8List>{};
  int _currentSizeBytes = 0;

  Uint8List? get(String key) {
    final value = _cache.remove(key);
    if (value != null) {
      _cache[key] = value;
    }
    return value;
  }

  void put(String key, Uint8List value) {
    if (_cache.containsKey(key)) {
      _currentSizeBytes -= _cache[key]!.length;
      _cache.remove(key);
    }
    _cache[key] = value;
    _currentSizeBytes += value.length;
    _evict();
  }

  bool contains(String key) => _cache.containsKey(key);

  void _evict() {
    while (_currentSizeBytes > maxSizeBytes && _cache.isNotEmpty) {
      final oldest = _cache.keys.first;
      final removed = _cache.remove(oldest);
      if (removed != null) {
        _currentSizeBytes -= removed.length;
      }
    }
  }
}

class _DownloadPool {
  _DownloadPool(this.maxConcurrent);

  final int maxConcurrent;
  int _running = 0;
  final _waiters = Queue<Completer<void>>();

  Future<void> acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _running--;
    }
  }
}

class ProxiedImageService {
  static ProxiedImageService? _defaultInstance;

  factory ProxiedImageService() {
    return _defaultInstance ??= ProxiedImageService._();
  }

  ProxiedImageService._() : _imageProxyBase = _readImageProxyBase();

  /// Базовый URL nginx image-прокси (http://HOST:PORT/ai-TOKEN/imgproxy).
  /// Используется ТОЛЬКО для доменов из [_proxiedDomains].
  final String? _imageProxyBase;

  static String? _readImageProxyBase() {
    final v = dotenv.env['NL_IMAGE_PROXY_URL']?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  /// Домены, заблокированные в РФ и требующие nginx-прокси.
  /// Appwrite, Firebase и прочие доступные напрямую — НЕ в этом списке.
  static const _proxiedDomains = {
    'img.theapi.app',
    'upload.theapi.app',
    'theapi.app',
    'mule-router-assets.muleusercontent.com',
    'app-uploads.krea.ai',
    'api.piapi.ai',
    'piapi.ai',
  };

  bool _shouldProxy(String url) {
    if (_imageProxyBase == null) return false;
    try {
      final host = Uri.parse(url).host.toLowerCase();
      return _proxiedDomains.any((d) => host == d || host.endsWith('.$d'));
    } catch (_) {
      return false;
    }
  }

  static final _memCache = _ImageMemoryCache();
  static final _pending = <String, Future<Uint8List?>>{};
  static final _pool = _DownloadPool(4);
  static String? _diskCachePath;

  Uint8List? getFromMemory(String url) => _memCache.get(url);

  void prefetch(List<String> urls) {
    for (final url in urls) {
      if (!_memCache.contains(url) && !_pending.containsKey(url)) {
        downloadImage(url);
      }
    }
  }

  Future<Uint8List?> downloadImage(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return _readLocalFile(url);
    }

    final memCached = _memCache.get(url);
    if (memCached != null) return memCached;

    final existing = _pending[url];
    if (existing != null) return existing;

    final future = _downloadImpl(url);
    _pending[url] = future;
    try {
      return await future;
    } finally {
      _pending.remove(url);
    }
  }

  Future<Uint8List?> _downloadImpl(String url) async {
    final diskCached = await _readDiskCache(url);
    if (diskCached != null) {
      _memCache.put(url, diskCached);
      return diskCached;
    }

    final useProxy = _shouldProxy(url);
    final effectiveUrl = useProxy
        ? '$_imageProxyBase?url=${Uri.encodeComponent(url)}'
        : url;

    final uri = Uri.tryParse(effectiveUrl);
    if (uri == null) return null;

    await _pool.acquire();
    final client = http.Client();
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        _memCache.put(url, bytes);
        unawaited(_writeDiskCache(url, bytes));
        return bytes;
      }
    } catch (e) {
      debugPrint('ProxiedImage: error downloading $url — $e');
    } finally {
      client.close();
      _pool.release();
    }
    return null;
  }

  Future<Uint8List?> _readLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) return file.readAsBytes();
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> _readDiskCache(String url) async {
    try {
      final file = await _diskCacheFile(url);
      if (await file.exists()) return file.readAsBytes();
    } catch (_) {}
    return null;
  }

  Future<void> _writeDiskCache(String url, Uint8List bytes) async {
    try {
      final file = await _diskCacheFile(url);
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  Future<File> _diskCacheFile(String url) async {
    if (_diskCachePath == null) {
      final dir = await getApplicationCacheDirectory();
      _diskCachePath = '${dir.path}/proxied_images';
      final cacheDir = Directory(_diskCachePath!);
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
    }
    final hash = md5.convert(utf8.encode(url)).toString();
    return File('$_diskCachePath/$hash.jpg');
  }

}
