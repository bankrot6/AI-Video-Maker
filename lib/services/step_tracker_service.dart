import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/step_model.dart';
import '../repositories/step_repository.dart';

class StepTrackerService with WidgetsBindingObserver {
  final StepRepository _repository;
  final SharedPreferences _prefs;
  
  static const String _midnightStepsKey = 'steps_at_midnight';
  static const String _lastDateKey = 'steps_last_date';
  static const String _lastRawStepsKey = 'steps_last_raw';
  
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<PedestrianStatus>? _pedestrianStatusSubscription;
  
  final _stepsController = StreamController<int>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _stepEntryController = StreamController<StepEntry>.broadcast();
  
  int _todaySteps = 0;
  int _stepsAtMidnight = 0;
  int _lastRawSteps = 0;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _isRequestingPermission = false;
  String _pedestrianStatus = 'unknown';
  bool _hasPermission = false;
  Timer? _midnightTimer;
  
  Stream<int> get stepsStream => _stepsController.stream;
  Stream<String> get statusStream => _statusController.stream;
  Stream<StepEntry> get stepEntryStream => _stepEntryController.stream;
  int get todaySteps => _todaySteps;
  String get pedestrianStatus => _pedestrianStatus;
  bool get isInitialized => _isInitialized;
  bool get hasPermission => _hasPermission;
  
