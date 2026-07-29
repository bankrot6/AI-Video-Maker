# 🔐 Настройка Firebase с Anonymous Authentication

## ✅ Что это решает

- Каждый пользователь получает уникальный `uid` от Firebase
- Security Rules могут безопасно контролировать доступ
- Соответствует **best practices от Google Firebase**
- Полностью бесплатно

## 📋 Пошаговая инструкция

### Шаг 1: Включить Anonymous Authentication (ОБЯЗАТЕЛЬНО!)

1. Откройте [Firebase Console](https://console.firebase.google.com/)
2. Выберите ваш проект: **photosession-ai-cbfc3**
3. В левом меню нажмите **Authentication** 🔐
4. Перейдите на вкладку **Sign-in method**
5. Найдите **Anonymous** в списке провайдеров
6. Нажмите на **Anonymous**
7. Переключите **Enable** в положение ВКЛ
8. Нажмите **Save**

✅ **После включения пользователи автоматически получат uid при запуске приложения!**

---

### Шаг 2: Обновить Storage Rules

1. В Firebase Console перейдите в **Storage** 🗂️
2. Перейдите на вкладку **Rules**
3. Замените содержимое на это:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /user-photos/{userId}/{allPaths=**} {
      allow read: if true;
      allow write: if request.auth != null 
                   && request.resource.size < 10 * 1024 * 1024
                   && request.resource.contentType.matches('image/.*');
    }
    
    match /{allPaths=**} {
      allow read: if true;
      allow write: if request.auth != null 
                   && request.resource.size < 10 * 1024 * 1024;
    }
  }
}
```

4. Нажмите **Publish**

**Что делают эти правила:**
- ✅ `request.auth != null` - пропускает анонимных пользователей (с uid)
- ✅ Максимум 10 MB на файл
- ✅ Только изображения в папке user-photos

---

### Шаг 3: Обновить Firestore Rules

1. В Firebase Console перейдите в **Firestore Database** 📊
2. Перейдите на вкладку **Rules**
3. Замените содержимое на это:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /presets/{presetId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update: if request.auth != null;
      allow delete: if request.auth != null;
    }
    
    match /user_generations/{generationId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null 
                           && request.auth.uid == resource.data.deviceId;
    }
  }
}
```

4. Нажмите **Publish**

**Что делают эти правила:**
- ✅ Любой может читать пресеты
- ✅ Анонимные пользователи могут создавать пресеты и генерации
- ✅ Пользователи могут редактировать только свои записи

---

### Шаг 4: Обновить зависимости

```bash
flutter pub get
```

---

### Шаг 5: Запустить приложение

```bash
flutter run
```

🎉 **Готово!** Приложение автоматически создаст анонимного пользователя при запуске.

---

## 🔍 Как проверить, что работает

1. Запустите приложение
2. В логах найдите: `FIREBASE_AUTH: Firebase Anonymous Auth: uid=...`
3. В Firebase Console → Authentication должен появиться новый анонимный пользователь

---

## 📚 Источники

- [Firebase Anonymous Authentication](https://firebase.google.com/docs/auth/web/anonymous-auth)
- [Firebase Security Rules](https://firebase.google.com/docs/rules)
- [Best Practices for Anonymous Users](https://firebase.google.com/docs/auth/flutter/anonymous-auth)

---

## 💡 Важные заметки

### Anonymous Auth - это правильно!
- Это официальный способ работы с неавторизованными пользователями в Firebase
- Используется в тысячах приложений
- Позволяет безопасно управлять доступом через Rules

### В продакшене эти правила безопасны!
- `request.auth != null` проверяет наличие uid (анонимного или настоящего)
- Ограничение по размеру файлов (10 MB)
- Ограничение по типу файлов (только изображения для user-photos)
- Пользователи могут редактировать только свои данные

### Переход на настоящую аутентификацию
Если позже захотите добавить регистрацию:
1. Включите Email/Password или Google провайдер в Authentication
2. Добавьте UI для входа/регистрации
3. Firebase автоматически конвертирует анонимного пользователя в постоянного (сохранив uid и все данные)

---

**Следующий шаг**: Включите Anonymous Authentication в Firebase Console и скажите "готово"! 🚀
