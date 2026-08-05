# 🚀 Сборка для первой публикации в RuStore

## Пошаговая инструкция

### Шаг 1: Создание Production Keystore ⚠️

Откройте **Terminal.app**:

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI
bash android/CREATE_KEYSTORE.sh
```

Введите `yes` для подтверждения.

**Результат:** Создан `upload-keystore.jks` в корне проекта.

**🔴 СРАЗУ ПОСЛЕ СОЗДАНИЯ:**

```bash
# Скопируйте пароли
cat android/PRODUCTION_PASSWORDS.txt

# СОХРАНИТЕ ИХ В МЕНЕДЖЕР ПАРОЛЕЙ!
# Без них вы не сможете обновить приложение.
```

---

### Шаг 2: Сборка App Bundle

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

# Очистка
flutter clean
flutter pub get

# Сборка (займет 5-15 минут)
flutter build appbundle --release

# Проверка подписи
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
```

**Ожидаемый результат:** `jar verified.`

**Файл:** `build/app/outputs/bundle/release/app-release.aab`

---

### Шаг 3: Экспорт PEPK для RuStore

**Откройте НОВЫЙ Terminal.app** (не в IDE):

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

java -jar pepk.jar \
  --keystore upload-keystore.jks \
  --alias upload \
  --output android/pepk_out.zip \
  --encryptionkey=000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0 \
  --include-cert
```

**Когда попросят пароли:**
1. Store password: `PhotoAI2026RuStoreSecureProd9xK8mL2n`
2. Key password: `UploadKey2026PhotoAI7wQ5bN4pSecure`

**Результат:** Создан `android/pepk_out.zip`

---

### Шаг 4: Настройка Product IDs в RuStore Console

Перейдите на [console.rustore.ru](https://console.rustore.ru/) → Ваше приложение → Монетизация:

#### Создайте подписки:

```
ID: aivideomaker.weekly.rustore
Название: Еженедельная подписка AI-Фотограф
Период: 7 дней
Цена: 149 ₽

ID: aivideomaker.monthly.rustore
Название: Ежемесячная подписка AI-Фотограф
Период: 30 дней
Цена: 449 ₽

ID: aivideomaker.yearly.rustore
Название: Годовая подписка AI-Фотограф
Период: 365 дней
Цена: 1499 ₽
```

#### Создайте consumable товары (кредиты):

```
ID: aivideomaker.credits.40.rustore
Название: Малый пакет (40 кредитов)
Тип: Consumable
Цена: 149 ₽

ID: aivideomaker.credits.150.rustore
Название: Средний пакет (150 кредитов)
Тип: Consumable
Цена: 449 ₽

ID: aivideomaker.credits.400.rustore
Название: Большой пакет (400 кредитов)
Тип: Consumable
Цена: 999 ₽
```

**⏱️ Важно:** После создания может потребоваться до 24 часов для активации.

---

### Шаг 5: Загрузка в RuStore

#### 5.1. Загрузка подписи (первым делом!)

1. RuStore Console → "Настройки" → "Загрузка подписи"
2. Загрузите `android/pepk_out.zip`
3. Дождитесь подтверждения

#### 5.2. Загрузка AAB

1. RuStore Console → "Релизы" → "Создать новый релиз"
2. Загрузите `build/app/outputs/bundle/release/app-release.aab`
3. Заполните метаданные:
   - Что нового в этой версии
   - Скриншоты
   - Описание
4. Отправьте на модерацию

---

## 📊 Текущая конфигурация

| Параметр | Значение |
|----------|----------|
| **App Name** | AI-Фотограф |
| **Package** | `com.aivideomaker.app` |
| **RuStore App ID** | `2063737207` ✓ обновлен |
| **Версия** | `1.2.5+9` ✓ увеличена |
| **Deep link** | `aivideomaker://` |
| **Firebase Project** | `photosession-ai-cbfc3` |

---

## 🎯 Итоговый чек-лист

Выполните по порядку:

1. ✓ RuStore App ID обновлен → `2063737207`
2. ✓ Версия увеличена → `1.2.5+9`
3. ✓ Production пароли готовы → `android/PRODUCTION_PASSWORDS.txt`
4. ⏳ Создать keystore → `bash android/CREATE_KEYSTORE.sh`
5. ⏳ Сохранить пароли в менеджер паролей
6. ⏳ Собрать AAB → `flutter build appbundle --release`
7. ⏳ Экспортировать PEPK → `java -jar pepk.jar ...`
8. ⏳ Создать Product IDs в RuStore Console
9. ⏳ Загрузить PEPK в RuStore
10. ⏳ Загрузить AAB в RuStore
11. ⏳ Отправить на модерацию

---

## 📞 Возможные проблемы

### "keystore not found"
→ Убедитесь что `upload-keystore.jks` в корне проекта

### "incorrect password"
→ Проверьте пароли в `android/PRODUCTION_PASSWORDS.txt`

### "Product ID not found" в приложении
→ Product IDs еще не активировались (подождите 24 часа)
→ Проверьте точное совпадение ID в RuStore Console

### PEPK не экспортируется
→ Запускайте в **Terminal.app**, не в IDE терминале
→ Используйте пароли из `PRODUCTION_PASSWORDS.txt`

---

**Готово к публикации! 🎉**
