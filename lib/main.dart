import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:ui' as ui;
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'package:flutter_rustore_review/flutter_rustore_review.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'features/home/home_navigation_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'data/shared_prefs_user_repository.dart';
import 'data/subscription_repository.dart';
import 'features/home/home_providers.dart' as home;
import 'features/subscription/subscription_providers.dart' as subscription;
import 'features/subscription/purchase_providers.dart' as purchase;
import 'features/photosession/photosession_providers.dart' as photosession;
// import 'data/showcase_repository.dart';  // Закомментировано - не используется напрямую в main.dart
import 'utils/app_logger.dart';
import 'services/localization/app_localization_service.dart';
import 'utils/deep_link_handler.dart';
import 'services/paywall_preloader_service.dart';
import 'services/theme_service.dart';
import 'config/photosession_backend.dart';
import 'config/ai_proxy_config.dart';
import 'services/appwrite_ensure_tags.dart';
import 'services/appwrite_auth_service.dart';
import 'services/device_id_service.dart' as device_id_svc;
import 'data/appwrite_user_generation_repository.dart';
import 'services/device_registry_service.dart';
import 'services/android_system_ui_controller.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'services/firebase_anonymous_auth_service.dart';
import 'data/local_user_generation_repository.dart';
import 'services/generation_migration_service.dart';
import 'services/analytics/mytracker_analytics_service.dart';
// import 'data/firebase_showcase_repository.dart';  // Закомментировано - используется через провайдеры

// Глобальная функция для логирования, доступная из любого места в приложении
void appLog(String message,
    {String tag = 'APP',
    LogLevel level = LogLevel.info,
    bool localize = false,
    List<String>? params}) {
  // Если нужно локализовать сообщение
  if (localize && _localizationService != null) {
    if (params != null && params.isNotEmpty) {
      message = _localizationService!.translateWithParams(message, params);
    } else {
      message = _localizationService!.translate(message);
    }
  }
  AppLogger.log(message, tag: tag, level: level);
}

// Глобальная функция для локализации, доступная до инициализации контекста
String localizeMessage(String key, [List<String>? params]) {
  // Эта функция будет использоваться только в main.dart до инициализации контекста
  // В большинстве случаев следует использовать context.tr() или context.trParams()
  try {
    if (_localizationService != null) {
      if (params != null && params.isNotEmpty) {
        return _localizationService!.translateWithParams(key, params);
      } else {
        return _localizationService!.translate(key);
      }
    }
  } catch (e) {
    // В случае ошибки просто возвращаем ключ
  }
  return key;
}

// Глобальная переменная для доступа к сервису локализации
AppLocalizationService? _localizationService;

// ── Helpers для синхронизации device registry ──────────────────────────────

