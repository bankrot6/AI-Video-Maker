import '../models/user_model.dart';

/// Абстрактный интерфейс для репозитория пользователя
abstract class UserRepository {
  /// Получает данные текущего пользователя
  Future<UserModel?> getCurrentUser();

  /// Сохраняет данные пользователя
  Future<void> saveUser(UserModel user);

  /// Обновляет отдельные поля пользователя
  Future<void> updateUser(UserModel user);

  /// Удаляет все данные пользователя
  Future<void> deleteUser();

  /// Проверяет, завершил ли пользователь онбординг
  Future<bool?> hasCompletedOnboarding();

  /// Устанавливает флаг завершения онбординга
  Future<void> setOnboardingCompleted(bool completed);

  Future<String?> getUserGender();

  Future<void> setUserGender(String gender);
}
