# Руководство по поддержке RTL (Right-to-Left) языков

В приложении AI Video Maker реализована полная поддержка RTL языков (арабский и иврит).

## Поддерживаемые RTL языки

- 🇸🇦 **Арабский** (`ar`) - `AppLanguage.ar`
- 🇮🇱 **Иврит** (`he`) - `AppLanguage.he`

## Компоненты RTL системы

### 1. RTLHelper
Утилитарный класс для работы с RTL языками:

```dart
import '../services/localization/rtl_helper.dart';

// Проверка, является ли язык RTL
bool isRTL = RTLHelper.isRTL(AppLanguage.ar); // true

// Получение направления текста
TextDirection direction = RTLHelper.getTextDirection(AppLanguage.he); // TextDirection.rtl

// Получение направления из контекста
TextDirection contextDirection = RTLHelper.getTextDirectionFromContext(context);
```

### 2. RTLWrapper
Виджет-обертка для автоматической поддержки RTL:

```dart
import '../widgets/rtl_wrapper.dart';

// Автоматическое определение направления текста
RTLWrapper(
  child: YourWidget(),
)
```

### 3. RTLExtension
Расширение для BuildContext с удобными RTL методами:

```dart
// Проверка RTL
if (context.isRTL) {
  // Логика для RTL языков
}

// Получение направления текста
TextDirection direction = context.textDirection;

// RTL-совместимые отступы
EdgeInsets padding = context.rtlPadding(
  start: 16.0,  // Слева для LTR, справа для RTL
  end: 8.0,     // Справа для LTR, слева для RTL
  top: 12.0,
  bottom: 12.0,
);

// RTL-совместимое выравнивание
Alignment alignment = context.rtlAlignment(Alignment.centerLeft);
MainAxisAlignment mainAxis = context.rtlMainAxisAlignment(MainAxisAlignment.start);
CrossAxisAlignment crossAxis = context.rtlCrossAxisAlignment(CrossAxisAlignment.start);
```

## Использование в виджетах

### Базовое использование

```dart
@override
Widget build(BuildContext context) {
  return RTLWrapper(
    child: Scaffold(
      body: Column(
        children: [
          // Ваш контент автоматически адаптируется к RTL
          Text('Привет мир'), // Для RTL будет справа налево
        ],
      ),
    ),
  );
}
```

### Ручная настройка направления

```dart
Row(
  textDirection: context.textDirection, // Автоматическое определение
  children: [
    // Элементы будут расположены правильно для RTL/LTR
  ],
)
```

### RTL-совместимые отступы

```dart
Container(
  // Вместо EdgeInsets.only(left: 16, right: 8)
  padding: context.rtlPadding(start: 16, end: 8),
  child: Text('Текст с правильными отступами'),
)
```

### RTL-совместимое выравнивание

```dart
Align(
  // Для LTR: слева, для RTL: справа
  alignment: context.rtlAlignment(Alignment.centerLeft),
  child: Text('Выровненный текст'),
)
```

## Автоматическая поддержка

Следующие элементы автоматически поддерживают RTL при использовании `RTLWrapper`:

- **Text** - автоматически выравнивается по направлению письма
- **TextField** - курсор и текст располагаются правильно
- **Row/Column** - порядок элементов инвертируется для RTL
- **AppBar** - кнопки и заголовок располагаются правильно
- **Drawer** - выдвигается с правильной стороны
- **FloatingActionButton** - позиционируется корректно

## Тестирование RTL

### Переключение языка в приложении

1. Откройте экран онбординга
2. Выберите арабский (العربية) или иврит (עברית)
3. Интерфейс автоматически переключится в RTL режим

### Эмулятор

Для тестирования в эмуляторе:

**iOS Simulator:**
```
Settings → General → Language & Region → Add Language → Arabic/Hebrew
```

**Android Emulator:**
```
Settings → System → Languages & input → Languages → Add language → Arabic/Hebrew
```

## Рекомендации

### ✅ Что делать

1. **Используйте RTLWrapper** для всех основных экранов
2. **Используйте context.rtlPadding()** вместо обычных EdgeInsets
3. **Используйте context.rtlAlignment()** для выравнивания
4. **Тестируйте** интерфейс на RTL языках

### ❌ Чего избегать

1. **Не используйте** жестко заданные `TextDirection.ltr`
2. **Не используйте** фиксированные left/right отступы
3. **Не забывайте** про иконки, которые могут нуждаться в отражении
4. **Не используйте** абсолютное позиционирование без учета RTL

## Примеры использования

### Простой экран с RTL поддержкой

```dart
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return RTLWrapper(
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('my_screen_title')),
        ),
        body: Padding(
          padding: context.rtlPadding(start: 16, end: 16, top: 20),
          child: Column(
            crossAxisAlignment: context.rtlCrossAxisAlignment(CrossAxisAlignment.start),
            children: [
              Text(
                context.tr('welcome_message'),
                style: TextStyle(fontSize: 18),
              ),
              SizedBox(height: 16),
              Row(
                textDirection: context.textDirection,
                children: [
                  Icon(Icons.star),
                  SizedBox(width: 8),
                  Text(context.tr('rating')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Кастомный виджет с RTL

```dart
class CustomCard extends StatelessWidget {
  final String title;
  final String subtitle;
  
  const CustomCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: context.rtlPadding(start: 16, end: 12, top: 12, bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey),
      ),
      child: Row(
        textDirection: context.textDirection,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: context.rtlCrossAxisAlignment(CrossAxisAlignment.start),
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold)),
                Text(subtitle, style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          Icon(
            context.isRTL ? Icons.arrow_back_ios : Icons.arrow_forward_ios,
          ),
        ],
      ),
    );
  }
}
```

## Отладка RTL

Для отладки RTL проблем:

1. **Включите границы виджетов** в Flutter Inspector
2. **Используйте** `debugPrint(context.isRTL.toString())` для проверки состояния
3. **Тестируйте** на реальных устройствах с RTL языками
4. **Проверяйте** правильность отображения иконок и изображений

## Заключение

RTL поддержка в AI Video Maker обеспечивает полную локализацию для арабского и иврита. Используйте предоставленные утилиты и следуйте рекомендациям для создания RTL-совместимого интерфейса. 