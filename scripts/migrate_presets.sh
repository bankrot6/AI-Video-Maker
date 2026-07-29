#!/usr/bin/env bash
# Миграция пресетов из Firebase в Appwrite
# Использует лучшие практики для минимальной нагрузки на сервер

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Firebase to Appwrite Migration Tool${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Функция проверки переменных окружения
check_env_vars() {
    local missing=()
    local env_file="$PROJECT_ROOT/.env"
    
    if [[ ! -f "$env_file" ]]; then
        echo -e "${RED}❌ .env file not found at $env_file${NC}"
        exit 1
    fi
    
    # Загрузка переменных
    set -a
    source "$env_file" 2>/dev/null || true
    set +a
    
    # Проверка Firebase переменных
    [[ -z "${FIREBASE_API_KEY:-}" ]] && missing+=("FIREBASE_API_KEY")
    [[ -z "${FIREBASE_PROJECT_ID:-}" ]] && missing+=("FIREBASE_PROJECT_ID")
    [[ -z "${FIREBASE_AUTH_DOMAIN:-}" ]] && missing+=("FIREBASE_AUTH_DOMAIN")
    
    # Проверка Appwrite переменных  
    [[ -z "${APPWRITE_ENDPOINT:-}" ]] && missing+=("APPWRITE_ENDPOINT")
    [[ -z "${APPWRITE_PROJECT_ID:-}" ]] && missing+=("APPWRITE_PROJECT_ID")
    [[ -z "${APPWRITE_API_KEY:-}" ]] && missing+=("APPWRITE_API_KEY")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Missing required environment variables:${NC}"
        printf '   • %s\n' "${missing[@]}"
        echo ""
        echo -e "${YELLOW}Please update your .env file with the required values.${NC}"
        echo ""
        echo "📋 Required variables:"
        echo "   Firebase: FIREBASE_API_KEY, FIREBASE_PROJECT_ID, FIREBASE_AUTH_DOMAIN"  
        echo "   Appwrite: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Environment variables validated${NC}"
}

# Функция установки зависимостей
install_dependencies() {
    echo "📦 Checking Node.js dependencies..."
    
    cd "$SCRIPT_DIR"
    
    if [[ ! -f "package.json" ]]; then
        echo -e "${RED}❌ package.json not found in scripts directory${NC}"
        exit 1
    fi
    
    # Проверка Node.js
    if ! command -v node &> /dev/null; then
        echo -e "${RED}❌ Node.js is not installed${NC}"
        echo "Please install Node.js 16+ from https://nodejs.org/"
        exit 1
    fi
    
    # Проверка версии Node.js
    local node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ "$node_version" -lt 16 ]]; then
        echo -e "${RED}❌ Node.js version 16+ required (current: $(node -v))${NC}"
        exit 1
    fi
    
    # Установка зависимостей
    if [[ ! -d "node_modules" ]] || [[ "package.json" -nt "node_modules" ]]; then
        echo "📥 Installing dependencies..."
        npm install --silent
    fi
    
    echo -e "${GREEN}✅ Dependencies ready${NC}"
}

# Функция проверки подключений
test_connections() {
    echo "🔗 Testing connections..."
    
    # Проверка доступности Appwrite
    local appwrite_url="${APPWRITE_ENDPOINT%/v1}"
    if ! curl -s --max-time 10 "$appwrite_url/health/version" > /dev/null; then
        echo -e "${RED}❌ Cannot reach Appwrite server at $appwrite_url${NC}"
        echo "Please ensure your Appwrite server is running and accessible."
        exit 1
    fi
    
    echo -e "${GREEN}✅ Connections validated${NC}"
}

