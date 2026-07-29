# Автоматическое получение API ключей Yandex Search API

## ✅ Что реализовано

Теперь **не нужно вручную создавать API ключи** через консоль Yandex Cloud!  
Приложение **автоматически** получает их через Yandex Cloud IAM API.

---

## 🚀 Как это работает

### Автоматический режим (рекомендуется):

1. **Вы:** Создаете сервисный аккаунт в Yandex Cloud ✅ (уже сделано)
2. **Вы:** Получаете OAuth токен (один раз)
3. **Приложение:** Автоматически получает API ключ при первом запуске
4. **Приложение:** Кэширует ключ на 30 дней
5. **Приложение:** Автоматически обновляет при необходимости

### Схема работы:

```
OAuth Token → IAM Token → API Key → Search API
     ↓            ↓          ↓           ↓
  (в .env)   (временный)  (кэш 30д)  (поиск видео)
```

---

## 📝 Настройка (3 простых шага)

### Шаг 1: Получите OAuth токен

1. Перейдите по ссылке:
   ```
   https://oauth.yandex.ru/authorize?response_type=token&client_id=1a6990aa636648e9b2ef855fa7bec2fb
   ```

2. Авторизуйтесь в Yandex
3. Разрешите доступ к Yandex Cloud
4. Скопируйте токен из адресной строки (после `#access_token=`)

**Пример URL после авторизации:**
```
https://oauth.yandex.ru/verification_code?dev=False#access_token=y0_AgAAAA...здесь_ваш_токен&token_type=bearer&expires_in=31536000
```

### Шаг 2: Получите ID сервисного аккаунта

