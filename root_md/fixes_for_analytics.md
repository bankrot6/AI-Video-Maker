# Исправления для страницы аналитики

## Описание проблем
1. Нелокализованные месяцы в календаре
2. Отображение "goal_label" вместо локализованного текста
3. Сломанный алгоритм построения графиков, который должен показывать рандомные данные для дней без данных

## Решения

### 1. Нелокализованные месяцы в календаре
В файле `lib/widgets/week_selector_header.dart` изменили жестко заданную локаль 'ru' на текущий язык пользователя:

```dart
// Было
final dateFormat = DateFormat('dd MMM', 'ru');
final monthFormat = DateFormat('MMM', 'ru');

// Стало
final localizationService = ref.watch(appLocalizationServiceProvider);
final locale = localizationService.getCurrentLanguage().name;
    
final dateFormat = DateFormat('dd MMM', locale);
final monthFormat = DateFormat('MMM', locale);
```

### 2. Отображение "goal_label" вместо локализованного текста
Добавили локализацию для ключа 'goal_label' в файл `lib/services/localization/app_localization_service.dart`:

```dart
// Русская локализация
'goal_label': 'Цель',

// Английская локализация
'goal_label': 'Goal',
```

### 3. Сломанный алгоритм построения графиков
В файле `lib/features/analytics/analytics_screen.dart` изменили алгоритм построения графиков, чтобы он показывал случайные данные для прошедших дней без данных:

- В методе `_buildWeeklyCaloriesChart` добавили генерацию случайных значений для дней, у которых нет данных
- В методе `_buildTripleNutrientsChart` добавили такую же логику для генерации случайных значений БЖУ

### Дополнительные исправления
В методе `initState` изменили жестко заданную локализацию на получение текущего языка пользователя:

```dart
// Было
initializeDateFormatting('ru', null);

// Стало
final localizationService = ref.read(appLocalizationServiceProvider);
final locale = localizationService.getCurrentLanguage().name;
initializeDateFormatting(locale, null);
```

## Возможные проблемы после исправлений
1. Если проблемы сохраняются после внесения изменений, возможно, потребуется полная пересборка приложения (`flutter clean && flutter pub get && flutter run`)
2. Может потребоваться перезапуск приложения на устройстве с полной очисткой кэша
3. В некоторых случаях бывает полезно обновить генерацию файлов локализации (если проект использует генерацию из ARB-файлов) 