Future<void> _applyDeviceRegistryResult(
  SharedPreferences prefs,
  DeviceRegistryResult result,
  void Function(String, {required String tag, required LogLevel level}) log,
) async {
  // Дата первой установки
  final serverDate = result.firstSeenAt;
  final localMs = prefs.getInt('first_app_launch');
  final localDate =
      localMs != null ? DateTime.fromMillisecondsSinceEpoch(localMs) : null;

  final effectiveDate = (localDate == null || serverDate.isBefore(localDate))
      ? serverDate
      : localDate;

  await prefs.setInt('first_app_launch', effectiveDate.millisecondsSinceEpoch);

  final storedQuota = prefs.getString('free_quota_start_date');
  if (storedQuota == null ||
      effectiveDate.isBefore(DateTime.parse(storedQuota))) {
    await prefs.setString(
        'free_quota_start_date', effectiveDate.toIso8601String());
    log(
      'DEVICE_REGISTRY: free_quota_start_date → ${effectiveDate.toIso8601String()} '
      '(isNewDevice=${result.isNewDevice})',
      tag: 'PREFS',
      level: LogLevel.info,
    );
  }

  // Кредиты: MAX(local, server) — сервер всегда авторитетен при отсутствии локальных данных
  final rawUsage = prefs.getString('credit_usage_data');
  Map<String, dynamic>? localJson;
  if (rawUsage != null) {
    try {
      localJson = jsonDecode(rawUsage) as Map<String, dynamic>;
    } catch (_) {}
  }

  final localPurchased = localJson?['purchasedCredits'] as int? ?? 0;
  final localEarned = localJson?['earnedCredits'] as int? ?? 0;
  // ВАЖНО: при успешном ответе сервера именно сервер является источником истины
  // для purchased/earned. Это гарантирует, что случайно выданные локальные кредиты
  // будут обнулены после серверной очистки.
  final effectivePurchased = result.isServerTrusted
      ? result.purchasedCredits
      : (localPurchased > result.purchasedCredits
          ? localPurchased
          : result.purchasedCredits);
  final effectiveEarned = result.isServerTrusted
      ? result.earnedCredits
      : (localEarned > result.earnedCredits
          ? localEarned
          : result.earnedCredits);

  // Для free-пользователей (в т.ч. при отсутствии данных — rawUsage == null)
  final isFreeLocally = localJson?['isFreeUser'] as bool? ?? rawUsage == null;

  final localFreeCredits = localJson?['usedCredits'] as int? ?? 0;
  final localFreeGens = localJson?['freePhotosUsed'] as int? ?? 0;
  final effectiveFreeCredits = localFreeCredits > result.freeCreditsUsed
      ? localFreeCredits
      : result.freeCreditsUsed;
  final effectiveFreeGens = localFreeGens > result.freeGenerationsUsed
      ? localFreeGens
      : result.freeGenerationsUsed;

  final needsUpdate = effectivePurchased != localPurchased ||
      effectiveEarned != localEarned ||
      (isFreeLocally &&
          (effectiveFreeCredits != localFreeCredits ||
              effectiveFreeGens != localFreeGens));

  // При отсутствии локальных данных всегда записываем серверные значения,
  // чтобы CreditService при первой инициализации видел корректное состояние.
  if (needsUpdate || rawUsage == null) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Синхронизация totalCredits с серверным currentBalance.
    // Модель клиента: remainingCredits = totalCredits - usedCredits
    // Модель сервера: currentBalance = remainingCredits
    // Чтобы remainingCredits == currentBalance, нужно:
    // totalCredits = usedCredits + currentBalance
    final int effectiveTotalCredits;
    if (result.isServerTrusted && result.currentBalance > 0) {
      // Сервер авторитетен — синхронизируем баланс.
      // Берём именно тот usedCredits, который реально запишется ниже (для
      // free-пользователя это счётчик бесплатного расхода), чтобы выполнялось
      // remainingCredits == currentBalance и на серверо-авторитетных сборках
      // (RuStore) баланс не занижался на величину free-расхода.
      final writtenUsed = isFreeLocally
          ? effectiveFreeCredits
          : (localJson?['usedCredits'] as int? ?? 0);
      effectiveTotalCredits = writtenUsed + result.currentBalance;
    } else if (rawUsage == null) {
      // Новый пользователь — totalCredits = currentBalance от сервера
      effectiveTotalCredits = result.currentBalance;
    } else {
      // Сервер недоступен или баланс 0 — сохраняем локальные данные
      effectiveTotalCredits = (localJson?['subscriptionCredits'] as int? ?? 0) +
          effectivePurchased +
          effectiveEarned;
    }

    final updatedUsage = <String, dynamic>{
      ...?localJson,
      'purchasedCredits': effectivePurchased,
      'earnedCredits': effectiveEarned,
      'totalCredits': effectiveTotalCredits,
      if (isFreeLocally) ...{
        'usedCredits': effectiveFreeCredits,
        'freePhotosUsed': effectiveFreeGens,
        'isFreeUser': true,
        'lastDailyResetDate': now,
      },
      'lastResetDate': now,
    };
    await prefs.setString('credit_usage_data', jsonEncode(updatedUsage));
    log(
      'DEVICE_REGISTRY: credit_usage_data обновлён — '
      'trusted=${result.isServerTrusted} '
      'purchased=$effectivePurchased earned=$effectiveEarned '
      'totalCredits=$effectiveTotalCredits '
      'serverBalance=${result.currentBalance} '
      '${isFreeLocally ? "freeCr=$effectiveFreeCredits freeGens=$effectiveFreeGens" : ""}',
      tag: 'PREFS',
      level: LogLevel.info,
    );
  }
}

