import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/water_entry_model.dart';

/// Репозиторий для хранения потребления воды
abstract class WaterRepository {
  Future<void> addEntry(WaterEntryModel entry);
  Future<List<WaterEntryModel>> getEntriesForDate(DateTime date);
  Future<int> getTotalForDate(DateTime date);
  Future<void> removeEntry(String id);
}

/// Реализация на SharedPreferences
class SharedPrefsWaterRepository implements WaterRepository {
  static const String _key = 'water_entries_v1';
  final SharedPreferences _prefs;

  SharedPrefsWaterRepository(this._prefs);

  @override
  Future<void> addEntry(WaterEntryModel entry) async {
    final all = await _readAll();
    all.add(entry);
    await _writeAll(all);
  }

  @override
  Future<List<WaterEntryModel>> getEntriesForDate(DateTime date) async {
    final all = await _readAll();
    return all
        .where((e) =>
            e.dateTime.year == date.year &&
            e.dateTime.month == date.month &&
            e.dateTime.day == date.day)
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  @override
  Future<int> getTotalForDate(DateTime date) async {
    final entries = await getEntriesForDate(date);
    return entries.fold<int>(0, (sum, e) => sum + e.volumeMl);
  }

  @override
  Future<void> removeEntry(String id) async {
    final all = await _readAll();
    all.removeWhere((e) => e.id == id);
    await _writeAll(all);
  }

  Future<List<WaterEntryModel>> _readAll() async {
    final jsonString = _prefs.getString(_key);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final list = (json.decode(jsonString) as List<dynamic>)
          .map((e) => WaterEntryModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<WaterEntryModel> entries) async {
    final jsonString =
        json.encode(entries.map((e) => e.toJson()).toList(growable: false));
    await _prefs.setString(_key, jsonString);
  }
}
