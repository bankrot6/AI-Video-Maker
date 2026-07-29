# Реализация плана недельных фокусов и фоновой генерации тренировок

## Обзор

Реализована улучшенная система генерации недельных тренировок с учетом выбранных пользователем фокусов на группы мышц и автоматической фоновой генерацией остальных дней при переходе на главную страницу.

## Основные улучшения

### 1. Расширение модели пользователя

**Файл:** `lib/models/user_model.dart`

Добавлено новое поле `weeklyFocuses` для хранения плана распределения фокусов по дням недели:

```dart
/// План распределения фокусов по дням недели (опционально)
/// Список содержит фокус для каждого тренировочного дня
/// Длина списка должна соответствовать workoutsPerWeek
/// Например: [BodyFocus.chest, BodyFocus.legs, BodyFocus.back] для 3 дней
final List<BodyFocus>? weeklyFocuses;
```

**Преимущества:**
- Поддержка мультивыбора групп мышц из онбоардинга
- Циклическое распределение фокусов по дням недели
- Гарантия разнообразия тренировок без повторений

### 2. Улучшенный онбоардинг

**Файл:** `lib/features/onboarding/onboarding_screen.dart`

Модифицирована логика сохранения пользователя для создания плана на неделю:

```dart
// Создаем план распределения фокусов по дням недели
List<BodyFocus>? weeklyFocuses;
if (_selectedFocuses.isNotEmpty && !_selectedFocuses.contains(BodyFocus.none)) {
  final selectedList = _selectedFocuses.toList();
  weeklyFocuses = [];
  
  // Распределяем фокусы по дням недели циклически
  for (int i = 0; i < _workoutsPerWeek; i++) {
    weeklyFocuses.add(selectedList[i % selectedList.length]);
  }
}
```

**Пример:**
- Пользователь выбрал: Грудь, Ноги, Спина
- Количество дней: 5
- Результат: [Грудь, Ноги, Спина, Грудь, Ноги]

### 3. Расширенный промт генерации

**Файл:** `lib/features/onboarding/services/workout_plan_generation_service.dart`

Промт теперь включает информацию о плане на всю неделю:

```dart
// Информация о плане на неделю (если есть)
if (user.weeklyFocuses != null && user.weeklyFocuses!.isNotEmpty) {
  buffer.writeln('\nWEEKLY FOCUS PLAN:');
  for (int i = 0; i < user.weeklyFocuses!.length; i++) {
    final focus = user.weeklyFocuses![i];
    final dayNum = i + 1;
    buffer.writeln('day_$dayNum: ${focus.name}');
  }
  buffer.writeln('Use this weekly plan to ensure proper muscle group rotation...');
}
```

**Преимущества:**
- LLM видит весь план на неделю
- Избегает повторения одних и тех же упражнений
- Гарантирует правильную ротацию групп мышц

### 4. Сервис фоновой генерации

**Файл:** `lib/services/workout/background_workout_generation_service.dart`

Создан новый сервис для фоновой генерации остальных дней с потоковым отображением:

**Ключевые функции:**

#### `generateRemainingDaysInBackground()`
Запускает фоновую генерацию дней 2-N с потоковым отображением:

```dart
Future<void> generateRemainingDaysInBackground({
  required BuildContext context,
  required UserModel user,
  required DateTime weekStart,
  required WorkoutPlanModel firstDay,
  required int totalDays,
}) async {
  // Генерируем каждый день ПОСЛЕДОВАТЕЛЬНО с потоковым отображением
  for (int dayIndex = 1; dayIndex < totalDays; dayIndex++) {
    final dayPlan = await _generateDayWithStreaming(...);
    await repository.saveDayAtIndex(weekStart, dayPlan, dayIndex, totalDays);
    weekGenerationState.completeDayGeneration(dayIndex);
    _ref.invalidate(weeklyWorkoutPlanForDateProvider(weekStart));
  }
}
```

#### `_generateDayWithStreaming()`
Генерирует один день с потоковым обновлением и ранней остановкой при достижении целевого количества упражнений:

```dart
const int targetExercises = 6;

final sub = generator.streamWorkoutText(...).listen((chunk) {
  buffer.write(chunk);
  final partial = generator.tryParseWorkoutFromText(buffer.toString());
  
  if (partial != null && partial.exercises.length >= targetExercises) {
    completer.complete(partial);
  }
});
```

**Преимущества:**
- Потоковое отображение каждого дня (как на онбоардинге)
- Постепенное сохранение и обновление UI
- Ранняя остановка при достижении целевого количества упражнений
- Таймаут 60 секунд с fallback на частичный результат

### 5. Интеграция на главной странице

**Файл:** `lib/features/home/home_screen.dart`

Добавлена автоматическая проверка и запуск фоновой генерации:

```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  _loadDailyMeals();
  _requestNotificationPermissions();
  
  // НОВОЕ: Проверяем и запускаем фоновую генерацию
  _ensureWeeklyWorkoutsAreComplete();
}

Future<void> _ensureWeeklyWorkoutsAreComplete() async {
  Future.microtask(() async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    final user = ref.read(currentUserProvider);
    final weekStart = startOfWeek(DateTime.now());
    final existingPlan = await repository.getPlanForWeek(weekStart);

    if (existingPlan != null && !existingPlan.isComplete) {
      final bgService = ref.read(backgroundWorkoutGenerationServiceProvider);
      await bgService.generateRemainingDaysInBackground(...);
    }
  });
}
```

