# Использование RUSTORE define флага

## Обзор

Флаг `RUSTORE` позволяет принудительно активировать RuStore платежную систему для тестирования и отладки, даже если RuStore не установлен на устройстве.

## Использование

### 1. Запуск с флагом RUSTORE

```bash
# Flutter run
flutter run --dart-define=RUSTORE=true

# Flutter build
flutter build apk --dart-define=RUSTORE=true
flutter build appbundle --dart-define=RUSTORE=true

# Для других платформ
flutter build ios --dart-define=RUSTORE=true
```

### 2. Комбинирование с другими флагами

```bash
# RuStore + годовая подписка для тестирования
flutter run --dart-define=RUSTORE=true --dart-define=MOCK_YEARLY=true

# RuStore + триал для тестирования
flutter run --dart-define=RUSTORE=true --dart-define=MOCK_TRIAL=true
```

## Что происходит при активации флага

### 1. Определение источника установки
- `AppStoreDetectionService` принудительно возвращает `AppStoreType.ruStore`
- Приложение начинает использовать RuStore провайдер платежей

### 2. Инициализация RuStore сервиса
- `RuStoreBillingService` пытается инициализироваться даже без установленного RuStore
- В случае ошибки инициализации сервис все равно помечается как инициализированный

### 3. Логирование
- Все операции детально логируются с префиксом `🛒 RUSTORE_BILLING`
- Специальные отметки для режима с флагом: `"флаг RUSTORE=true"`

## Тестирование функций

### Восстановление покупок
```bash
flutter run --dart-define=RUSTORE=true
# В приложении: 
# - Подписки: Настройки -> Подписка -> Восстановить покупки
# - Токены: Чат -> Купить токены -> Восстановить покупки
```

### Покупка подписки
```bash
flutter run --dart-define=RUSTORE=true
# В приложении: перейти в Paywall и попробовать купить подписку
```

### Проверка при запуске
```bash
flutter run --dart-define=RUSTORE=true
# При запуске автоматически проверяются существующие покупки
```

## Отладка

### Логи для отслеживания
- `🏪 STORE_DETECTION: Источник установки определен по флагу: ruStore`
- `🛒 RUSTORE_BILLING: Обнаружен флаг RUSTORE=true - форсируем инициализацию`
- `🔄 PAYWALL: Восстановление покупок через RuStore`
- `🔄 TOKEN_RESTORE: Начинаем восстановление токенов`
- `🛒 RUSTORE_BILLING: ✅ Найдены токены: chatcoach.75k.rustore`

### Поиск логов
```bash
# Android
adb logcat | grep -E "(RUSTORE|STORE_DETECTION)"

# iOS (через Xcode или симулятор)
# Фильтр: RUSTORE или STORE_DETECTION
```

## Производственное использование

⚠️ **ВАЖНО**: Флаг `RUSTORE=true` НЕ должен использоваться в production сборках!

### Правильное использование в CI/CD:
```yaml
# .github/workflows/build.yml
- name: Build Debug APK with RuStore
  run: flutter build apk --debug --dart-define=RUSTORE=true
  if: github.ref == 'refs/heads/rustore-testing'

- name: Build Release APK (without flags)
  run: flutter build apk --release
  if: github.ref == 'refs/heads/main'
```

## Устранение проблем

### Проблема: Флаг не работает
1. Убедитесь, что используется точный синтаксис: `--dart-define=RUSTORE=true`
2. Проверьте логи на наличие сообщения о флаге
3. Убедитесь, что кэш сброшен: `flutter clean && flutter pub get`

### Проблема: Ошибки инициализации
1. Проверьте, что `flutter_rustore_billing` добавлен в `pubspec.yaml`
2. Убедитесь, что Android SDK настроен правильно
3. Проверьте наличие необходимых разрешений в `AndroidManifest.xml`

### Проблема: Восстановление покупок не работает
1. Убедитесь, что `handleExistingPurchases()` вызывается при запуске
2. Проверьте логи на наличие найденных покупок
3. Убедитесь, что subscription providers правильно обновляются

## Связанные файлы

- `lib/services/app_store_detection_service.dart` - определение источника установки
- `lib/services/rustore_billing_service.dart` - основная логика RuStore
- `lib/features/subscription/paywall_screen.dart` - UI для покупок и восстановления
- `lib/main.dart` - инициализация при запуске
- `lib/services/payment_providers.dart` - провайдеры платежных систем