Future<void> _doMigrationUpload(
  SharedPreferences prefs,
  void Function(String, {required String tag, required LogLevel level}) log,
) async {
  final currentRaw = prefs.getString('credit_usage_data');
  if (currentRaw == null) return;
  Map<String, dynamic>? currentJson;
  try {
    currentJson = jsonDecode(currentRaw) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  final isFree = currentJson['isFreeUser'] as bool? ?? false;
  final isTrialU = currentJson['isTrialUser'] as bool? ?? false;
  final subType = isTrialU
      ? 'trial'
      : isFree
          ? 'free'
          : 'paid';
  final totalCredits = currentJson['totalCredits'] as int? ?? 0;
  final usedCredits = currentJson['usedCredits'] as int? ?? 0;
  final currentBalance = (totalCredits - usedCredits).clamp(0, 1000000000);

  await DeviceRegistryService().syncCredits(
    freeCreditsUsed: isFree ? (currentJson['usedCredits'] as int? ?? 0) : 0,
    freeGenerationsUsed:
        isFree ? (currentJson['freePhotosUsed'] as int? ?? 0) : 0,
    purchasedCredits: currentJson['purchasedCredits'] as int? ?? 0,
    earnedCredits: currentJson['earnedCredits'] as int? ?? 0,
    currentBalance: currentBalance,
    subscriptionType: subType,
  );

  log(
    'DEVICE_REGISTRY: migration upload — subType=$subType '
    'purchased=${currentJson['purchasedCredits']} '
    'earned=${currentJson['earnedCredits']} '
    'balance=$currentBalance',
    tag: 'PREFS',
    level: LogLevel.info,
  );
}

/// Основная точка входа в приложение
void main() async {
  try {
    // Отправляем лог о начале запуска приложения
    appLog('Запуск приложения', tag: 'MAIN', level: LogLevel.info);

    // Убедимся, что Flutter инициализирован
    WidgetsFlutterBinding.ensureInitialized();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      AndroidSystemUiController.refresh();
    }
    // RuStore Review init только при сборке с флагом RUSTORE и только при наличии сети
    const bool isRuStoreBuild = bool.fromEnvironment('RUSTORE');
    if (isRuStoreBuild) {
      try {
        await RustoreReviewClient.initialize()
            .timeout(const Duration(seconds: 3), onTimeout: () {});
      } catch (_) {}
    }
    appLog('Flutter инициализирован', tag: 'INIT', level: LogLevel.debug);

    // Получаем экземпляр SharedPreferences для всего приложения (ранняя инициализация)
    final prefs = await SharedPreferences.getInstance();
    appLog('SharedPreferences инициализированы',
        tag: 'PREFS', level: LogLevel.debug);

    await Hive.initFlutter();
    appLog('Hive инициализирован', tag: 'INIT', level: LogLevel.debug);

    await LocalUserGenerationRepository.ensureOpen();

    // Сохраняем дату первой установки приложения (если ещё не сохранена)
    const String firstInstallKey = 'first_install_date';
    final bool isFirstInstallLaunch = !prefs.containsKey(firstInstallKey);
    DateTime? firstInstallAt;
    if (isFirstInstallLaunch) {
      final now = DateTime.now().toIso8601String();
      await prefs.setString(firstInstallKey, now);
      firstInstallAt = DateTime.tryParse(now) ?? DateTime.now();
      appLog('Сохранена дата первой установки: $now',
          tag: 'PREFS', level: LogLevel.info);
    }

    // ВАЖНО: Инициализируем сервис локализации ПЕРЕД использованием localizeMessage
    final localizationService = AppLocalizationService(prefs);
    await localizationService.loadSavedLanguage();
    _localizationService =
        localizationService; // Устанавливаем глобальный экземпляр

    // Инициализируем Deep Link Handler для обработки платежей
    await DeepLinkHandler().initialize();
    appLog(localizeMessage('deeplink_handler_initialized'),
        tag: 'INIT', level: LogLevel.debug);

    // Инициализируем локализацию Intl только для текущего языка,
    // остальные догружаются в фоне после старта
    final currentLocale = localizationService.getIntlLocaleString();
    await initializeIntl(currentLocale);
    appLog(localizeMessage('intl_localization_initialized'),
        tag: 'INIT', level: LogLevel.debug);

    // Переопределяем стандартные функции логирования
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        appLog(message, tag: 'FLUTTER', level: LogLevel.debug);
      }
    };

    // Расширенная обработка ошибок для отладки
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      appLog('${details.exception}', tag: 'ERROR', level: LogLevel.error);
      appLog('${details.stack}', tag: 'STACK', level: LogLevel.error);
    };

    // Отлавливаем необработанные ошибки зоны
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      appLog('Необработанная ошибка: $error',
          tag: 'FATAL', level: LogLevel.critical);
      appLog('$stack', tag: 'STACK', level: LogLevel.critical);
      return true;
    };

    try {
      // Загружаем переменные окружения из .env файла
      await dotenv.load(fileName: ".env");
      appLog(localizeMessage('env_file_loaded'),
          tag: 'ENV', level: LogLevel.info);
      logPhotosessionBackendConfigOnce();
      // Отключаем SOCKS5 и подключаем nginx image-прокси
      // независимо от Appwrite — достаточно наличия NL_SERVER_HOST + NL_PROXY_TOKEN.
      final proxyImageBase = AiProxyConfig.imageProxyBaseUrl();
      dotenv.env.remove('PIAPI_IMAGE_PROXY');
      if (proxyImageBase != null) {
        dotenv.env['NL_IMAGE_PROXY_URL'] = proxyImageBase;
      }

      if (AiProxyConfig.isEnabled) {
        // Перезаписываем URL'ы напрямую в dotenv — это гарантирует что
        // любой сервис, создающий PiApiUploadService/NanaBanana внутри себя
        // (без явного uploadUrl параметра), тоже получит прокси-адрес.
        final proxyTaskUrl = AiProxyConfig.piApiTaskUrl();
        final proxyUploadUrl = AiProxyConfig.piApiUploadUrl();
        if (proxyTaskUrl != null) {
          dotenv.env['PIAPI_TASK_URL'] = proxyTaskUrl;
        }
        if (proxyUploadUrl != null) {
          dotenv.env['PIAPI_UPLOAD_URL'] = proxyUploadUrl;
        }

        final elevenLabsProxyUrl = AiProxyConfig.elevenLabsBaseUrl();
        if (elevenLabsProxyUrl != null) {
          dotenv.env['ELEVENLABS_BASE_URL'] = elevenLabsProxyUrl;
        }

        appLog(
          'nginx AI-прокси активен — SOCKS5 отключён\n'
          '  task    : $proxyTaskUrl\n'
          '  upload  : $proxyUploadUrl\n'
          '  images  : $proxyImageBase\n'
          '  elevenlabs: $elevenLabsProxyUrl',
          tag: 'PROXY',
          level: LogLevel.info,
        );
      } else if (proxyImageBase != null) {
        appLog(
          'nginx image-прокси активен (без Appwrite) — SOCKS5 отключён\n'
          '  images  : $proxyImageBase',
          tag: 'PROXY',
          level: LogLevel.info,
        );
      }
      if (useAppwriteBackend()) {
        unawaited(ensurePresetsTagsAttribute());
        unawaited(ensurePresetsImageStyleAttribute());
        unawaited(_initAppwriteSessionAndMigrate());
      }

      // Firebase.initializeApp() — быстрая локальная операция (~100мс), ждём до runApp
      // чтобы FirebaseFirestore.instance не падал с [core/no-app].
      // signInAnonymously() — сетевой вызов, запускаем отдельно в фоне.
      await _initFirebaseApp();
      unawaited(_initFirebaseAuthInBackground());
    } catch (e) {
      appLog(localizeMessage('env_file_error', ['$e']),
          tag: 'ENV', level: LogLevel.warning);

      // Создаем переменные окружения вручную
      dotenv.env.clear(); // Очищаем перед добавлением
      dotenv.env['GOOGLE_CLOUD_VISION_API_KEY'] = 'test_key';
      dotenv.env['OPENAI_API_KEY'] = 'test_key';
      dotenv.env['CLAUDE_API_KEY'] = 'test_key';
      dotenv.env['DEEPSEEK_API_KEY'] = 'test_key';
      dotenv.env['GOOGLE_CSE_API_KEY'] = 'test_key';
      dotenv.env['GOOGLE_CSE_ID'] = 'test_id';
      dotenv.env['GOOGLE_SPEECH_API_KEY'] = 'test_key';
      dotenv.env['NANO_BANANA_API_KEY'] = 'test_key';
      dotenv.env['NANO_BANANA_ACCESS_TOKEN'] = 'test_token';
      dotenv.env['NANO_BANANA_PROJECT_ID'] = 'test_project';
      dotenv.env['NANO_BANANA_LOCATION'] = 'global';
      dotenv.env['NANO_BANANA_BASE_URL'] = 'test_url';
      dotenv.env['NANO_BANANA_MODEL'] = 'gemini-2.5-flash-image';
      dotenv.env['HUGGINGFACE_API_TOKEN'] = 'test_token';
      dotenv.env['HUGGINGFACE_IMAGE_MODEL'] = 'stabilityai/sdxl-turbo';
      dotenv.env['HUGGINGFACE_IMAGE_URL'] = 'test_url';
      dotenv.env['HUGGINGFACE_VIDEO_MODEL'] = 'cerspense/zeroscope_v2_576w';
      dotenv.env['HUGGINGFACE_VIDEO_URL'] = 'test_url';
      dotenv.env['HUGGINGFACE_WAIT_FOR_MODEL'] = 'true';
      dotenv.env['VEO2_API_KEY'] = 'test_key';
      dotenv.env['VEO2_ACCESS_TOKEN'] = 'test_token';
      dotenv.env['VEO2_PROJECT_ID'] = 'test_project';
      dotenv.env['VEO2_LOCATION'] = 'us-central1';
      dotenv.env['VEO2_MODEL'] = 'veo-2.0-generate-001';
      dotenv.env['VEO2_BASE_URL'] = 'test_url';
      dotenv.env['VEO2_STORAGE_URI'] = '';
      // VK Video API keys (fallback if .env file not found)
      dotenv.env['VKVIDEO_SERVICE_KEY'] = 'test_vk_key';
      dotenv.env['VK_API_TOKEN'] = 'test_vk_key';
      dotenv.env['VK_VIDEO_API_TOKEN'] = 'test_vk_key';
      // Yandex Search API keys (для поиска видео без капчи)
      dotenv.env['YANDEX_SEARCH_API_KEY'] = 'test_yandex_key';
      dotenv.env['YANDEX_FOLDER_ID'] = 'test_folder_id';
      dotenv.env['YANDEX_API_USER'] = 'test_user';
      // Yandex Cloud IAM (для автоматического получения API ключей)
      dotenv.env['YANDEX_OAUTH_TOKEN'] = 'test_oauth_token';
      dotenv.env['YANDEX_SERVICE_ACCOUNT_ID'] = 'test_service_account_id';

      appLog(localizeMessage('keys_created'), tag: 'ENV', level: LogLevel.info);
    }

    await MyTrackerAnalyticsService.instance.initialize();
    if (isFirstInstallLaunch) {
      await MyTrackerAnalyticsService.instance.trackFirstInstall(
        platform: defaultTargetPlatform.name,
        firstInstallDate: firstInstallAt ?? DateTime.now(),
      );
    }

    // Логируем значения ключей из .env файла (без секретов)
    appLog(localizeMessage('available_keys', [dotenv.env.keys.join(", ")]),
        tag: 'ENV', level: LogLevel.debug);

    appLog(localizeMessage('shared_prefs_initialized'),
        tag: 'PREFS', level: LogLevel.debug);

    // Инициализация сервиса покупок происходит через провайдер
    // при первом использовании

    // ── Синхронизация кредитов с сервером ─────────────────────────────────
    //
    // ВСЕГДА ждём ответа сервера синхронно, прежде чем создавать репозитории.
    // Это единственный способ гарантировать что пользователь не видит
    // «сброшенные» кредиты: ни при очистке кэша, ни при переустановке,
    // ни при любом другом способе манипуляции с локальными данными.
    //
    // Таймаут 6 сек + fail-open: если сервер недоступен — продолжаем
    // с локальными данными, не блокируем пользователя.
    try {
      final result = await DeviceRegistryService()
          .registerAndGetFirstSeen()
          .timeout(const Duration(seconds: 6));
      await _applyDeviceRegistryResult(prefs, result, appLog);

      // Migration upload: первый запуск с server-sync — загружаем
      // существующие локальные данные на сервер немедленно.
      final alreadySynced = prefs.getBool('device_registry_synced') ?? false;
      if (!alreadySynced) {
        await _doMigrationUpload(prefs, appLog);
        await prefs.setBool('device_registry_synced', true);
      }
    } catch (e) {
      appLog(
          'DEVICE_REGISTRY: ошибка ($e), fail-open — продолжаем с локальными данными',
          tag: 'PREFS',
          level: LogLevel.warning);
    }

    // Создаем репозитории
    final userRepository = SharedPrefsUserRepository(prefs);
    final subscriptionRepository = SubscriptionRepository(prefs);
    appLog(localizeMessage('repositories_created'),
        tag: 'REPOS', level: LogLevel.debug);

    // DEBUG: Форсируем подписку через флаги сборки, чтобы смоделировать сценарии
    // Использование:
    // - Годовая подписка:  --dart-define=MOCK_YEARLY=true
    // - Триал:             --dart-define=MOCK_TRIAL=true
    // Если заданы оба, приоритет у годовой подписки.
    const bool mockTrial = bool.fromEnvironment('MOCK_TRIAL');
    const bool mockYearly = bool.fromEnvironment('MOCK_YEARLY');
    if (mockTrial || mockYearly) {
      try {
        if (mockTrial) {
          await subscriptionRepository.activateTrial();
          appLog('DEBUG: Активирован триал через MOCK_TRIAL',
              tag: 'SUBSCRIPTION', level: LogLevel.warning);
        }
        if (mockYearly) {
          await subscriptionRepository.activateYearly();
          appLog('DEBUG: Активирована годовая подписка через MOCK_YEARLY',
              tag: 'SUBSCRIPTION', level: LogLevel.warning);
        }
      } catch (e) {
        appLog('DEBUG: Ошибка принудительной активации подписки: $e',
            tag: 'SUBSCRIPTION', level: LogLevel.error);
      }
    }

    // Проверяем, завершен ли онбординг (только первый запуск).
    final onboardingState =
        await userRepository.hasCompletedOnboarding() ?? false;
    appLog(localizeMessage('onboarding_flag', ['$onboardingState']),
        tag: 'ONBOARDING', level: LogLevel.info);

    // Старт с главной (витрина). Вернуть онбординг: заменить true на onboardingState ниже
    // Закомментировано - мигрировано на Firebase
    // final appwriteEndpoint = dotenv.env['APPWRITE_ENDPOINT']?.trim();
    // final appwriteProjectId = dotenv.env['APPWRITE_PROJECT_ID']?.trim();
    // final appwriteDatabaseId = dotenv.env['APPWRITE_DATABASE_ID']?.trim();
    // final appwriteCollectionId =
    //     dotenv.env['APPWRITE_PRESETS_COLLECTION_ID']?.trim();
    // final showCaseRepo = (appwriteEndpoint != null &&
    //         appwriteEndpoint.isNotEmpty &&
    //         appwriteProjectId != null &&
    //         appwriteProjectId.isNotEmpty &&
    //         appwriteDatabaseId != null &&
    //         appwriteDatabaseId.isNotEmpty &&
    //         appwriteCollectionId != null &&
    //         appwriteCollectionId.isNotEmpty)
    //     ? AppwriteShowcaseRepository(
    //         endpoint: appwriteEndpoint,
    //         projectId: appwriteProjectId,
    //         databaseId: appwriteDatabaseId,
    //         collectionId: appwriteCollectionId,
    //       )
    //     : null;

    // Firebase используется теперь через провайдеры в photosession_providers.dart
    final showCaseRepo = null; // Не используется напрямую в main.dart

    // Запускаем приложение с настроенными провайдерами
    appLog(localizeMessage('ui_start'), tag: 'MAIN', level: LogLevel.info);
    runApp(
      ProviderScope(
        observers: const [],
        overrides: [
          home.userRepositoryProvider.overrideWithValue(userRepository),
          subscription.subscriptionRepositoryProvider
              .overrideWithValue(subscriptionRepository),
          sharedPreferencesProvider.overrideWithValue(prefs),
          appLocalizationServiceProvider.overrideWithValue(localizationService),
          if (showCaseRepo != null)
            photosession.showcaseRepositoryProvider
                .overrideWithValue(showCaseRepo),
        ],
        child: _AppWithProviders(
          onboardingCompleted: true,
        ),
      ),
    );
  } catch (e, stackTrace) {
    // Ловим все необработанные исключения при старте
    appLog(localizeMessage('startup_error', ['$e']),
        tag: 'STARTUP', level: LogLevel.critical);
    appLog('$stackTrace', tag: 'STACK', level: LogLevel.critical);
    rethrow; // Перебрасываем исключение, чтобы система могла его обработать
  }
}

