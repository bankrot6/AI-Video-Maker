# Создание файлов для загрузки подписи в RuStore

## 📋 Что нужно создать

Согласно скриншоту RuStore Console, нужны 2 файла:

1. **ZIP-архив** (pepk_out.zip) — зашифрованный ключ, не более 100 KB
2. **PEM сертификат** (upload-cert.pem) — сертификат загрузки, не более 100 KB

---

## 🚀 Команды для выполнения

Откройте **Terminal.app** и выполните команды по порядку:

### Шаг 1: Создание PEM сертификата

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

keytool -exportcert \
  -alias upload \
  -keystore upload-keystore.jks \
  -storepass PhotoAI2026RuStoreSecureProd9xK8mL2n \
  -rfc \
  -file android/upload-cert.pem

ls -lh android/upload-cert.pem
```

**Результат:** Создан файл `android/upload-cert.pem` (обычно 1-2 KB)

---

### Шаг 2: Создание ZIP архива (PEPK)

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

java -jar pepk.jar \
  --keystore upload-keystore.jks \
  --alias upload \
  --output android/pepk_out.zip \
  --encryptionkey=000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0 \
  --include-cert
```

**Когда попросят пароли, введите:**

```
Store password: PhotoAI2026RuStoreSecureProd9xK8mL2n
Key password:   UploadKey2026PhotoAI7wQ5bN4pSecure
```

**Результат:** Создан файл `android/pepk_out.zip` (обычно 2-5 KB)

---

## 📤 Загрузка в RuStore Console

После создания обоих файлов:

1. **Шаг 3:** Загрузите `android/pepk_out.zip` (кнопка "Выберите файлы")
2. **Шаг 4:** Загрузите `android/upload-cert.pem` (кнопка "Выберите файлы")
3. Нажмите **"Отправить подпись"**

---

## ✅ Проверка размеров файлов

После создания проверьте размеры:

```bash
ls -lh android/pepk_out.zip android/upload-cert.pem
```

Оба файла должны быть < 100 KB (обычно 2-5 KB каждый).

---

## 🔑 Пароли для справки

| Параметр | Значение |
|----------|----------|
| **Store password** | `PhotoAI2026RuStoreSecureProd9xK8mL2n` |
| **Key password** | `UploadKey2026PhotoAI7wQ5bN4pSecure` |
| **Alias** | `upload` |
| **Keystore** | `upload-keystore.jks` (в корне проекта) |

---

## ❓ Если что-то пошло не так

### Ошибка: "keystore not found"
```bash
# Проверьте что файл существует
ls -lh /Volumes/External_Storage/Projects/Photosession-AI/upload-keystore.jks
```

### Ошибка: "incorrect password"
```bash
# Проверьте пароли в файле
cat android/PRODUCTION_PASSWORDS.txt
```

### Ошибка: "alias not found"
```bash
# Посмотрите какие алиасы есть в keystore
keytool -list -v -keystore upload-keystore.jks -storepass PhotoAI2026RuStoreSecureProd9xK8mL2n
```

---

## 🎯 Краткая версия (для копирования)

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

# 1. Сертификат
keytool -exportcert -alias upload -keystore upload-keystore.jks -storepass PhotoAI2026RuStoreSecureProd9xK8mL2n -rfc -file android/upload-cert.pem

# 2. PEPK архив (будет запрос паролей)
java -jar pepk.jar --keystore upload-keystore.jks --alias upload --output android/pepk_out.zip --encryptionkey=000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0 --include-cert

# 3. Проверка
ls -lh android/pepk_out.zip android/upload-cert.pem
```

Пароли при запросе:
- Store: `PhotoAI2026RuStoreSecureProd9xK8mL2n`
- Key: `UploadKey2026PhotoAI7wQ5bN4pSecure`
