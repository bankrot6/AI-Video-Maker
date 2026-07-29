# Система локализации для AI Video Maker

Данная система локализации обеспечивает поддержку нескольких языков в приложении AI Video Maker.

## Поддерживаемые языки

- 🇷🇺 Русский
- 🇺🇸 Английский

## Архитектура

Система локализации построена на основе принципов SOLID:

1. **Принцип единственной ответственности (SRP)**: `AppLocalizationService` отвечает только за локализацию
2. **Принцип разделения интерфейсов (ISP)**: Интерфейс `IAppLocalizationService` определяет контракт для сервиса
3. **Принцип открытости/закрытости (OCP)**: Система расширяема для добавления новых языков без изменения основного кода

## Компоненты

- `AppLanguage` - перечисление поддерживаемых языков
- `IAppLocalizationService` - интерфейс для сервиса локализации
- `AppLocalizationService` - реализация сервиса локализации
- `LanguageSelector` - виджет для выбора языка
- `LocalizationExtension` - расширение для удобного доступа к переводам через `context.tr('key')`

## Особенности

- Автоматическое определение языка устройства
- Сохранение выбранного языка в SharedPreferences
- Простой доступ к переводам через метод расширения `context.tr('key')`
- Виджет переключения языков с флагами стран

## Как использовать

### Добавление новых переводов

Для добавления новых переводов нужно добавить ключи и значения в словарях `_russianTranslations` и `_englishTranslations` в файле `app_localization_service.dart`.

```dart
static final Map<String, String> _russianTranslations = {
  // Добавьте ваши ключи и переводы здесь
  'new_key': 'Новый перевод',
};

static final Map<String, String> _englishTranslations = {
  // Добавьте ваши ключи и переводы здесь
  'new_key': 'New translation',
};
```

### Использование в коде

```dart
// В виджетах
Text(context.tr('your_key'))

// Через провайдер (для WidgetRef)
final localizationService = ref.read(appLocalizationServiceProvider);
String translatedText = localizationService.translate('your_key');
```

### Изменение языка

```dart
final localizationService = ref.read(appLocalizationServiceProvider);
await localizationService.setLanguage(AppLanguage.ru);
ref.read(currentLanguageProvider.notifier).state = AppLanguage.ru;
```

### Добавление виджета выбора языка

```dart
Scaffold(
  appBar: AppBar(
    title: Text(context.tr('app_name')),
    actions: [
      const LanguageSelector(), // Виджет выбора языка
    ],
  ),
)
```

## Добавление поддержки новых языков

1. Добавьте новый язык в перечисление `AppLanguage`
2. Создайте словарь переводов для нового языка
3. Добавьте обработку нового языка в метод `translate`
4. Обновите виджет `LanguageSelector` для нового языка 