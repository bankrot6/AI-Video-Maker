# Инструкция по перезапуску приложения

## Проблема
Приложение не загружает пресеты из БД из-за старого кода в памяти.

## Решение

### Вариант 1: Hot Restart (быстрый)
В терминале где запущен `flutter run` нажми клавишу **R** (заглавная)

### Вариант 2: Полный перезапуск
1. В терминале где запущен `flutter run` нажми **q** для остановки
2. Запусти заново:
```bash
cd /Volumes/External_Storage/Projects/Photosession-AI
flutter run
```

## Что проверить после запуска

В логах должны появиться строки:
- `ShowcaseRepository: _fetchPresetsViaHttp старт`
- `ShowcaseRepository: HTTP GET https://fra.cloud.appwrite.io/v1/databases/...`
- `ShowcaseRepository: HTTP 200`
- `ShowcaseRepository: получено 3 документов` (или больше)
- `ShowcaseRepository: загружено 3 пресетов`

На главном экране должны отобразиться **3 пресета с картинками** в виде сетки 2x2.

## Если не помогло

Проверь в `.env` строку 68:
```
APPWRITE_API_KEY=standard_ed1dfc497f8477205b24663fff98c21a518c7cf0d7d86af5c3d0da0721b4ec6c7876d2e5a887ba6356ed81a2955f3a28593f49085ce877497d0ae11d0a986dd6f505ebbc909160101b5cec1fbf52af40e77cd334cf669c5391ba274547ddf1a4e53200138a3537cad98cd8e4c28fae84101abae70e19261f052dc5333ecad8b4
```

Ключ должен быть на одной строке, без переносов.
