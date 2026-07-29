import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/friend_persona.dart';

abstract class FriendPersonaRepository {
  Future<FriendPersona> load(String contactId);
  Future<void> save(String contactId, FriendPersona persona);
  Future<void> clear(String contactId);
}

class SharedPrefsFriendPersonaRepository implements FriendPersonaRepository {
  static const String _personaPrefix = 'friend_persona_';

  final SharedPreferences _prefs;

  SharedPrefsFriendPersonaRepository(this._prefs);

  @override
  Future<FriendPersona> load(String contactId) async {
    final raw = _prefs.getString(_key(contactId));
    if (raw == null) {
      return const FriendPersona();
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return FriendPersona.fromJson(data);
    } catch (e) {
      debugPrint('Ошибка загрузки персонализации друга: $e');
      return const FriendPersona();
    }
  }

  @override
  Future<void> save(String contactId, FriendPersona persona) async {
    final raw = jsonEncode(persona.toJson());
    await _prefs.setString(_key(contactId), raw);
  }

  @override
  Future<void> clear(String contactId) async {
    await _prefs.remove(_key(contactId));
  }

  String _key(String contactId) => '$_personaPrefix$contactId';
}
