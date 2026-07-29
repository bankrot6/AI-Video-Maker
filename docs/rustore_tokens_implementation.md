# Поддержка токенов в RuStore

## Обзор изменений

Добавлена полная поддержка восстановления покупок токенов для RuStore с кнопкой "Восстановить покупки" в токенном экране.

## Новые продукты RuStore

### Токенные продукты:
- `chatcoach.25k.rustore` - 25,000 токенов (99₽)
- `chatcoach.75k.rustore` - 75,000 токенов (199₽)  
- `chatcoach.200k.rustore` - 200,000 токенов (499₽)

## Изменения в коде

### 1. RuStoreBillingService (`lib/services/rustore_billing_service.dart`)

**Добавлено:**
- Константы токенных продуктов RuStore
- Метод `restoreTokenPurchases()` - восстановление только токенов
- Метод `getTokenCountFromProductId()` - получение количества токенов по ID
- Обновлен метод `restorePurchases()` для поддержки токенов

```dart
// Новые константы
static const Map<String, String> _rustoreTokenIds = {
  'small': 'chatcoach.25k.rustore',
  'medium': 'chatcoach.75k.rustore',  
  'large': 'chatcoach.200k.rustore',
};

// Новые методы
Future<List<Purchase>> restoreTokenPurchases()
int getTokenCountFromProductId(String productId)
```

### 2. PaywallScreen (`lib/features/subscription/paywall_screen.dart`)

**Добавлено:**
- Метод `_processRestoredRuStorePurchases()` - обработка подписок и токенов
- Автоматическое восстановление токенов при восстановлении покупок
- Разделение покупок на подписки и токены

### 3. TokenPurchaseScreen (`lib/features/subscription/token_purchase_screen.dart`)

**Добавлено:**
- Кнопка "Восстановить покупки" в UI
- Метод `_restoreTokenPurchases()` - восстановление токенов
- Методы показа сообщений (`_showSuccessMessage`, `_showInfoMessage`, `_showErrorMessage`)

## Логика работы

### Восстановление в основном Paywall (подписки)
1. Вызывается `ruStoreService.restorePurchases()`
2. Возвращаются все покупки (подписки + токены)
3. `_processRestoredRuStorePurchases()` разделяет их на категории
4. Подписки активируются через subscription provider
5. Токены добавляются через token provider

### Восстановление в токенном экране
1. Вызывается `ruStoreService.restoreTokenPurchases()`
2. Возвращаются только токенные покупки
3. Подсчитывается общее количество токенов
4. Токены добавляются через `tokenUsageNotifierProvider`
5. Показывается сообщение с количеством восстановленных токенов

## Использование

### Флаг RUSTORE
```bash
flutter run --dart-define=RUSTORE=true
```

### В приложении
1. **Подписки**: Paywall -> "Восстановить покупки"
2. **Токены**: Токенный экран -> "Восстановить покупки"

## Логирование

```
🛒 RUSTORE_BILLING: 🔄 Восстановление токенов RuStore...
🛒 RUSTORE_BILLING: ✅ Найдены токены: chatcoach.75k.rustore
🔄 TOKEN_RESTORE: Восстановлены токены chatcoach.75k.rustore: 75000
🟢 PAYWALL: Всего восстановлено токенов: 75000
```

## Совместимость

- ✅ RuStore (полная поддержка)
- ✅ App Store/Google Play (полная поддержка через стандартные IAP) 
- ✅ YooKassa (полная поддержка через локальное хранилище)

## Тестирование

1. Запустить с флагом `RUSTORE=true`
2. Перейти в токенный экран
3. Нажать "Восстановить покупки" 
4. Проверить логи и количество токенов

Решение готово к использованию и протестировано!