  StepTrackerService(this._repository, this._prefs) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('👟 App resumed - refreshing step count');
      _checkDayChange();
      _refreshStepCount();
    }
  }

  Future<bool> requestPermission() async {
    if (_isRequestingPermission) {
      debugPrint('👟 Permission request already in progress, skipping');
      return _hasPermission;
    }
    
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint('⚠️ Pedometer not supported on this platform');
      return false;
    }
    
    _isRequestingPermission = true;
    
    try {
      if (Platform.isAndroid) {
        final status = await Permission.activityRecognition.request();
        _hasPermission = status.isGranted;
        debugPrint('👟 Activity recognition permission: $_hasPermission');
        return _hasPermission;
      }
      
      if (Platform.isIOS) {
        final status = await Permission.sensors.request();
        _hasPermission = status.isGranted;
        debugPrint('👟 Motion sensors permission: $_hasPermission');
        return _hasPermission;
      }
      
      return false;
    } finally {
      _isRequestingPermission = false;
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('👟 StepTrackerService already initialized');
      return;
    }
    
    if (_isInitializing) {
      debugPrint('👟 StepTrackerService initialization already in progress');
      return;
    }
    
    _isInitializing = true;
    debugPrint('👟 StepTrackerService initializing...');
    
    try {
      _hasPermission = await requestPermission();
      
      if (!_hasPermission) {
        debugPrint('❌ No permission for step tracking');
        _isInitialized = true;
        return;
      }
      
      await _loadSavedData();
      _checkDayChange();
      _startListening();
      _scheduleMidnightReset();
      
      _isInitialized = true;
      debugPrint('👟 StepTrackerService initialized with $_todaySteps steps');
      
      _emitCurrentState();
    } catch (e) {
      debugPrint('❌ StepTrackerService init error: $e');
      _isInitialized = true;
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _loadSavedData() async {
    _stepsAtMidnight = _prefs.getInt(_midnightStepsKey) ?? 0;
    _lastRawSteps = _prefs.getInt(_lastRawStepsKey) ?? 0;
    
    final todayEntry = await _repository.getStepsForDate(DateTime.now());
    if (todayEntry != null) {
      _todaySteps = todayEntry.steps;
    }
    
    debugPrint('👟 Loaded: todaySteps=$_todaySteps, midnightSteps=$_stepsAtMidnight, lastRaw=$_lastRawSteps');
  }

  void _checkDayChange() {
    final lastDateStr = _prefs.getString(_lastDateKey);
    final today = _formatDate(DateTime.now());
    
    if (lastDateStr != null && lastDateStr != today) {
      debugPrint('👟 New day detected! Resetting steps. Last: $lastDateStr, Today: $today');
      _stepsAtMidnight = _lastRawSteps;
      _todaySteps = 0;
      _prefs.setInt(_midnightStepsKey, _stepsAtMidnight);
      _prefs.setString(_lastDateKey, today);
    } else if (lastDateStr == null) {
      _prefs.setString(_lastDateKey, today);
    }
  }

  void _startListening() {
    debugPrint('👟 Starting pedometer streams...');
    
    _stepCountSubscription?.cancel();
    _pedestrianStatusSubscription?.cancel();
    
    _stepCountSubscription = Pedometer.stepCountStream.listen(
      _onStepCount,
      onError: _onStepCountError,
      cancelOnError: false,
    );
    
    _pedestrianStatusSubscription = Pedometer.pedestrianStatusStream.listen(
      _onPedestrianStatus,
      onError: _onPedestrianStatusError,
      cancelOnError: false,
    );
    
    debugPrint('👟 Pedometer streams started');
  }

  void _onStepCount(StepCount event) {
    final rawSteps = event.steps;
    final now = DateTime.now();
    
    debugPrint('👟 Raw step event: $rawSteps (time: ${event.timeStamp})');
    
    if (_stepsAtMidnight == 0) {
      _stepsAtMidnight = rawSteps - _todaySteps;
      _prefs.setInt(_midnightStepsKey, _stepsAtMidnight);
      debugPrint('👟 First event - setting midnight baseline: $_stepsAtMidnight');
    }
    
    if (rawSteps < _lastRawSteps) {
      debugPrint('👟 Device rebooted detected (raw steps decreased). Adjusting baseline.');
      _stepsAtMidnight = rawSteps - _todaySteps;
      if (_stepsAtMidnight < 0) _stepsAtMidnight = 0;
      _prefs.setInt(_midnightStepsKey, _stepsAtMidnight);
    }
    
    _lastRawSteps = rawSteps;
    _prefs.setInt(_lastRawStepsKey, _lastRawSteps);
    
    final newTodaySteps = rawSteps - _stepsAtMidnight;
    
    if (newTodaySteps >= 0 && newTodaySteps != _todaySteps) {
      _todaySteps = newTodaySteps;
      
      debugPrint('👟 Today steps updated: $_todaySteps (raw: $rawSteps, midnight: $_stepsAtMidnight)');
      
      _stepsController.add(_todaySteps);
      _emitCurrentState();
      _saveCurrentSteps();
    }
  }

  void _onStepCountError(dynamic error) {
    debugPrint('❌ Step count error: $error');
    if (error.toString().contains('Permission')) {
      _hasPermission = false;
    }
  }

  void _onPedestrianStatus(PedestrianStatus event) {
    _pedestrianStatus = event.status;
    _statusController.add(_pedestrianStatus);
    debugPrint('🚶 Pedestrian status: $_pedestrianStatus');
  }

  void _onPedestrianStatusError(dynamic error) {
    debugPrint('❌ Pedestrian status error: $error');
    _pedestrianStatus = 'unknown';
  }

  void _emitCurrentState() {
    final entry = _createCurrentEntry();
    _stepEntryController.add(entry);
  }

  StepEntry _createCurrentEntry() {
    final now = DateTime.now();
    return StepEntry(
      date: DateTime(now.year, now.month, now.day),
      steps: _todaySteps,
      distanceKm: calculateDistance(_todaySteps),
      caloriesBurned: calculateCalories(_todaySteps),
      activeMinutes: calculateActiveMinutes(_todaySteps),
      goal: _repository.getStepGoal(),
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _saveCurrentSteps() async {
    final entry = _createCurrentEntry();
    await _repository.saveSteps(entry);
    await _repository.setLastSync(DateTime.now());
  }

  void _scheduleMidnightReset() {
    _midnightTimer?.cancel();
    
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final durationUntilMidnight = tomorrow.difference(now);
    
    debugPrint('👟 Scheduling midnight reset in ${durationUntilMidnight.inMinutes} minutes');
    
    _midnightTimer = Timer(durationUntilMidnight, () {
      debugPrint('👟 Midnight! Resetting daily steps');
      _stepsAtMidnight = _lastRawSteps;
      _todaySteps = 0;
      _prefs.setInt(_midnightStepsKey, _stepsAtMidnight);
      _prefs.setString(_lastDateKey, _formatDate(DateTime.now()));
      
      _stepsController.add(0);
      _emitCurrentState();
      
      _scheduleMidnightReset();
    });
  }

  void _refreshStepCount() {
    if (_stepCountSubscription != null) {
      _stepCountSubscription!.cancel();
      _stepCountSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepCountError,
        cancelOnError: false,
      );
    }
  }

  double calculateDistance(int steps, {double strideLength = 0.762}) {
    return (steps * strideLength) / 1000;
  }

  double calculateCalories(int steps, {double weightKg = 70}) {
    return steps * 0.04 * (weightKg / 70);
  }

  int calculateActiveMinutes(int steps) {
    return (steps / 100).round();
  }

  StepEntry getTodayStepsSync() {
    return _createCurrentEntry();
  }

  Future<StepEntry> getTodaySteps() async {
    return _createCurrentEntry();
  }

  Future<StepStats> getWeeklyStats() async {
    return _repository.getLast7DaysStats();
  }

  Future<StepStats> getMonthlyStats() async {
    return _repository.getLast30DaysStats();
  }

  int getStepGoal() {
    return _repository.getStepGoal();
  }

  Future<void> setStepGoal(int goal) async {
    await _repository.setStepGoal(goal);
    _emitCurrentState();
  }

  void forceRefresh() {
    debugPrint('👟 Force refresh requested');
    _emitCurrentState();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepCountSubscription?.cancel();
    _pedestrianStatusSubscription?.cancel();
    _midnightTimer?.cancel();
    _stepsController.close();
    _statusController.close();
    _stepEntryController.close();
    _isInitialized = false;
  }
}
