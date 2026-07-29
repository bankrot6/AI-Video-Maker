import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Мини-клиент VK API для поиска видео
class VkApiClient {
  static const String _apiBase = 'https://api.vk.com/method';
  static const String _apiVersion = '5.199';

  /// Приоритет: .env → dart-define (поддерживаем несколько имён для надёжности)
  final String _accessToken = (() {
    final envCandidates = <String?>[
      dotenv.env['VKVIDEO_SERVICE_KEY'],
      dotenv.env['VK_API_TOKEN'],
      dotenv.env['VK_VIDEO_API_TOKEN'],
    ];
    for (final v in envCandidates) {
      if ((v ?? '').isNotEmpty) return v!;
    }
    // dart-define фолбэки
    const dd1 = String.fromEnvironment('VKVIDEO_SERVICE_KEY', defaultValue: '');
    if (dd1.isNotEmpty) return dd1;
    const dd2 = String.fromEnvironment('VK_SERVICE_TOKEN', defaultValue: '');
    if (dd2.isNotEmpty) return dd2;
    return '';
  })();

  bool get hasToken => _accessToken.isNotEmpty;

  /// Поиск видео по запросу. Возвращает необработанный список элементов VK.
  Future<List<VkApiVideoItem>> searchVideos(
    String query, {
    int count = 15,
    bool adult = false,
  }) async {
    if (!hasToken) return const [];

    final uri = Uri.parse('$_apiBase/video.search').replace(queryParameters: {
      'q': query,
      'count': count.toString(),
      'adult': adult ? '1' : '0',
      'extended': '1',
      'v': _apiVersion,
      'access_token': _accessToken,
    });

    try {
      final resp = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        debugPrint('❌ VK_API: HTTP ${resp.statusCode}');
        debugPrint(
            '   Response: ${resp.body.substring(0, resp.body.length > 200 ? 200 : resp.body.length)}');
        return const [];
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      if (data['error'] != null) {
        final errorData = data['error'] as Map<String, dynamic>;
        debugPrint(
            '❌ VK_API error: ${errorData['error_msg']} (код: ${errorData['error_code']})');
        if (errorData['error_code'] == 5) {
          debugPrint(
              '   💡 Неверный токен доступа! Проверьте VKVIDEO_SERVICE_KEY в .env');
        } else if (errorData['error_code'] == 15) {
          debugPrint(
              '   💡 Доступ запрещен! Токен не имеет прав на video.search');
        } else if (errorData['error_code'] == 28) {
          debugPrint('   💡 Метод недоступен с сервисным ключом!');
          debugPrint(
              '   💡 Для video.search нужен пользовательский токен (User Access Token)');
          debugPrint('   💡 Временное решение: используем веб-скрейпинг');
        }
        return const [];
      }
      final response = data['response'] as Map<String, dynamic>?;
      final items = (response?['items'] as List<dynamic>? ?? []);
      return items
          .map((e) => VkApiVideoItem.fromJson(e as Map<String, dynamic>))
          .where((e) => e.ownerId != null && e.id != null)
          .toList(growable: false);
    } catch (e) {
      debugPrint('❌ VK_API: exception: $e');
      return const [];
    }
  }
}

class VkApiVideoItem {
  final int? ownerId;
  final int? id;
  final String? title;
  final int? views;
  final int? duration; // в секундах
  final String? thumbnailUrl; // лучшая из image

  const VkApiVideoItem({
    required this.ownerId,
    required this.id,
    this.title,
    this.views,
    this.duration,
    this.thumbnailUrl,
  });

  factory VkApiVideoItem.fromJson(Map<String, dynamic> json) {
    String? pickThumb(List<dynamic>? arr) {
      if (arr == null || arr.isEmpty) return null;
      // Берём самую большую по высоте
      arr.sort((a, b) =>
          ((a['height'] ?? 0) as int).compareTo(((b['height'] ?? 0) as int)));
      return (arr.last['url'] as String?);
    }

    return VkApiVideoItem(
      ownerId: json['owner_id'] as int?,
      id: json['id'] as int?,
      title: json['title'] as String?,
      views: (json['views'] is int)
          ? json['views'] as int
          : int.tryParse('${json['views']}'),
      duration: (json['duration'] is int)
          ? json['duration'] as int
          : int.tryParse('${json['duration']}'),
      thumbnailUrl: pickThumb(json['image'] as List<dynamic>?),
    );
  }

  String get ownerIdStr => ownerId?.toString() ?? '';
  String get idStr => id?.toString() ?? '';
}
