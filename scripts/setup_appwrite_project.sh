#!/usr/bin/env bash
# Автоматическая настройка проекта Appwrite через API

set -euo pipefail

APPWRITE_ENDPOINT="${APPWRITE_ENDPOINT:-http://158.160.254.66/v1}"
BASE_URL="${APPWRITE_ENDPOINT%/v1}"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Настройка проекта Appwrite через API ===${NC}"
echo "Endpoint: $APPWRITE_ENDPOINT"
echo ""

# Функция для выполнения HTTP запросов
api_call() {
    local method="$1"
    local endpoint="$2" 
    local data="${3:-}"
    local headers="${4:-}"
    
    local curl_args=(-X "$method" -H "Content-Type: application/json")
    
    if [[ -n "$headers" ]]; then
        while IFS= read -r header; do
            [[ -n "$header" ]] && curl_args+=(-H "$header")
        done <<< "$headers"
    fi
    
    if [[ -n "$data" && "$method" != "GET" ]]; then
        curl_args+=(-d "$data")
    fi
    
    curl -s -w "\nHTTP_STATUS:%{http_code}\n" "${curl_args[@]}" "$APPWRITE_ENDPOINT$endpoint"
}

# Получение данных для входа
echo -e "${YELLOW}Для настройки нужны данные администратора:${NC}"
read -p "Email администратора: " ADMIN_EMAIL
read -s -p "Пароль администратора: " ADMIN_PASSWORD
echo ""
echo ""

# 1. Авторизация администратора
echo -e "${GREEN}1. Авторизация администратора...${NC}"
LOGIN_RESPONSE=$(api_call "POST" "/account/sessions/email" "{
    \"email\": \"$ADMIN_EMAIL\",
    \"password\": \"$ADMIN_PASSWORD\"
}")

HTTP_STATUS=$(echo "$LOGIN_RESPONSE" | tail -1 | cut -d: -f2)
LOGIN_DATA=$(echo "$LOGIN_RESPONSE" | head -n -1)

if [[ "$HTTP_STATUS" != "201" ]]; then
    echo -e "${RED}❌ Ошибка авторизации (HTTP $HTTP_STATUS):${NC}"
    echo "$LOGIN_DATA"
    echo ""
    echo "Возможные причины:"
    echo "1. Неверный email или пароль"
    echo "2. Администратор еще не создан - откройте $BASE_URL и зарегистрируйтесь"
    exit 1
fi

# Извлечение cookie сессии
COOKIE=$(echo "$LOGIN_DATA" | jq -r '.secret // empty')
if [[ -z "$COOKIE" ]]; then
    echo -e "${RED}❌ Не удалось получить сессию${NC}"
    exit 1
fi

SESSION_HEADERS="Cookie: a_session_console_legacy=$COOKIE"

echo -e "${GREEN}✅ Авторизация успешна${NC}"
echo ""

# 2. Создание проекта
echo -e "${GREEN}2. Создание проекта...${NC}"
PROJECT_NAME="AI Video Maker"
PROJECT_ID="photosession-ai-$(date +%s)"

PROJECT_RESPONSE=$(api_call "POST" "/projects" "{
    \"projectId\": \"$PROJECT_ID\",
    \"name\": \"$PROJECT_NAME\",
    \"teamId\": \"console\",
    \"region\": \"default\",
    \"description\": \"AI фотосессия - Flutter приложение\"
}" "$SESSION_HEADERS")

HTTP_STATUS=$(echo "$PROJECT_RESPONSE" | tail -1 | cut -d: -f2)
PROJECT_DATA=$(echo "$PROJECT_RESPONSE" | head -n -1)

if [[ "$HTTP_STATUS" != "201" ]]; then
    echo -e "${RED}❌ Ошибка создания проекта (HTTP $HTTP_STATUS):${NC}"
    echo "$PROJECT_DATA"
    exit 1
fi

echo -e "${GREEN}✅ Проект создан: $PROJECT_ID${NC}"
echo ""

# 3. Создание базы данных
echo -e "${GREEN}3. Создание базы данных...${NC}"
DATABASE_ID="main"
DATABASE_NAME="Main Database"

DATABASE_RESPONSE=$(api_call "POST" "/databases" "{
    \"databaseId\": \"$DATABASE_ID\",
    \"name\": \"$DATABASE_NAME\",
    \"enabled\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID")

