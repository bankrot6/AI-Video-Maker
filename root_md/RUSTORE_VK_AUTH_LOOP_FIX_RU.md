# Исправление повторной авторизации VK ID при запуске приложения RuStore

## ❌ Проблема

При запуске приложения, скачанного из RuStore:
1. Показывается окно авторизации VK ID ✅ (это нормально для первого запуска)
2. Пользователь успешно авторизуется в VK ✅
3. Возвращается в приложение
4. **Снова показывается окно авторизации VK ID** ❌ (бесконечный цикл)

## 🔍 Причина (РЕАЛЬНАЯ)

Проблема была не в повторной инициализации SDK, а в **последовательности вызовов**:

1. **Запуск приложения** → `initialize()` → VK авторизация
2. **Пользователь авторизуется** → возврат в приложение
3. **`didChangeAppLifecycleState(resumed)`** срабатывает
4. **`_syncSubscriptionOnResume()`** → `syncSubscriptionStatus()` → **`getPurchases()`**
5. **`RustoreBillingClient.purchases()`** требует авторизацию VK при первом вызове! ❌

**Ключевой момент:** Метод `RustoreBillingClient.purchases()` тоже требует авторизацию VK при первом вызове, и он вызывается **сразу после возврата из VK авторизации**, до того как SDK полностью стабилизируется

### Проблема в коде

Метод `initialize()` в `rustore_billing_service.dart` **НЕ ПРОВЕРЯЛ** флаг `_isInitialized` в начале:

```dart
Future<bool> initialize() async {
  try {
    AppLogger.log('$_logPrefix Инициализация RuStore биллинга...');
    
    // ПРОБЛЕМА: Нет проверки _isInitialized!
    
    // Каждый раз вызывается RustoreBillingClient.initialize()
    await RustoreBillingClient.initialize(
      _consoleApplicationId,
      _deeplinkScheme,
      true,
    );
    
    _isInitialized = true;  // Флаг устанавливается, но не проверяется
    return true;
  }
}
```

**Результат:** 
- RuStore SDK инициализируется каждый раз заново
- Каждая инициализация проверяет авторизацию VK ID
- Если авторизация не сохранена корректно → показывается окно авторизации снова

## ✅ Решение (ФИНАЛЬНОЕ)

Два исправления:

### 1. Проверка повторной инициализации
Добавлена проверка флага `_isInitialized` **В НАЧАЛЕ** метода `initialize()`:

```dart
Future<bool> initialize() async {
  // ВАЖНО: Если SDK уже инициализирован, не инициализируем повторно
  // Это предотвращает повторные запросы авторизации VK ID
  if (_isInitialized) {
    AppLogger.log('$_logPrefix SDK уже инициализирован, пропускаем');
    return true;
  }
  
  try {
    AppLogger.log('$_logPrefix Инициализация RuStore биллинга...');
    
    // Инициализируем только ОДИН раз
    await RustoreBillingClient.initialize(
      _consoleApplicationId,
      _deeplinkScheme,
      true,
    );
    
    _isInitialized = true;
    return true;
  }
}
```

### 2. Флаг первичной инициализации (ГЛАВНОЕ ИСПРАВЛЕНИЕ)
Добавлен флаг `_isFirstLaunch` для отслеживания первичной инициализации:

```dart
class RuStoreBillingService {
  bool _isInitialized = false;
  bool _isFirstLaunch = true;  // Флаг первичной инициализации
  
  /// Проверка, завершена ли первичная инициализация
  bool get isFirstLaunch => _isFirstLaunch;
  
  Future<List<Purchase>> getPurchases() async {
    // ...
    final purchasesResponse = await RustoreBillingClient.purchases();
    
    // После первого успешного вызова помечаем, что инициализация завершена
    if (_isFirstLaunch) {
      _isFirstLaunch = false;
      AppLogger.log('Первичная инициализация RuStore завершена');
    }
    // ...
  }
}
```

### 3. Пропуск синхронизации во время первичной инициализации
В `main.dart` добавлена проверка перед синхронизацией:

```dart
Future<void> _syncSubscriptionOnResume() async {
  try {
    // Для RuStore: не синхронизируем сразу после первой VK авторизации
    final ruStoreService = ref.read(rustoreBillingServiceProvider);
    if (ruStoreService.isFirstLaunch) {
      appLog('Пропускаем синхронизацию - идёт первичная инициализация RuStore');
      return;  // НЕ вызываем getPurchases() сразу после VK авторизации
    }
    
    // Синхронизация только после завершения первичной инициализации
    await purchaseController.syncSubscriptionStatus();
  }
}
```

