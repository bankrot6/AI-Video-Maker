# Быстрая загрузка 10 пресетов

## ✅ Готово
- 10 пресетов сгенерированы в `tool/generated_presets.json`
- Уникальные промпты через DeepSeek
- Превью изображения через Nano Banana

## 🎯 Загрузить в Firebase (выберите один вариант)

### Вариант 1: Самый быстрый (3 минуты)

1. Откройте Firebase Console Rules:
   https://console.firebase.google.com/project/photosession-ai-cbfc3/firestore/rules

2. Измените строку 6:
   ```javascript
   // Было:
   allow create: if request.auth != null;
   
   // Сделайте:
   allow create: if true;
   ```

3. Нажмите **"Publish"** (вверху справа)

4. Запустите в терминале:
   ```bash
   dart tool/upload_presets_to_firebase.dart
   ```

5. После успешной загрузки - верните правило обратно:
   ```javascript
   allow create: if request.auth != null;
   ```

6. Нажмите **"Publish"** снова

---

### Вариант 2: Постоянное решение через Service Account (10 минут)

#### Настройка (один раз):

1. **Скачайте Service Account ключ**:
   - https://console.firebase.google.com/project/photosession-ai-cbfc3/settings/serviceaccounts/adminsdk
   - Вкладка "Service accounts"
   - Нажмите "Generate new private key"
   - Сохраните JSON как: `tool/firebase-service-account.json`

2. **Установите Python библиотеку**:
   ```bash
   pip3 install firebase-admin
   ```

3. **Загрузите пресеты**:
   ```bash
   python3 tool/upload_with_service_account.py
   ```

#### Преимущества:
- ✅ Не нужно менять правила Firestore
- ✅ Admin SDK обходит безопасность
- ✅ Работает всегда
- ✅ Для всех будущих пресетов

---

### Вариант 3: Cloud Function (идеальное решение, но требует времени)

#### Статус:
- ✅ Код готов в `functions/index.js`
- ⏳ Развертывание зависло (системные проблемы)

#### Что делать:
1. Попробуйте позже: `firebase deploy --only functions`
2. Или разверните вручную через Google Cloud Console:
   - https://console.cloud.google.com/functions/list?project=photosession-ai-cbfc3
   - Upload ZIP с содержимым `functions/`
   - Runtime: Node.js 20
   - Entry point: `createPresetsBatch`
   - Trigger: HTTPS

---

## ⚡ Мгновенный план действий

**Для загрузки прямо сейчас:**

```bash
# 1. Откройте Firebase Console и измените правила (см. Вариант 1)

# 2. Запустите загрузку:
dart tool/upload_presets_to_firebase.dart

# 3. Верните правила обратно в консоли
```

**Для постоянного использования:**

```bash
# 1. Скачайте Service Account JSON (см. Вариант 2)

# 2. Установите:
pip3 install firebase-admin

# 3. В будущем просто:
python3 tool/upload_with_service_account.py
```

---

## 📞 Что дальше?

Скажите, какой вариант выбираете, и я помогу выполнить шаги!
