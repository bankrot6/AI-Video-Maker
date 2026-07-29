# Руководство по загрузке пресетов в Firebase

## Текущая ситуация
✅ 10 пресетов сгенерированы в `tool/generated_presets.json`
❌ Системные команды зависают (Node.js, Python, gcloud)
🎯 Нужно загрузить пресеты в Firestore

---

## ⚡ Быстрое решение (5 минут)

### Вариант A: Вручную через Firebase Console

1. **Временно разрешите публичную запись**:
   - Откройте: https://console.firebase.google.com/project/photosession-ai-cbfc3/firestore/rules
   - Измените строку 6:
     ```javascript
     allow create: if true;  // было: if request.auth != null;
     ```
   - Нажмите "Publish"

2. **Запустите загрузку**:
   ```bash
   dart tool/upload_presets_to_firebase.dart
   ```

3. **Верните правила обратно**:
   ```javascript
   allow create: if request.auth != null;
   ```
   - Нажмите "Publish"

---

## 🔐 Постоянное решение 1: Service Account (РЕКОМЕНДУЕТСЯ)

### Настройка (один раз):

1. **Скачайте Service Account ключ**:
   - https://console.firebase.google.com/project/photosession-ai-cbfc3/settings/serviceaccounts/adminsdk
   - "Generate new private key" → скачать JSON
   - Сохраните как: `tool/firebase-service-account.json`

2. **Добавьте в .gitignore**:
   ```
   tool/firebase-service-account.json
   ```

3. **Установите firebase-admin для Python**:
   ```bash
   pip3 install firebase-admin
   ```

4. **Используйте скрипт**:
   ```python
   # tool/upload_with_service_account.py
   ```

### Преимущества:
- ✅ Работает всегда, без дополнительной настройки
- ✅ Admin SDK обходит правила безопасности
- ✅ Не требует изменения Firestore правил
- ✅ Простой в использовании

### Использование:
```bash
python3 tool/upload_with_service_account.py
```

---

## 🚀 Постоянное решение 2: Cloud Function (Правильная архитектура)

### Преимущества:
- ✅ Максимальная безопасность
- ✅ Работает из любого места
- ✅ Масштабируемо
- ✅ Не нужна локальная аутентификация

### Статус:
🔨 Код готов в `functions/index.js`
⏳ Нужно развернуть (когда Node.js/Firebase CLI заработают)

### Развертывание:
1. **Через Firebase CLI** (когда Node.js исправится):
   ```bash
   cd functions && npm install
   firebase deploy --only functions
   ```

2. **Через Google Cloud Console UI** (альтернатива):
   - Откройте: https://console.cloud.google.com/functions/list?project=photosession-ai-cbfc3
   - "Create Function"
   - Загрузите код из `functions/`
   - Установите trigger: HTTPS
   - Runtime: Node.js 20

### Использование после развертывания:
```bash
dart tool/upload_via_cloud_function.dart
```

---

## 🔧 Постоянное решение 3: Application Default Credentials

### Настройка (один раз):
```bash
gcloud auth application-default login
```

### Использование:
```bash
python3 tool/upload_via_python.py
```

---

## 🎯 Моя рекомендация для вас

**Сейчас** (загрузить 10 пресетов):
- **Вариант A** (вручную) - 5 минут

**Постоянно** (будущие пресеты):
- **Решение 1** (Service Account) - настройка 10 минут, использование 10 секунд

**Идеально** (позже):
- **Решение 2** (Cloud Function) - когда исправите Node.js/Firebase CLI

---

## Следующие шаги:

1. Выберите вариант выше
2. Я создам недостающие скрипты
3. Загрузим пресеты
4. Вернем правила обратно (если использовали Вариант A)
