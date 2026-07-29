import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/step_model.dart';

class StepRepository {
  static const String _stepsKey = 'steps_data';
  static const String _goalKey = 'steps_goal';
  static const String _lastSyncKey = 'steps_last_sync';

  final SharedPreferences _prefs;

  StepRepository(this._prefs);

  Future<StepEntry?> getStepsForDate(DateTime date) async {
    final dateKey = _formatDateKey(date);
    final allData = _getAllStepsData();
    if (allData.containsKey(dateKey)) {
      return StepEntry.fromJson(allData[dateKey] as Map<String, dynamic>);
    }
    return null;
  }

  Future<StepEntry> getOrCreateStepsForDate(DateTime date) async {
    final existing = await getStepsForDate(date);
    if (existing != null) return existing;
    
    final goal = getStepGoal();
    return StepEntry.empty(date, goal: goal);
  }

  Future<void> saveSteps(StepEntry entry) async {
    final allData = _getAllStepsData();
    allData[entry.dateKey] = entry.toJson();
    await _prefs.setString(_stepsKey, jsonEncode(allData));
  }

  Future<List<StepEntry>> getStepsForPeriod(DateTime start, DateTime end) async {
    final allData = _getAllStepsData();
    final entries = <StepEntry>[];
    
    DateTime current = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    
    while (!current.isAfter(endDate)) {
      final dateKey = _formatDateKey(current);
      if (allData.containsKey(dateKey)) {
        entries.add(StepEntry.fromJson(allData[dateKey] as Map<String, dynamic>));
      } else {
        entries.add(StepEntry.empty(current, goal: getStepGoal()));
      }
      current = current.add(const Duration(days: 1));
    }
    
    return entries;
  }

  Future<StepStats> getWeeklyStats(DateTime referenceDate) async {
    final startOfWeek = _getStartOfWeek(referenceDate);
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final entries = await getStepsForPeriod(startOfWeek, endOfWeek);
    return StepStats.fromEntries(entries);
  }

  Future<StepStats> getMonthlyStats(DateTime referenceDate) async {
    final startOfMonth = DateTime(referenceDate.year, referenceDate.month, 1);
    final endOfMonth = DateTime(referenceDate.year, referenceDate.month + 1, 0);
    final entries = await getStepsForPeriod(startOfMonth, endOfMonth);
    return StepStats.fromEntries(entries);
  }

  Future<StepStats> getLast7DaysStats() async {
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 6));
    final entries = await getStepsForPeriod(start, today);
    return StepStats.fromEntries(entries);
  }

  Future<StepStats> getLast30DaysStats() async {
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 29));
    final entries = await getStepsForPeriod(start, today);
    return StepStats.fromEntries(entries);
  }

  int getStepGoal() {
    return _prefs.getInt(_goalKey) ?? 10000;
  }

  Future<void> setStepGoal(int goal) async {
    await _prefs.setInt(_goalKey, goal);
  }

  DateTime? getLastSync() {
    final timestamp = _prefs.getInt(_lastSyncKey);
    if (timestamp != null) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }

  Future<void> setLastSync(DateTime time) async {
    await _prefs.setInt(_lastSyncKey, time.millisecondsSinceEpoch);
  }

  Map<String, dynamic> _getAllStepsData() {
    final data = _prefs.getString(_stepsKey);
    if (data != null) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return {};
  }

  String _formatDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DateTime _getStartOfWeek(DateTime date) {
    final weekday = date.weekday;
    return DateTime(date.year, date.month, date.day - (weekday - 1));
  }

  Future<void> clearAllData() async {
    await _prefs.remove(_stepsKey);
    await _prefs.remove(_lastSyncKey);
  }
}








