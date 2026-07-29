# Потоковое отображение упражнений на главной странице

## Задача

Реализовать потоковое отображение упражнений дней 2-3 на главной странице, аналогичное тому, как это работает на онбоардинге для первого дня.

## Проблема ДО исправления

Дни 2 и 3 генерировались слишком долго и появлялись сразу все упражнения целиком:

```
Пользователь на главной странице:
↓
[Загрузка... 10-15 секунд] 
↓
День 2 появляется сразу со ВСЕМИ 6 упражнениями ❌
День 3 появляется сразу со ВСЕМИ 6 упражнениями ❌
```

## Решение ✅

Теперь упражнения появляются по одному в реальном времени:

```
Пользователь на главной странице:
↓
День 2: Заголовок появляется ✅
↓ (2 сек)
День 2: Упражнение 1 появляется ✅
↓ (2 сек)
День 2: Упражнение 2 появляется ✅
↓ (2 сек)
...
✅ День 2 полностью готов
↓
День 3: Заголовок появляется ✅
...
```

## Архитектура

### Компоненты

1. **`workoutDayStreamingProvider`** - провайдер состояния генерации дня
   - Хранит: заголовок, список упражнений, флаг активности
   - Методы: `start()`, `setTitle()`, `addExercise()`, `complete()`

2. **`BackgroundWorkoutGenerationService`** - сервис фоновой генерации
   - Интегрирован с провайдером стриминга
   - Вызывает колбеки `onTitle` и `onExercise` по мере парсинга
   - Обновляет UI в реальном времени

3. **`WeekGenerationState`** - глобальное состояние недели
   - Отслеживает какие дни генерируются
   - Показывает прогресс (completedDays/totalDays)

### Поток работы

```
ОНБОАРДИНГ:
├─ Генерирует День 1 с потоковым UI ✅
└─ Сохраняет первый день
   └─ Завершает работу (НЕ генерирует дни 2-3)

↓ Переход на главную ↓

ГЛАВНАЯ СТРАНИЦА:
├─ Обнаруживает неполный план (1/3 дней)
└─ Запускает BackgroundWorkoutGenerationService
   ├─ Инициализирует weekGenerationState
   ├─ Для каждого дня (2, 3):
   │  ├─ Отмечает начало: startDayGeneration(dayIndex)
   │  ├─ Создает провайдер: workoutDayStreamingProvider(key)
   │  ├─ Запускает: provider.start()
   │  ├─ Генерирует с колбеками:
   │  │  ├─ onTitle() → provider.setTitle()
   │  │  └─ onExercise() → provider.addExercise()
   │  ├─ UI обновляется автоматически (watch)
   │  ├─ Завершает: provider.complete()
   │  └─ Сохраняет в репозиторий
   └─ Завершает: completeWeekGeneration()
```

## Реализация

### 1. Интеграция с провайдером стриминга

**Файл:** `lib/services/workout/background_workout_generation_service.dart`

```dart
// Для каждого дня создаем уникальный ключ
final streamingKey = '${weekStart.millisecondsSinceEpoch}_$dayIndex';
final streamingProvider = workoutDayStreamingProvider(streamingKey);

// Запускаем стриминг
_ref.read(streamingProvider.notifier).start();

// Генерируем с колбеками
final dayPlan = await _generateDayWithStreaming(
  context: context,
  user: user,
  dayIndex: dayIndex,
  totalDays: totalDays,
  weekStart: weekStart,
  onTitle: (title) {
    _ref.read(streamingProvider.notifier).setTitle(title);
  },
  onExercise: (exercise) {
    _ref.read(streamingProvider.notifier).addExercise(exercise);
  },
);

// Завершаем стриминг
_ref.read(streamingProvider.notifier).complete(finalPlan: dayPlan);
```

### 2. Колбеки в генерации

```dart
Future<WorkoutPlanModel> _generateDayWithStreaming({
  required BuildContext context,
  required UserModel user,
  required int dayIndex,
  required int totalDays,
  required DateTime weekStart,
  void Function(String title)? onTitle,  // ← НОВОЕ
  void Function(ExerciseItem exercise)? onExercise,  // ← НОВОЕ
}) async {
  // ...
  
  generator.streamWorkoutText(...).listen((chunk) {
    // Парсим текстовый поток
    final parsedData = _parseStreamingText(buffer.toString());
    
    // Обрабатываем заголовок
    if (parsedData['title'] != null) {
      final newTitle = parsedData['title'] as String;
      if (currentDayTitle == null || currentDayTitle!.length < newTitle.length) {
        currentDayTitle = newTitle;
        onTitle?.call(newTitle);  // ← Вызов колбека
      }
    }
    
    // Обрабатываем упражнения
    if (parsedData['exercises'] != null) {
      for (final ex in newExercises) {
        if (!existsAlready && canAdd) {
          currentExercises.add(ex);
          onExercise?.call(ex);  // ← Вызов колбека
        }
      }
    }
  });
}
```

### 3. UI отображение (уже было реализовано)

**Файл:** `lib/features/home/home_screen.dart`

```dart
// UI автоматически обновляется через watch
final streamState = ref.watch(workoutDayStreamingProvider(streamingKey));

// Показываем заголовок
if (streamState.dayTitle != null)
  Text(streamState.dayTitle!);

// Показываем упражнения по мере появления
for (final ex in streamState.exercises) 
  _exerciseCardWithActions(...)

// Показываем шиммеры для недостающих
if (streamState.exercises.length < 6)
  Column(children: List.generate(6 - streamState.exercises.length, (_) => _skeletonExercise()))
```

