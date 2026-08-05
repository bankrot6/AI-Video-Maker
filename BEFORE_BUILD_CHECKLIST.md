# Чек-лист перед сборкой нового AAB для RuStore

## ✅ УЖЕ ГОТОВО

- [x] RuStore App ID обновлен на `2063737207`
- [x] Product IDs переименованы:
  - Подписки: `aivideomaker.weekly/monthly/yearly.rustore`
  - Кредиты: `aivideomaker.credits.40/150/400.rustore`
- [x] Firebase конфигурация для нового проекта (`google-services.json`)
- [x] Package name: `com.aivideomaker.app`
- [x] Deep links настроены (aivideomaker://)
- [x] Текущая версия: `1.2.5+8` (versionName 1.2.5, versionCode 8)

---

## ⚠️ КРИТИЧЕСКИ ВАЖНО: Keystore

**Текущая ситуация:**
- `android/key.properties` указывает на **DEMO keystore** (`upload-keystore-DEMO.jks`)
- Это **ТЕСТОВЫЙ** ключ, созданный автоматически

### Что нужно сделать:

#### Вариант A: Обновление существующего приложения

Если приложение **УЖЕ ОПУБЛИКОВАНО** в RuStore:

1. **Найдите НАСТОЯЩИЙ keystore** который использовался для предыдущей версии
2. Обновите `android/key.properties`:

```properties
storePassword=ВАШ_НАСТОЯЩИЙ_ПАРОЛЬ_KEYSTORE
keyPassword=ВАШ_НАСТОЯЩИЙ_ПАРОЛЬ_КЛЮЧА
keyAlias=ВАШ_НАСТОЯЩИЙ_ALIAS
storeFile=../upload-keystore.jks
```

3. Положите настоящий keystore в корень проекта (или укажите правильный путь в `storeFile`)

**ЕСЛИ НЕ НАЙДЁТЕ НАСТОЯЩИЙ KEYSTORE → НЕВОЗМОЖНО ОБНОВИТЬ ПРИЛОЖЕНИЕ**

#### Вариант B: Новое приложение (первая публикация)

Если это **НОВОЕ** приложение:

1. **Создайте production keystore:**

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

# Генерация надежных паролей
STORE_PASS=$(openssl rand -base64 32 | tr -d '/+=')
KEY_PASS=$(openssl rand -base64 32 | tr -d '/+=')

echo "Store Password: $STORE_PASS"
echo "Key Password: $KEY_PASS"

# Создание keystore
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -storepass "$STORE_PASS" \
  -keypass "$KEY_PASS" \
  -dname "CN=AI Photographer, OU=Mobile Development, O=AI Video Maker, L=Moscow, ST=Moscow, C=RU"
```

2. **Сохраните пароли в безопасном месте!** (менеджер паролей, шифрованный файл)

3. Обновите `android/key.properties` с реальными паролями:

```properties
storePassword=СГЕНЕРИРОВАННЫЙ_STORE_PASSWORD
keyPassword=СГЕНЕРИРОВАННЫЙ_KEY_PASSWORD
keyAlias=upload
storeFile=../upload-keystore.jks
```

---

## 📱 Настройки RuStore Console

Перед сборкой убедитесь что в [RuStore Console](https://console.rustore.ru/) настроено:

### 1. Application ID

```
2063737207
```

### 2. Product IDs (подписки)

| ID | Название | Цена |
|----|----------|------|
| `aivideomaker.weekly.rustore` | Еженедельная подписка | 149 ₽ |
| `aivideomaker.monthly.rustore` | Ежемесячная подписка | 449 ₽ |
| `aivideomaker.yearly.rustore` | Годовая подписка | 1499 ₽ |

### 3. Product IDs (кредиты)

| ID | Название | Кредиты | Цена |
|----|----------|---------|------|
| `aivideomaker.credits.40.rustore` | Малый пакет | 40 | 149 ₽ |
| `aivideomaker.credits.150.rustore` | Средний пакет | 150 | 449 ₽ |
| `aivideomaker.credits.400.rustore` | Большой пакет | 400 | 999 ₽ |

**Важно:** Product IDs должны быть созданы в RuStore Console **ТОЧНО** с этими названиями.

---

## 🏗️ Команды для сборки

### Шаг 1: Очистка предыдущей сборки

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

flutter clean
flutter pub get
```

### Шаг 2: Увеличьте версию (если нужно)

Текущая версия: `1.2.5+8`

Если это обновление, увеличьте **build number**:

В `pubspec.yaml`:
```yaml
version: 1.2.5+9  # или 1.2.6+9 если есть новые фичи
```

### Шаг 3: Сборка AAB

```bash
flutter build appbundle --release
```

Файл будет создан:
```
build/app/outputs/bundle/release/app-release.aab
```

### Шаг 4: Проверка подписи

```bash
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
```

Должно быть: `jar verified.`

---

## 🔐 Экспорт ключа для RuStore (если требуется)

После **первой** публикации RuStore может запросить PEPK файл.

### Вручную в Terminal.app:

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

java -jar pepk.jar \
  --keystore upload-keystore.jks \
  --alias upload \
  --output android/pepk_out.zip \
  --encryptionkey=000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0 \
  --include-cert
```

Введите пароли из `key.properties` когда попросят.

Затем загрузите `android/pepk_out.zip` в RuStore Console → "Загрузка подписи".

---

## 🚨 Частые ошибки

### Ошибка: "keystore not found"

- Проверьте что файл существует: `ls -lh upload-keystore.jks`
- Проверьте путь в `key.properties` (относительно `android/app/`)

### Ошибка: "incorrect password"

- Убедитесь что пароли в `key.properties` правильные
- Попробуйте открыть keystore вручную:
  ```bash
  keytool -list -v -keystore upload-keystore.jks
  ```

### Ошибка: "Product ID not found" в приложении

- Убедитесь что Product IDs созданы в RuStore Console
- Проверьте что они **точно совпадают** с теми что в коде
- RuStore может требовать до 24 часов для активации новых Product IDs

---

## 📊 Итоговый чек-лист

Перед запуском `flutter build appbundle`:

- [ ] **НАСТОЯЩИЙ keystore** (не DEMO) находится в нужном месте
- [ ] `android/key.properties` с **РЕАЛЬНЫМИ** паролями
- [ ] Версия увеличена в `pubspec.yaml` (если обновление)
- [ ] Product IDs созданы в RuStore Console
- [ ] RuStore App ID = `2063737207` (уже обновлен)
- [ ] `flutter clean && flutter pub get` выполнены
- [ ] Firebase `google-services.json` для нового проекта (✓ уже есть)

После сборки:

- [ ] Проверена подпись: `jarsigner -verify`
- [ ] Размер AAB разумный (< 100MB)
- [ ] Если первая публикация → экспортировать PEPK файл

---

## 🎯 Быстрый старт

Если у вас **УЖЕ ЕСТЬ** настоящий keystore:

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

# 1. Обновите android/key.properties с реальными данными
# 2. Затем:

flutter clean
flutter pub get
flutter build appbundle --release

# Проверка
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
```
