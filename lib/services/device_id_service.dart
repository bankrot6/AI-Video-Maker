import 'dart:io';
import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class DeviceIdService {
  static const String _legacyDeviceIdKey = 'stable_device_id';
  static const String _androidDeviceIdV2Key = 'stable_device_id_v2_android';
  static const String _androidMigrationDoneKey =
      'stable_device_id_v2_android_migrated';
  
  static DeviceIdService? _instance;
  static DeviceIdService get instance {
    _instance ??= DeviceIdService._();
    return _instance!;
  }
  
  DeviceIdService._();
  
  String? _cachedDeviceId;

  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    final prefs = await SharedPreferences.getInstance();
    if (Platform.isAndroid) {
      final androidV2Id = prefs.getString(_androidDeviceIdV2Key);
      if (androidV2Id != null && androidV2Id.isNotEmpty) {
        _cachedDeviceId = androidV2Id;
        return androidV2Id;
      }

      final legacyId = prefs.getString(_legacyDeviceIdKey);
      final nextId = await _generateStableDeviceId();
      await prefs.setString(_androidDeviceIdV2Key, nextId);
      await prefs.setString(_legacyDeviceIdKey, nextId);

      final migrationDone = prefs.getBool(_androidMigrationDoneKey) ?? false;
      if (!migrationDone) {
        final hasLegacyId = legacyId != null && legacyId.isNotEmpty;
        if (hasLegacyId && legacyId != nextId) {
          await _dropLegacyAccidentalCredits(prefs);
        }
        await prefs.setBool(_androidMigrationDoneKey, true);
      }

      _cachedDeviceId = nextId;
      return nextId;
    }

    final storedId = prefs.getString(_legacyDeviceIdKey);
    if (storedId != null && storedId.isNotEmpty) {
      _cachedDeviceId = storedId;
      return storedId;
    }

    final deviceId = await _generateStableDeviceId();
    await prefs.setString(_legacyDeviceIdKey, deviceId);
    _cachedDeviceId = deviceId;
    
    return deviceId;
  }

  Future<String> _generateStableDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String identifier = '';

      if (Platform.isAndroid) {
        const androidIdPlugin = AndroidId();
        identifier = await androidIdPlugin.getId() ?? '';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        identifier = iosInfo.identifierForVendor ?? '';
      }

      if (identifier.isEmpty) {
        identifier = DateTime.now().millisecondsSinceEpoch.toString();
      }

      final bytes = utf8.encode(identifier);
      final hash = sha256.convert(bytes);
      return hash.toString();
    } catch (e) {
      final fallbackId = DateTime.now().millisecondsSinceEpoch.toString();
      final bytes = utf8.encode(fallbackId);
      final hash = sha256.convert(bytes);
      return hash.toString();
    }
  }

  Future<void> _dropLegacyAccidentalCredits(SharedPreferences prefs) async {
    final rawUsage = prefs.getString('credit_usage_data');
    if (rawUsage == null || rawUsage.isEmpty) return;

    try {
      final usage = jsonDecode(rawUsage) as Map<String, dynamic>;
      final purchased = usage['purchasedCredits'] as int? ?? 0;
      final earned = usage['earnedCredits'] as int? ?? 0;
      if (purchased == 0 && earned == 0) return;

      final total = usage['totalCredits'] as int? ?? 0;
      final cleanedTotal = (total - purchased - earned).clamp(0, 1000000000);

      usage['purchasedCredits'] = 0;
      usage['earnedCredits'] = 0;
      usage['totalCredits'] = cleanedTotal;
      usage['lastResetDate'] = DateTime.now().millisecondsSinceEpoch;

      await prefs.setString('credit_usage_data', jsonEncode(usage));
    } catch (_) {}
  }

  void clearCache() {
    _cachedDeviceId = null;
  }
}
