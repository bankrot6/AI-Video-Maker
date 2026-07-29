#!/usr/bin/env bash
# Полная настройка и миграция из Firebase в Appwrite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 ПОЛНАЯ НАСТРОЙКА И МИГРАЦИЯ FIREBASE → APPWRITE${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# Проверка зависимостей
echo "📦 Установка зависимостей..."
cd "$SCRIPT_DIR"

if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js не найден!${NC}"
    echo "Установите Node.js 16+ с https://nodejs.org/"
    exit 1
fi

if [[ ! -d "node_modules" ]]; then
    echo "📥 Установка npm пакетов..."
    npm install --silent
fi

echo -e "${GREEN}✅ Зависимости готовы${NC}"
echo ""

# Проверка .env файла
ENV_FILE="$PROJECT_ROOT/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}❌ .env файл не найден!${NC}"
    exit 1
fi

# Проверка API ключа
if ! grep -q "APPWRITE_API_KEY=standard_" "$ENV_FILE" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  APPWRITE_API_KEY не найден в .env файле!${NC}"
    echo ""
    echo -e "${BLUE}📋 Быстрые инструкции:${NC}"
    echo ""
    echo "1️⃣  Откройте в браузере:"
    echo "   http://158.160.254.66/console/project-project-default-6a66f25200139fc454e7/settings/keys"
    echo ""
    echo "2️⃣  Создайте API Key:"
    echo "   • Name: Migration Key"
    echo "   • Scopes: отметьте ВСЕ галочки (databases.*, documents.*, files.*)"
    echo "   • Нажмите Create"
    echo ""
    echo "3️⃣  Скопируйте ключ и добавьте в .env файл:"
    echo "   APPWRITE_API_KEY=standard_ваш_ключ_здесь"
    echo ""
    echo "4️⃣  Запустите скрипт снова:"
    echo "   ./scripts/complete_setup.sh"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ API ключ найден в .env файле${NC}"
echo ""

# Создание ресурсов Appwrite
echo -e "${BLUE}⚙️  Создание ресурсов в Appwrite...${NC}"
node create_appwrite_resources.js

# Проверка успешности создания ресурсов
if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Ресурсы Appwrite созданы успешно!${NC}"
    echo ""
    
    # Запуск миграции
    echo -e "${BLUE}🔄 Запуск миграции пресетов...${NC}"
    echo ""
    
    # Возвращаемся в корень проекта для запуска миграции
    cd "$PROJECT_ROOT"
    ./scripts/migrate_presets.sh migrate
else
    echo ""
    echo -e "${RED}❌ Ошибка создания ресурсов Appwrite${NC}"
    echo "Проверьте API ключ и повторите попытку"
    exit 1
fi