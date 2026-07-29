import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/messenger_pending_ai_task.dart';

class MessengerPendingAiTaskRepository {
  static const String _storageKey = 'messenger_pending_ai_tasks';

  final SharedPreferences _prefs;

  MessengerPendingAiTaskRepository(this._prefs);

  Future<List<MessengerPendingAiTask>> loadAll() async {
    try {
      final rawList = _prefs.getStringList(_storageKey) ?? const [];
      final tasks = rawList
          .map((raw) => MessengerPendingAiTask.fromJson(
                jsonDecode(raw) as Map<String, dynamic>,
              ))
          .toList();
      tasks.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return tasks;
    } catch (e) {
      debugPrint('Ошибка загрузки pending AI задач: $e');
      return const [];
    }
  }

  Future<void> saveAll(List<MessengerPendingAiTask> tasks) async {
    try {
      final rawList = tasks.map((task) => jsonEncode(task.toJson())).toList();
      await _prefs.setStringList(_storageKey, rawList);
    } catch (e) {
      debugPrint('Ошибка сохранения pending AI задач: $e');
    }
  }

  Future<void> upsert(MessengerPendingAiTask task) async {
    final tasks = await loadAll();
    final index = tasks.indexWhere((item) => item.id == task.id);
    if (index == -1) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    await saveAll(tasks);
  }

  Future<void> removeById(String taskId) async {
    final tasks = await loadAll();
    tasks.removeWhere((task) => task.id == taskId);
    await saveAll(tasks);
  }

  Future<void> removeByMessageId({
    required String contactId,
    required String userMessageId,
  }) async {
    final tasks = await loadAll();
    tasks.removeWhere(
      (task) =>
          task.contactId == contactId && task.userMessageId == userMessageId,
    );
    await saveAll(tasks);
  }

  Future<MessengerPendingAiTask?> findByMessageId({
    required String contactId,
    required String userMessageId,
  }) async {
    final tasks = await loadAll();
    for (final task in tasks) {
      if (task.contactId == contactId && task.userMessageId == userMessageId) {
        return task;
      }
    }
    return null;
  }
}