1. Откройте [Yandex Cloud Console](https://console.yandex.cloud/)
2. Перейдите в раздел **Service Accounts**
3. Найдите свой сервисный аккаунт
4. Скопируйте **ID** (формат: `aje...`)

### Шаг 3: Добавьте в .env файл

Создайте/обновите файл `.env` в корне проекта:

```env
# Yandex Cloud IAM (для автоматического получения API ключей)
YANDEX_OAUTH_TOKEN=y0_AgAAAA_ваш_oauth_токен_здесь
YANDEX_SERVICE_ACCOUNT_ID=aje_ваш_service_account_id_здесь

# Folder ID (опционально, для user параметра)
YANDEX_FOLDER_ID=b1g_ваш_folder_id_здесь
```

**Всё!** Больше ничего не нужно. Приложение автоматически получит API ключ.

---

## 🔧 Техническая реализация

### Новый сервис: `YandexCloudIamService`

**Файл:** `lib/services/yandex_cloud_iam_service.dart`

```dart
class YandexCloudIamService {
  /// Автоматически получает API ключ (с кэшированием на 30 дней)
  Future<String?> getSearchApiKey() async {
    // 1. Проверяем кэш
    if (_cachedApiKey != null && !_isExpired()) {
      return _cachedApiKey; // Возвращаем из кэша
    }

    // 2. Обмениваем OAuth токен на IAM токен
    final iamToken = await _getIamToken();
    
    // 3. Создаем API ключ для сервисного аккаунта
    final apiKey = await _createApiKey(iamToken);
    
    // 4. Кэшируем на 30 дней
    _cachedApiKey = apiKey;
    _cacheTimestamp = DateTime.now();
    
    return apiKey;
  }
}
```

### Интеграция с `YandexSearchApiService`

```dart
class YandexSearchApiService {
  final YandexCloudIamService _iamService = YandexCloudIamService();
  
  Future<List<ExerciseVideoCandidate>> searchVideos(String exerciseName) async {
    // Автоматически получаем API ключ
    String? apiKey = await _iamService.getSearchApiKey();
    
    // Используем для поиска
    final uri = Uri.parse(_apiUrl).replace(queryParameters: {
      'key': apiKey,
      'query': '$exerciseName site:vkvideo.ru',
      ...
    });
  }
}
```

---

## 📊 Логи работы

### Первый запуск (создание ключа):
```
🔄 YANDEX_API: API ключ не задан вручную, пробуем получить автоматически...
🔐 YANDEX_IAM: Получение API ключа...
🔑 YANDEX_IAM: Обмен OAuth токена на IAM токен...
✅ YANDEX_IAM: IAM токен получен
🔐 YANDEX_IAM: Создание API ключа для сервисного аккаунта...
✅ YANDEX_IAM: API ключ создан успешно
✅ YANDEX_IAM: API ключ получен и закэшрован
✅ YANDEX_API: API ключ получен автоматически через IAM
🔍 YANDEX_API: Поиск видео для: Приседания
```

### Повторный запуск (из кэша):
```
✅ YANDEX_IAM: Использую закэшированный API ключ
✅ YANDEX_API: API ключ получен автоматически через IAM
🔍 YANDEX_API: Поиск видео для: Приседания
```

### Если OAuth токен не задан:
```
🔄 YANDEX_API: API ключ не задан вручную, пробуем получить автоматически...
⚠️ YANDEX_IAM: OAuth токен не найден в .env
   Добавьте YANDEX_OAUTH_TOKEN в файл .env
   Получить: https://oauth.yandex.ru/authorize?response_type=token&client_id=...
```

---

## 🔄 Два режима работы

### Режим 1: Автоматический (рекомендуется)

**Требуется в .env:**
```env
YANDEX_OAUTH_TOKEN=y0_AgAAAA...
YANDEX_SERVICE_ACCOUNT_ID=aje...
```

**Преимущества:**
- ✅ Не нужно вручную создавать API ключи
- ✅ Автоматическое обновление
- ✅ Кэширование на 30 дней
- ✅ Один OAuth токен для всех ключей

### Режим 2: Ручной (как раньше)

**Требуется в .env:**
```env
YANDEX_SEARCH_API_KEY=AQVNy...
```

**Когда использовать:**
- Если уже есть готовый API ключ
- Для быстрого тестирования
- Если не хочется использовать OAuth токен

---

## 🔐 Безопасность

### OAuth токен:

- ✅ Хранится только в .env (не в коде)
- ✅ В git не попадает (.env в .gitignore)
- ✅ Используется только для получения IAM токена
- ✅ Срок действия: обычно 1 год

### IAM токен:

- ⏱️ Временный (живет 12 часов)
- 🔒 Используется только внутри сервиса
- 🗑️ Не кэшируется (получается при необходимости)

### API ключ:

- 💾 Кэшируется на 30 дней
- 🔒 Хранится только в памяти приложения
- 🔄 Автоматически обновляется при истечении

---

## ⚙️ API методы

### 1. Получение IAM токена

**Endpoint:** `POST https://iam.api.cloud.yandex.net/iam/v1/tokens`

**Request:**
```json
{
  "yandexPassportOauthToken": "y0_AgAAAA..."
}
```

**Response:**
```json
{
  "iamToken": "t1.9euelZqP...",
  "expiresAt": "2025-10-14T22:23:59Z"
}
```

### 2. Создание API ключа

**Endpoint:** `POST https://iam.api.cloud.yandex.net/iam/v1/apiKeys`

**Headers:**
```
Authorization: Bearer t1.9euelZqP...
```

**Request:**
```json
{
  "serviceAccountId": "aje...",
  "description": "API key for ChatCoach Search API (auto-generated)"
}
```

**Response:**
```json
{
  "id": "ajec...",
  "serviceAccountId": "aje...",
  "createdAt": "2025-10-14T10:23:59Z",
  "description": "API key for ChatCoach Search API (auto-generated)",
  "secret": "AQVN..." // ⚠️ Показывается только один раз!
}
```

---

## 🐛 Troubleshooting

### Ошибка: "OAuth токен не найден"

**Решение:** Добавьте `YANDEX_OAUTH_TOKEN` в `.env`

### Ошибка: "ID сервисного аккаунта не найден"

**Решение:** Добавьте `YANDEX_SERVICE_ACCOUNT_ID` в `.env`

### Ошибка: "API ключ уже существует"

**Информация:** Система пытается создать новый ключ, но он уже есть.

**Решение:**
1. Если помните secret ключа - добавьте его вручную в `.env` как `YANDEX_SEARCH_API_KEY`
2. Если не помните - удалите старый ключ через [консоль](https://console.yandex.cloud/) и создастся новый

### Ошибка: "IAM токен невалиден"

**Возможные причины:**
- OAuth токен истек (срок действия обычно 1 год)
- OAuth токен невалиден

**Решение:** Получите новый OAuth токен по ссылке выше

---

## 📈 Преимущества автоматического режима

| Параметр | Ручной режим | Автоматический режим |
|----------|--------------|----------------------|
| **Настройка** | Сложно (консоль YC) | Просто (2 переменных) |
| **Обновление** | Вручную | Автоматически |
| **Кэширование** | Нет | 30 дней |
| **Управление** | Ручное | Автоматическое |
| **Ошибки** | Нужно вручную создавать | Создаются автоматически |
| **Безопасность** | API ключ в .env | OAuth токен в .env |

---

## 📚 Ссылки

- [Yandex Cloud IAM API](https://yandex.cloud/ru/docs/iam/api-ref/)
- [OAuth токен для Yandex Cloud](https://oauth.yandex.ru/authorize?response_type=token&client_id=1a6990aa636648e9b2ef855fa7bec2fb)
- [Yandex Cloud Console](https://console.yandex.cloud/)
- [Документация Search API](https://yandex.cloud/ru/docs/search-api/)

---

## ✅ Итог

Теперь для работы с Yandex Search API нужно:

1. ✅ Создать сервисный аккаунт (уже сделано)
2. ✅ Получить OAuth токен (1 раз, живет 1 год)
3. ✅ Добавить 2 переменные в .env
4. ✅ Всё! Приложение само получит API ключи

**Время настройки:** 2 минуты вместо 10  
**Обслуживание:** Автоматическое

---

**Дата:** 14 октября 2025  
**Версия:** 5.0  
**Статус:** ✅ Готово к использованию