## Изменения в коде

### Изменено

**1. `lib/services/workout/background_workout_generation_service.dart`**

- ✅ Добавлена инициализация `weekGenerationState`
- ✅ Добавлено создание `workoutDayStreamingProvider` для каждого дня
- ✅ Добавлены параметры `onTitle` и `onExercise` в `_generateDayWithStreaming()`
- ✅ Добавлены вызовы колбеков при парсинге текста
- ✅ Добавлен вызов `complete()` после завершения генерации

**2. `lib/features/onboarding/train_plan_screen.dart`**

- ✅ Удалены методы `_generateRemainingDaysInBackground()` и `_generateOneDayWithoutUI()`
- ✅ Теперь генерируется только первый день
- ✅ Остальные дни генерируются на главной странице

**3. `lib/features/home/home_screen.dart`**

- ✅ Увеличена задержка проверки до 2 секунд (как fallback)
- ✅ Добавлены метки (FALLBACK) в логах

### Удалено

- ❌ Дублирующая фоновая генерация на онбоардинге
- ❌ Методы генерации без UI обновлений
- ❌ Неиспользуемый импорт `home_providers` в онбоардинге

## Преимущества

### 1. Визуальная обратная связь
Пользователь видит процесс генерации в реальном времени:
- ✅ Заголовок появляется сразу
- ✅ Упражнения добавляются по одному
- ✅ Шиммеры показывают что еще загружается

### 2. Единая логика
Один и тот же алгоритм используется везде:
- Онбоардинг: День 1 с потоковым UI
- Главная: Дни 2-N с потоковым UI
- Консистентный UX

### 3. Нет дублирования работы
- Онбоардинг: генерирует только День 1
- Главная: генерирует Дни 2-N
- Никакой конкуренции за ресурсы

### 4. Производительность
- Ранняя остановка при достижении 6 упражнений
- Нет ожидания финального JSON
- Сразу показываем то что сгенерировано

## Тестирование

### Как проверить:

```bash
# 1. Очистить данные
adb shell pm clear com.yourcompany.chatcoach

# 2. Запустить приложение
flutter run

# 3. Пройти онбоардинг
- Выбрать 3 дня в неделю
- Выбрать фокусы: Грудь, Ноги, Спина
- Дождаться генерации первого дня

# 4. Перейти на главную страницу

# 5. Наблюдать
```

### Ожидаемое поведение:

**На онбоардинге:**
```
🏋️ Генерируем ВСЕ 1 дня(ей): первый с UI
📝 Заголовок дня: Тренировка груди
➕ ADDING new exercise: Жим штанги лежа
➕ ADDING new exercise: Разводка гантелей
...
✅ Первый день сохранен
✅ Первый день готов. Остальные дни (2) будут сгенерированы на главной странице
```

**На главной странице:**
```
🔄 ФОНОВАЯ ГЕНЕРАЦИЯ: Запуск генерации дней 2-3
🏋️ ФОНОВАЯ ГЕНЕРАЦИЯ: День 2/3
📝 ФОНОВАЯ ГЕНЕРАЦИЯ: Заголовок дня 2: Тренировка ног
➕ ФОНОВАЯ ГЕНЕРАЦИЯ: День 2: Приседания
➕ ФОНОВАЯ ГЕНЕРАЦИЯ: День 2: Жим ногами
➕ ФОНОВАЯ ГЕНЕРАЦИЯ: День 2: Выпады
...
✅ ФОНОВАЯ ГЕНЕРАЦИЯ: День 2/3 сохранен
🏋️ ФОНОВАЯ ГЕНЕРАЦИЯ: День 3/3
📝 ФОНОВАЯ ГЕНЕРАЦИЯ: Заголовок дня 3: Тренировка спины
...
✅ ФОНОВАЯ ГЕНЕРАЦИЯ: Все 3 дня завершены
```

**Визуально:**
- День 2: Заголовок → Упражнение 1 → Упражнение 2 → ... (по одному!)
- День 3: Заголовок → Упражнение 1 → Упражнение 2 → ... (по одному!)
- Шиммеры для незагруженных упражнений

## Производительность

### Время генерации

**До:**
```
День 2-3: [Загрузка 20-30 секунд] → [Все упражнения сразу]
```

**После:**
```
День 2: [Заголовок 0с] → [Упр 1: 2с] → [Упр 2: 4с] → ...
День 3: [Заголовок 12с] → [Упр 1: 14с] → [Упр 2: 16с] → ...
```

### Восприятие пользователем

- ❌ Было: "Почему так долго? Зависло?"
- ✅ Стало: "Ого, упражнения появляются! Идет работа!"

Perceived performance значительно улучшился!

## Заключение

Реализовано полноценное потоковое отображение генерации тренировок на главной странице:

✅ Упражнения появляются по одному
✅ Визуальная обратная связь в реальном времени
✅ Единая логика с онбоардингом
✅ Нет дублирования работы
✅ Оптимизированная производительность
✅ Улучшенный UX

---

**Статус:** ✅ Реализовано  
**Дата:** 24.10.2025  
**Версия:** 1.3

