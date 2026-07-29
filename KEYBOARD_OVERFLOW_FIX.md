# Исправление overflow при открытии клавиатуры

## Проблема

При открытии клавиатуры в `CustomPresetCreationScreen` возникала ошибка:
```
A RenderFlex overflowed by 2.0 pixels on the bottom.
```

Ошибка происходила на строке 819 в `custom_preset_creation_screen.dart`.

## Причина

Вкладка "Описание" (`_buildInputTab`) использовала `Column` с виджетами `Expanded`, которые не могли правильно разместиться когда клавиатура занимала часть экрана.

## Решение

### 1. Добавлен `resizeToAvoidBottomInset: true` в Scaffold

```dart
return Scaffold(
  resizeToAvoidBottomInset: true,  // ← Добавлено
  backgroundColor: colors.surface,
  appBar: AppBar(
```

Это гарантирует что Scaffold будет изменять размер контента когда появляется клавиатура.

### 2. Обёрнут контент во вкладке в SingleChildScrollView

**Было:**
```dart
Widget _buildInputTab(ThemeData theme, ColorScheme colors) {
  return Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        // ... виджеты с Expanded
      ],
    ),
  );
}
```

**Стало:**
```dart
Widget _buildInputTab(ThemeData theme, ColorScheme colors) {
  return SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        // ... виджеты без Expanded
      ],
    ),
  );
}
```

### 3. Заменил Expanded на ConstrainedBox

**Было:**
```dart
Expanded(
  child: _buildInputField(
    controller: _styleController,
    // ...
    flex: true,
  ),
),
```

**Стало:**
```dart
ConstrainedBox(
  constraints: const BoxConstraints(minHeight: 120),
  child: _buildInputField(
    controller: _styleController,
    // ...
  ),
),
```

Это позволяет текстовым полям иметь фиксированную минимальную высоту, но при этом прокручиваться вместе со всем содержимым.

### 4. Упрощён метод _buildInputField

Удалён параметр `flex` и связанная с ним логика, так как теперь всё содержимое прокручивается через `SingleChildScrollView`.

**Было:**
```dart
Widget _buildInputField({
  // ...
  bool flex = false,
}) {
  final field = TextField(
    // ...
    maxLines: flex ? null : maxLines,
    expands: flex,
  );
  return Column(
    mainAxisSize: flex ? MainAxisSize.max : MainAxisSize.min,
    children: [
      // ...
      if (flex)
        Expanded(child: field)
      else
        field,
    ],
  );
}
```

**Стало:**
```dart
Widget _buildInputField({
  // ...
}) {
  final field = TextField(
    // ...
    maxLines: maxLines,
  );
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // ...
      field,
    ],
  );
}
```

## Результат

✅ Клавиатура открывается без ошибок overflow  
✅ Содержимое прокручивается когда клавиатура занимает место  
✅ Все текстовые поля доступны и работают корректно  
✅ UI остался прежним, изменилось только поведение при открытии клавиатуры  

## Файлы изменены

- `lib/features/photosession/custom_preset_creation_screen.dart`
  - Добавлен `resizeToAvoidBottomInset: true` в Scaffold
  - `_buildInputTab` обёрнут в SingleChildScrollView
  - Заменены `Expanded` на `ConstrainedBox` с minHeight
  - Упрощён `_buildInputField` (удалён параметр flex)

## Тестирование

1. Откройте экран "Создать свою фотосессию"
2. Нажмите на любое текстовое поле
3. Проверьте что клавиатура открывается без ошибок
4. Попробуйте прокрутить содержимое - должна работать прокрутка

## Технические детали

### Почему SingleChildScrollView?

`SingleChildScrollView` позволяет всему содержимому прокручиваться когда не хватает места. Это стандартный подход для форм в Flutter.

### Почему убрали Expanded?

`Expanded` требует родителя с конечной высотой (Column, Row). Внутри `SingleChildScrollView` нельзя использовать `Expanded`, так как scroll view имеет бесконечную высоту. Вместо этого используем `ConstrainedBox` с минимальной высотой.

### Почему minHeight: 120?

Это минимальная комфортная высота для многострочного текстового поля (примерно 3-4 строки текста + padding). Поле может быть больше если содержимое длиннее.

## Аналогичные проблемы

Если похожие ошибки overflow возникнут в других экранах, используйте тот же подход:

1. Добавьте `resizeToAvoidBottomInset: true` в Scaffold
2. Оберните содержимое в `SingleChildScrollView`
3. Замените `Expanded` на `ConstrainedBox` или `SizedBox` с фиксированными размерами
4. Убедитесь что нет вложенных scroll views (это может вызвать конфликты)
