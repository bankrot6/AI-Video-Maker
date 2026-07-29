import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../models/friend_profile.dart';

class FriendProfileRepository {
  static const String _profilesKey = 'friend_profiles';
  static const String _legacyProfileKey = 'friend_profile';
  static const String _defaultContactId = 'friend';

  final SharedPreferences _prefs;

  FriendProfileRepository(this._prefs);

  FriendProfile? load([String contactId = _defaultContactId]) {
    final profiles = loadAll();
    return profiles[contactId];
  }

  Map<String, FriendProfile> loadAll() {
    Map<String, FriendProfile> profiles = {};
    final raw = _prefs.getString(_profilesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final parsed = <String, FriendProfile>{};
          decoded.forEach((key, value) {
            if (value is Map<String, dynamic>) {
              parsed[key] = FriendProfile.fromJson(value);
            }
          });
          profiles = parsed;
        }
      } catch (e) {
        debugPrint('Ошибка загрузки профилей друзей: $e');
      }
    }

    final legacyRaw = _prefs.getString(_legacyProfileKey);
    if (legacyRaw != null &&
        legacyRaw.isNotEmpty &&
        !profiles.containsKey(_defaultContactId)) {
      try {
        final legacyJson = jsonDecode(legacyRaw) as Map<String, dynamic>;
        profiles[_defaultContactId] = FriendProfile.fromJson(legacyJson);
      } catch (e) {
        debugPrint('Ошибка загрузки legacy профиля друга: $e');
      }
    }

    return profiles;
  }

  Future<void> save(String contactId, FriendProfile profile) async {
    final profiles = loadAll();
    profiles[contactId] = profile;
    await _prefs.setString(_profilesKey, jsonEncode(_toJson(profiles)));
    if (contactId == _defaultContactId) {
      await _prefs.remove(_legacyProfileKey);
    }
  }

  Future<void> remove(String contactId) async {
    final profiles = loadAll();
    profiles.remove(contactId);
    await _prefs.setString(_profilesKey, jsonEncode(_toJson(profiles)));
    if (contactId == _defaultContactId) {
      await _prefs.remove(_legacyProfileKey);
    }
  }

  Future<void> clear() async {
    await _prefs.remove(_profilesKey);
    await _prefs.remove(_legacyProfileKey);
  }

  Map<String, dynamic> _toJson(Map<String, FriendProfile> profiles) {
    return profiles.map((key, value) => MapEntry(key, value.toJson()));
  }
}
