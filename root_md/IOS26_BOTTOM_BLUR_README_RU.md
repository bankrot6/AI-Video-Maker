# 🌊 iOS 26 Размытие нижней части контента

## 📱 Описание

Реализован эффект размытия нижней части контента под навигационным баром, аналогичный iOS 26. Вместо жесткого обрезания контента, теперь используется плавное **fade-out** с **градиентным размытием**.

---

## 🎨 Что было реализовано

### 1️⃣ **Новый виджет: `BottomContentBlur`**
**Файл:** `lib/widgets/bottom_content_blur.dart`

Универсальная система из трех виджетов для создания эффекта размытия снизу:

#### **BottomContentBlur** - Размытие контента
```dart
BottomContentBlur(
  blurHeight: 140.0,         // Высота области размытия
  blurIntensity: 15.0,       // Интенсивность размытия (sigma)
  overlayColor: Colors.black, // Цвет наложения
)
```

**Особенности:**
- Использует `BackdropFilter` с `ImageFilter.blur`
- Градиент от прозрачного к полупрозрачному
- Не перехватывает касания (`IgnorePointer`)
- Positioned снизу экрана

#### **BottomFadeMask** - Маска затухания
```dart
BottomFadeMask(
  fadeHeight: 140.0,    // Высота области затухания
  fadeStart: 0.75,      // Где начинается затухание (0.0-1.0)
  child: YourContent(), // Контент для размытия
)
```

**Особенности:**
- Использует `ShaderMask` для плавного исчезновения контента
- Градиент от непрозрачного к прозрачному
- Применяется к контенту, а не к фону

#### **IOSStyleBottomBlur** - Комбинированный виджет
```dart
IOSStyleBottomBlur(
  effectHeight: 120.0,
  blurIntensity: 15.0,
  fadeStart: 0.80,
  child: YourContent(),
)
```

**Особенности:**
- Объединяет `BottomFadeMask` + `BottomContentBlur`
- Максимально приближен к эффекту iOS 26
- Удобен для быстрого применения

---

## 🛠️ Интеграция в экраны

Эффект был интегрирован во все экраны с нижней навигацией:

### ✅ HomeScreen
**Файл:** `lib/features/home/home_screen.dart`

**До:**
```dart
Expanded(
  child: Container(
    margin: const EdgeInsets.only(bottom: 100), // Жесткое обрезание
    clipBehavior: Clip.hardEdge,
    child: SingleChildScrollView(...)
  ),
)
```

**После:**
```dart
Expanded(
  child: Stack(
    children: [
      BottomFadeMask(
        fadeHeight: 140.0,
        fadeStart: 0.75,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 140),
          child: ...,
        ),
      ),
      BottomContentBlur(
        blurHeight: 140.0,
        blurIntensity: 15.0,
        overlayColor: Colors.black,
      ),
    ],
  ),
)
```

### ✅ AnalyticsScreen
**Файл:** `lib/features/analytics/analytics_screen.dart`

Применен к `CustomScrollView` с `Slivers`:
```dart
Stack(
  children: [
    BottomFadeMask(
      child: RefreshIndicator(
        child: CustomScrollView(
          slivers: [
            // ... контент
            SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ),
      ),
    ),
    BottomContentBlur(blurHeight: 140.0, ...),
  ],
)
```

### ✅ ProfileSettingsScreen
**Файл:** `lib/features/profile/profile_settings_screen.dart`

Применен к `ListView`:
```dart
Stack(
  children: [
    BottomFadeMask(
      child: ListView(
        padding: const EdgeInsets.only(bottom: 140),
        children: [...],
      ),
    ),
    BottomContentBlur(blurHeight: 140.0, ...),
  ],
)
```

### ✅ AddScreen
**Файл:** `lib/features/add/add_screen.dart`

Применен к простому контенту + добавлено фоновое изображение:
```dart
Stack(
  children: [
    Positioned.fill(child: Image.asset(...)), // Фон
    SafeArea(
      child: Stack(
        children: [
          BottomFadeMask(
            child: SingleChildScrollView(...),
          ),
          BottomContentBlur(blurHeight: 140.0, ...),
        ],
      ),
    ),
  ],
)
```

### ✅ HistoryScreen
**Файл:** `lib/features/history/history_screen.dart`

Применен к `CustomScrollView` + изменен фон:
- Изменен `backgroundColor` с `Color(0xFFF5F5F5)` на `Colors.black`
- Добавлено фоновое изображение
- Добавлен эффект размытия

---

## 🎯 Технические детали

### Параметры эффекта

Все экраны используют единые параметры для консистентности:

| Параметр | Значение | Описание |
|----------|----------|----------|
| `blurHeight` | `140.0` | Высота области размытия (px) |
| `blurIntensity` | `15.0` | Интенсивность размытия (sigma) |
| `fadeStart` | `0.75` | Начало затухания контента (75% от высоты) |
| `overlayColor` | `Colors.black` | Цвет наложения для темных тем |
| `bottomPadding` | `140` | Отступ снизу в ScrollView |

