# Восстановление токенов для всех платформ

## Обзор

Реализована полная поддержка восстановления токенных покупок для всех платежных систем:

- **RuStore** - через официальный RuStore SDK
- **App Store/Google Play** - через стандартные In-App Purchase (IAP)
- **YooKassa** - через локальное хранилище покупок

## Архитектура решения

### 1. Сервисы восстановления токенов

#### RuStoreBillingService
- Метод: `restoreTokenPurchases()`
- Поддерживаемые продукты: `chatcoach.25k.rustore`, `chatcoach.75k.rustore`, `chatcoach.200k.rustore`
- Логика: получение покупок через RuStore SDK

#### TokenPurchaseService  
- Метод: `restoreTokenPurchases()`
- Поддерживаемые продукты: стандартные IAP токены для iOS/Android
- Логика: восстановление через `InAppPurchase.restorePurchases()`

#### YooKassaTokenService
- Метод: `restoreTokenPurchases()`
- Поддерживаемые продукты: веб-платежи через YooKassa
- Логика: локальное хранилище в SharedPreferences

### 2. Точки восстановления

#### Основной Paywall (подписки + токены)
- Файл: `lib/features/subscription/paywall_screen.dart`
- Кнопка: "Восстановить покупки"
- Функция: восстанавливает подписки И токены одновременно

#### Токенный экран (только токены)
- Файл: `lib/features/subscription/token_purchase_screen.dart`
- Кнопка: "Восстановить покупки"
- Функция: восстанавливает только токены

## Логика работы

### RuStore
```dart
final ruStoreService = ref.read(rustoreBillingServiceProvider);
final tokenPurchases = await ruStoreService.restoreTokenPurchases();

for (final purchase in tokenPurchases) {
  final tokenCount = ruStoreService.getTokenCountFromProductId(purchase.productId);
  totalTokens += tokenCount;
}

await tokenProvider.addPurchasedTokens(totalTokens);
```

### App Store/Google Play
```dart
final tokenService = ref.read(tokenPurchaseServiceProvider);
await tokenService.initialize();
final tokenPurchases = await tokenService.restoreTokenPurchases();

for (final purchase in tokenPurchases) {
  final tokenCount = tokenService.getTokenCountFromProductId(purchase.productID);
  totalTokens += tokenCount;
}

await tokenProvider.addPurchasedTokens(totalTokens);
```

### YooKassa
```dart
final yookassaTokenService = ref.read(yookassaTokenServiceProvider);
final yookassaTokenPurchases = await yookassaTokenService.restoreTokenPurchases();

for (final purchase in yookassaTokenPurchases) {
  totalTokens += purchase.tokenCount; // уже содержит количество
}

await tokenProvider.addPurchasedTokens(totalTokens);
```

## Токенные продукты

### RuStore
- `chatcoach.25k.rustore` - 25,000 токенов (99₽)
- `chatcoach.75k.rustore` - 75,000 токенов (199₽)
- `chatcoach.200k.rustore` - 200,000 токенов (499₽)

### iOS App Store
- `chatcoach.25k` - 25,000 токенов
- `chatcoach.75k` - 75,000 токенов
- `chatcoach.200k` - 200,000 токенов

### Android Google Play
- `chatcoach.tokens.small.android` - 25,000 токенов
- `chatcoach.tokens.medium.android` - 75,000 токенов
- `chatcoach.tokens.large.android` - 200,000 токенов

### YooKassa (веб)
- `chatcoach.tokens.small.yoomoney` - 25,000 токенов
- `chatcoach.tokens.medium.yoomoney` - 75,000 токенов
- `chatcoach.tokens.large.yoomoney` - 200,000 токенов

## Провайдеры

### В payment_providers.dart добавлены:
```dart
/// Провайдер для сервиса токенных покупок через IAP
final tokenPurchaseServiceProvider = Provider<TokenPurchaseService>((ref) {
  return TokenPurchaseService();
});

/// Провайдер для сервиса токенов YooKassa
final yookassaTokenServiceProvider = Provider<YooKassaTokenService>((ref) {
  return YooKassaTokenService();
});
```

## Логирование

### RuStore
```
🛒 RUSTORE_BILLING: 🔄 Восстановление токенов RuStore...
🛒 RUSTORE_BILLING: ✅ Найдены токены: chatcoach.75k.rustore
🔄 TOKEN_RESTORE: Восстановлены токены chatcoach.75k.rustore: 75000
```

### IAP (App Store/Google Play)
```
🪙 TOKEN_IAP: 🔄 Восстановление токенных покупок...
🪙 TOKEN_IAP: ✅ Найдена токенная покупка: chatcoach.75k
🔄 TOKEN_RESTORE: Восстановлены токены IAP chatcoach.75k: 75000
```

### YooKassa
```
💳 YOOKASSA_TOKENS: 🔄 Восстановление токенных покупок YooKassa...
💳 YOOKASSA_TOKENS: ✅ Восстановлено токенных покупок: 2
🔄 TOKEN_RESTORE: Восстановлены токены YooKassa chatcoach.tokens.medium.yoomoney: 75000
```

## Тестирование

### 1. RuStore
```bash
flutter run --dart-define=RUSTORE=true
# Чат -> Купить токены -> Восстановить покупки
```

### 2. App Store (iOS)
```bash
flutter run --flavor dev
# Чат -> Купить токены -> Восстановить покупки
# Проверить TestFlight или Sandbox аккаунт
```

### 3. Google Play (Android)
```bash
flutter run --flavor dev
# Чат -> Купить токены -> Восстановить покупки
# Проверить Google Play Console тестирование
```

### 4. YooKassa
```bash
flutter run
# Локаль = RU, источник = Google Play
# Чат -> Купить токены -> Восстановить покупки
```

## Поиск логов

```bash
# Все токенные восстановления
adb logcat | grep -E "(TOKEN_RESTORE|RUSTORE_BILLING.*токены|TOKEN_IAP|YOOKASSA_TOKENS)"

# Только RuStore токены
adb logcat | grep "RUSTORE_BILLING.*токены"

# Только IAP токены  
adb logcat | grep "TOKEN_IAP"

# Только YooKassa токены
adb logcat | grep "YOOKASSA_TOKENS"
```

## Обработка ошибок

### Общие ошибки:
1. **Сервис не инициализирован** - автоматическая инициализация
2. **Нет интернета** - повторная попытка с таймаутом
3. **Магазин недоступен** - показ соответствующего сообщения
4. **Нет покупок** - информационное сообщение

### Специфичные ошибки:
- **RuStore**: проверка установки приложения
- **IAP**: проверка доступности магазина
- **YooKassa**: проверка локального хранилища

## Безопасность

### RuStore & IAP
- Верификация через официальные SDK
- Проверка подписей покупок
- Завершение транзакций

### YooKassa  
- Хранение только метаданных
- Защита от дублирования
- Автоочистка старых записей (30+ дней)

Решение готово к production использованию!
