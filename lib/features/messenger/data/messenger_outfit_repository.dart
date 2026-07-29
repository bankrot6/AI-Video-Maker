import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/messenger_outfit_state.dart';

class MessengerOutfitRepository {
  static const String _prefix = 'messenger_outfit_state_';

  final SharedPreferences _prefs;

  MessengerOutfitRepository(this._prefs);

  MessengerOutfitState? load(String contactId) {
    final raw = _prefs.getString(_key(contactId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return MessengerOutfitState.fromJson(json);
    } catch (e) {
      debugPrint('🔴 MESSENGER: Ошибка загрузки одежды $contactId: $e');
      return null;
    }
  }

  Future<void> save(MessengerOutfitState state) async {
    await _prefs.setString(_key(state.contactId), jsonEncode(state.toJson()));
  }

  Future<void> clear(String contactId) async {
    await _prefs.remove(_key(contactId));
  }

  String _key(String contactId) => '$_prefix$contactId';
}
