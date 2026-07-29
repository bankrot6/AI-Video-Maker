import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/appwrite_user_generation_repository.dart';
import '../data/local_user_generation_repository.dart';
import '../models/user_generation.dart';
import '../services/appwrite_storage_service.dart';
import '../services/local_generation_storage.dart';

/// Ключ в SharedPreferences.
/// true  = пользователь новый ИЛИ миграция завершена → работаем локально.
/// false / отсутствует = старый пользователь, есть данные на сервере.
const _kLocalStorageReady = 'gen_local_storage_v1';

/// Определяет режим хранения генераций.
enum GenerationStorageMode {
  /// Все данные хранятся локально на устройстве.
  local,

  /// Данные на сервере, идёт или ожидается миграция.
  remote,
}

class GenerationMigrationService {
  GenerationMigrationService._();
  static final GenerationMigrationService instance =
      GenerationMigrationService._();

  bool _initialized = false;
  GenerationStorageMode _mode = GenerationStorageMode.remote;

  GenerationStorageMode get mode => _mode;
  bool get isLocalMode => _mode == GenerationStorageMode.local;

  /// Вызывается при запуске приложения.
  /// Определяет режим и запускает фоновую миграцию для старых пользователей.
  Future<void> init(SharedPreferences prefs) async {
    if (_initialized) return;
    _initialized = true;

    final ready = prefs.getBool(_kLocalStorageReady) ?? false;
    if (ready) {
      _mode = GenerationStorageMode.local;
      debugPrint('GenerationMigration: режим LOCAL (ранее мигрировано)');
      return;
    }

    // Проверяем — действительно ли есть данные на сервере.
    // Если это первый запуск нового пользователя — сразу переводим в local.
    final hasRemoteData = await _checkHasRemoteData();
    if (!hasRemoteData) {
      await prefs.setBool(_kLocalStorageReady, true);
      _mode = GenerationStorageMode.local;
      debugPrint('GenerationMigration: новый пользователь → режим LOCAL');
      return;
    }

    _mode = GenerationStorageMode.remote;
    debugPrint('GenerationMigration: старый пользователь → запуск фоновой миграции');
    unawaited(_runMigrationInBackground(prefs));
  }

  /// Проверяет наличие данных на сервере (быстрый запрос, не блокирует UI).
  Future<bool> _checkHasRemoteData() async {
    try {
      final repo = AppwriteUserGenerationRepository();
      // Смотрим на первый попавшийся preset — нам важен факт наличия записей
      final ids = <String>{};
      await for (final set in repo.watchUsedPresetIds('').take(1)) {
        ids.addAll(set);
        break;
      }
      return ids.isNotEmpty;
    } catch (e) {
      debugPrint('GenerationMigration: ошибка проверки remote данных: $e');
      // При ошибке сети считаем что данных нет → режим local
      return false;
    }
  }

  Future<void> _runMigrationInBackground(SharedPreferences prefs) async {
    try {
      await Future.delayed(const Duration(seconds: 5));
      debugPrint('GenerationMigration: начало фоновой миграции');

      final remoteRepo = AppwriteUserGenerationRepository();
      final localRepo = LocalUserGenerationRepository();
      final localStorage = LocalGenerationStorage.instance;
      final appwriteStorage = AppwriteStorageService();

      // Собираем все presetId пользователя
      final presetIds = <String>{};
      await for (final set in remoteRepo.watchUsedPresetIds('').take(1)) {
        presetIds.addAll(set);
        break;
      }

      debugPrint(
        'GenerationMigration: найдено ${presetIds.length} пресетов на сервере',
      );

      var migratedCount = 0;
      var failedCount = 0;

      for (final presetId in presetIds) {
        final generations = await remoteRepo.getGenerationsByPreset(
          presetId,
          deviceId: '',
        );

        for (final gen in generations) {
          final success = await _migrateOne(
            generation: gen,
            localRepo: localRepo,
            localStorage: localStorage,
            appwriteStorage: appwriteStorage,
            remoteRepo: remoteRepo,
          );
          if (success) {
            migratedCount++;
          } else {
            failedCount++;
          }

          // Небольшая пауза чтобы не перегружать сеть и батарею
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      debugPrint(
        'GenerationMigration: завершено. Мигрировано: $migratedCount, ошибок: $failedCount',
      );

      if (failedCount == 0) {
        await prefs.setBool(_kLocalStorageReady, true);
        _mode = GenerationStorageMode.local;
        debugPrint('GenerationMigration: переключились в режим LOCAL');
      } else {
        debugPrint(
          'GenerationMigration: есть ошибки, повторим при следующем запуске',
        );
      }
    } catch (e) {
      debugPrint('GenerationMigration: ошибка фоновой миграции: $e');
    }
  }

  Future<bool> _migrateOne({
    required UserGeneration generation,
    required LocalUserGenerationRepository localRepo,
    required LocalGenerationStorage localStorage,
    required AppwriteStorageService appwriteStorage,
    required AppwriteUserGenerationRepository remoteRepo,
  }) async {
    try {
      // Скачиваем resultImageUrl на устройство
      String? localResultPath;
      if (LocalGenerationStorage.isLocalPath(generation.resultImageUrl)) {
        localResultPath = generation.resultImageUrl; // уже локальный
      } else {
        localResultPath = await localStorage.saveImageFromUrl(
          generation.resultImageUrl,
          id: 'migr_${generation.id}_result',
        );
        if (localResultPath == null) {
          debugPrint(
            'GenerationMigration: не удалось скачать resultImage для ${generation.id}',
          );
          return false;
        }
      }

      // referenceImageUrl (если есть и это Appwrite URL)
      String? localRefPath = generation.referenceImageUrl;
      if (localRefPath != null &&
          !LocalGenerationStorage.isLocalPath(localRefPath) &&
          _isAppwriteUrl(localRefPath)) {
        final downloaded = await localStorage.saveImageFromUrl(
          localRefPath,
          id: 'migr_${generation.id}_ref',
        );
        localRefPath = downloaded ?? localRefPath;
      }

      // Создаём локальную запись
      final localGen = UserGeneration(
        id: generation.id,
        presetId: generation.presetId,
        userImageUrl: generation.userImageUrl,
        resultImageUrl: localResultPath,
        referenceImageUrl: localRefPath,
        createdAt: generation.createdAt,
        firebaseUid: generation.firebaseUid,
      );
      await localRepo.addMigratedGeneration(localGen);

      // Удаляем с Appwrite Storage
      if (!LocalGenerationStorage.isLocalPath(generation.resultImageUrl) &&
          _isAppwriteUrl(generation.resultImageUrl)) {
        await appwriteStorage.deleteFile(generation.resultImageUrl);
      }
      if (generation.referenceImageUrl != null &&
          !LocalGenerationStorage.isLocalPath(generation.referenceImageUrl!) &&
          _isAppwriteUrl(generation.referenceImageUrl!)) {
        await appwriteStorage.deleteFile(generation.referenceImageUrl!);
      }

      // Удаляем документ из Appwrite DB
      await remoteRepo.deleteGeneration(
        generation.id,
        deviceId: '',
        presetId: generation.presetId,
      );

      debugPrint('GenerationMigration: мигрировано ${generation.id}');
      return true;
    } catch (e) {
      debugPrint(
        'GenerationMigration: ошибка миграции ${generation.id}: $e',
      );
      return false;
    }
  }

  bool _isAppwriteUrl(String url) {
    return url.contains('/storage/buckets/') || url.contains('appwrite');
  }
}
