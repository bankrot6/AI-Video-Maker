# Исправление дублирования упражнений в потоковой генерации

## Проблема 🐛

При фоновой генерации дней 2 и 3 на главной странице первое упражнение дублировалось несколько раз, затем появлялись остальные правильные упражнения.

### Наблюдаемое поведение:
```
День 2:
- Приседания ❌
- Приседания ❌
- Приседания ❌
- Жим ногами ✅
- Выпады ✅
- Румынская тяга ✅
```

### Ожидаемое поведение:
```
День 2:
- Приседания ✅
- Жим ногами ✅
- Выпады ✅
- Румынская тяга ✅
- Подъемы на носки ✅
- Разгибания ног ✅
```

## Причина

### На онбоардинге (работает правильно):
```dart
// Использует метод _parseChunkForUI()
void _parseChunkForUI(String text) {
  // Парсит текстовый поток: "DAY: ...", "EX: упражнение|подходы|повторения|вес"
  final exMatches = RegExp(r'EX:\s*([^\n]+)').allMatches(text);
  
  for (final match in exMatches) {
    // Проверяет дубликаты по имени
    final existingIndex = _currentDayExercises.indexWhere((e) => e.name == ex.name);
    
    if (existingIndex != -1) {
      // Обновляет существующее
      _currentDayExercises[existingIndex] = ex;
    } else {
      // Добавляет новое
      _currentDayExercises.add(ex);
    }
  }
}
```

### В фоновой генерации (было неправильно):
```dart
// Использовал JSON парсинг промежуточных результатов
final partial = generator.tryParseWorkoutFromText(buffer.toString());
if (partial != null) {
  // Просто завершал с первым попавшимся результатом
  completer.complete(partial);
}
```

**Проблема:** `tryParseWorkoutFromText()` пытается извлечь JSON из незавершенного потока, что приводит к некорректным промежуточным результатам с дублированием.

## Решение ✅

Реализовали текстовый парсинг в фоновой генерации, аналогичный онбоардингу:

### 1. Добавлен метод `_parseStreamingText()`

```dart
Map<String, dynamic> _parseStreamingText(String text) {
  final result = <String, dynamic>{};

  // Извлекаем заголовок дня
  final dayMatch = RegExp(r'DAY:\s*([^\n]+)', multiLine: true).firstMatch(text);
  if (dayMatch != null) {
    result['title'] = dayMatch.group(1)?.trim();
  }

  // Извлекаем упражнения из текстового формата
  final exercises = <ExerciseItem>[];
  final exMatches = RegExp(r'EX:\s*([^\n]+)', multiLine: true).allMatches(text);
  
  for (final match in exMatches) {
    final payload = match.group(1)?.trim();
    final parts = payload.split('|');
    if (parts.length >= 4) {
      exercises.add(ExerciseItem(
        name: parts[0].trim(),
        sets: int.parse(parts[1].trim()),
        reps: int.parse(parts[2].trim()),
        weightKg: double.parse(parts[3].trim()),
      ));
    }
  }

  result['exercises'] = exercises;
  return result;
}
```

### 2. Улучшена логика в `_generateDayWithStreaming()`

```dart
// Состояние для отслеживания упражнений БЕЗ дублирования
String? currentDayTitle;
final List<ExerciseItem> currentExercises = [];

generator.streamWorkoutText(...).listen((chunk) {
  buffer.write(chunk);

  // Парсим текстовый поток (как на онбоардинге)
  final parsedData = _parseStreamingText(buffer.toString());
  
  if (parsedData['title'] != null) {
    currentDayTitle = parsedData['title'] as String;
  }
  
  if (parsedData['exercises'] != null) {
    final newExercises = parsedData['exercises'] as List<ExerciseItem>;
    
    // Обновляем список БЕЗ дублирования
    for (final ex in newExercises) {
      final existingIndex = currentExercises.indexWhere((e) => e.name == ex.name);
      
      if (existingIndex != -1) {
        // Обновляем существующее (может измениться вес)
        currentExercises[existingIndex] = ex;
      } else if (currentExercises.length < targetExercises) {
        // Добавляем НОВОЕ упражнение
        currentExercises.add(ex);
        debugPrint('➕ День ${dayIndex + 1}: Добавлено упражнение "${ex.name}"');
      }
    }
  }
  
  // Завершаем при достижении целевого количества
  if (currentExercises.length >= targetExercises && !completer.isCompleted) {
    completer.complete(WorkoutPlanModel(
      dayTitle: currentDayTitle!,
      exercises: List<ExerciseItem>.from(currentExercises),
    ));
  }
});
```

