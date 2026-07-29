import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class TravelPlanOfflineStorage {
  static const _key = 'travel_plan_offline_v1';

  Future<Map<String, dynamic>> _loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return <String, dynamic>{};
  }

  Future<void> _saveRaw(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map));
  }

  Future<bool> isDownloaded(String planId) async {
    final raw = await _loadRaw();
    final item = raw[planId];
    if (item is Map<String, dynamic>) {
      return item['downloadedAtMs'] is int;
    }
    return false;
  }

  Future<int?> downloadedAtMs(String planId) async {
    final raw = await _loadRaw();
    final item = raw[planId];
    if (item is Map<String, dynamic>) {
      final value = item['downloadedAtMs'];
      return value is int ? value : null;
    }
    return null;
  }

  Future<void> markDownloaded(String planId, {required int totalPlaces}) async {
    final raw = await _loadRaw();
    raw[planId] = <String, dynamic>{
      'downloadedAtMs': DateTime.now().millisecondsSinceEpoch,
      'totalPlaces': totalPlaces,
    };
    await _saveRaw(raw);
  }

  Future<void> clearDownloaded(String planId) async {
    final raw = await _loadRaw();
    raw.remove(planId);
    await _saveRaw(raw);
  }
}











