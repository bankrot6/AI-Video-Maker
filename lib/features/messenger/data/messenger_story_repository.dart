import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/messenger_story.dart';

class MessengerStoryRepository {
  static const String _storiesKey = 'messenger_stories';
  static const int _maxStories = 60;

  final SharedPreferences _prefs;
  final StreamController<void> _updatesController =
      StreamController<void>.broadcast();

  MessengerStoryRepository(this._prefs);

  Stream<void> get updates => _updatesController.stream;

  void dispose() {
    _updatesController.close();
  }

  Future<List<MessengerStory>> loadStories({
    String? contactId,
    bool includeExpired = false,
  }) async {
    final stories = _readStories();
    final filtered = stories.where((story) {
      if (!includeExpired && story.isExpired) return false;
      if (contactId == null || contactId.isEmpty) return true;
      return story.contactId == contactId;
    }).toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  Future<void> saveStory(MessengerStory story) async {
    final stories = _readStories();
    final updated = [
      story,
      ...stories.where((item) => item.id != story.id),
    ];
    await _writeStories(_trimStories(updated));
    _emitUpdate();
  }

  Future<void> removeStory(String storyId) async {
    final stories = _readStories();
    await _writeStories(stories.where((story) => story.id != storyId).toList());
    _emitUpdate();
  }

  Future<void> clearExpired() async {
    final stories = _readStories();
    await _writeStories(stories.where((story) => !story.isExpired).toList());
    _emitUpdate();
  }

  Future<void> markViewed(String storyId, DateTime viewedAt) async {
    final stories = _readStories();
    final index = stories.indexWhere((story) => story.id == storyId);
    if (index == -1) return;
    final story = stories[index];
    final existing = story.viewedAt;
    if (existing != null && !viewedAt.isAfter(existing)) return;
    stories[index] = story.copyWith(viewedAt: viewedAt);
    await _writeStories(_trimStories(stories));
    _emitUpdate();
  }

  Future<void> clearAll() async {
    await _prefs.remove(_storiesKey);
    _emitUpdate();
  }

  List<MessengerStory> _readStories() {
    final raw = _prefs.getString(_storiesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(MessengerStory.fromJson)
          .toList();
    } catch (e) {
      debugPrint('🎬 STORY: failed to read stories: $e');
      return [];
    }
  }

  Future<void> _writeStories(List<MessengerStory> stories) async {
    final json = stories.map((story) => story.toJson()).toList();
    await _prefs.setString(_storiesKey, jsonEncode(json));
  }

  List<MessengerStory> _trimStories(List<MessengerStory> stories) {
    if (stories.length <= _maxStories) return stories;
    return stories.sublist(0, _maxStories);
  }

  void _emitUpdate() {
    if (_updatesController.isClosed) return;
    _updatesController.add(null);
  }
}