// Логгер для Riverpod (ОТКЛЮЧЕН)
// Данные кешируются в провайдерах через keepAlive и SharedPreferences
// UI обновляется только при явном выборе дня пользователем
// Это уменьшает количество логов и нагрузку на систему
/*
class ProviderLogger extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    appLog(
      localizeMessage('provider_updated',
          ['${provider.name ?? provider.runtimeType}', '$newValue']),
      tag: 'RIVERPOD',
      level: LogLevel.verbose,
    );
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    appLog(
      localizeMessage('provider_added',
          ['${provider.name ?? provider.runtimeType}', '$value']),
      tag: 'RIVERPOD',
      level: LogLevel.verbose,
    );
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    appLog(
      localizeMessage(
          'provider_removed', ['${provider.name ?? provider.runtimeType}']),
      tag: 'RIVERPOD',
      level: LogLevel.verbose,
    );
  }
}
*/

// Дополнительный виджет для предварительной инициализации провайдеров
class _AppWithProviders extends ConsumerStatefulWidget {
  final bool onboardingCompleted;

  const _AppWithProviders({required this.onboardingCompleted});

  @override
  _AppWithProvidersState createState() => _AppWithProvidersState();
}

class _AppWithProvidersState extends ConsumerState<_AppWithProviders>
    with WidgetsBindingObserver {
  // Флаг первого запуска - используется для предотвращения преждевременной
  // синхронизации подписки при возврате из авторизации VK в RuStore
  bool _isFirstLaunch = true;

  // Время последней синхронизации - используется для дебаунса
  DateTime? _lastSyncTime;

  // Минимальный интервал между синхронизациями (в секундах)
  static const int _minSyncIntervalSeconds = 5;

  void _applyAndroidSystemUi() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    AndroidSystemUiController.refresh();
  }

  @override
  void initState() {
    super.initState();
    // Подписываемся на изменения состояния приложения
    WidgetsBinding.instance.addObserver(this);
    _applyAndroidSystemUi();
    // Загружаем сохраненный язык
    _loadSavedLanguage();
    // IAP и paywall не нужны в первом кадре — откладываем чтобы
    // showcase-экран отрисовался без задержек.
    // Подписка уже загружена из SharedPrefs до runApp(), поэтому UI
    // показывает корректное состояние сразу, без ожидания IAP.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 2), _initializePurchaseService);
      Future.delayed(const Duration(seconds: 4), _preloadPaywallData);
    });
  }

  @override
  void dispose() {
    // Отписываемся от изменений состояния приложения
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Когда приложение возвращается на передний план
    if (state == AppLifecycleState.resumed) {
      // Повторно скрываем системную панель после сворачивания/возврата.
      _applyAndroidSystemUi();
      // Дополнительно: при каждом возврате на передний план синхронизируем подписку
      _syncSubscriptionOnResume();
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Принудительно применяем настройки UI при любых изменениях метрик
    // (включая показ/скрытие клавиатуры)
    _applyAndroidSystemUi();
  }

  /// Синхронизация статуса подписки при возврате приложения из бэкграунда
  Future<void> _syncSubscriptionOnResume() async {
    // Проверяем флаг RUSTORE для специальной обработки
    const bool isRuStoreBuild = bool.fromEnvironment('RUSTORE');

    // Для RuStore: при первом возврате (после авторизации VK) пропускаем синхронизацию
    // чтобы избежать бесконечного цикла авторизации
    if (isRuStoreBuild && _isFirstLaunch) {
      _isFirstLaunch = false;
      appLog(
          'RuStore: Пропускаем первую синхронизацию при возврате (возможно после VK авторизации)',
          tag: 'PURCHASES',
          level: LogLevel.info);

      // Даём SDK время на стабилизацию после авторизации VK
      await Future.delayed(const Duration(seconds: 2));

      // Теперь пробуем синхронизировать
      if (!mounted) return;
      try {
        final purchaseController =
            ref.read(purchase.purchaseControllerProvider);
        await purchaseController.syncSubscriptionStatus();
        _lastSyncTime = DateTime.now();
        appLog('RuStore: Первая синхронизация подписки выполнена успешно',
            tag: 'PURCHASES', level: LogLevel.info);
      } catch (e) {
        appLog('RuStore: Ошибка первой синхронизации подписки: $e',
            tag: 'PURCHASES', level: LogLevel.error);
      }
      return;
    }

    // Дебаунс: не синхронизируем слишком часто
    if (_lastSyncTime != null) {
      final secondsSinceLastSync =
          DateTime.now().difference(_lastSyncTime!).inSeconds;
      if (secondsSinceLastSync < _minSyncIntervalSeconds) {
        appLog(
            'Пропускаем синхронизацию - прошло только $secondsSinceLastSync сек с последней',
            tag: 'PURCHASES',
            level: LogLevel.debug);
        return;
      }
    }

    try {
      final purchaseController = ref.read(purchase.purchaseControllerProvider);
      await purchaseController.syncSubscriptionStatus();
      _lastSyncTime = DateTime.now();
      appLog('Синхронизация подписки при возврате выполнена',
          tag: 'PURCHASES', level: LogLevel.info);
    } catch (e) {
      appLog('Ошибка синхронизации подписки при возврате: $e',
          tag: 'PURCHASES', level: LogLevel.error);
    }
  }

  Future<void> _loadSavedLanguage() async {
    try {
      final languageNotifier = ref.read(currentLanguageProvider.notifier);
      await languageNotifier.loadSavedLanguage();

      appLog(
          'Сохраненный язык загружен: ${ref.read(currentLanguageProvider).name}',
          tag: 'LOCALIZATION',
          level: LogLevel.info);
    } catch (e) {
      appLog('Ошибка при загрузке сохраненного языка: $e',
          tag: 'LOCALIZATION', level: LogLevel.error);
    }
  }

  Future<void> _initializePurchaseService() async {
    try {
      // Получаем сервис покупок
      final purchaseService = ref.read(purchase.purchaseServiceProvider);

      // Инициализируем сервис
      appLog('Инициализация сервиса покупок',
          tag: 'PURCHASES', level: LogLevel.info);
      await purchaseService.initialize();
      // Централизованная синхронизация подписки (RuStore/IAP внутри контроллера)
      final purchaseController = ref.read(purchase.purchaseControllerProvider);
      final synced = await purchaseController.syncSubscriptionStatus();
      appLog('Статус активной подписки (после синхронизации): $synced',
          tag: 'PURCHASES', level: LogLevel.info);
    } catch (e) {
      appLog('Ошибка при инициализации сервиса покупок: $e',
          tag: 'PURCHASES', level: LogLevel.error);
    }
  }

  Future<void> _preloadPaywallData() async {
    try {
      appLog('Начинаем предварительную загрузку данных Paywall',
          tag: 'PAYWALL_PRELOADER', level: LogLevel.info);

      // Импортируем сервис предзагрузки
      final paywallPreloader = ref.read(paywallPreloaderServiceProvider);

      // Выполняем предзагрузку в фоне без блокировки UI
      paywallPreloader.preloadPaywallData().catchError((error) {
        appLog('Ошибка при предварительной загрузке Paywall: $error',
            tag: 'PAYWALL_PRELOADER', level: LogLevel.error);
      });

      appLog('Предварительная загрузка Paywall запущена в фоне',
          tag: 'PAYWALL_PRELOADER', level: LogLevel.info);
    } catch (e) {
      appLog('Ошибка при запуске предварительной загрузки Paywall: $e',
          tag: 'PAYWALL_PRELOADER', level: LogLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MyApp(onboardingCompleted: widget.onboardingCompleted);
  }
}

/// Создаёт Appwrite anonymous session и запускает soft-миграцию старых документов.
/// Firebase — запасной сервер. Инициализируется в фоне после запуска UI.
/// Быстрая локальная инициализация Firebase (~100мс).
/// Должна завершиться ДО runApp — иначе FirebaseFirestore.instance кидает [core/no-app].
Future<void> _initFirebaseApp() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    appLog('Firebase инициализирован успешно',
        tag: 'FIREBASE', level: LogLevel.info);

    if (!kIsWeb) {
      try {
        final firestore = FirebaseFirestore.instance;
        firestore.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: 100 * 1024 * 1024,
        );
        appLog('Firestore persistence включен (100MB cache)',
            tag: 'FIRESTORE', level: LogLevel.info);
      } catch (e) {
        appLog('Firestore persistence: $e',
            tag: 'FIRESTORE', level: LogLevel.warning);
      }
    }
  } catch (e) {
    appLog('Ошибка инициализации Firebase: $e',
        tag: 'FIREBASE', level: LogLevel.error);
  }
}

