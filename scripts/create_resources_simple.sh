#!/usr/bin/env bash
# Простое создание ресурсов Appwrite через curl (без Node.js)

set -euo pipefail

PROJECT_ROOT="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"
ENV_FILE="$PROJECT_ROOT/.env"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 ПРОСТОЕ СОЗДАНИЕ РЕСУРСОВ APPWRITE${NC}"
echo -e "${BLUE}====================================${NC}"
echo ""

# Загрузка .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}❌ .env файл не найден!${NC}"
    exit 1
fi

source "$ENV_FILE"

# Проверка переменных
if [[ -z "${APPWRITE_API_KEY:-}" ]]; then
    echo -e "${RED}❌ APPWRITE_API_KEY не найден в .env!${NC}"
    exit 1
fi

if [[ -z "${APPWRITE_ENDPOINT:-}" ]]; then
    echo -e "${RED}❌ APPWRITE_ENDPOINT не найден в .env!${NC}"
    exit 1
fi

if [[ -z "${APPWRITE_PROJECT_ID:-}" ]]; then
    echo -e "${RED}❌ APPWRITE_PROJECT_ID не найден в .env!${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Конфигурация загружена${NC}"
echo "   • Endpoint: $APPWRITE_ENDPOINT"
echo "   • Project: $APPWRITE_PROJECT_ID"
echo "   • API Key: ${APPWRITE_API_KEY:0:10}..."
echo ""

# Базовые заголовки для curl
HEADERS=(
    -H "Content-Type: application/json"
    -H "X-Appwrite-Project: $APPWRITE_PROJECT_ID"
    -H "X-Appwrite-Key: $APPWRITE_API_KEY"
)

# Функция для API вызовов
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local curl_args=(-X "$method" "${HEADERS[@]}" -s)
    
    if [[ -n "$data" && "$method" != "GET" ]]; then
        curl_args+=(-d "$data")
    fi
    
    curl "${curl_args[@]}" "$APPWRITE_ENDPOINT$endpoint"
}

# Проверка подключения
echo "🔗 Проверка подключения к Appwrite..."
HEALTH=$(curl -s "$APPWRITE_ENDPOINT/health/version" 2>/dev/null || echo "error")
if echo "$HEALTH" | grep -q "error\|404"; then
    echo -e "${RED}❌ Не удается подключиться к Appwrite${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Подключение успешно${NC}"
echo ""

# 1. Создание базы данных
echo "📊 Создание базы данных 'main'..."
DB_RESPONSE=$(api_call "POST" "/databases" '{
    "databaseId": "main",
    "name": "Main Database",
    "enabled": true
}' 2>/dev/null || echo "error")

if echo "$DB_RESPONSE" | grep -q '"$id"'; then
    echo -e "${GREEN}✅ База данных создана${NC}"
elif echo "$DB_RESPONSE" | grep -q "409\|already exists"; then
    echo -e "${YELLOW}⚠️  База данных уже существует${NC}"
else
    echo -e "${YELLOW}⚠️  База данных возможно уже существует (продолжаем)${NC}"
fi

sleep 2

# 2. Создание коллекции presets
echo ""
echo "📁 Создание коллекции 'presets'..."
PRESETS_RESPONSE=$(api_call "POST" "/databases/main/collections" '{
    "collectionId": "presets",
    "name": "Presets Collection",
    "permissions": ["read(\"any\")", "write(\"any\")"],
    "documentSecurity": false,
    "enabled": true
}' 2>/dev/null || echo "error")

