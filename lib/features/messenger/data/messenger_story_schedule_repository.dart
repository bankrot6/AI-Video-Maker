import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MessengerStoryScheduleRepository {
  static const String _keyPrefix = 'messenger_story_daily_';
  static const String _anchorPrefix = 'messenger_story_anchor_';

  final SharedPreferences _prefs;

  MessengerStoryScheduleRepository(this._prefs);

  DateTime? loadLastPublishedAt(String contactId) {
    final raw = _prefs.getString(_key(contactId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (e) {
      debugPrint('Ошибка чтения даты сторис: $e');
      return null;
    }
  }

  Future<void> saveLastPublishedAt(String contactId, DateTime value) async {
    await _prefs.setString(_key(contactId), value.toIso8601String());
  }

  DateTime? loadAnchorAt(String contactId) {
    final raw = _prefs.getString(_anchorKey(contactId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (e) {
      debugPrint('Ошибка чтения времени якоря сторис: $e');
      return null;
    }
  }

  Future<void> saveAnchorAt(String contactId, DateTime value) async {
    await _prefs.setString(_anchorKey(contactId), value.toIso8601String());
  }

  String _key(String contactId) => '$_keyPrefix$contactId';
  String _anchorKey(String contactId) => '$_anchorPrefix$contactId';
}
