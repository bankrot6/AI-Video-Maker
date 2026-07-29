# Сгенерированные файлы для подписи Android

## ✓ Созданные файлы

### Keystore и конфигурация

| Файл | Назначение | Статус |
|------|-----------|--------|
| `upload-keystore-DEMO.jks` | **DEMO** keystore для тестирования | ✓ Создан (корень проекта) |
| `android/key.properties` | Параметры подписи (пароли, alias, путь) | ✓ Создан с DEMO паролями |
| `android/.pepk_encryption_key` | Ключ шифрования RuStore | ✓ Создан |

### Сгенерированные данные

**DEMO пароли (только для тестирования):**
- Store Password: `Demo7RuStore9Photosession2026Key!Temp`
- Key Password: `DemoKey8PhotoAI2026Upload!Secure`
- Alias: `upload`

**Ключ шифрования RuStore:**
```
000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0
```

---

## 🚀 Как использовать

### Быстрый старт (DEMO)

Откройте **Terminal.app** и выполните:

```bash
cd /Volumes/External_Storage/Projects/Photosession-AI

java -jar pepk.jar \
  --keystore upload-keystore-DEMO.jks \
  --alias upload \
  --output android/pepk_out.zip \
  --encryptionkey=000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0 \
  --include-cert
```

Когда попросят пароли, скопируйте из таблицы выше.

---

## ⚠️ КРИТИЧЕСКИ ВАЖНО

У вас уже есть `app-release.aab` (77.9MB), значит **keystore уже существует**.

**НИКОГДА не используйте DEMO keystore для production!**

Для production:
1. Найдите ваш **РЕАЛЬНЫЙ** keystore (тот что использовался для сборки AAB)
2. Замените пути и пароли в `android/key.properties`
3. Запустите команду выше с реальным keystore

Если заменить keystore, **вы не сможете обновить приложение в RuStore!**

---

## 📚 Дополнительная документация

- `android/SIGNING_README.md` — полное руководство
- `android/RUN_THIS_IN_TERMINAL.txt` — команды для копирования
- `android/key.properties.example` — шаблон конфигурации