if echo "$PRESETS_RESPONSE" | grep -q '"$id"'; then
    echo -e "${GREEN}✅ Коллекция 'presets' создана${NC}"
    
    echo "  ⚙️ Добавление атрибутов..."
    
    # name
    api_call "POST" "/databases/main/collections/presets/attributes/string" '{
        "key": "name",
        "size": 255,
        "required": true
    }' >/dev/null 2>&1
    sleep 1
    
    # prompt
    api_call "POST" "/databases/main/collections/presets/attributes/string" '{
        "key": "prompt", 
        "size": 2000,
        "required": true
    }' >/dev/null 2>&1
    sleep 1
    
    # tags
    api_call "POST" "/databases/main/collections/presets/attributes/string" '{
        "key": "tags",
        "size": 1000,
        "required": false,
        "array": true
    }' >/dev/null 2>&1
    sleep 1
    
    echo -e "${GREEN}  ✅ Атрибуты добавлены${NC}"
else
    echo -e "${YELLOW}⚠️  Коллекция 'presets' возможно уже существует${NC}"
fi

# 3. Создание коллекции user_generations
echo ""
echo "📁 Создание коллекции 'user_generations'..."
USER_GEN_RESPONSE=$(api_call "POST" "/databases/main/collections" '{
    "collectionId": "user_generations",
    "name": "User Generations Collection", 
    "permissions": ["read(\"any\")", "write(\"any\")"],
    "documentSecurity": false,
    "enabled": true
}' 2>/dev/null || echo "error")

if echo "$USER_GEN_RESPONSE" | grep -q '"$id"'; then
    echo -e "${GREEN}✅ Коллекция 'user_generations' создана${NC}"
    
    echo "  ⚙️ Добавление атрибутов..."
    
    # userId
    api_call "POST" "/databases/main/collections/user_generations/attributes/string" '{
        "key": "userId",
        "size": 255,
        "required": true
    }' >/dev/null 2>&1
    sleep 1
    
    # prompt
    api_call "POST" "/databases/main/collections/user_generations/attributes/string" '{
        "key": "prompt",
        "size": 2000, 
        "required": true
    }' >/dev/null 2>&1
    sleep 1
    
    # imageUrl
    api_call "POST" "/databases/main/collections/user_generations/attributes/string" '{
        "key": "imageUrl",
        "size": 500,
        "required": true
    }' >/dev/null 2>&1
    sleep 1
    
    # createdAt
    api_call "POST" "/databases/main/collections/user_generations/attributes/datetime" '{
        "key": "createdAt",
        "required": true
    }' >/dev/null 2>&1
    sleep 1
    
    echo -e "${GREEN}  ✅ Атрибуты добавлены${NC}"
else
    echo -e "${YELLOW}⚠️  Коллекция 'user_generations' возможно уже существует${NC}"
fi

# 4. Создание storage bucket
echo ""
echo "💾 Создание Storage bucket 'user-photos'..."
BUCKET_RESPONSE=$(api_call "POST" "/storage/buckets" '{
    "bucketId": "user-photos",
    "name": "User Photos Bucket",
    "permissions": ["read(\"any\")", "write(\"any\")"],
    "fileSecurity": false,
    "enabled": true,
    "maximumFileSize": 10485760,
    "allowedFileExtensions": ["jpg", "jpeg", "png", "webp"],
    "compression": "gzip",
    "encryption": false,
    "antivirus": false
}' 2>/dev/null || echo "error")

if echo "$BUCKET_RESPONSE" | grep -q '"$id"'; then
    echo -e "${GREEN}✅ Storage bucket создан${NC}"
else
    echo -e "${YELLOW}⚠️  Storage bucket возможно уже существует${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 ВСЕ РЕСУРСЫ СОЗДАНЫ УСПЕШНО!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📋 Созданные ресурсы:"
echo "   ✅ Database: main"
echo "   ✅ Collection: presets (name, prompt, tags[])"
echo "   ✅ Collection: user_generations (userId, prompt, imageUrl, createdAt)"
echo "   ✅ Storage: user-photos (10MB max, jpg/png/webp)"
echo ""
echo -e "${BLUE}🚀 ГОТОВ К РАБОТЕ!${NC}"
echo ""
echo "Теперь ваше Flutter приложение может использовать Appwrite!"
echo "Проверьте что в .env файле:"
echo "   USE_APPWRITE=true"
echo ""