/// Сетевой вызов — анонимная авторизация в Firebase. Запускается в фоне.
Future<void> _initFirebaseAuthInBackground() async {
  try {
    final authService = FirebaseAnonymousAuthService.instance;
    final user = await authService.signInAnonymously();
    if (user != null) {
      appLog('Firebase Anonymous Auth: uid=${user.uid}',
          tag: 'FIREBASE_AUTH', level: LogLevel.info);
    } else {
      appLog('Firebase Anonymous Auth: не удалось авторизоваться',
          tag: 'FIREBASE_AUTH', level: LogLevel.warning);
    }
  } catch (e) {
    appLog('Ошибка Firebase Auth: $e',
        tag: 'FIREBASE_AUTH', level: LogLevel.error);
  }
}

/// Выполняется в фоне — не блокирует запуск приложения.
Future<void> _initAppwriteSessionAndMigrate() async {
  try {
    final userId = await AppwriteAuthService.instance.ensureSession();
    if (userId == null) {
      appLog('AppwriteAuth: не удалось создать сессию',
          tag: 'APPWRITE_AUTH', level: LogLevel.warning);
      return;
    }
    appLog('AppwriteAuth: uid=$userId',
        tag: 'APPWRITE_AUTH', level: LogLevel.info);

    final prefs = await SharedPreferences.getInstance();
    await GenerationMigrationService.instance.init(prefs);
    appLog(
        'GenerationMigrationService инициализирован: '
        'mode=${GenerationMigrationService.instance.mode.name}',
        tag: 'INIT',
        level: LogLevel.info);

    final deviceId = await device_id_svc.DeviceIdService.instance.getDeviceId();
    final repo = AppwriteUserGenerationRepository();
    await repo.migrateIfNeeded(deviceId);
  } catch (e) {
    appLog('AppwriteAuth: ошибка инициализации: $e',
        tag: 'APPWRITE_AUTH', level: LogLevel.error);
  }
}

