import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

bool _truthyEnv(String? v) {
  final s = v?.trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

bool useAppwriteBackend() {
  final flag = dotenv.env['USE_APPWRITE']?.trim().toLowerCase();
  if (flag != 'true' && flag != '1' && flag != 'yes') {
    return false;
  }
  final ep = dotenv.env['APPWRITE_ENDPOINT']?.trim() ?? '';
  final project = dotenv.env['APPWRITE_PROJECT_ID']?.trim() ?? '';
  final database = dotenv.env['APPWRITE_DATABASE_ID']?.trim() ?? '';
  return ep.isNotEmpty && project.isNotEmpty && database.isNotEmpty;
}

/// Клиентская генерация ApiBost напрямую по relay (Yandex → NL) вместо вызова
/// серверной функции `apibost-proxy`. Снимает нагрузку с пула Appwrite-функций.
///
/// Требует настроенный relay (YANDEX_AI_RELAY_BASE_URL/NL_SERVER_HOST +
/// NL_PROXY_TOKEN). По умолчанию выключено — миграция постепенная, старая
/// серверная схема продолжает работать.
bool clientSideApiBostEnabled() {
  if (!_truthyEnv(dotenv.env['USE_CLIENT_SIDE_APIBOST'])) return false;
  final relay = dotenv.env['YANDEX_AI_RELAY_BASE_URL']?.trim() ?? '';
  final host = dotenv.env['NL_SERVER_HOST']?.trim() ?? '';
  final token = dotenv.env['NL_PROXY_TOKEN']?.trim() ?? '';
  if (token.isEmpty) return false;
  return relay.isNotEmpty || host.isNotEmpty;
}

bool firebaseProjectConfiguredForClient() {
  return (dotenv.env['FIREBASE_PROJECT_ID']?.trim() ?? '').isNotEmpty;
}

bool appwriteClientMirrorCredentialsOk() {
  final ep = dotenv.env['APPWRITE_ENDPOINT']?.trim() ?? '';
  final project = dotenv.env['APPWRITE_PROJECT_ID']?.trim() ?? '';
  final database = dotenv.env['APPWRITE_DATABASE_ID']?.trim() ?? '';
  return ep.isNotEmpty && project.isNotEmpty && database.isNotEmpty;
}

bool _dualBackendMirrorEnvEnabled() {
  return _truthyEnv(dotenv.env['DUAL_BACKEND_CLIENT_MIRROR']) ||
      _truthyEnv(dotenv.env['PHOTOSESSION_DUAL_STORAGE']);
}

bool _falsyEnv(String? v) {
  final s = v?.trim().toLowerCase();
  return s == 'false' || s == '0' || s == 'no' || s == 'off';
}

/// Явное отключение зеркала (иначе при Firebase+Appwrite зеркало **включено по умолчанию**).
bool clientDualBackendMirrorExplicitlyDisabled() {
  return _falsyEnv(dotenv.env['DUAL_BACKEND_CLIENT_MIRROR']) ||
      _falsyEnv(dotenv.env['PHOTOSESSION_DUAL_STORAGE']);
}

/// Двойная запись: Firestore + Appwrite и загрузка картинок в оба Storage
/// (см. [PhotosessionDualUploadService]).
bool clientDualBackendMirrorEnabled() {
  if (!firebaseProjectConfiguredForClient()) return false;
  if (clientDualBackendMirrorExplicitlyDisabled()) return false;
  return useAppwriteBackend() || appwriteClientMirrorCredentialsOk();
}

bool _photosessionBackendConfigLogged = false;

/// Один раз за запуск: почему включён или выключен dual (Firestore + Firebase Storage).
void logPhotosessionBackendConfigOnce() {
  if (_photosessionBackendConfigLogged) return;
  _photosessionBackendConfigLogged = true;

  final flagDual = dotenv.env['DUAL_BACKEND_CLIENT_MIRROR']?.trim() ?? '';
  final flagStorage = dotenv.env['PHOTOSESSION_DUAL_STORAGE']?.trim() ?? '';
  final dualEnv = _dualBackendMirrorEnvEnabled();
  final explicitOff = clientDualBackendMirrorExplicitlyDisabled();
  final fbProj = firebaseProjectConfiguredForClient();
  final useAw = useAppwriteBackend();
  final awCreds = appwriteClientMirrorCredentialsOk();
  final dual = clientDualBackendMirrorEnabled();

  debugPrint(
    '🌐 PHOTOSESSION_DUAL: DUAL_BACKEND_CLIENT_MIRROR="$flagDual" '
    'PHOTOSESSION_DUAL_STORAGE="$flagStorage" → legacyEnvTrue=$dualEnv '
    'explicitOff=$explicitOff firebaseProjectConfigured=$fbProj '
    'useAppwrite=$useAw appwriteMirrorCredsOk=$awCreds '
    '→ clientDualBackendMirrorEnabled=$dual',
  );
  if (!dual) {
    if (explicitOff) {
      debugPrint(
        '🌐 PHOTOSESSION_DUAL: зеркало отключено явным false в .env '
        '(DUAL_BACKEND_CLIENT_MIRROR / PHOTOSESSION_DUAL_STORAGE).',
      );
    } else {
      debugPrint(
        '🌐 PHOTOSESSION_DUAL: зеркало выключено — нужен FIREBASE_PROJECT_ID и '
        'либо USE_APPWRITE=true, либо endpoint+project+database в .env.',
      );
    }
  } else {
    debugPrint(
      '🌐 PHOTOSESSION_DUAL: зеркало в Firebase **включено** (запись в Appwrite + Firebase). '
      'Отключить: DUAL_BACKEND_CLIENT_MIRROR=false',
    );
  }
}