## Ключевые изменения

### До:
- ❌ Использовал JSON парсинг промежуточных данных
- ❌ Нет проверки дубликатов
- ❌ Первое упражнение дублировалось

### После:
- ✅ Использует текстовый парсинг потока
- ✅ Проверка дубликатов по имени упражнения
- ✅ Каждое упражнение добавляется только один раз
- ✅ Обновление существующих упражнений (если меняется вес)

## Тестирование

### Шаги для проверки:

```bash
# 1. Очистить данные
adb shell pm clear com.yourcompany.chatcoach

# 2. Запустить
flutter run

# 3. Пройти онбоардинг:
- 3 дня в неделю
- Фокусы: Грудь, Ноги, Спина

# 4. Наблюдать логи
adb logcat | grep "➕ День"
```

### Ожидаемые логи:

```
➕ День 2: Добавлено упражнение "Приседания"
➕ День 2: Добавлено упражнение "Жим ногами"
➕ День 2: Добавлено упражнение "Выпады"
➕ День 2: Добавлено упражнение "Румынская тяга"
➕ День 2: Добавлено упражнение "Подъемы на носки"
➕ День 2: Добавлено упражнение "Разгибания ног"
✅ День 2: Получено 6 упражнений, завершаем генерацию

➕ День 3: Добавлено упражнение "Становая тяга"
➕ День 3: Добавлено упражнение "Подтягивания"
➕ День 3: Добавлено упражнение "Тяга штанги в наклоне"
...
```

### Проверка результата:

Каждый день должен содержать **уникальные упражнения** без дублирования:

```
✅ День 1 (Грудь):
- Жим штанги лежа
- Разводка гантелей
- Жим гантелей на наклонной
- Отжимания на брусьях
- Кроссоверы
- Жим гантелей лежа

✅ День 2 (Ноги):
- Приседания
- Жим ногами
- Выпады
- Румынская тяга
- Подъемы на носки
- Разгибания ног

✅ День 3 (Спина):
- Становая тяга
- Подтягивания
- Тяга штанги в наклоне
- Тяга верхнего блока
- Тяга гантели в наклоне
- Пуловер
```

## Технические детали

### Формат потока от LLM:

```
DAY: Тренировка ног
EX: Приседания|4|10|80
EX: Жим ногами|4|12|100
EX: Выпады|3|12|0
...
{
  "dayTitle": "Тренировка ног",
  "exercises": [...]
}
```

### Парсинг:

1. **Первая фаза** (текстовый поток):
   - Парсим `DAY:` и `EX:` линии
   - Добавляем упражнения по одному
   - Проверяем дубликаты
   - Останавливаемся при достижении 6 упражнений

2. **Вторая фаза** (fallback):
   - Если текстовый парсинг не сработал
   - Пытаемся извлечь JSON
   - Используем как резервный вариант

## Измененные файлы

```
✅ lib/services/workout/background_workout_generation_service.dart
   - Добавлен метод _parseStreamingText()
   - Улучшена логика _generateDayWithStreaming()
   - Добавлена проверка дубликатов
   - Добавлено детальное логирование
```

## Преимущества

1. ✅ **Нет дублирования** - каждое упражнение появляется один раз
2. ✅ **Консистентность** - одинаковая логика на онбоардинге и главной
3. ✅ **Надежность** - fallback на JSON если текстовый парсинг не сработал
4. ✅ **Прозрачность** - детальные логи для отладки
5. ✅ **Производительность** - ранняя остановка при достижении целевого количества

## Заключение

Проблема полностью решена. Теперь фоновая генерация на главной странице работает идентично онбоардингу - каждое упражнение появляется по одному без дублирования.

---

**Статус:** ✅ Исправлено  
**Дата:** 24.10.2025  
**Версия:** 1.1