class MyApp extends ConsumerWidget {
  final bool onboardingCompleted;

  const MyApp({super.key, required this.onboardingCompleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    appLog('Построение MaterialApp', tag: 'UI', level: LogLevel.debug);

    // Отслеживаем изменения языка через провайдер
    final currentLanguage = ref.watch(currentLanguageProvider);
    final localizationService = ref.watch(appLocalizationServiceProvider);
    final themeMode = ref.watch(themeModeProvider);

    appLog('Текущий язык приложения: ${currentLanguage.name}',
        tag: 'LOCALIZATION', level: LogLevel.debug);

    // Проверяем, что локализация работает
    final appTitle = localizationService.translate('app_name');
    appLog('Заголовок приложения: $appTitle',
        tag: 'LOCALIZATION', level: LogLevel.debug);

    // Обрабатываем отложенные диплинки после появления первого кадра UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkHandler().processPending();
    });

    return RestorationScope(
      restorationId: 'ai_plate_app',
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        navigatorObservers: [appRouteObserver],
        title: appTitle,
        // Устанавливаем локаль в зависимости от выбранного языка
        locale: _getLocaleFromLanguage(currentLanguage),
        // Добавляем поддержку локализации
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('ru', 'RU'),
          Locale('es', 'ES'),
          Locale('ar', 'SA'),
          Locale('he', 'IL'),
          Locale('fr', 'FR'),
          Locale('fr', 'CA'),
          Locale('fil', 'PH'),
          Locale('ja', 'JP'),
          Locale('it', 'IT'),
          Locale('ko', 'KR'),
          Locale('pt', 'BR'),
          Locale('pt', 'PT'),
          Locale('zh', 'CN'),
          Locale('uk', 'UA'),
          Locale('th', 'TH'),
          Locale('el', 'GR'),
          Locale('tr', 'TR'),
          Locale('vi', 'VN'),
          Locale('hi', 'IN'),
          Locale('de', 'DE'),
          Locale('hu', 'HU'),
          Locale('da', 'DK'),
          Locale('id', 'ID'),
          Locale('es', 'MX'),
          Locale('ca', 'ES'),
          Locale('zh', 'TW'),
          Locale('ms', 'MY'),
          Locale('nl', 'NL'),
          Locale('no', 'NO'),
          Locale('pl', 'PL'),
          Locale('ro', 'RO'),
          Locale('sk', 'SK'),
          Locale('fi', 'FI'),
          Locale('hr', 'HR'),
          Locale('cs', 'CZ'),
          Locale('sv', 'SE'),
        ],
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        // Добавляем именованные маршруты для навигации (кроме начального экрана)
        routes: {
          '/onboarding': (context) => const OnboardingScreen(),
          '/home': (context) => const HomeNavigationScreen(),
        },
        // Онбординг только при первом запуске
        home: _InitialScreenSelector(
          onboardingCompleted: onboardingCompleted,
        ),
      ),
    );
  }

  /// Получить объект Locale на основе выбранного языка
  Locale _getLocaleFromLanguage(AppLanguage language) {
    switch (language) {
      case AppLanguage.ru:
        return const Locale('ru', 'RU');
      case AppLanguage.es:
        return const Locale('es', 'ES');
      case AppLanguage.ar:
        return const Locale('ar', 'SA');
      case AppLanguage.he:
        return const Locale('he', 'IL');
      case AppLanguage.fr:
        return const Locale('fr', 'FR');
      case AppLanguage.frCA:
        return const Locale('fr', 'CA');
      case AppLanguage.fil:
        return const Locale('fil', 'PH');
      case AppLanguage.ja:
        return const Locale('ja', 'JP');
      case AppLanguage.it:
        return const Locale('it', 'IT');
      case AppLanguage.ko:
        return const Locale('ko', 'KR');
      case AppLanguage.ptBR:
        return const Locale('pt', 'BR');
      case AppLanguage.pt:
        return const Locale('pt', 'PT');
      case AppLanguage.zh:
        return const Locale('zh', 'CN');
      case AppLanguage.uk:
        return const Locale('uk', 'UA');
      case AppLanguage.th:
        return const Locale('th', 'TH');
      case AppLanguage.el:
        return const Locale('el', 'GR');
      case AppLanguage.tr:
        return const Locale('tr', 'TR');
      case AppLanguage.vi:
        return const Locale('vi', 'VN');
      case AppLanguage.hi:
        return const Locale('hi', 'IN');
      case AppLanguage.de:
        return const Locale('de', 'DE');
      case AppLanguage.hu:
        return const Locale('hu', 'HU');
      case AppLanguage.da:
        return const Locale('da', 'DK');
      case AppLanguage.id:
        return const Locale('id', 'ID');
      case AppLanguage.esMX:
        return const Locale('es', 'MX');
      case AppLanguage.ca:
        return const Locale('ca', 'ES');
      case AppLanguage.zhTW:
        return const Locale('zh', 'TW');
      case AppLanguage.ms:
        return const Locale('ms', 'MY');
      case AppLanguage.nl:
        return const Locale('nl', 'NL');
      case AppLanguage.no:
        return const Locale('no', 'NO');
      case AppLanguage.pl:
        return const Locale('pl', 'PL');
      case AppLanguage.ro:
        return const Locale('ro', 'RO');
      case AppLanguage.sk:
        return const Locale('sk', 'SK');
      case AppLanguage.fi:
        return const Locale('fi', 'FI');
      case AppLanguage.hr:
        return const Locale('hr', 'HR');
      case AppLanguage.cs:
        return const Locale('cs', 'CZ');
      case AppLanguage.sv:
        return const Locale('sv', 'SE');
      case AppLanguage.en:
        return const Locale('en', 'US');
    }
  }
}

