# 🌊 Унифицированные шиммеры в стиле жидкого стекла

## Проблема

**ДО:**
- **Главная страница**: Яркие белые шиммеры (`Colors.white`, `Colors.grey.shade100`) - слишком выбиваются из дизайна
- **Онбоардинг**: Полупрозрачные белые шиммеры (`Colors.white.withOpacity(0.2)`) - более мягкие
- **Несогласованность**: Разный внешний вид в разных частях приложения

## Решение

Создан унифицированный компонент `LiquidGlassShimmer` в стиле жидкого стекла, который:
- ✅ Согласован с дизайном карточек упражнений (`matteList`)
- ✅ Использует полупрозрачные цвета вместо ярких белых
- ✅ Имеет эффект `BackdropFilter` и `FakeGlass` как на реальных карточках
- ✅ Плавно переходит в карточки упражнений при загрузке
- ✅ Одинаковый на онбоардинге и главной странице

## Компоненты

### 1. `LiquidGlassShimmer` (основной)
```dart
const LiquidGlassShimmer(
  width: double.infinity,
  height: 78,
  borderRadius: 12,
)
```

**Характеристики:**
- Базовый цвет: `Color(0x20FFFFFF)` (12% белого)
- Подсветка: `Color(0x35FFFFFF)` (20% белого)
- Период анимации: 1500ms (плавная)
- BackdropFilter: `blur(sigmaX: 2, sigmaY: 2)`
- FakeGlass: `GlassSettingsConstants.matteList`

### 2. `LiquidGlassShimmerTitle` (для заголовков)
```dart
const LiquidGlassShimmerTitle(
  width: double.infinity,
  height: 24,
)
```

**Использование:** Заголовки дней тренировок

### 3. `LiquidGlassShimmerLight` (облегченный)
```dart
const LiquidGlassShimmerLight(
  width: double.infinity,
  height: 78,
  borderRadius: 12,
)
```

**Характеристики:**
- БЕЗ `BackdropFilter` и `FakeGlass` (более производительный)
- Для списков с большим количеством элементов
- Базовый цвет: `Color(0x18FFFFFF)` (9% белого)

## Визуальный переход

```
ЗАГРУЗКА → КАРТОЧКА

┌─────────────────────────┐     ┌─────────────────────────┐
│ LiquidGlassShimmer      │     │ LiquidGlassExerciseCard │
│                         │     │                         │
│ ░░░░░░░░░░░░░░░░░░░░░  │ --> │ Жим штанги лежа        │
│ (матовое стекло)        │     │ 4 подхода • 8 повторов │
│ (полупрозрачный)        │     │ 60 кг                  │
└─────────────────────────┘     └─────────────────────────┘
   ↑                                 ↑
   12-20% белого                   25% белого (matteList)
   Плавная анимация                Матовое стекло
```

**Почему это работает:**
- Оба используют полупрозрачные белые цвета (12-25%)
- Оба имеют эффект матового стекла
- Оба имеют одинаковые закругленные углы (12px)
- Плавный визуальный переход без "скачков"

## Измененные файлы

### 1. Новый файл: `lib/widgets/liquid_glass_shimmer.dart`
Содержит три компонента шиммеров в стиле жидкого стекла.

### 2. `lib/features/home/home_screen.dart`
**Было:**
```dart
Widget _skeletonExercise() {
  return Shimmer.fromColors(
    baseColor: Colors.grey.shade300,      // Светло-серый
    highlightColor: Colors.grey.shade100, // Почти белый
    child: Container(
      height: 78,
      decoration: BoxDecoration(
        color: Colors.white,                // ЯРКО БЕЛЫЙ!
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}
```

**Стало:**
```dart
Widget _skeletonExercise() {
  return const LiquidGlassShimmer(
    width: double.infinity,
    height: 78,
    borderRadius: 12,
  );
}
```

### 3. `lib/features/onboarding/train_plan_screen.dart`
**Было:**
```dart
Widget _shimmerBox({...}) {
  return Shimmer.fromColors(
    baseColor: Colors.white.withOpacity(0.2),
    highlightColor: Colors.white.withOpacity(0.4),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        ...
      ),
    ),
  );
}
```