**Преимущества:**
- Автоматический запуск при первом заходе на главную страницу
- Не блокирует UI (запуск в microtask)
- Проверка на необходимость генерации
- Использует уже сгенерированный первый день

## Поток работы

### Онбоардинг

1. **Выбор фокусов** (экран 8/9)
   - Пользователь выбирает несколько групп мышц: Грудь, Ноги, Спина
   - Выбирает количество дней: 3 дня в неделю

2. **Сохранение плана**
   - Создается `weeklyFocuses: [chest, legs, back]`
   - Сохраняется в `UserModel`

3. **Генерация первого дня**
   - Промт включает информацию о плане на всю неделю
   - LLM генерирует День 1 с фокусом на Грудь
   - Потоковое отображение упражнений в UI
   - Сохранение первого дня

4. **Фоновая генерация (в онбоардинге)**
   - Дни 2-3 генерируются в фоне
   - Без блокировки перехода на главную страницу

### Главная страница (первый запуск)

1. **Инициализация**
   - Загрузка пользователя
   - Проверка плана на текущую неделю

2. **Обнаружение неполного плана**
   - План существует, но содержит только День 1
   - Дни 2-3 отсутствуют

3. **Запуск фоновой генерации**
   - Автоматический старт через 500мс
   - Генерация День 2 (Ноги) с потоковым отображением
   - Сохранение → Обновление UI
   - Генерация День 3 (Спина) с потоковым отображением
   - Сохранение → Обновление UI

4. **Результат**
   - Пользователь видит постепенное появление всех дней
   - Каждый день появляется с упражнениями по мере генерации
   - Нет долгого ожидания
   - Нет повторяющихся упражнений

## Технические детали

### Состояние генерации

Используется существующий `weekGenerationStateProvider` для отслеживания прогресса:

```dart
final state = ref.watch(weekGenerationStateProvider);
// state.isGenerating - идет ли генерация
// state.completedDays - количество завершенных дней
// state.totalDays - общее количество дней
```

### Паттерн дней недели

Автоматическое распределение тренировок по дням недели:

```dart
List<int> _getWeekdayPattern(int totalDays, DateTime weekStart) {
  // 3 дня: Пн(1), Ср(3), Пт(5)
  // 4 дня: Пн(1), Вт(2), Чт(4), Сб(6)
  // 5 дней: Пн(1), Вт(2), Ср(3), Чт(4), Пт(5)
}
```

### Обработка ошибок

- Таймаут 60 секунд на генерацию каждого дня
- Fallback на частичный результат при таймауте
- Продолжение генерации остальных дней при ошибке
- Детальное логирование всех этапов

## Преимущества реализации

### Для пользователя

1. ✅ **Персонализация** - выбор фокусов на онбоардинге
2. ✅ **Разнообразие** - нет повторения упражнений
3. ✅ **Быстрый старт** - первый день готов сразу
4. ✅ **Прогрессивная загрузка** - остальные дни появляются в фоне
5. ✅ **Визуальная обратная связь** - потоковое отображение

### Для системы

1. ✅ **SOLID принципы** - каждый сервис отвечает за свою задачу
2. ✅ **Separation of Concerns** - разделение логики онбоардинга и главной страницы
3. ✅ **Reusability** - сервис можно использовать в разных местах
4. ✅ **Testability** - легко тестировать отдельные компоненты
5. ✅ **Maintainability** - понятная структура кода

## Измененные файлы

1. `lib/models/user_model.dart` - добавлено поле `weeklyFocuses`
2. `lib/features/onboarding/onboarding_screen.dart` - создание плана на неделю
3. `lib/features/onboarding/services/workout_plan_generation_service.dart` - расширенный промт
4. `lib/services/workout/background_workout_generation_service.dart` - **НОВЫЙ** сервис
5. `lib/features/home/home_screen.dart` - интеграция фоновой генерации

## Пример логов

```
🎯 Создан план фокусов на 3 дней: chest, legs, back
🏋️ WORKOUT: Prompt length: 1542
🔄 ФОНОВАЯ ГЕНЕРАЦИЯ: Запуск для дней 2-3
🏋️ ФОНОВАЯ ГЕНЕРАЦИЯ: День 2/3
🏋️ Генерация дня 1 с потоковым обновлением
✅ День 2: Получено 6 упражнений, завершаем генерацию
✅ ФОНОВАЯ ГЕНЕРАЦИЯ: День 2/3 сохранен
🏋️ ФОНОВАЯ ГЕНЕРАЦИЯ: День 3/3
✅ День 3: Получено 6 упражнений, завершаем генерацию
✅ ФОНОВАЯ ГЕНЕРАЦИЯ: День 3/3 сохранен
✅ ФОНОВАЯ ГЕНЕРАЦИЯ: Все 3 дня завершены
```

## Заключение

Реализованная система обеспечивает:
- Плавный пользовательский опыт без долгого ожидания
- Персонализированные тренировки с учетом выбранных фокусов
- Правильную ротацию групп мышц без повторений
- Надежную архитектуру с хорошей обработкой ошибок
- Масштабируемость для будущих улучшений

Все изменения следуют лучшим практикам разработки и принципам SOLID.