### Структура Stack

Правильная последовательность виджетов:

```dart
Stack(
  children: [
    // 1. Контент с fade-out маской (внизу стека)
    BottomFadeMask(
      child: ScrollableContent(...),
    ),
    
    // 2. Размытие (сверху контента)
    BottomContentBlur(...),
  ],
)
```

### Использование с SafeArea

Важно установить `bottom: false` для `SafeArea`:

```dart
SafeArea(
  bottom: false, // ❗ Важно! Позволяет контенту уходить под меню
  child: Stack(...),
)
```

---

## 🔄 До и После

### До реализации:
- ❌ Контент жестко обрезался снизу
- ❌ Использовался `margin` + `Clip.hardEdge`
- ❌ Резкий переход между контентом и меню
- ❌ Разный padding в разных экранах (100px, 110px)

### После реализации:
- ✅ Плавное размытие контента снизу
- ✅ Градиентное затухание (fade-out)
- ✅ Естественный переход как в iOS 26
- ✅ Единый стиль во всех экранах (140px)
- ✅ Улучшенный UX и визуальная привлекательность

---

## 🎨 Визуальный эффект

Эффект создает иллюзию, что:
1. Контент **плавно исчезает** снизу (fade-out)
2. Область под меню **размыта** (blur)
3. Переход выглядит **естественно** и **плавно**

Это соответствует лучшим практикам современного UI/UX дизайна и паттернам iOS 26.

---

## 🚀 Преимущества подхода

### 1. **Производительность**
- Использует нативный `BackdropFilter` (аппаратное ускорение)
- Легковесный `ShaderMask` для fade-out
- Не создает дополнительных слоев рендеринга

### 2. **Гибкость**
- Легко настраиваемые параметры
- Работает с любым типом контента (ListView, CustomScrollView, Column)
- Можно применить к любому экрану

### 3. **Консистентность**
- Единый стиль во всех экранах
- Одинаковые параметры размытия
- Соответствие дизайн-системе

### 4. **UX**
- Плавные переходы
- Естественное поведение как в iOS
- Улучшенная читаемость контента

---

## 📋 Чеклист интеграции

Если нужно добавить эффект в новый экран:

- [ ] Импортировать `bottom_content_blur.dart`
- [ ] Обернуть `Scaffold.body` в `Stack`
- [ ] Добавить фоновое изображение (опционально)
- [ ] Установить `SafeArea(bottom: false)`
- [ ] Обернуть контент в `BottomFadeMask`
- [ ] Добавить `BottomContentBlur` в Stack
- [ ] Добавить `padding` снизу в ScrollView (140px)
- [ ] Установить `extendBody: true` в Scaffold

---

## 🎓 Лучшие практики

### ✅ Правильно
```dart
// Использовать Stack с правильной последовательностью
Stack(
  children: [
    BottomFadeMask(child: Content()),
    BottomContentBlur(),
  ],
)

// Единые параметры
blurHeight: 140.0
fadeStart: 0.75
```

### ❌ Неправильно
```dart
// НЕ использовать margin + clip
Container(
  margin: EdgeInsets.only(bottom: 100),
  clipBehavior: Clip.hardEdge,
  child: Content(),
)

// НЕ ставить BottomContentBlur под контент
Stack(
  children: [
    BottomContentBlur(), // ❌ Неправильный порядок
    BottomFadeMask(child: Content()),
  ],
)
```

---

## 📦 Файлы

### Новые файлы
- `lib/widgets/bottom_content_blur.dart` - система виджетов

### Изменённые файлы
- `lib/features/home/home_screen.dart`
- `lib/features/analytics/analytics_screen.dart`
- `lib/features/profile/profile_settings_screen.dart`
- `lib/features/add/add_screen.dart`
- `lib/features/history/history_screen.dart`

---

## 🎉 Результат

✨ **Все экраны с нижней навигацией теперь имеют плавное размытие контента снизу, как в iOS 26!**

Эффект полностью соответствует лучшим практикам современного дизайна и создает премиальное ощущение от использования приложения.

---

## 🔍 Примеры использования

### Базовое применение
```dart
Stack(
  children: [
    BottomFadeMask(
      child: YourScrollableContent(),
    ),
    BottomContentBlur(),
  ],
)
```

### С кастомными параметрами
```dart
Stack(
  children: [
    BottomFadeMask(
      fadeHeight: 200.0,
      fadeStart: 0.70,
      child: YourContent(),
    ),
    BottomContentBlur(
      blurHeight: 200.0,
      blurIntensity: 20.0,
      overlayColor: Colors.blue,
    ),
  ],
)
```

### Упрощенный вариант
```dart
IOSStyleBottomBlur(
  effectHeight: 140.0,
  child: YourContent(),
)
```

---

**Дата реализации:** 23 октября 2025  
**Версия:** 1.0.0  
**Совместимость:** Flutter 3.0+, Dart 3.0+

