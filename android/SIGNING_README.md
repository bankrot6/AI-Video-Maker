# Подпись приложения для RuStore

## ВАЖНОЕ ПРЕДУПРЕЖДЕНИЕ

В проекте уже есть собранный `app-release.aab` файл (77.9MB), что означает **keystore УЖЕ СУЩЕСТВУЕТ**.

**НИКОГДА не заменяйте keystore для опубликованного приложения!** Магазины требуют одну подпись для всех версий.

---

## Текущая ситуация

Созданы **ДЕМОНСТРАЦИОННЫЕ** файлы:

1. **`upload-keystore-DEMO.jks`** — тестовый keystore (в корне проекта)
2. **`android/key.properties`** — параметры подписи с DEMO паролями
3. **`android/.pepk_encryption_key`** — ключ шифрования RuStore

---

## Для ТЕСТИРОВАНИЯ процесса

Если вы хотите просто **протестировать** процесс экспорта:

```bash
cd android
./export_pepk_auto.sh
```

**Требования:** `expect` (установка: `brew install expect`)

Скрипт создаст `android/pepk_out.zip` из DEMO keystore.

---

## Для PRODUCTION (РЕАЛЬНОЕ приложение)

### Шаг 1: Найдите ваш НАСТОЯЩИЙ keystore

Файл `.jks` или `.keystore`, который использовался для сборки `app-release.aab`.

**Где искать:**
- Обычно в корне проекта или `android/app/keys/`
- Возможные имена: `upload-keystore.jks`, `key.jks`, `photosession-ai.keystore`
- Проверьте старые конфиги или бэкапы

### Шаг 2: Обновите `android/key.properties`

```properties
storePassword=ВАШ_РЕАЛЬНЫЙ_ПАРОЛЬ_KEYSTORE
keyPassword=ВАШ_РЕАЛЬНЫЙ_ПАРОЛЬ_КЛЮЧА
keyAlias=ИМЯ_КЛЮЧА_В_KEYSTORE
storeFile=../upload-keystore.jks
```

**Важно:**
- `storeFile` — относительный путь от `android/app/` (как в Gradle)
- Если keystore в корне проекта: `../upload-keystore.jks`
- Если в `android/`: `../../android/upload-keystore.jks`

### Шаг 3: Запустите экспорт

```bash
cd android
./export_pepk_auto.sh
```

Или вручную (если нет `expect`):

```bash
java -jar pepk.jar \
  --keystore /ПОЛНЫЙ/ПУТЬ/К/upload-keystore.jks \
  --alias upload \
  --output android/pepk_out.zip \
  --encryptionkey=000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0 \
  --include-cert
```

Введите пароли когда попросят.

### Шаг 4: Загрузите в RuStore

1. Откройте [RuStore Console](https://console.rustore.ru/)
2. Перейдите в раздел "Загрузка подписи"
3. Загрузите файл `android/pepk_out.zip`

---

## Генерация случайных паролей (для НОВОГО keystore)

Если вам действительно нужен **новый** keystore (например для совершенно нового приложения):

```bash
# Генерация паролей
openssl rand -base64 24 | tr -d '/+='
openssl rand -base64 24 | tr -d '/+='

# Создание keystore
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -storepass "ПЕРВЫЙ_ПАРОЛЬ" \
  -keypass "ВТОРОЙ_ПАРОЛЬ" \
  -dname "CN=Your Name, OU=Mobile, O=Company, L=City, C=RU"
```

---

## Файлы в .gitignore

Следующие файлы **НЕ коммитятся** в Git (уже добавлены в `.gitignore`):

- `android/key.properties` — содержит пароли
- `android/.signing_env` — переменные окружения с паролями
- `android/.pepk_encryption_key` — ключ шифрования
- `android/pepk_out.zip` — экспортированный ключ
- `*.jks`, `*.keystore` — файлы keystore

**Храните keystore и пароли в безопасном месте!**
