# Быстрая настройка Yandex Search API

## 🎯 3 простых шага до работающего поиска видео

### Шаг 1: Получите OAuth токен (2 минуты)

1. **Откройте ссылку в браузере:**
   ```
   https://oauth.yandex.ru/authorize?response_type=token&client_id=1a6990aa636648e9b2ef855fa7bec2fb
   ```

2. **Авторизуйтесь** в Yandex (если еще не авторизованы)

3. **Разрешите доступ** к Yandex Cloud

4. **Скопируйте токен** из адресной строки:
   ```
   https://oauth.yandex.ru/verification_code?...#access_token=y0_AgAAAA...ВАШ_ТОКЕН_ЗДЕСЬ&token_type=bearer
   ```
   
   Нужна часть после `access_token=` и до `&token_type`

### Шаг 2: Получите ID сервисного аккаунта (1 минута)

1. **Откройте:** [console.yandex.cloud](https://console.yandex.cloud/)

2. **Перейдите в:** Service Accounts

3. **Найдите** свой сервисный аккаунт (который вы создали)

4. **Скопируйте ID** (формат: `aje...`)

### Шаг 3: Добавьте в .env файл (30 секунд)

Создайте файл `.env` в корне проекта ChatCoach:

```env
# Yandex Cloud IAM - для автоматического получения API ключей
YANDEX_OAUTH_TOKEN=y0_AgAAAA_ВАШ_OAUTH_ТОКЕН_СЮДА
YANDEX_SERVICE_ACCOUNT_ID=aje_ВАШ_SERVICE_ACCOUNT_ID_СЮДА

# Опционально (для user параметра в API)
YANDEX_FOLDER_ID=b1g_ваш_folder_id
```

**Пример:**
```env
YANDEX_OAUTH_TOKEN=y0_AgAAAAABcDefGhIjKlMnOpQrStUvWxYz123456789
YANDEX_SERVICE_ACCOUNT_ID=ajeabcdefghijklmnop
YANDEX_FOLDER_ID=b1g1234567890abcdef
```

---

## ✅ Готово!

Теперь:
1. Запустите приложение
2. Откройте любое упражнение
3. Видео будут загружаться **автоматически** без капчи!

### Что произойдет автоматически:

```
1. Приложение обменяет OAuth токен на IAM токен
   ↓
2. Создаст API ключ для Search API
   ↓
3. Закэширует ключ на 30 дней
   ↓
4. Будет использовать для поиска видео
```

---

## 🔍 Проверка работы

### В логах должно быть:

```
🔄 YANDEX_API: API ключ не задан вручную, пробуем получить автоматически...
🔐 YANDEX_IAM: Получение API ключа...
🔑 YANDEX_IAM: Обмен OAuth токена на IAM токен...
✅ YANDEX_IAM: IAM токен получен
🔐 YANDEX_IAM: Создание API ключа для сервисного аккаунта...
✅ YANDEX_IAM: API ключ создан успешно
✅ YANDEX_IAM: API ключ получен и закэширован
✅ YANDEX_API: API ключ получен автоматически через IAM
🔍 YANDEX_API: Поиск видео для: Приседания
🔎 YANDEX_API: Запрос: "Приседания техника site:vkvideo.ru"
🌐 YANDEX_API: Запрос к API...
📄 YANDEX_API: Парсинг XML ответа
   🎥 Найдено: https://vksport.vkvideo.ru/video1441257_456240595
   ✅ Добавлено: video1441257_456240595
✅ YANDEX_API: Найдено 2 видео
```

### Если что-то не так:

**Ошибка:** `⚠️ YANDEX_IAM: OAuth токен не найден в .env`
- **Решение:** Добавьте `YANDEX_OAUTH_TOKEN` в `.env`

**Ошибка:** `⚠️ YANDEX_IAM: ID сервисного аккаунта не найден в .env`
- **Решение:** Добавьте `YANDEX_SERVICE_ACCOUNT_ID` в `.env`

**Ошибка:** `❌ YANDEX_IAM: Ошибка получения IAM токена: 401`
- **Решение:** OAuth токен невалиден или истек, получите новый по ссылке выше

---

## 📱 Альтернатива: Ручной режим

Если не хотите использовать OAuth токен, можно вручную создать API ключ:

1. Откройте [console.yandex.cloud](https://console.yandex.cloud/)
2. Перейдите: Service Accounts → Ваш аккаунт → API Keys
3. Нажмите "Create API key"
4. Скопируйте ключ (показывается только один раз!)
5. Добавьте в `.env`:
   ```env
   YANDEX_SEARCH_API_KEY=AQVN_ваш_api_ключ_здесь
   ```

---

## 🎉 Результат

После настройки:
- ✅ Поиск видео работает **без капчи**
- ⚡ Быстро (1-2 секунды)
- 🔄 Автоматическое управление ключами
- 💾 Кэширование результатов
- 📱 Топ-4 качественных видео для каждого упражнения

**Время настройки:** ~3 минуты  
**Время работы:** Навсегда (пока валиден OAuth токен - обычно 1 год)

---

**Подробная документация:** `YANDEX_AUTO_API_KEY_RU.md`

