# Руководство по первой публикации в RuStore

## ✅ Что уже готово

- [x] RuStore App ID обновлен на `2063737207`
- [x] Product IDs настроены для нового проекта
- [x] Firebase конфигурация (`google-services.json`)
- [x] Package name: `com.aivideomaker.app`
- [x] Production пароли сгенерированы
- [x] `android/key.properties` настроен

---

## 🔐 Шаг 1: Создание Production Keystore

Откройте **Terminal.app** и выполните:

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI
bash android/CREATE_KEYSTORE.sh
```

Скрипт:
1. Создаст `upload-keystore.jks` в корне проекта
2. Использует пароли из `android/PRODUCTION_PASSWORDS.txt`
3. Попросит подтверждение (введите `yes`)

**⚠️ КРИТИЧЕСКИ ВАЖНО:**
Сохраните файл `android/PRODUCTION_PASSWORDS.txt` в безопасное место:
- Менеджер паролей
- Зашифрованное облако
- Надежный бэкап

**БЕЗ ЭТИХ ПАРОЛЕЙ ВЫ НЕ СМОЖЕТЕ ОБНОВИТЬ ПРИЛОЖЕНИЕ!**

---

## 📱 Шаг 2: Настройка RuStore Console

Перейдите на [console.rustore.ru](https://console.rustore.ru/) и создайте продукты:

### Подписки (Subscriptions)

| Product ID | Название | Период | Цена |
|------------|----------|--------|------|
| `aivideomaker.weekly.rustore` | Еженедельная подписка | 7 дней | 149 ₽ |
| `aivideomaker.monthly.rustore` | Ежемесячная подписка | 30 дней | 449 ₽ |
| `aivideomaker.yearly.rustore` | Годовая подписка | 365 дней | 1499 ₽ |

### Кредиты (Consumable)

| Product ID | Название | Тип | Цена |
|------------|----------|-----|------|
| `aivideomaker.credits.50.rustore` | Малый пакет кредитов (50) | Consumable | 149 ₽ |
| `aivideomaker.credits.200.rustore` | Средний пакет кредитов (200) | Consumable | 449 ₽ |
| `aivideomaker.credits.600.rustore` | Большой пакет кредитов (600) | Consumable | 999 ₽ |

**Важно:**
- Product IDs должны **ТОЧНО** совпадать (включая регистр)
- После создания может потребоваться до 24 часов для активации

---

## 📦 Шаг 3: Увеличение версии

Текущая версия: `1.2.5+8`

Для первой публикации рекомендую использовать `1.0.0+1`:

Откройте `pubspec.yaml`:

```yaml
version: 1.0.0+1  # или оставьте 1.2.5+9 если это часть линейки версий
```

---

## 🏗️ Шаг 4: Сборка AAB

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

# Очистка предыдущей сборки
flutter clean
flutter pub get

# Сборка release AAB
flutter build appbundle --release

# Проверка подписи
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
```

Должно вывести: `jar verified.`

Файл будет здесь:
```
build/app/outputs/bundle/release/app-release.aab
```

---

## 🔑 Шаг 5: Экспорт ключа для RuStore (PEPK)

RuStore требует загрузить зашифрованный ключ для подписи.

Откройте **Terminal.app**:

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

java -jar pepk.jar \
  --keystore upload-keystore.jks \
  --alias upload \
  --output android/pepk_out.zip \
  --encryptionkey=000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0 \
  --include-cert
```

Когда попросят пароли, скопируйте из `android/PRODUCTION_PASSWORDS.txt`:
1. Store password: `PhotoAI2026RuStoreSecureProd9xK8mL2n`
2. Key password: `UploadKey2026PhotoAI7wQ5bN4pSecure`

Будет создан файл: `android/pepk_out.zip`

---

## 🚀 Шаг 6: Загрузка в RuStore

### 6.1. Загрузка AAB

1. Откройте [RuStore Console](https://console.rustore.ru/)
2. Перейдите в ваше приложение (App ID: `2063737207`)
3. Раздел "Релизы" → "Создать новый релиз"
4. Загрузите `build/app/outputs/bundle/release/app-release.aab`

### 6.2. Загрузка подписи (PEPK)

1. В RuStore Console перейдите в "Настройки" → "Загрузка подписи"
2. Загрузите файл `android/pepk_out.zip`
3. Дождитесь подтверждения

---

## 📋 Финальный чек-лист

Перед публикацией убедитесь:

### Обязательные шаги
- [ ] Production keystore создан (`upload-keystore.jks`)
- [ ] Пароли сохранены в менеджере паролей
- [ ] Бэкап keystore файла сделан
- [ ] Product IDs созданы в RuStore Console
- [ ] AAB успешно собран
- [ ] Подпись проверена (`jarsigner -verify`)
- [ ] PEPK файл экспортирован (`pepk_out.zip`)

### Метаданные приложения
- [ ] Иконка приложения
- [ ] Скриншоты (минимум 2, рекомендуется 4-8)
- [ ] Описание приложения
- [ ] Категория
- [ ] Возрастной рейтинг
- [ ] Политика конфиденциальности (URL)

### Технические требования RuStore
- [ ] minSdk >= 24 (✓ уже установлено)
- [ ] targetSdk = 36 (✓ уже установлено)
- [ ] Размер AAB < 150MB
- [ ] Deep links настроены (✓ `aivideomaker://`)

---

## 🎯 Быстрый старт (все команды в одном месте)

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

# 1. Создание keystore (ОДИН РАЗ!)
bash android/CREATE_KEYSTORE.sh

# 2. Сохраните пароли!
cat android/PRODUCTION_PASSWORDS.txt
# СКОПИРУЙТЕ В МЕНЕДЖЕР ПАРОЛЕЙ!

# 3. Сборка AAB
flutter clean
flutter pub get
flutter build appbundle --release

# 4. Проверка
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab

# 5. Экспорт PEPK (откройте отдельный Terminal.app - нужен интерактивный ввод)
java -jar pepk.jar \
  --keystore upload-keystore.jks \
  --alias upload \
  --output android/pepk_out.zip \
  --encryptionkey=000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0 \
  --include-cert
# Введите пароли из PRODUCTION_PASSWORDS.txt
```

---

## 📊 Информация о конфигурации

| Параметр | Значение |
|----------|----------|
| **Package name** | `com.aivideomaker.app` |
| **RuStore App ID** | `2063737207` |
| **Deep link scheme** | `aivideomaker://` |
| **Версия** | `1.2.5+8` (увеличьте до `1.2.5+9` или `1.0.0+1`) |
| **Min SDK** | 24 (Android 7.0+) |
| **Target SDK** | 36 (Android 15) |
| **Keystore alias** | `upload` |

---

## ❓ Частые вопросы

**Q: Нужно ли создавать новый keystore если файл upload-keystore.jks уже существует?**

A: НЕТ! Если файл существует, используйте его. Проверьте пароли в `android/key.properties`.

**Q: Что делать если потерял пароли?**

A: Если приложение не опубликовано - создайте новый keystore. Если опубликовано - восстановить невозможно, придется публиковать как новое приложение.

**Q: Зачем нужен PEPK файл?**

A: RuStore использует его для подписи приложения на стороне магазина (App Signing). Это стандартная практика для безопасности.

**Q: Когда создавать Product IDs?**

A: ПЕРЕД первой публикацией. Можно создать позже, но платежи не будут работать до их создания.