**Стало:**
```dart
const LiquidGlassShimmer(
  width: double.infinity,
  height: 80,
  borderRadius: 16,
)
```

## Преимущества

### UX
✅ **Согласованность**: Одинаковый вид везде  
✅ **Плавность**: Мягкий переход от шиммера к карточке  
✅ **Премиум**: Эффект жидкого стекла как на реальных карточках  
✅ **Не отвлекает**: Полупрозрачный вместо яркого белого

### Производительность
✅ **Три варианта**:
  - Полный эффект (`LiquidGlassShimmer`) - для 1-6 элементов
  - Облегченный (`LiquidGlassShimmerLight`) - для списков
  - Заголовок (`LiquidGlassShimmerTitle`) - маленький вариант

✅ **Оптимизированная анимация**: 1500ms вместо 1200ms (более плавная)

### Поддержка
✅ **Единый компонент**: Изменения применяются сразу везде  
✅ **Переиспользуемый**: Можно использовать в других экранах  
✅ **Настраиваемый**: Параметры `width`, `height`, `borderRadius`

## Использование

### В списках упражнений
```dart
Column(
  children: [
    // Заголовок
    const LiquidGlassShimmerTitle(),
    const SizedBox(height: 12),
    
    // Упражнения
    for (int i = 0; i < 6; i++) ...[
      const LiquidGlassShimmer(
        height: 78,
        borderRadius: 12,
      ),
      const SizedBox(height: 12),
    ],
  ],
)
```

### Кастомные размеры
```dart
// Маленькая карточка
const LiquidGlassShimmer(
  width: 120,
  height: 40,
  borderRadius: 8,
)

// Большая карточка
const LiquidGlassShimmer(
  width: double.infinity,
  height: 120,
  borderRadius: 16,
)
```

### Производительный вариант
```dart
// Для больших списков (10+ элементов)
const LiquidGlassShimmerLight(
  height: 78,
  borderRadius: 12,
)
```

## Цветовая палитра

```
Шиммеры (загрузка):
  Base:      #FFFFFF @ 12% (0x20FFFFFF)
  Highlight: #FFFFFF @ 20% (0x35FFFFFF)
  Gradient:  #FFFFFF @ 9-6% (0x18FFFFFF → 0x10FFFFFF)

Карточки (данные):
  Glass:     #FFFFFF @ 25% (0x40FFFFFF) - matteList
  Text:      #000000 @ 87% (Colors.black87)
  Chips:     #000000 @ 7%  (полупрозрачный фон)
```

**Согласованность:** Все в диапазоне 9-25% белого, создает единый стиль "матового стекла"

## Сравнение

| Аспект | До | После |
|--------|-----|-------|
| **Главная (base)** | `Colors.grey.shade300` (RGB ~77%) | `Color(0x20FFFFFF)` (~12%) |
| **Главная (highlight)** | `Colors.grey.shade100` (RGB ~96%) | `Color(0x35FFFFFF)` (~20%) |
| **Главная (фон)** | `Colors.white` (100% белый!) | Градиент 9-6% белого |
| **Онбоардинг (base)** | `Colors.white @ 20%` | `Color(0x20FFFFFF)` (~12%) |
| **Онбоардинг (highlight)** | `Colors.white @ 40%` | `Color(0x35FFFFFF)` (~20%) |
| **Эффект стекла** | ❌ Нет | ✅ BackdropFilter + FakeGlass |
| **Согласованность** | ❌ Разные | ✅ Одинаковые |

## Результат

### Визуальный
- 🎨 Премиум вид с эффектом жидкого стекла
- 🌊 Плавный переход от загрузки к данным
- ✨ Элегантный полупрозрачный дизайн

### Технический
- 📦 Один компонент вместо разных решений
- 🔧 Легко настраивать и поддерживать
- ⚡ Три варианта для разных сценариев

### UX
- 👁️ Не отвлекает ярким белым
- 🔄 Согласованность по всему приложению
- 💎 Премиум ощущение

---

**Дата:** 24 октября 2025  
**Файл:** `lib/widgets/liquid_glass_shimmer.dart`  
**Статус:** ✅ Готово к использованию