HTTP_STATUS=$(echo "$DATABASE_RESPONSE" | tail -1 | cut -d: -f2)
DATABASE_DATA=$(echo "$DATABASE_RESPONSE" | head -n -1)

if [[ "$HTTP_STATUS" != "201" ]]; then
    echo -e "${RED}❌ Ошибка создания базы данных (HTTP $HTTP_STATUS):${NC}"
    echo "$DATABASE_DATA"
    exit 1
fi

echo -e "${GREEN}✅ База данных создана: $DATABASE_ID${NC}"
echo ""

# 4. Создание коллекции presets
echo -e "${GREEN}4. Создание коллекции 'presets'...${NC}"
PRESETS_RESPONSE=$(api_call "POST" "/databases/$DATABASE_ID/collections" "{
    \"collectionId\": \"presets\",
    \"name\": \"Presets\",
    \"permissions\": [
        \"read(\\\"any\\\")\",
        \"write(\\\"any\\\")\"
    ],
    \"documentSecurity\": false,
    \"enabled\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID")

HTTP_STATUS=$(echo "$PRESETS_RESPONSE" | tail -1 | cut -d: -f2)
if [[ "$HTTP_STATUS" == "201" ]]; then
    echo -e "${GREEN}✅ Коллекция 'presets' создана${NC}"
else
    echo -e "${YELLOW}⚠️ Коллекция 'presets' уже существует или ошибка (HTTP $HTTP_STATUS)${NC}"
fi

# Добавление атрибутов для presets
echo -e "${GREEN}   Добавление атрибутов в 'presets'...${NC}"

# name (строка)
api_call "POST" "/databases/$DATABASE_ID/collections/presets/attributes/string" "{
    \"key\": \"name\",
    \"size\": 255,
    \"required\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" > /dev/null

# prompt (строка)
api_call "POST" "/databases/$DATABASE_ID/collections/presets/attributes/string" "{
    \"key\": \"prompt\",
    \"size\": 2000,
    \"required\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" > /dev/null

# tags (массив строк)
api_call "POST" "/databases/$DATABASE_ID/collections/presets/attributes/string" "{
    \"key\": \"tags\",
    \"size\": 1000,
    \"required\": false,
    \"array\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" > /dev/null

echo -e "${GREEN}   ✅ Атрибуты добавлены в 'presets'${NC}"
echo ""

# 5. Создание коллекции user_generations
echo -e "${GREEN}5. Создание коллекции 'user_generations'...${NC}"
USER_GEN_RESPONSE=$(api_call "POST" "/databases/$DATABASE_ID/collections" "{
    \"collectionId\": \"user_generations\",
    \"name\": \"User Generations\",
    \"permissions\": [
        \"read(\\\"any\\\")\",
        \"write(\\\"any\\\")\"
    ],
    \"documentSecurity\": false,
    \"enabled\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID")

HTTP_STATUS=$(echo "$USER_GEN_RESPONSE" | tail -1 | cut -d: -f2)
if [[ "$HTTP_STATUS" == "201" ]]; then
    echo -e "${GREEN}✅ Коллекция 'user_generations' создана${NC}"
else
    echo -e "${YELLOW}⚠️ Коллекция 'user_generations' уже существует или ошибка (HTTP $HTTP_STATUS)${NC}"
fi

# Добавление атрибутов для user_generations
echo -e "${GREEN}   Добавление атрибутов в 'user_generations'...${NC}"

# userId (строка)
api_call "POST" "/databases/$DATABASE_ID/collections/user_generations/attributes/string" "{
    \"key\": \"userId\",
    \"size\": 255,
    \"required\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" > /dev/null

# prompt (строка)
api_call "POST" "/databases/$DATABASE_ID/collections/user_generations/attributes/string" "{
    \"key\": \"prompt\",
    \"size\": 2000,
    \"required\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" > /dev/null

# imageUrl (строка)
api_call "POST" "/databases/$DATABASE_ID/collections/user_generations/attributes/string" "{
    \"key\": \"imageUrl\",
    \"size\": 500,
    \"required\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" > /dev/null

