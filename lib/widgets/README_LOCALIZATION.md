# Локализация в AI Video Maker

В приложении AI Video Maker реализована система локализации, позволяющая переключаться между различными языками интерфейса.

## Структура локализации

Система локализации состоит из следующих компонентов:

1. **AppLocalizationService** - сервис для работы с локализацией, хранит словари с переводами и предоставляет методы для доступа к ним.
2. **LanguageSelector** - виджет для выбора языка интерфейса.
3. **LocalizationExtension** - расширение контекста для удобного доступа к локализованным строкам через метод `tr()`.

## Использование локализации в коде

### Получение локализованного текста

Для получения локализованного текста используйте метод `tr()`, который доступен в контексте любого виджета:

```dart
// Вместо обычного текста
Text('Unlimited Access');

// Используйте локализованный текст
Text(context.tr('unlimited_access'));
```

### Добавление виджета выбора языка

Чтобы добавить виджет выбора языка на экран, импортируйте и используйте `LanguageSelector`:

```dart
import '../../widgets/language_selector.dart';

// В методе build виджета:
appBar: AppBar(
  title: const Text('AI Video Maker'),
  actions: [
    // Добавляем селектор языка
    const LanguageSelector(),
    // Другие действия
  ],
),
```

### Добавление новых строк для локализации

Для добавления новых строк для локализации отредактируйте словари `_russianTranslations` и `_englishTranslations` в файле `lib/services/localization/app_localization_service.dart`:

```dart
static final Map<String, String> _russianTranslations = {
  // Добавьте новую строку
  'new_key': 'Новая строка на русском',
};

static final Map<String, String> _englishTranslations = {
  // Добавьте соответствующую строку на английском
  'new_key': 'New string in English',
};
```

## Добавление поддержки нового языка

Для добавления поддержки нового языка требуется:

1. Добавить новый язык в enum `AppLanguage`:

```dart
enum AppLanguage {
  /// Русский язык
  ru,
  
  /// Английский язык
  en,
  
  /// Новый язык
  de, // Например, немецкий
}
```

2. Создать словарь с переводами для нового языка:

```dart
static final Map<String, String> _germanTranslations = {
  'unlimited_access': 'Unbegrenzter Zugriff',
  // Другие переводы
};
```

3. Обновить метод `translate` в классе `AppLocalizationService`:

```dart
@override
String translate(String key) {
  switch (_currentLanguage) {
    case AppLanguage.ru:
      return _getRussianTranslation(key) ?? key;
    case AppLanguage.de:
      return _getGermanTranslation(key) ?? key;
    case AppLanguage.en:
    default:
      return _getEnglishTranslation(key) ?? key;
  }
}

String? _getGermanTranslation(String key) {
  final translations = _germanTranslations;
  return translations[key];
}
```

4. Обновить виджет `LanguageSelector` для отображения нового языка.

## Пример использования локализации в кастомном виджете

```dart
import 'package:flutter/material.dart';
import '../services/localization/app_localization_service.dart';

class MyCustomWidget extends StatelessWidget {
  const MyCustomWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          context.tr('my_custom_title'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        ElevatedButton(
          onPressed: () {
            // Действия по нажатию
          },
          child: Text(context.tr('my_custom_button')),
        ),
      ],
    );
  }
}
```

## Принципы SOLID в реализации локализации

Реализация локализации в приложении соответствует принципам SOLID:

1. **Single Responsibility Principle** - Класс `AppLocalizationService` отвечает только за локализацию и не содержит другой логики.
2. **Open/Closed Principle** - Система локализации открыта для расширения (можно добавлять новые языки), но закрыта для модификации (основной интерфейс и механизм работы не меняются).
3. **Liskov Substitution Principle** - Любая реализация интерфейса `IAppLocalizationService` может быть использована вместо базовой.
4. **Interface Segregation Principle** - Интерфейс `IAppLocalizationService` содержит только необходимые методы.
5. **Dependency Inversion Principle** - Компоненты зависят от абстракций (интерфейса `IAppLocalizationService`), а не от конкретных реализаций. 