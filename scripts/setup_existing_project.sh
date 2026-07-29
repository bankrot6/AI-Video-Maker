#!/usr/bin/env bash
# Настройка существующего Appwrite проекта

set -euo pipefail

APPWRITE_ENDPOINT="http://158.160.254.66/v1"
PROJECT_ID="project-default-6a66f25200139fc454e7"
BASE_URL="http://158.160.254.66"

echo "🚀 Настройка Appwrite проекта: $PROJECT_ID"
echo ""

# Создание временной сессии администратора
echo "📝 Для настройки нужны данные администратора Appwrite:"
read -p "Email администратора: " ADMIN_EMAIL
read -s -p "Пароль администратора: " ADMIN_PASSWORD
echo ""

# Функция для API вызовов
api_call() {
    local method="$1"
    local endpoint="$2" 
    local data="${3:-}"
    local headers="${4:-}"
    
    local curl_args=(-X "$method" -H "Content-Type: application/json" -s)
    
    if [[ -n "$headers" ]]; then
        while IFS= read -r header; do
            [[ -n "$header" ]] && curl_args+=(-H "$header")
        done <<< "$headers"
    fi
    
    if [[ -n "$data" && "$method" != "GET" ]]; then
        curl_args+=(-d "$data")
    fi
    
    curl "${curl_args[@]}" "$APPWRITE_ENDPOINT$endpoint"
}

echo "🔐 Авторизация..."
LOGIN_RESPONSE=$(api_call "POST" "/account/sessions/email" "{
    \"email\": \"$ADMIN_EMAIL\",
    \"password\": \"$ADMIN_PASSWORD\"
}")

if echo "$LOGIN_RESPONSE" | grep -q "error"; then
    echo "❌ Ошибка авторизации: $LOGIN_RESPONSE"
    exit 1
fi

COOKIE=$(echo "$LOGIN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('secret', ''))" 2>/dev/null || echo "")
if [[ -z "$COOKIE" ]]; then
    echo "❌ Не удалось получить сессию"
    exit 1
fi

SESSION_HEADERS="Cookie: a_session_console_legacy=$COOKIE"

echo "✅ Авторизация успешна"

# Создание базы данных
echo "📊 Создание базы данных 'main'..."
DATABASE_RESPONSE=$(api_call "POST" "/databases" "{
    \"databaseId\": \"main\",
    \"name\": \"Main Database\",
    \"enabled\": true
}" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID")

if echo "$DATABASE_RESPONSE" | grep -q "error" && ! echo "$DATABASE_RESPONSE" | grep -q "409"; then
    echo "⚠️ База данных уже существует или ошибка: $DATABASE_RESPONSE"
fi

echo "✅ База данных готова"

# Создание коллекции presets
echo "📁 Создание коллекции 'presets'..."
PRESETS_RESPONSE=$(api_call "POST" "/databases/main/collections" "{
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

if ! echo "$PRESETS_RESPONSE" | grep -q "error" || echo "$PRESETS_RESPONSE" | grep -q "409"; then
    echo "✅ Коллекция 'presets' создана"
    
    echo "  ⚙️ Добавление атрибутов..."
    
    # name
    api_call "POST" "/databases/main/collections/presets/attributes/string" "{
        \"key\": \"name\",
        \"size\": 255,
        \"required\": true
    }" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" >/dev/null
    
    sleep 1
    
    # prompt  
    api_call "POST" "/databases/main/collections/presets/attributes/string" "{
        \"key\": \"prompt\",
        \"size\": 2000,
        \"required\": true
    }" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" >/dev/null
    
    sleep 1
    
    # tags
    api_call "POST" "/databases/main/collections/presets/attributes/string" "{
        \"key\": \"tags\",
        \"size\": 1000,
        \"required\": false,
        \"array\": true
    }" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" >/dev/null
    
    echo "  ✅ Атрибуты добавлены"
else
    echo "⚠️ Коллекция уже существует"
fi

# Создание коллекции user_generations  
echo "📁 Создание коллекции 'user_generations'..."
USER_GEN_RESPONSE=$(api_call "POST" "/databases/main/collections" "{
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

if ! echo "$USER_GEN_RESPONSE" | grep -q "error" || echo "$USER_GEN_RESPONSE" | grep -q "409"; then
    echo "✅ Коллекция 'user_generations' создана"
    
    echo "  ⚙️ Добавление атрибутов..."
    
    # userId
    api_call "POST" "/databases/main/collections/user_generations/attributes/string" "{
        \"key\": \"userId\",
        \"size\": 255,
        \"required\": true
    }" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" >/dev/null
    
    sleep 1
    
    # prompt
    api_call "POST" "/databases/main/collections/user_generations/attributes/string" "{
        \"key\": \"prompt\",
        \"size\": 2000,
        \"required\": true
    }" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" >/dev/null
    
    sleep 1
    
    # imageUrl
    api_call "POST" "/databases/main/collections/user_generations/attributes/string" "{
        \"key\": \"imageUrl\",
        \"size\": 500,
        \"required\": true
    }" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" >/dev/null
    
    sleep 1
    
    # createdAt
    api_call "POST" "/databases/main/collections/user_generations/attributes/datetime" "{
        \"key\": \"createdAt\",
        \"required\": true
    }" "$SESSION_HEADERS
X-Appwrite-Project: $PROJECT_ID" >/dev/null
    
    echo "  ✅ Атрибуты добавлены"
else
    echo "⚠️ Коллекция уже существует"
fi

# Создание storage bucket
echo "💾 Создание Storage bucket 'user-photos'..."
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

if ! echo "$BUCKET_RESPONSE" | grep -q "error" || echo "$BUCKET_RESPONSE" | grep -q "409"; then
    echo "✅ Storage bucket создан"
else
    echo "⚠️ Storage bucket уже существует"
fi

# Создание API ключа
echo "🔑 Создание API ключа..."
API_KEY_RESPONSE=$(api_call "POST" "/projects/$PROJECT_ID/keys" "{
    \"name\": \"Migration API Key\",
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

if echo "$API_KEY_RESPONSE" | grep -q "error"; then
    echo "⚠️ Ошибка создания API ключа или уже существует"
    echo "Используйте существующий API ключ из консоли"
    API_KEY="YOUR_API_KEY_HERE"
else
    API_KEY=$(echo "$API_KEY_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('secret', ''))" 2>/dev/null || echo "")
    echo "✅ API ключ создан"
fi

# Обновление .env файла
echo "📝 Обновление .env файла..."
ENV_FILE="/Volumes/External_Storage/Projects/Photosession-AI/.env"

cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%s)"

if [[ -n "$API_KEY" && "$API_KEY" != "YOUR_API_KEY_HERE" ]]; then
    sed -i.tmp -e "s|APPWRITE_API_KEY=.*|APPWRITE_API_KEY=$API_KEY|" "$ENV_FILE"
    rm -f "$ENV_FILE.tmp"
    echo "✅ .env файл обновлен с новым API ключом"
else
    echo "⚠️ API ключ не был получен - обновите APPWRITE_API_KEY в .env вручную"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 НАСТРОЙКА ЗАВЕРШЕНА!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Детали:"
echo "• Проект: $PROJECT_ID"
echo "• База данных: main"
echo "• Коллекции: presets, user_generations"
echo "• Storage: user-photos"
echo "• Console: $BASE_URL/console"
echo ""
echo "🚀 Теперь можно запускать миграцию:"
echo "./scripts/migrate_presets.sh migrate"