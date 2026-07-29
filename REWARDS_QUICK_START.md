# Система вознаграждений - Краткая справка

## Как это работает

```
Пользователь создает пресет → Делает публичным → Получает лайки → Автоматически получает кредиты
```

## Экономика

| Параметр | Значение |
|----------|----------|
| За 1 лайк | 1 кредит |
| Минимум для старта | 3 лайка |
| Максимум с пресета | 50 кредитов |
| Условие | Пресет публичный |

## Основные файлы

### Модели
- `lib/models/preset_earnings.dart` - модель заработка
- `lib/models/credit_usage_model.dart` - расширена для earnedCredits

### Сервисы
- `lib/services/preset_reward_service.dart` - логика вознаграждений
- `lib/services/credit_service.dart` - метод addEarnedCredits()

### UI
- `lib/widgets/earned_credits_badge.dart` - бадж в showcase
- `lib/widgets/preset_earnings_card.dart` - карточка пресета с заработком
- `lib/features/earnings/preset_earnings_screen.dart` - экран статистики

### Backend
- `functions/index.js` - функция processPresetRewards
- `firestore.rules` - правила для preset_earnings
- `firestore.indexes.json` - индексы для запросов

## Быстрое развертывание

```bash
# 1. Обновить зависимости
flutter pub get

# 2. Применить Firestore конфигурацию
firebase deploy --only firestore:rules,firestore:indexes

# 3. Развернуть Cloud Function
firebase deploy --only functions:processPresetRewards

# 4. Пересобрать приложение
flutter clean && flutter pub get
flutter build apk --release
```

## Проверка работы

### Проверка #1: Cloud Function работает
```bash
# Поставить лайк на публичный пресет с ownerId
# Проверить логи
firebase functions:log --only processPresetRewards

# Должно быть:
# ✅ Reward: preset XXX earned 1 credits (4 likes, owner: YYY)
```

### Проверка #2: Синхронизация работает
```dart
// В коде приложения
final credits = await PresetRewardService().syncEarnedCredits();
print('Начислено: $credits кредитов');
```

### Проверка #3: UI отображается
1. Создать публичный пресет
2. Получить 3+ лайков (можно с другого устройства)
3. Перезапустить приложение
4. Проверить:
   - SnackBar с уведомлением о кредитах
   - Зеленый бадж в showcase screen
   - Статистику в PresetEarningsScreen

## Полезные команды

```bash
# Логи Cloud Functions
firebase functions:log --only processPresetRewards --since 1h

# Состояние функций
firebase functions:list

# Тестовый запрос к Firestore
# В Firebase Console → Firestore → preset_earnings
# Сортировка: creditsEarned (desc)

# Очистить данные заработков (dev)
# В Firebase Console → Firestore → preset_earnings → Delete collection
```

## Troubleshooting

| Проблема | Решение |
|----------|---------|
| Бадж не показывается | Проверить, что earnedCredits > 0 в локальном хранилище |
| Cloud Function не работает | Проверить логи, убедиться что пресет public с ownerId |
| Кредиты не начисляются | Вызвать syncEarnedCredits() вручную |
| Индексы не готовы | Подождать 5-10 минут после деплоя |

## Контакты для вопросов

- Документация: `PRESET_REWARDS_SYSTEM.md`
- Детальное развертывание: `REWARDS_DEPLOYMENT.md`