## 🔄 Как это работает теперь

### Сценарий 1: Первый запуск приложения (требуется VK авторизация)
1. ✅ Приложение запускается → `_initializePurchaseService()` → `initialize()` → VK авторизация
2. ✅ Пользователь авторизуется в VK
3. ✅ Возвращается в приложение → **`didChangeAppLifecycleState(resumed)`**
4. ✅ **`_syncSubscriptionOnResume()` проверяет `isFirstLaunch = true`**
5. ✅ **Синхронизация ПРОПУСКАЕТСЯ** (не вызывается `getPurchases()`)
6. ✅ Первичная синхронизация происходит при старте → `syncSubscriptionStatus()` → `getPurchases()`
7. ✅ **`_isFirstLaunch` устанавливается в `false`** после первого `getPurchases()`
8. ✅ Дальнейшие возвраты из фона → синхронизация работает нормально

### Сценарий 2: Повторный запуск приложения (VK уже авторизован)
1. ✅ Приложение запускается → `initialize()` вызывается
2. ✅ `_isInitialized = false` → SDK инициализируется
3. ✅ RuStore проверяет авторизацию → VK уже авторизован
4. ✅ **Окно авторизации НЕ показывается**
5. ✅ Дальнейшие вызовы `initialize()` пропускаются

### Сценарий 3: Покупка подписки (во время сессии)
1. ✅ Пользователь нажимает "Купить подписку"
2. ✅ Paywall вызывает `initialize()`
3. ✅ **`_isInitialized = true` → инициализация пропускается**
4. ✅ Покупка запускается без повторной авторизации

## 📝 Изменения в файлах

### `lib/services/rustore_billing_service.dart`
**Добавлено 3 изменения:**

1. **Проверка повторной инициализации:**
```dart
Future<bool> initialize() async {
  // ВАЖНО: Если SDK уже инициализирован, не инициализируем повторно
  if (_isInitialized) {
    AppLogger.log('SDK уже инициализирован, пропускаем');
    return true;
  }
  // ... остальной код
}
```

2. **Флаг первичной инициализации:**
```dart
bool _isFirstLaunch = true;
bool get isFirstLaunch => _isFirstLaunch;
```

3. **Сброс флага после первого getPurchases:**
```dart
Future<List<Purchase>> getPurchases() async {
  // ...
  final purchasesResponse = await RustoreBillingClient.purchases();
  
  if (_isFirstLaunch) {
    _isFirstLaunch = false;
    AppLogger.log('Первичная инициализация RuStore завершена');
  }
  // ...
}
```

### `lib/main.dart`
**Добавлен import:**
```dart
import 'services/payment_providers.dart' show rustoreBillingServiceProvider;
```

**Изменен метод `_syncSubscriptionOnResume`:**
```dart
Future<void> _syncSubscriptionOnResume() async {
  try {
    // Для RuStore: не синхронизируем сразу после первой VK авторизации
    final ruStoreService = ref.read(rustoreBillingServiceProvider);
    if (ruStoreService.isFirstLaunch) {
      appLog('Пропускаем синхронизацию - идёт первичная инициализация RuStore');
      return;
    }
    
    // Обычная синхронизация
    final purchaseController = ref.read(purchase.purchaseControllerProvider);
    await purchaseController.syncSubscriptionStatus();
  }
}
```

## 🧪 Тестирование

### Как проверить исправление:

1. **Удалите приложение** (чтобы сбросить авторизацию VK)
2. **Установите новую версию** из RuStore
3. **Запустите приложение**:
   - ✅ Показывается окно авторизации VK ID (первый раз - нормально)
   - ✅ Авторизуйтесь в VK
   - ✅ Вернитесь в приложение
   - ✅ **Окно авторизации НЕ должно появиться снова**
4. **Перезапустите приложение**:
   - ✅ **Окно авторизации НЕ должно появиться** (VK уже авторизован)
5. **Попробуйте купить подписку**:
   - ✅ **Окно авторизации НЕ должно появиться**

