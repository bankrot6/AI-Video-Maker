import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/travel_plan.dart';

class TravelPlanStorage {
  static const _key = 'travel_plans_v1';

  Future<List<TravelPlan>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(TravelPlan.fromJson)
          .toList(growable: false);
    } catch (e) {
      debugPrint('❌ TravelPlanStorage.load: $e');
      return [];
    }
  }

  Future<void> save(List<TravelPlan> plans) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(
          plans.map((plan) => plan.toJson()).toList(growable: false));
      await prefs.setString(_key, payload);
      debugPrint('💾 TravelPlanStorage.save: ${plans.length} планов');
    } catch (e) {
      debugPrint('❌ TravelPlanStorage.save: $e');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (e) {
      debugPrint('❌ TravelPlanStorage.clear: $e');
    }
  }
}

















