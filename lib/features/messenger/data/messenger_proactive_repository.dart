import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/messenger_proactive_message.dart';

class MessengerProactiveRepository {
  static const String _storageKey = 'messenger_proactive_messages';

  final SharedPreferences _prefs;

  MessengerProactiveRepository(this._prefs);

  Future<List<MessengerProactiveMessage>> loadAll() async {
    try {
      final rawList = _prefs.getStringList(_storageKey) ?? [];
      return rawList
          .map((raw) => MessengerProactiveMessage.fromJson(
                jsonDecode(raw) as Map<String, dynamic>,
              ))
          .toList();
    } catch (e) {
      debugPrint('Ошибка загрузки proactive сообщений: $e');
      return [];
    }
  }

  Future<void> saveAll(List<MessengerProactiveMessage> messages) async {
    try {
      final rawList =
          messages.map((message) => jsonEncode(message.toJson())).toList();
      await _prefs.setStringList(_storageKey, rawList);
    } catch (e) {
      debugPrint('Ошибка сохранения proactive сообщений: $e');
    }
  }

  Future<void> upsert(MessengerProactiveMessage message) async {
    final messages = await loadAll();
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index == -1) {
      messages.add(message);
    } else {
      messages[index] = message;
    }
    await saveAll(messages);
  }

  Future<void> removeByIds(Iterable<String> ids) async {
    final messages = await loadAll();
    messages.removeWhere((message) => ids.contains(message.id));
    await saveAll(messages);
  }
}