# createdAt (datetime)
api_call "POST" "/databases/$DATABASE_ID/collections/user_generations/attributes/datetime" "{
    \"key\": \"createdAt\",
    \"required\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" > /dev/null

echo -e "${GREEN}   ✅ Атрибуты добавлены в 'user_generations'${NC}"
echo ""

# 6. Создание Storage Bucket
echo -e "${GREEN}6. Создание Storage bucket 'user-photos'...${NC}"
BUCKET_RESPONSE=$(api_call "POST" "/storage/buckets" "{
    \"bucketId\": \"user-photos\",
    \"name\": \"User Photos\",
    \"permissions\": [
        \"read(\\\"any\\\")\",
        \"write(\\\"any\\\")\"
    ],
    \"fileSecurity\": false,
    \"enabled\": true,
    \"maximumFileSize\": 10485760,
    \"allowedFileExtensions\": [\"jpg\", \"jpeg\", \"png\", \"webp\"],
    \"compression\": \"gzip\",
    \"encryption\": false,
    \"antivirus\": false
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID")

HTTP_STATUS=$(echo "$BUCKET_RESPONSE" | tail -1 | cut -d: -f2)
if [[ "$HTTP_STATUS" == "201" ]]; then
    echo -e "${GREEN}✅ Storage bucket 'user-photos' создан${NC}"
else
    echo -e "${YELLOW}⚠️ Storage bucket уже существует или ошибка (HTTP $HTTP_STATUS)${NC}"
fi
echo ""

# 7. Создание API ключа
echo -e "${GREEN}7. Создание API ключа...${NC}"
API_KEY_RESPONSE=$(api_call "POST" "/projects/$PROJECT_ID/keys" "{
    \"name\": \"Flutter App Key\",
    \"scopes\": [
        \"databases.read\",
        \"databases.write\",
        \"documents.read\", 
        \"documents.write\",
        \"files.read\",
        \"files.write\",
        \"buckets.read\"
    ],
    \"expire\": null
}" "$SESSION_HEADERS")

HTTP_STATUS=$(echo "$API_KEY_RESPONSE" | tail -1 | cut -d: -f2)
API_KEY_DATA=$(echo "$API_KEY_RESPONSE" | head -n -1)

if [[ "$HTTP_STATUS" != "201" ]]; then
    echo -e "${RED}❌ Ошибка создания API ключа (HTTP $HTTP_STATUS):${NC}"
    echo "$API_KEY_DATA"
    exit 1
fi

API_KEY=$(echo "$API_KEY_DATA" | jq -r '.secret')
echo -e "${GREEN}✅ API ключ создан${NC}"
echo ""

# 8. Обновление .env файла
echo -e "${GREEN}8. Обновление .env файла...${NC}"
ENV_FILE="/Volumes/External_Storage/Projects/Photosession-AI/.env"

# Создаем резервную копию
cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%s)"

# Обновляем значения
sed -i.tmp \
    -e "s|APPWRITE_PROJECT_ID=.*|APPWRITE_PROJECT_ID=$PROJECT_ID|" \
    -e "s|APPWRITE_DATABASE_ID=.*|APPWRITE_DATABASE_ID=$DATABASE_ID|" \
    -e "s|APPWRITE_API_KEY=.*|APPWRITE_API_KEY=$API_KEY|" \
    "$ENV_FILE"

rm -f "$ENV_FILE.tmp"
echo -e "${GREEN}✅ .env файл обновлен${NC}"
echo ""

# Финальная информация
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 ПРОЕКТ APPWRITE УСПЕШНО НАСТРОЕН!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📋 Детали проекта:"
echo "• Проект ID: $PROJECT_ID"
echo "• База данных: $DATABASE_ID"
echo "• Endpoint: $APPWRITE_ENDPOINT"
echo "• Console URL: $BASE_URL"
echo ""
echo "📁 Созданные ресурсы:"
echo "• Коллекция: presets (атрибуты: name, prompt, tags)"
echo "• Коллекция: user_generations (атрибуты: userId, prompt, imageUrl, createdAt)"
echo "• Storage bucket: user-photos (10MB, jpg/png/webp)"
echo "• API ключ с правами на databases, documents, files"
echo ""
echo "📝 .env файл обновлен с новыми значениями"
echo ""
echo "🚀 Теперь можно запускать Flutter приложение с Appwrite!"