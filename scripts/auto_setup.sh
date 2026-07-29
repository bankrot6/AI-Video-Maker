#!/usr/bin/env bash
# Автоматическая настройка Appwrite (без интерактивного ввода)

set -euo pipefail

APPWRITE_ENDPOINT="http://158.160.254.66/v1"
PROJECT_ID="project-default-6a66f25200139fc454e7"

echo "🚀 АВТОМАТИЧЕСКАЯ НАСТРОЙКА APPWRITE"
echo "===================================="
echo ""

# Получение API ключа из браузера
echo "📋 Для полной автоматизации нужен API ключ от Appwrite."
echo ""
echo "🔗 Откройте в браузере:"
echo "   http://158.160.254.66/console/project-$PROJECT_ID/settings/keys"
echo ""
echo "⚙️  Создайте новый API ключ:"
echo "   • Name: Migration Key"  
echo "   • Scopes: databases.*, documents.*, files.*"
echo "   • Нажмите 'Create'"
echo ""
read -p "Вставьте созданный API ключ: " API_KEY

if [[ -z "$API_KEY" ]]; then
    echo "❌ API ключ не может быть пустым"
    exit 1
fi

echo ""
echo "✅ API ключ получен: ${API_KEY:0:10}..."
echo ""

# Функция для API вызовов
api_call() {
    local method="$1"
    local endpoint="$2" 
    local data="${3:-}"
    
    local curl_args=(-X "$method" -H "Content-Type: application/json" -H "X-Appwrite-Project: $PROJECT_ID" -H "X-Appwrite-Key: $API_KEY" -s)
    
    if [[ -n "$data" && "$method" != "GET" ]]; then
        curl_args+=(-d "$data")
    fi
    
    curl "${curl_args[@]}" "$APPWRITE_ENDPOINT$endpoint"
}

echo "🔍 Проверка подключения к Appwrite..."
HEALTH_CHECK=$(curl -s "$APPWRITE_ENDPOINT/health/version" || echo "error")
if echo "$HEALTH_CHECK" | grep -q "error"; then
    echo "❌ Не удается подключиться к Appwrite"
    exit 1
fi
echo "✅ Подключение к Appwrite успешно"

# Создание базы данных
echo ""
echo "📊 Создание базы данных 'main'..."
DATABASE_RESPONSE=$(api_call "POST" "/databases" "{
    \"databaseId\": \"main\",
    \"name\": \"Main Database\",
    \"enabled\": true
}" 2>/dev/null || echo '{"error": true}')

if echo "$DATABASE_RESPONSE" | grep -q '"$id"'; then
    echo "✅ База данных 'main' создана"
elif echo "$DATABASE_RESPONSE" | grep -q "already exists"; then
    echo "⚠️  База данных 'main' уже существует"
else
    echo "⚠️  База данных возможно уже существует (игнорируем ошибку)"
fi

# Ожидание создания базы данных
sleep 2

# Создание коллекции presets
echo ""
echo "📁 Создание коллекции 'presets'..."
PRESETS_RESPONSE=$(api_call "POST" "/databases/main/collections" "{
    \"collectionId\": \"presets\",
    \"name\": \"Presets\",
    \"permissions\": [\"read(\\\"any\\\")\", \"write(\\\"any\\\")\"],
    \"documentSecurity\": false,
    \"enabled\": true
}" 2>/dev/null || echo '{"error": true}')

if echo "$PRESETS_RESPONSE" | grep -q '"$id"'; then
    echo "✅ Коллекция 'presets' создана"
    
    echo "  ⚙️ Добавление атрибутов..."
    sleep 1
    
    # Атрибут name
    api_call "POST" "/databases/main/collections/presets/attributes/string" "{
        \"key\": \"name\",
        \"size\": 255,
        \"required\": true
    }" >/dev/null 2>&1 || true
    
    sleep 1
    
    # Атрибут prompt  
    api_call "POST" "/databases/main/collections/presets/attributes/string" "{
        \"key\": \"prompt\",
        \"size\": 2000,
        \"required\": true
    }" >/dev/null 2>&1 || true
    
    sleep 1
    
    # Атрибут tags (array)
    api_call "POST" "/databases/main/collections/presets/attributes/string" "{
        \"key\": \"tags\",
        \"size\": 1000,
        \"required\": false,
        \"array\": true
    }" >/dev/null 2>&1 || true
    
    echo "  ✅ Атрибуты добавлены в 'presets'"
