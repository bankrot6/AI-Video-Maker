#!/usr/bin/env bash
# Простая настройка Appwrite через Console API

set -euo pipefail

APPWRITE_ENDPOINT="http://158.160.254.66/v1"
PROJECT_ID="project-default-6a66f25200139fc454e7"

echo "🔧 Создание базы данных и коллекций в Appwrite..."
echo "Project: $PROJECT_ID"
echo "Endpoint: $APPWRITE_ENDPOINT"
echo ""

echo "Для настройки нужны данные администратора Appwrite:"
read -p "Email администратора: " ADMIN_EMAIL
read -s -p "Пароль администратора: " ADMIN_PASSWORD
echo ""

# Авторизация
echo "1. Авторизация администратора..."
SESSION_RESPONSE=$(curl -s \
  -X POST "$APPWRITE_ENDPOINT/account/sessions/email" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASSWORD\"}")

if echo "$SESSION_RESPONSE" | grep -q '"secret"'; then
    COOKIE=$(echo "$SESSION_RESPONSE" | grep -o '"secret":"[^"]*"' | cut -d'"' -f4)
    echo "✅ Авторизация успешна"
else
    echo "❌ Ошибка авторизации:"
    echo "$SESSION_RESPONSE"
    exit 1
fi

HEADERS=(-H "Content-Type: application/json" -H "Cookie: a_session_console_legacy=$COOKIE" -H "X-Appwrite-Project: $PROJECT_ID")

# Создание базы данных
echo "2. Создание базы данных 'main'..."
DB_RESPONSE=$(curl -s -X POST "$APPWRITE_ENDPOINT/databases" \
  "${HEADERS[@]}" \
  -d '{"databaseId":"main","name":"Main Database"}')

if echo "$DB_RESPONSE" | grep -q '"name"'; then
    echo "✅ База данных создана"
else
    echo "⚠️  База данных уже существует или ошибка"
fi

# Создание коллекции presets
echo "3. Создание коллекции 'presets'..."
PRESETS_RESPONSE=$(curl -s -X POST "$APPWRITE_ENDPOINT/databases/main/collections" \
  "${HEADERS[@]}" \
  -d '{
    "collectionId": "presets",
    "name": "Presets",
    "permissions": ["read(\"any\")", "write(\"any\")"],
    "documentSecurity": false
  }')

if echo "$PRESETS_RESPONSE" | grep -q '"name"'; then
    echo "✅ Коллекция presets создана"
    
    echo "3a. Добавление атрибута 'name'..."
    curl -s -X POST "$APPWRITE_ENDPOINT/databases/main/collections/presets/attributes/string" \
      "${HEADERS[@]}" \
      -d '{"key":"name","size":255,"required":true}' > /dev/null
    
    sleep 2
    
    echo "3b. Добавление атрибута 'prompt'..."
    curl -s -X POST "$APPWRITE_ENDPOINT/databases/main/collections/presets/attributes/string" \
      "${HEADERS[@]}" \
      -d '{"key":"prompt","size":2000,"required":true}' > /dev/null
    
    sleep 2
    
    echo "3c. Добавление атрибута 'tags'..."
    curl -s -X POST "$APPWRITE_ENDPOINT/databases/main/collections/presets/attributes/string" \
      "${HEADERS[@]}" \
      -d '{"key":"tags","size":1000,"required":false,"array":true}' > /dev/null
    
    echo "✅ Атрибуты добавлены"
else
    echo "⚠️  Коллекция presets уже существует"
fi

# Создание коллекции user_generations
echo "4. Создание коллекции 'user_generations'..."
USER_GEN_RESPONSE=$(curl -s -X POST "$APPWRITE_ENDPOINT/databases/main/collections" \
  "${HEADERS[@]}" \
  -d '{
    "collectionId": "user_generations",
    "name": "User Generations", 
    "permissions": ["read(\"any\")", "write(\"any\")"],
    "documentSecurity": false
  }')

