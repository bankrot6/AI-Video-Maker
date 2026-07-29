import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'user_repository.dart';

class SharedPrefsUserRepository implements UserRepository {
  // Ключи для доступа к данным в SharedPreferences
  static const String _userKey = 'user_data';
  static const String _onboardingCompletedKey = 'onboarding_completed';
  static const String _userGenderKey = 'user_gender';

  final SharedPreferences _prefs;

  // Конструктор с внедрением зависимости - SharedPreferences
  SharedPrefsUserRepository(this._prefs);

  // Фабричный метод для создания репозитория
  static Future<SharedPrefsUserRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPrefsUserRepository(prefs);
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    final userJson = _prefs.getString(_userKey);
    if (userJson == null) {
      return null;
    }

    try {
      final Map<String, dynamic> userMap = json.decode(userJson);

      // Миграция: если отсутствует dailyWaterMl в nutritionGoals —
      // рассчитываем персональную цель воды и сохраняем обратно
      final Map<String, dynamic> goals =
          (userMap['nutritionGoals'] as Map<String, dynamic>?) ?? {};
      if (!goals.containsKey('dailyWaterMl')) {
        final double weight = (userMap['weight'] as num).toDouble();
        final int recommendedWater =
            (30 * weight).round().clamp(1500, 5000); // 30 мл/кг, границы
        goals['dailyWaterMl'] = recommendedWater;
        userMap['nutritionGoals'] = goals;
        // Сохраняем назад в SharedPreferences, чтобы миграция была одноразовой
        await _prefs.setString(_userKey, json.encode(userMap));
      }

      return UserModel.fromJson(userMap);
    } catch (e) {
      // Обработка ошибок десериализации
      print('Error deserializing user data: $e');
      return null;
    }
  }

  @override
  Future<void> saveUser(UserModel user) async {
    final userJson = json.encode(user.toJson());
    await _prefs.setString(_userKey, userJson);
  }

  @override
  Future<void> updateUser(UserModel user) async {
    // В этой простой реализации обновление - это просто перезапись
    await saveUser(user);
  }

  @override
  Future<void> deleteUser() async {
    await _prefs.remove(_userKey);
  }

  @override
  Future<bool?> hasCompletedOnboarding() async {
    return _prefs.getBool(_onboardingCompletedKey);
  }

  @override
  Future<void> setOnboardingCompleted(bool completed) async {
    await _prefs.setBool(_onboardingCompletedKey, completed);
  }

  @override
  Future<String?> getUserGender() async {
    return _prefs.getString(_userGenderKey);
  }

  @override
  Future<void> setUserGender(String gender) async {
    await _prefs.setString(_userGenderKey, gender);
  }
}
