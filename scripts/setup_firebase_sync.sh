#!/usr/bin/env bash
# setup_firebase_sync.sh
# ─────────────────────────────────────────────────────────────────────
# Настраивает Firebase Functions для двусторонней синхронизации
# Firebase Firestore ↔ Appwrite.
#
# Запуск: bash scripts/setup_firebase_sync.sh
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"

# ── 1. Загружаем .env из корня проекта ───────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  echo "❌  Файл .env не найден: $ENV_FILE"
  exit 1
fi

# shellcheck disable=SC2046
export $(grep -v '^#' "$ENV_FILE" | grep -v '^[[:space:]]*$' | xargs)

APPWRITE_ENDPOINT="${APPWRITE_ENDPOINT:-}"
APPWRITE_PROJECT_ID="${APPWRITE_PROJECT_ID:-}"
APPWRITE_DATABASE_ID="${APPWRITE_DATABASE_ID:-main}"
APPWRITE_PRESETS_COLLECTION_ID="${APPWRITE_PRESETS_COLLECTION_ID:-presets}"
APPWRITE_API_KEY="${APPWRITE_API_KEY:-}"

if [[ -z "$APPWRITE_ENDPOINT" || -z "$APPWRITE_PROJECT_ID" || -z "$APPWRITE_API_KEY" ]]; then
  echo "❌  В .env не заполнены APPWRITE_ENDPOINT / APPWRITE_PROJECT_ID / APPWRITE_API_KEY"
  exit 1
fi

# ── 2. Создаём functions/.env (не-чувствительные переменные) ─────────
FUNCTIONS_ENV="$ROOT/functions/.env"
echo "📝  Записываем $FUNCTIONS_ENV"
cat > "$FUNCTIONS_ENV" <<EOF
APPWRITE_ENDPOINT=$APPWRITE_ENDPOINT
APPWRITE_PROJECT_ID=$APPWRITE_PROJECT_ID
APPWRITE_DATABASE_ID=$APPWRITE_DATABASE_ID
APPWRITE_PRESETS_COLLECTION_ID=$APPWRITE_PRESETS_COLLECTION_ID
EOF
echo "✅  functions/.env создан"

# ── 3. Устанавливаем Firebase Secret для API-ключа ────────────────────
echo ""
echo "🔐  Устанавливаем Firebase Secret APPWRITE_API_KEY..."
echo "$APPWRITE_API_KEY" | firebase functions:secrets:set APPWRITE_API_KEY --data-file=-
echo "✅  Secret APPWRITE_API_KEY установлен"

# ── 4. Деплоим функции ────────────────────────────────────────────────
echo ""
echo "🚀  Деплоим Cloud Functions (только sync-функции)..."
firebase deploy --only functions:syncPresetToAppwrite,functions:syncFromAppwrite
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✅  Готово! Синхронизация Firebase ↔ Appwrite запущена.    ║"
echo "║                                                              ║"
echo "║  Firebase → Appwrite  push при каждом изменении пресета     ║"
echo "║  Appwrite → Firebase  pull каждые 5 минут                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