if echo "$USER_GEN_RESPONSE" | grep -q '"name"'; then
    echo "✅ Коллекция user_generations создана"
    
    echo "4a. Добавление атрибутов..."
    curl -s -X POST "$APPWRITE_ENDPOINT/databases/main/collections/user_generations/attributes/string" \
      "${HEADERS[@]}" \
      -d '{"key":"userId","size":255,"required":true}' > /dev/null
    sleep 1
    
    curl -s -X POST "$APPWRITE_ENDPOINT/databases/main/collections/user_generations/attributes/string" \
      "${HEADERS[@]}" \
      -d '{"key":"prompt","size":2000,"required":true}' > /dev/null
    sleep 1
    
    curl -s -X POST "$APPWRITE_ENDPOINT/databases/main/collections/user_generations/attributes/string" \
      "${HEADERS[@]}" \
      -d '{"key":"imageUrl","size":500,"required":true}' > /dev/null
    sleep 1
    
    curl -s -X POST "$APPWRITE_ENDPOINT/databases/main/collections/user_generations/attributes/datetime" \
      "${HEADERS[@]}" \
      -d '{"key":"createdAt","required":true}' > /dev/null
    
    echo "✅ Атрибуты добавлены"
else
    echo "⚠️  Коллекция user_generations уже существует"
fi

# Создание Storage Bucket
echo "5. Создание Storage bucket 'user-photos'..."
BUCKET_RESPONSE=$(curl -s -X POST "$APPWRITE_ENDPOINT/storage/buckets" \
  "${HEADERS[@]}" \
  -d '{
    "bucketId": "user-photos",
    "name": "User Photos",
    "permissions": ["read(\"any\")", "write(\"any\")"],
    "fileSecurity": false,
    "maximumFileSize": 10485760,
    "allowedFileExtensions": ["jpg", "jpeg", "png", "webp"]
  }')

if echo "$BUCKET_RESPONSE" | grep -q '"name"'; then
    echo "✅ Storage bucket создан"
else
    echo "⚠️  Storage bucket уже существует"
fi

# Создание API ключа
echo "6. Создание API ключа..."
API_KEY_RESPONSE=$(curl -s -X POST "$APPWRITE_ENDPOINT/projects/$PROJECT_ID/keys" \
  -H "Content-Type: application/json" \
  -H "Cookie: a_session_console_legacy=$COOKIE" \
  -d '{
    "name": "Flutter Migration Key",
    "scopes": [
      "databases.read", "databases.write",
      "documents.read", "documents.write", 
      "files.read", "files.write",
      "buckets.read"
    ]
  }')

if echo "$API_KEY_RESPONSE" | grep -q '"secret"'; then
    API_KEY=$(echo "$API_KEY_RESPONSE" | grep -o '"secret":"[^"]*"' | cut -d'"' -f4)
    echo "✅ API ключ создан: ${API_KEY:0:20}..."
    
    # Обновление .env файла
    echo "7. Обновление .env файла..."
    ENV_FILE="./.env"
    
    # Создаем резервную копию
    cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%s)"
    
    # Обновляем API_KEY
    sed -i.tmp "s|APPWRITE_API_KEY=.*|APPWRITE_API_KEY=$API_KEY|" "$ENV_FILE"
    rm -f "$ENV_FILE.tmp"
    
    echo "✅ .env файл обновлен"
else
    echo "❌ Ошибка создания API ключа:"
    echo "$API_KEY_RESPONSE"
    exit 1
fi

echo ""
echo "🎉 Настройка завершена успешно!"
echo ""
echo "📋 Созданные ресурсы:"
echo "• База данных: main"
echo "• Коллекции: presets, user_generations"  
echo "• Storage bucket: user-photos"
echo "• API ключ: добавлен в .env"
echo ""
echo "🚀 Теперь можно запустить миграцию пресетов!"