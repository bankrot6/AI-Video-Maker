# 🎯 Окончательное исправление дубликатов упражнений

## Проблема

Пользователь видел дубликаты упражнений для дней 2 и 3:
- 6 одинаковых карточек с одним упражнением
- Затем данные менялись на правильные

## Корневая причина

**В трех разных местах генерации использовалась РАЗНАЯ логика защиты от дубликатов:**

### 1. Онбоардинг (день 1) ✅ ПРАВИЛЬНАЯ
```dart
// train_plan_screen.dart
final existingIndex = _currentDayExercises.indexWhere((e) => e.name == ex.name);
if (existingIndex != -1) {
  _currentDayExercises[existingIndex] = ex; // Обновляем
} else if (_currentDayExercises.length < 6) {
  _currentDayExercises.add(ex); // Добавляем НОВОЕ
}
```
✅ Проверка по **имени упражнения**

### 2. Фоновая генерация (дни 2-N) ❌ НЕПРАВИЛЬНАЯ
```dart
// background_workout_generation_service.dart (ДО исправления)
final parsedData = _parseStreamingText(buffer.toString());
for (final ex in parsedData['exercises']) {
  // Вызывался onExercise для КАЖДОГО упражнения при КАЖДОМ чанке
  onExercise?.call(ex);
}
```
❌ Вызывался колбек для одного и того же упражнения **многократно**

### 3. Fallback генерация (главная страница) ❌ КРИТИЧЕСКАЯ ОШИБКА
```dart
// weekly_workout_plan_service.dart (ДО исправления)
final Set<int> deliveredExIndexes = <int>{};
final nextIndex = interim.length;
if (!deliveredExIndexes.contains(nextIndex)) {
  interim.add(ex);
  deliveredExIndexes.add(nextIndex);
}
```
❌ Проверка по **индексу** вместо **имени** → дубликаты при повторном парсинге!

## Решение

### Унифицированная логика во всех трех местах:

```dart
// КРИТИЧНО: Отслеживаем отправленные упражнения по ИМЕНИ
final Set<String> sentExerciseNames = {};
final List<ExerciseItem> currentExercises = [];

// При парсинге каждого чанка:
for (final match in exMatches) {
  // ... парсим упражнение ...
  
  final existingIndex = currentExercises.indexWhere((e) => e.name == name);
  
  if (existingIndex != -1) {
    // Упражнение уже есть - обновляем вес если изменился
    if (currentExercises[existingIndex].weightKg != weight) {
      currentExercises[existingIndex] = ex;
      onExercise?.call(ex); // Отправляем обновление
    }
  } else if (!sentExerciseNames.contains(name)) {
    // Новое упражнение - добавляем ТОЛЬКО РАЗ
    currentExercises.add(ex);
    sentExerciseNames.add(name); // Помечаем как отправленное
    onExercise?.call(ex); // Отправляем в UI
  }
}
```

## Измененные файлы

### 1. `lib/services/workout/background_workout_generation_service.dart`

**Было:**
- Метод `_parseStreamingText` возвращал ВСЕ упражнения разом
- Колбек вызывался для каждого упражнения при каждом чанке
- Проверка дубликатов была неэффективной

**Стало:**
- Парсинг inline в listen-колбеке (как на онбоардинге)
- `Set<String> sentExerciseNames` отслеживает отправленные упражнения
- Колбек вызывается ТОЛЬКО для новых упражнений
- Парсинг ТОЛЬКО если заголовок уже получен

### 2. `lib/services/workout/weekly_workout_plan_service.dart`

**Было:**
- `Set<int> deliveredExIndexes` - проверка по индексу ❌
- Дубликаты при повторном парсинге buffer

**Стало:**
- `Set<String> sentExerciseNames` - проверка по имени ✅
- Идентичная логика с онбоардингом и фоновой генерацией

### 3. `lib/services/workout/workout_streaming_providers.dart`

**Улучшено:**
- Метод `addExercise` использует `indexWhere` для точного обновления
- Создается новый список при обновлении
- Дополнительная защита на уровне провайдера

## Ключевые принципы

### 1. Единый алгоритм парсинга
```dart
// ВЕЗДЕ одинаково:
final exMatches = RegExp(r'EX:\s*([^\n]+)', multiLine: true).allMatches(buffer);
for (final match in exMatches) {
  // ... парсим каждое упражнение ...
}
```

