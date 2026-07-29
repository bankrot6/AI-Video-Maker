# Инструкция по загрузке подписи в RuStore

## ✅ Что уже готово

- [x] **Сертификат PEM создан:** `android/upload-cert.pem` (1.3 KB)
- [x] Keystore: `upload-keystore.jks`
- [x] Пароли сохранены в: `android/PRODUCTION_PASSWORDS.txt`

---

## 📦 Создание PEPK архива (Шаг 2)

Откройте **Terminal.app** (НЕ терминал в IDE!) и выполните:

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

java -jar pepk.jar \
  --keystore upload-keystore.jks \
  --alias upload \
  --output android/pepk_out.zip \
  --encryptionkey=000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0 \
  --include-cert
```

### Когда попросят пароли:

```
Enter password for store: PhotoAI2026RuStoreSecureProd9xK8mL2n
Enter password for key: UploadKey2026PhotoAI7wQ5bN4pSecure
```

**Скопируйте пароли из этого файла, не вводите вручную!**

---

## 📤 Загрузка в RuStore Console

После создания `pepk_out.zip`:

### Шаг 3: Загрузите ZIP-архив
1. В RuStore Console нажмите **"Выберите файлы"** в разделе "Загрузите созданный ZIP-архив"
2. Выберите файл: `android/pepk_out.zip`

### Шаг 4: Загрузите сертификат
1. Нажмите **"Выберите файлы"** в разделе "Загрузите сертификат загрузки"
2. Выберите файл: `android/upload-cert.pem`

### Шаг 5: Отправьте
Нажмите кнопку **"Отправить подпись"**

---

## 🔍 Проверка файлов

Перед загрузкой проверьте что оба файла созданы:

```bash
ls -lh /Volumes/External_Storage/Projects/Photosession-AI/android/pepk_out.zip
ls -lh /Volumes/External_Storage/Projects/Photosession-AI/android/upload-cert.pem
```

Ожидаемые размеры:
- `pepk_out.zip`: 2-5 KB
- `upload-cert.pem`: 1-2 KB

Оба должны быть < 100 KB (по требованиям RuStore).

---

## 🎯 Краткая команда (одной строкой)

Для создания PEPK архива просто скопируйте и вставьте в Terminal.app:

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI && java -jar pepk.jar --keystore upload-keystore.jks --alias upload --output android/pepk_out.zip --encryptionkey=000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0 --include-cert
```

Затем введите пароли:
1. `PhotoAI2026RuStoreSecureProd9xK8mL2n`
2. `UploadKey2026PhotoAI7wQ5bN4pSecure`

---

## 📋 Итоговый чек-лист

- [x] Сертификат PEM создан
- [ ] PEPK архив создан (требует запуск команды выше)
- [ ] Оба файла загружены в RuStore Console
- [ ] Нажата кнопка "Отправить подпись"
- [ ] AAB файл готов к загрузке: `build/app/outputs/bundle/release/app-release.aab`

После загрузки подписи сможете загрузить AAB в разделе "Релизы".