// Создаем виджет для определения начального экрана
class _InitialScreenSelector extends StatelessWidget {
  final bool onboardingCompleted;

  const _InitialScreenSelector({required this.onboardingCompleted});

  @override
  Widget build(BuildContext context) {
    if (onboardingCompleted) {
      return const HomeNavigationScreen();
    }
    return const OnboardingScreen();
  }
}

// Инициализация локализации для Intl.
// Инициализируем только текущий язык пользователя + английский как запасной.
// Остальные языки инициализируются лениво при первом использовании в фоне.
Future<void> initializeIntl([String currentLocale = 'ru']) async {
  await initializeDateFormatting(currentLocale, null);
  if (currentLocale != 'en') {
    await initializeDateFormatting('en', null);
  }
  // Остальные языки загружаем в фоне чтобы не блокировать запуск
  unawaited(_initRemainingLocalesInBackground(currentLocale));
}

Future<void> _initRemainingLocalesInBackground(String currentLocale) async {
  const allLocales = [
    'ru',
    'en',
    'es',
    'ar',
    'he',
    'fr',
    'fil',
    'ja',
    'it',
    'ko',
    'pt',
    'zh',
    'uk',
    'th',
    'el',
    'tr',
    'vi',
    'hi',
    'de',
    'hu',
    'da',
    'id',
    'ca',
    'ms',
    'nl',
    'no',
    'pl',
    'ro',
    'sk',
    'fi',
    'hr',
    'cs',
    'sv',
  ];
  for (final locale in allLocales) {
    if (locale == currentLocale || locale == 'en') continue;
    try {
      await initializeDateFormatting(locale, null);
    } catch (_) {}
    await Future.delayed(Duration.zero);
  }
}