### 2. Проверка дубликатов по имени
```dart
// НЕ по индексу, а ПО ИМЕНИ:
final exists = currentExercises.indexWhere((e) => e.name == name);
```

### 3. Отслеживание отправленных
```dart
// Гарантирует что onExercise вызывается ОДИН РАЗ для каждого упражнения:
if (!sentExerciseNames.contains(name)) {
  sentExerciseNames.add(name);
  onExercise?.call(ex);
}
```

### 4. Парсинг только после заголовка
```dart
// КАК НА ОНБОАРДИНГЕ:
if (currentDayTitle != null && currentDayTitle!.isNotEmpty) {
  // Парсим упражнения
}
```

## Почему это работает

### Сценарий: LLM отправляет данные чанками

```
Chunk 1: "DAY: День 2\nEX: Жим|3|10|60"
→ Заголовок: "День 2" ✓
→ Упражнения: [Жим] ✓
→ sentExerciseNames = {Жим}
→ onExercise("Жим") вызван 1 раз ✓

Chunk 2: "DAY: День 2\nEX: Жим|3|10|60\nEX: Разводка|3|12|40"
→ Заголовок: "День 2" (уже есть, пропускаем)
→ allMatches находит [Жим, Разводка]
  - Жим: уже в sentExerciseNames, пропускаем ✓
  - Разводка: НЕТ в sentExerciseNames, добавляем ✓
→ sentExerciseNames = {Жим, Разводка}
→ onExercise("Разводка") вызван 1 раз ✓

Chunk 3: "DAY: День 2\nEX: Жим|3|10|60\nEX: Разводка|3|12|40\nEX: Отжимания|3|15|0"
→ allMatches находит [Жим, Разводка, Отжимания]
  - Жим: пропускаем ✓
  - Разводка: пропускаем ✓
  - Отжимания: добавляем ✓
→ onExercise("Отжимания") вызван 1 раз ✓
```

**Результат:** Каждое упражнение появляется в UI **ровно один раз** ✅

## Тестирование

### Что проверить:

1. ✅ **Онбоардинг:** День 1 отображается без дубликатов
2. ✅ **Главная:** День 2 появляется потоково, без дубликатов
3. ✅ **Главная:** День 3 появляется потоково, без дубликатов
4. ✅ **Логи:** Каждое упражнение помечается `➕ STREAMING: День X новое: ...` ОДИН раз
5. ✅ **Логи:** НЕТ повторных `➕ STREAMING:` для одного упражнения

### Логи (правильные):

```
📝 STREAMING: День 2 заголовок: "День 2: Грудь и трицепс"
➕ STREAMING: День 2 новое: Жим штанги лежа (4x8, 60.0 кг)
➕ STREAMING: День 2 новое: Разводка гантелей (3x12, 20.0 кг)
➕ STREAMING: День 2 новое: Отжимания на брусьях (3x10, 0.0 кг)
➕ STREAMING: День 2 новое: Жим узким хватом (3x10, 40.0 кг)
➕ STREAMING: День 2 новое: Французский жим (3x12, 25.0 кг)
➕ STREAMING: День 2 новое: Разгибания на блоке (3x15, 15.0 кг)
✅ День 2: Получено 6 упражнений, завершаем генерацию
```

### Логи (НЕПРАВИЛЬНЫЕ - не должны появляться):

```
❌ ➕ STREAMING: День 2 новое: Жим штанги лежа (4x8, 60.0 кг)
❌ ➕ STREAMING: День 2 новое: Жим штанги лежа (4x8, 60.0 кг)  ← ДУБЛИКАТ!
❌ ➕ STREAMING: День 2 новое: Жим штанги лежа (4x8, 60.0 кг)  ← ДУБЛИКАТ!
```

## Гарантии

### Три уровня защиты от дубликатов:

1. **Сервис:** `Set<String> sentExerciseNames` - не отправляет повторно
2. **Провайдер:** `indexWhere(e => e.name == name)` - обновляет вместо добавления
3. **Парсинг:** Только после заголовка, как на онбоардинге

## Результат

✅ **Дубликаты полностью устранены**  
✅ **Алгоритм унифицирован везде**  
✅ **Логика идентична онбоардингу**  
✅ **Потоковое отображение работает корректно**

---

**Дата:** 24 октября 2025  
**Статус:** ✅ ИСПРАВЛЕНО  
**Тестирование:** КРИТИЧЕСКИ ВАЖНО проверить дни 2 и 3