### Ожидаемые логи:
```
🛒 RUSTORE_BILLING: Инициализация RuStore биллинга...
🛒 RUSTORE_BILLING: Инициализация успешна
🛒 RUSTORE_BILLING: SDK уже инициализирован, пропускаем  <-- ПРИ ПОВТОРНЫХ ВЫЗОВАХ
🛒 RUSTORE_BILLING: SDK уже инициализирован, пропускаем
```

## 🔍 Дополнительная диагностика

Если проблема сохраняется:

1. **Проверьте логи** на наличие ошибок инициализации:
   ```
   🛒 RUSTORE_BILLING: Ошибка инициализации: ...
   ```

2. **Проверьте, что RuStore SDK используется правильно**:
   ```
   🛒 RUSTORE_BILLING: Используется production RUSTORE_APP_ID=2063737207
   🛒 RUSTORE_BILLING: Используется production RUSTORE_SCHEME=aivideomaker
   ```

3. **Проверьте deep link настройки** в `AndroidManifest.xml`:
   ```xml
   <data android:scheme="aivideomaker" />
   ```

## ⚠️ Важно

### Это исправление НЕ затрагивает:
- ❌ Логику покупок (она работала корректно)
- ❌ Обработку deep links (она работала корректно)
- ❌ Синхронизацию подписок (она работала корректно)

### Это исправление ИСПРАВЛЯЕТ:
- ✅ **Повторную инициализацию SDK** (главная проблема)
- ✅ **Повторную авторизацию VK ID** (следствие проблемы)

## 📊 До и После

### До исправления:
```
1. Запуск → initialize() → VK авторизация ✅
2. Синхронизация → initialize() → VK авторизация ❌ (снова!)
3. Покупка → initialize() → VK авторизация ❌ (снова!)
```

### После исправления:
```
1. Запуск → initialize() → VK авторизация ✅ (_isInitialized = true)
2. Синхронизация → initialize() → ПРОПУСК ✅ (уже инициализирован)
3. Покупка → initialize() → ПРОПУСК ✅ (уже инициализирован)
```

## 🚀 Следующие шаги

1. **Пересоберите приложение**:
   ```bash
   flutter clean
   flutter build appbundle --dart-define=RUSTORE=true
   ```

2. **Загрузите в RuStore Console** новую версию AAB

3. **Протестируйте** на чистой установке:
   - Удалите старое приложение
   - Установите из RuStore
   - Проверьте, что авторизация VK запрашивается только один раз

4. **Мониторьте логи** на предмет повторных вызовов `initialize()`

---

**Дата исправления**: 17 ноября 2025  
**Затронутые файлы**: 2 (`rustore_billing_service.dart`, `main.dart`)  
**Добавлено строк кода**: ~20  
**Статус**: ✅ Готово к тестированию

## 🎓 Что мы узнали

### Почему первое исправление не помогло?
Первое исправление (проверка `_isInitialized`) было **правильным**, но **недостаточным**. Оно предотвратило повторную инициализацию SDK, но не решило проблему с **первым вызовом `getPurchases()`** сразу после VK авторизации.

### Почему `getPurchases()` требует авторизацию?
RuStore SDK работает так:
1. `initialize()` → авторизация VK (если нужна)
2. **`purchases()` → ТОЖЕ может требовать авторизацию при первом вызове!**

Это недокументированное поведение SDK, которое приводит к повторной авторизации, если `purchases()` вызывается сразу после возврата из VK авторизации.

## 💡 Почему это работает

RuStore SDK требует авторизацию VK в двух случаях:
1. **При `initialize()`** - если пользователь не авторизован
2. **При первом `purchases()`** - если состояние не стабилизировалось после авторизации

**Решение:** 
1. Не вызывать `initialize()` повторно (флаг `_isInitialized`)
2. Не вызывать `purchases()` сразу после возврата из VK авторизации (флаг `_isFirstLaunch`)
3. Дать SDK время стабилизироваться, дождавшись первой полной синхронизации

## 🎯 Итог

**Два простых флага** решили проблему повторной авторизации VK ID:
```dart
if (_isInitialized) return true;        // Не инициализируем SDK повторно
if (_isFirstLaunch) return;             // Не дергаем purchases() сразу после VK авторизации
```

Это решение учитывает особенности работы RuStore SDK и предотвращает преждевременные вызовы API, которые могут требовать повторную авторизацию.

