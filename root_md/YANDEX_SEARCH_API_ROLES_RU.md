# Настройка прав доступа для Yandex Search API

## ⚠️ Важно! Нужно назначить роль сервисному аккаунту

Если вы получаете ошибку **HTTP 403**, это означает, что у сервисного аккаунта нет прав на использование Search API.

---

## 🔧 Как исправить (2 минуты):

### Вариант 1: Через консоль Yandex Cloud (рекомендуется)

1. **Откройте:** [console.yandex.cloud](https://console.yandex.cloud/)

2. **Перейдите в:** Service Accounts → Ваш сервисный аккаунт

3. **Нажмите:** "Assign roles" (Назначить роли)

4. **Добавьте роль:** `search-api.webSearch.user`

5. **Сохраните**

### Вариант 2: Через Yandex Cloud CLI

```bash
# Назначить роль search-api.webSearch.user
yc resource-manager folder add-access-binding <FOLDER_ID> \
  --role search-api.webSearch.user \
  --subject serviceAccount:<SERVICE_ACCOUNT_ID>
```

**Замените:**
- `<FOLDER_ID>` - ID вашего каталога (folder)
- `<SERVICE_ACCOUNT_ID>` - ID вашего сервисного аккаунта (aje...)

---

## 📋 Необходимые роли

Для работы с Yandex Search API нужна **одна из** этих ролей:

| Роль | Описание | Рекомендуется |
|------|----------|---------------|
| `search-api.webSearch.user` | Выполнение поисковых запросов | ✅ Да |
| `search-api.executor` | Устаревшая роль | ⚠️ Работает, но deprecated |
| `editor` | Полный доступ к папке | ❌ Слишком много прав |

**Используйте:** `search-api.webSearch.user`

---

## 🔍 Как проверить текущие роли

### Через консоль:
1. Service Accounts → Ваш аккаунт
2. Вкладка "Access bindings"
3. Проверьте наличие `search-api.webSearch.user`

### Через CLI:
```bash
yc resource-manager folder list-access-bindings <FOLDER_ID> \
  --format json | grep search-api
```

---

## ✅ После назначения роли

1. **Подождите 1-2 минуты** (роли применяются не мгновенно)
2. **Перезапустите приложение**
3. **Откройте любое упражнение**
4. Видео должны загрузиться без ошибки 403

---

## 📊 Логи

### ❌ Было (ошибка 403):
```
🌐 YANDEX_API: Запрос к API...
❌ YANDEX_API: HTTP 403
   Response: Access Denied
```

### ✅ Стало (после назначения роли):
```
🌐 YANDEX_API: Запрос к API...
📄 YANDEX_API: Парсинг XML ответа (12345 байт)
   🎥 Найдено: https://vksport.vkvideo.ru/video1441257_456240595
   ✅ Добавлено: video1441257_456240595
✅ YANDEX_API: Найдено 2 видео
```

---

## 🐛 Другие возможные ошибки

### HTTP 401 - Неверный API ключ
**Решение:** Проверьте, что ключ в `.env` правильный

### HTTP 403 - Нет прав доступа
**Решение:** Назначьте роль `search-api.webSearch.user` (см. выше)

### HTTP 429 - Превышен лимит запросов
**Решение:** 
- Бесплатный tier: 1000 запросов/день
- Подождите или обновите тарифный план

### HTTP 400 - Неверный запрос
**Решение:** Проверьте параметры запроса (query, folderid и т.д.)

---

## 🔗 Полезные ссылки

- [Роли для Search API](https://yandex.cloud/ru/docs/search-api/security/)
- [Управление доступом](https://yandex.cloud/ru/docs/iam/concepts/access-control/roles)
- [Консоль Yandex Cloud](https://console.yandex.cloud/)

---

## 📝 Краткая инструкция

```
1. Откройте console.yandex.cloud
2. Service Accounts → Ваш аккаунт
3. Assign roles → search-api.webSearch.user
4. Сохраните
5. Подождите 1-2 минуты
6. Перезапустите приложение
✅ Готово!
```

---

**Дата:** 14 октября 2025  
**Версия:** 5.1  
**Статус:** ✅ Критичное исправление