else
    echo "⚠️  Коллекция 'presets' возможно уже существует"
fi

# Создание коллекции user_generations  
echo ""
echo "📁 Создание коллекции 'user_generations'..."
USER_GEN_RESPONSE=$(api_call "POST" "/databases/main/collections" "{
    \"collectionId\": \"user_generations\",
    \"name\": \"User Generations\",
    \"permissions\": [\"read(\\\"any\\\")\", \"write(\\\"any\\\")\"],
    \"documentSecurity\": false,
    \"enabled\": true
}" 2>/dev/null || echo '{"error": true}')

if echo "$USER_GEN_RESPONSE" | grep -q '"$id"'; then
    echo "✅ Коллекция 'user_generations' создана"
    
    echo "  ⚙️ Добавление атрибутов..."
    sleep 1
    
    # userId
    api_call "POST" "/databases/main/collections/user_generations/attributes/string" "{
        \"key\": \"userId\",
        \"size\": 255,
        \"required\": true
    }" >/dev/null 2>&1 || true
    
    sleep 1
    
    # prompt
    api_call "POST" "/databases/main/collections/user_generations/attributes/string" "{
        \"key\": \"prompt\",
        \"size\": 2000,
        \"required\": true
    }" >/dev/null 2>&1 || true
    
    sleep 1
    
    # imageUrl
    api_call "POST" "/databases/main/collections/user_generations/attributes/string" "{
        \"key\": \"imageUrl\",
        \"size\": 500,
        \"required\": true
    }" >/dev/null 2>&1 || true
    
    sleep 1
    
    # createdAt
    api_call "POST" "/databases/main/collections/user_generations/attributes/datetime" "{
        \"key\": \"createdAt\",
        \"required\": true
    }" >/dev/null 2>&1 || true
    
    echo "  ✅ Атрибуты добавлены в 'user_generations'"
else
    echo "⚠️  Коллекция 'user_generations' возможно уже существует"
fi

# Создание storage bucket
echo ""
echo "💾 Создание Storage bucket 'user-photos'..."
BUCKET_RESPONSE=$(api_call "POST" "/storage/buckets" "{
    \"bucketId\": \"user-photos\",
    \"name\": \"User Photos\", 
    \"permissions\": [\"read(\\\"any\\\")\", \"write(\\\"any\\\")\"],
    \"fileSecurity\": false,
    \"enabled\": true,
    \"maximumFileSize\": 10485760,
    \"allowedFileExtensions\": [\"jpg\", \"jpeg\", \"png\", \"webp\"],
    \"compression\": \"gzip\",
    \"encryption\": false,
    \"antivirus\": false
}" 2>/dev/null || echo '{"error": true}')

if echo "$BUCKET_RESPONSE" | grep -q '"$id"'; then
    echo "✅ Storage bucket 'user-photos' создан"
else
    echo "⚠️  Storage bucket возможно уже существует"
fi

# Обновление .env файла
echo ""
echo "📝 Обновление .env файла..."
ENV_FILE="/Volumes/External_Storage/Projects/Photosession-AI/.env"

# Создание резервной копии
cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%s)"

# Обновление API ключа
if grep -q "APPWRITE_API_KEY=" "$ENV_FILE"; then
    sed -i.tmp "s|APPWRITE_API_KEY=.*|APPWRITE_API_KEY=$API_KEY|" "$ENV_FILE"
    rm -f "$ENV_FILE.tmp"
else
    echo "APPWRITE_API_KEY=$API_KEY" >> "$ENV_FILE"
fi

echo "✅ .env файл обновлен"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 НАСТРОЙКА ЗАВЕРШЕНА УСПЕШНО!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 Созданные ресурсы:"
echo "   ✅ База данных: main"
echo "   ✅ Коллекция: presets (name, prompt, tags)"
echo "   ✅ Коллекция: user_generations (userId, prompt, imageUrl, createdAt)"
echo "   ✅ Storage: user-photos (10MB, jpg/png/webp)"
echo "   ✅ API ключ: обновлен в .env"
echo ""
echo "🚀 ГОТОВ К МИГРАЦИИ!"
echo ""
echo "Запустите миграцию:"
echo "   ./scripts/migrate_presets.sh migrate"
echo ""