# Инструкция по развертыванию системы вознаграждений

## ✅ Что уже готово

Весь код реализован и готов к развертыванию:
- ✅ 7 новых файлов создано
- ✅ 9 файлов обновлено
- ✅ Нет ошибок линтера
- ✅ Зависимости Flutter обновлены

## 🚀 Шаги развертывания

### Шаг 1: Проверить Firebase CLI

```bash
# Проверить установлен ли Firebase CLI
firebase --version

# Если не установлен
npm install -g firebase-tools

# Войти в аккаунт
firebase login
```

### Шаг 2: Применить Firestore правила безопасности

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI
firebase deploy --only firestore:rules
```

**Ожидаемый результат:**
```
✔ Deploy complete!
Firestore Rules updated
```

### Шаг 3: Применить Firestore индексы

```bash
firebase deploy --only firestore:indexes
```

**Ожидаемый результат:**
```
✔ Deploy complete!
Firestore Indexes updated
```

**Важно:** Создание индексов может занять 5-10 минут. Прогресс можно посмотреть в Firebase Console → Firestore → Indexes.

### Шаг 4: Установить зависимости Cloud Functions

```bash
cd functions
npm install
cd ..
```

**Проверка:**
```bash
ls functions/node_modules
# Должны быть папки: firebase-admin, firebase-functions, sharp
```

### Шаг 5: Развернуть Cloud Function

```bash
firebase deploy --only functions:processPresetRewards
```

**Ожидаемый результат:**
```
✔ functions[processPresetRewards(us-central1)] Successful create operation.
Function URL: https://us-central1-photosession-ai-cbfc3.cloudfunctions.net/processPresetRewards
✔ Deploy complete!
```

### Шаг 6: Проверить развертывание

```bash
# Посмотреть список функций
firebase functions:list

# Проверить логи
firebase functions:log --only processPresetRewards --limit 10
```

## 🧪 Тестирование

### Тест 1: Проверка Cloud Function

1. Откройте Firebase Console
2. Перейдите в Firestore
3. Найдите любой публичный пресет с `ownerId`
4. Вручную увеличьте `likesCount` на 1
5. Подождите 10 секунд
6. Проверьте логи: `firebase functions:log --only processPresetRewards`
7. В Firestore должна появиться коллекция `preset_earnings` с документом

### Тест 2: Проверка в приложении

```bash
# Пересобрать и запустить
flutter clean
flutter pub get
flutter run
```

**Сценарий теста:**
1. Создать новый пресет
2. Сделать его публичным
3. С другого устройства/аккаунта поставить 3+ лайков
4. Вернуться на первое устройство, перезапустить приложение
5. Должен появиться SnackBar: "🎉 Вы получили X кредитов за лайки!"
6. Должен появиться зеленый бадж "Заработано: +X"

## 🔍 Диагностика проблем

### Проблема: "Error: Failed to get Firebase project"

**Решение:**
```bash
firebase login --reauth
firebase use photosession-ai-cbfc3
```

### Проблема: "Error: HTTP Error: 403"

**Решение:**
- Проверить права доступа в Firebase Console → Project Settings → Service Accounts
- Убедиться, что текущий пользователь имеет роль Editor или Owner

### Проблема: Cloud Function не срабатывает

**Проверка:**
```bash
# Посмотреть логи
firebase functions:log --only processPresetRewards

# Проверить статус функции
firebase functions:list | grep processPresetRewards
```

**Возможные причины:**
1. Функция не развернута → повторить deploy
2. Пресет не публичный → проверить `isPublic: true`
3. Нет `ownerId` → проверить наличие поля
4. Меньше 3 лайков → добавить больше лайков

### Проблема: Индексы не созданы

**Проверка в Firebase Console:**
1. Firestore → Indexes
2. Должны быть индексы для:
   - `presets`: `ownerId` + `isPublic`
   - `preset_earnings`: `ownerId` + `creditsEarned`

**Ручное создание:**
- Перейти в Firebase Console → Firestore → Indexes → Add Index
- Создать композитные индексы вручную

## 📊 Мониторинг после развертывания

### Проверка работы системы

```bash
# Логи за последний час
firebase functions:log --only processPresetRewards --since 1h

# Статистика вызовов
# Firebase Console → Functions → processPresetRewards → Usage
```

### Запросы к Firestore

В Firebase Console → Firestore можно выполнить запросы:

```
Коллекция: preset_earnings
Сортировка: creditsEarned (desc)
Лимит: 20
```

Это покажет топ-20 пресетов по заработку.

## 🎯 Финальный чеклист

- [ ] Firebase CLI установлен и авторизован
- [ ] Firestore rules применены
- [ ] Firestore indexes применены (и созданы в консоли)
- [ ] npm install в functions выполнен
- [ ] Cloud Function развернута
- [ ] Логи показывают успешное развертывание
- [ ] Тестовый лайк обработан корректно
- [ ] В приложении появился бадж "Заработано"
- [ ] Экран статистики открывается и показывает данные

## 📞 Поддержка

Если возникли проблемы:
1. Проверить логи: `firebase functions:log`
2. Проверить Firebase Console → Firestore → Indexes
3. Проверить Firebase Console → Functions → processPresetRewards
4. Убедиться, что есть публичные пресеты с `ownerId` и лайками

## 🎉 После развертывания

Система автоматически начнет работать:
- Каждый новый лайк на публичный пресет → автоматическое начисление
- При запуске приложения → синхронизация всех заработков
- Пользователи могут видеть статистику в реальном времени

**Готово к продакшену!** 🚀