# Функция показа статуса
show_status() {
    echo "📊 Migration Status:"
    echo "==================="
    
    local log_file="$PROJECT_ROOT/migration.log"
    local progress_file="$PROJECT_ROOT/migration_progress.json"
    
    if [[ -f "$progress_file" ]]; then
        echo "📈 Progress:"
        cat "$progress_file" | jq -r '
            "   • Status: \(.status // "unknown")",
            "   • Processed: \(.totalProcessed // 0) documents", 
            "   • Migrated: \(.totalMigrated // 0) documents",
            "   • Errors: \(.totalErrors // 0)",
            "   • Current Batch: \(.currentBatch // 0)",
            "   • Started: \(if .startTime then (.startTime / 1000 | strftime("%Y-%m-%d %H:%M:%S")) else "Not started" end)"
        ' 2>/dev/null || echo "   • No valid progress data found"
    else
        echo "   • No migration in progress"
    fi
    
    echo ""
    
    if [[ -f "$log_file" ]]; then
        echo "📋 Recent logs (last 10 lines):"
        tail -10 "$log_file" | jq -r '"\(.timestamp) [\(.level)] \(.message)"' 2>/dev/null || tail -10 "$log_file"
    else
        echo "📋 No logs found"
    fi
}

# Функция запуска миграции
run_migration() {
    echo ""
    echo -e "${YELLOW}⚠️  ВАЖНО: Миграция начнется через 5 секунд${NC}"
    echo ""
    echo "Настройки миграции:"
    echo "   • Источник: Firebase Project '$FIREBASE_PROJECT_ID'"
    echo "   • Получатель: Appwrite Project '$APPWRITE_PROJECT_ID'"  
    echo "   • Коллекция: presets → presets"
    echo "   • Размер батча Firebase: 25 документов"
    echo "   • Размер батча Appwrite: 10 документов"
    echo "   • Задержка между батчами: 1 секунда"
    echo ""
    echo -e "${YELLOW}Нажмите Ctrl+C для отмены...${NC}"
    
    for i in {5..1}; do
        echo -ne "\rЗапуск через $i секунд..."
        sleep 1
    done
    echo -e "\n"
    
    echo -e "${GREEN}🚀 Starting migration...${NC}"
    echo ""
    
    # Запуск миграции
    cd "$SCRIPT_DIR"
    node migrate_firebase_to_appwrite.js
}

# Функция очистки
cleanup_migration() {
    echo -e "${YELLOW}🧹 Cleaning up migration files...${NC}"
    
    local log_file="$PROJECT_ROOT/migration.log"
    local progress_file="$PROJECT_ROOT/migration_progress.json"
    
    [[ -f "$log_file" ]] && rm "$log_file" && echo "   • Removed migration.log"
    [[ -f "$progress_file" ]] && rm "$progress_file" && echo "   • Removed migration_progress.json"
    
    echo -e "${GREEN}✅ Cleanup completed${NC}"
}

# Главная функция
main() {
    local command="${1:-migrate}"
    
    case "$command" in
        "migrate"|"start"|"run")
            check_env_vars
            install_dependencies  
            test_connections
            run_migration
            ;;
        "status"|"info")
            show_status
            ;;
        "cleanup"|"clean")
            cleanup_migration
            ;;
        "test"|"check")
            check_env_vars
            install_dependencies
            test_connections
            echo -e "${GREEN}✅ All checks passed - ready for migration!${NC}"
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "   migrate, start, run  - Start the migration process (default)"
            echo "   status, info         - Show current migration status"  
            echo "   test, check          - Test connections and validate setup"
            echo "   cleanup, clean       - Remove migration files"
            echo "   help                 - Show this help message"
            echo ""
            echo "Features:"
            echo "   • Batch processing with rate limiting"
            echo "   • Automatic retry on failures"
            echo "   • Resume capability after interruption"  
            echo "   • Duplicate detection and skipping"
            echo "   • Detailed logging and progress tracking"
            ;;
        *)
            echo -e "${RED}❌ Unknown command: $command${NC}"
            echo "Use '$0 help' for available commands."
            exit 1
            ;;
    esac
}

# Обработка сигналов для graceful shutdown
trap 'echo -e "\n${YELLOW}⚠️  Migration interrupted by user${NC}"; exit 130' INT TERM

# Запуск
main "$@"