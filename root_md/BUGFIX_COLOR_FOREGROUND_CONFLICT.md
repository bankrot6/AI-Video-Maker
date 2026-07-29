# 🐛 Исправление бага: Конфликт color и foreground

## Проблема

При запуске приложения появлялась ошибка:

```
Cannot provide both a color and a foreground
The color argument is just a shorthand for "foreground: Paint()..color = color".
```

**Местоположение:** `lib/features/onboarding/widgets/typewriter_glitch_text.dart:169`

## Причина

В Flutter нельзя одновременно указывать `color` и `foreground` в `TextStyle`. 

Проблема возникала при использовании `copyWith()` на стиле, который уже содержал `color: Colors.black`:

```dart
// ❌ НЕПРАВИЛЬНО
style: widget.style?.copyWith(
  color: Colors.red.withValues(alpha: 0.8),  // конфликт!
  foreground: Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = Colors.red.withValues(alpha: 0.5),
)
```

`widget.style` передавался с параметром `color`, и при `copyWith` с `foreground` возникал конфликт.

## Решение

Заменил использование `copyWith()` на создание нового `TextStyle` без `color`, используя только `foreground`:

```dart
// ✅ ПРАВИЛЬНО
style: TextStyle(
  fontSize: widget.style?.fontSize ?? 32,
  fontWeight: widget.style?.fontWeight ?? FontWeight.w800,
  foreground: Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = Colors.red.withValues(alpha: 0.5),
)
```

## Измененные части

### 1. RGB Split - Красный канал (строка 161-179)
**Было:** `widget.style?.copyWith(color: ..., foreground: ...)`  
**Стало:** `TextStyle(fontSize: ..., fontWeight: ..., foreground: ...)`

### 2. RGB Split - Синий канал (строка 180-198)
**Было:** `widget.style?.copyWith(color: ..., foreground: ...)`  
**Стало:** `TextStyle(fontSize: ..., fontWeight: ..., foreground: ...)`

### 3. Белая обводка (строка 199-210)
**Было:** `widget.style?.copyWith(foreground: ...)`  
**Стало:** `TextStyle(fontSize: ..., fontWeight: ..., foreground: ...)`

### 4. Зеленый артефакт (строка 234-250)
**Было:** `widget.style?.copyWith(color: ...)`  
**Стало:** `TextStyle(fontSize: ..., fontWeight: ..., color: ...)`

## Результат

✅ Ошибка полностью устранена  
✅ Эффекты работают корректно  
✅ Нет предупреждений анализатора  
✅ Код соответствует best practices Flutter

## Проверка

```bash
flutter analyze lib/features/onboarding/widgets/typewriter_glitch_text.dart
# Результат: No issues found!
```

## Важно запомнить

В Flutter при работе с `TextStyle`:
- **Либо** используйте `color` для простого цвета
- **Либо** используйте `foreground` для сложных эффектов (градиенты, stroke и т.д.)
- **Но не оба одновременно!**

```dart
// ✅ Правильно
TextStyle(color: Colors.red)

// ✅ Правильно
TextStyle(foreground: Paint()..color = Colors.red)

// ❌ Неправильно
TextStyle(
  color: Colors.red,
  foreground: Paint()..color = Colors.blue
)
```

---

**Дата исправления:** 17 октября 2025  
**Версия:** 2.0.1 (hotfix)  
**Статус:** ✅ Исправлено и протестировано

