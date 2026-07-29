# Быстрое решение ошибки 403 в Yandex Search API

## ❌ Ошибка:
```
❌ YANDEX_API: HTTP 403
   Response: Access Denied
```

---

## ✅ Решение (5 минут):

### Шаг 1: Назначьте роль сервисному аккаунту

1. **Откройте:** https://console.yandex.cloud/
2. **Перейдите:** Service Accounts
3. **Найдите:** Ваш сервисный аккаунт (например `ajeegskf6bkkhbg6jl5o`)
4. **Нажмите:** "Assign roles" / "Назначить роли"
5. **Выберите роль:** `search-api.webSearch.user`
6. **Сохраните**
7. **Подождите 1-2 минуты**

### Шаг 2: Добавьте Folder ID в .env

1. **В консоли Yandex Cloud** (верхняя часть) найдите dropdown с названием каталога
2. **Скопируйте ID** каталога (формат: `b1g...`)
3. **Откройте файл:** `/Volumes/External_Storage/Projects/ChatCoach/.env`
4. **Найдите строку:** `YANDEX_FOLDER_ID=ваш_folder_id_здесь`
5. **Замените на:** `YANDEX_FOLDER_ID=b1g_ваш_реальный_id`

**Пример:**
```env
YANDEX_FOLDER_ID=b1g1234567890abcdef
```

### Шаг 3: Перезапустите приложение

```bash
flutter run -d 00008030-001258D42601802E
```

---

## 📊 Проверка

### ✅ Правильные логи:
```
✅ YANDEX_API: Использую ручной API ключ из .env
🔍 YANDEX_API: Поиск видео для: Приседания
🔑 YANDEX_API: Использую API ключ: AQVNzoco8y...
🌐 YANDEX_API: Запрос к API...
📄 YANDEX_API: Парсинг XML ответа (12345 байт)
   🎥 Найдено: https://vksport.vkvideo.ru/video1441257_456240595
✅ YANDEX_API: Найдено 2 видео
```

### ❌ Если всё ещё 403:

**Проверьте:**
1. Роль `search-api.webSearch.user` назначена? (подождите 2 минуты после назначения)
2. Folder ID правильный в `.env`?
3. API ключ правильный?

---

## 🔧 Что было исправлено в коде:

### 1. Authorization заголовок:
```dart
// ❌ Было
'key': apiKey,  // в параметрах URL

// ✅ Стало
'Authorization': 'Api-Key $apiKey'  // в заголовке
```

### 2. Параметр folderid:
```dart
// ❌ Было
'user': _apiUser ?? 'default',

// ✅ Стало
'folderid': _apiUser ?? 'default',  // folder ID!
```

---

## 📝 Checklist

- [ ] Назначена роль `search-api.webSearch.user`
- [ ] Добавлен `YANDEX_FOLDER_ID` в `.env`
- [ ] Добавлен `YANDEX_SEARCH_API_KEY` в `.env`
- [ ] Подождал 1-2 минуты после назначения роли
- [ ] Перезапустил приложение
- [ ] Проверил логи (должна быть ✅ вместо ❌)

---

## 🎯 Итог:

После выполнения всех шагов видео будут загружаться **без ошибки 403**!

```
Роль → Folder ID → Перезапуск → ✅ Работает!
```

---

**Дата:** 14 октября 2025  
**Статус:** ✅ Критичное исправление

