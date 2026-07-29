import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/messenger_mood_state.dart';

class MessengerMoodRepository {
  static const String _prefix = 'messenger_mood_state_';

  final SharedPreferences _prefs;

  MessengerMoodRepository(this._prefs);

  MessengerMoodState? load(String contactId) {
    final raw = _prefs.getString(_key(contactId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return MessengerMoodState.fromJson(json);
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка загрузки настроения $contactId: $e');
      return null;
    }
  }

  Future<void> save(MessengerMoodState state) async {
    await _prefs.setString(_key(state.contactId), jsonEncode(state.toJson()));
  }

  Future<void> clear(String contactId) async {
    await _prefs.remove(_key(contactId));
  }

  String _key(String contactId) => '$_prefix$contactId';
}
