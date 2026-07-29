import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/measurement_entry_model.dart';

/// Репозиторий для работы с историей замеров тела
abstract class MeasurementRepository {
  Future<void> addEntry(MeasurementEntryModel entry);
  Future<List<MeasurementEntryModel>> getAllEntries();
  Future<MeasurementEntryModel?> getLatestEntry();
}

/// Реализация репозитория на SharedPreferences
class SharedPrefsMeasurementRepository implements MeasurementRepository {
  static const String _key = 'body_measurements_v1';
  final SharedPreferences _prefs;

  SharedPrefsMeasurementRepository(this._prefs);

  @override
  Future<void> addEntry(MeasurementEntryModel entry) async {
    final all = await getAllEntries();
    all.add(entry);
    all.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final jsonString = json.encode(all.map((e) => e.toJson()).toList());
    await _prefs.setString(_key, jsonString);
  }

  @override
  Future<List<MeasurementEntryModel>> getAllEntries() async {
    final jsonString = _prefs.getString(_key);
    if (jsonString == null || jsonString.isEmpty) return [];
    try {
      final list = (json.decode(jsonString) as List<dynamic>)
          .map((e) => MeasurementEntryModel.fromJson(e as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      return list;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<MeasurementEntryModel?> getLatestEntry() async {
    final all = await getAllEntries();
    if (all.isEmpty) return null;
    all.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return all.first;
  }
}
