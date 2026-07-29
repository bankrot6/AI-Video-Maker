#!/usr/bin/env bash
# Полная установка Appwrite на VPS одной командой с вашего Mac (нужен сеть до сервера).
# Использование:
#   cd /path/to/Photosession-AI
#   chmod +x scripts/deploy_appwrite_to_vps.sh
#   ./scripts/deploy_appwrite_to_vps.sh
#
# Переменные (опционально):
#   VPS_SSH=ubuntu@158.160.254.66
#   SSH_KEY_ZIP="$PWD/ssh-key-1775452628632.zip"   (реальный путь к zip, не «/полный/путь»)
#
# Важно: compose берётся с appwrite.io/install/compose (продакшен, образы appwrite/appwrite:*).
# Сырой docker-compose.yml из ветки GitHub — это DEV (appwrite-dev + build) и без Dockerfile падает.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VPS_SSH="${VPS_SSH:-bankr0t@158.160.254.66}"
SSH_KEY_ZIP="${SSH_KEY_ZIP:-$ROOT_DIR/ssh-key-1775452628632.zip}"
REMOTE_IP="${REMOTE_IP:-${VPS_SSH##*@}}"
COMPOSE_URL="${COMPOSE_URL:-https://appwrite.io/install/compose}"
ENV_URL="${ENV_URL:-https://appwrite.io/install/env}"

if [[ ! -f "$SSH_KEY_ZIP" ]]; then
  echo "Нет архива ключа: $SSH_KEY_ZIP"
  exit 1
fi

TMP_KEYS="$(mktemp -d)"
cleanup() { rm -rf "$TMP_KEYS"; }
trap cleanup EXIT

unzip -q -o "$SSH_KEY_ZIP" -d "$TMP_KEYS"
PRIV="$(find "$TMP_KEYS" -type f ! -name '*.pub' ! -name '*.txt' | head -1)"
if [[ -z "$PRIV" || ! -f "$PRIV" ]]; then
  echo "В zip не найден приватный ключ"
  exit 1
fi
chmod 600 "$PRIV"

SSH_BASE=(ssh -i "$PRIV" -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=20)

echo "==> Проверка SSH $VPS_SSH ..."
"${SSH_BASE[@]}" "$VPS_SSH" 'echo "SSH OK" && uname -a'

echo "==> Установка Docker и Appwrite (продакшен compose) на сервере (sudo) ..."
REMOTE_SCRIPT=$(cat <<'EOS'
set -euo pipefail
REMOTE_IP="__REMOTE_IP__"
COMPOSE_URL="__COMPOSE_URL__"
ENV_URL="__ENV_URL__"
if ! command -v docker >/dev/null 2>&1; then
  echo "[remote] Устанавливаю Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER" || true
fi
if command -v systemctl >/dev/null 2>&1; then
  echo "[remote] Включаю автозапуск Docker при старте сервера..."
  sudo systemctl enable --now docker
  sudo systemctl is-enabled docker >/dev/null
  sudo systemctl is-active docker >/dev/null
fi
sudo docker info >/dev/null
mkdir -p "$HOME/appwrite"
cd "$HOME/appwrite"
echo "[remote] Качаю продакшен compose с appwrite.io..."
curl -fsSL "$COMPOSE_URL" -o docker-compose.yml
curl -fsSL "$ENV_URL" -o .env.raw
if head -1 .env.raw | grep -q '^```'; then
  tail -n +2 .env.raw | sed '$d' > .env
  rm -f .env.raw
else
  mv .env.raw .env
fi

OPENSSL_KEY="$(openssl rand -hex 32)"
EXEC_SECRET="$(openssl rand -hex 32)"
DB_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
DB_ROOT="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"

sed -i.bak \
  -e "s|_APP_OPENSSL_KEY_V1=.*|_APP_OPENSSL_KEY_V1=${OPENSSL_KEY}|" \
  -e "s|_APP_EXECUTOR_SECRET=.*|_APP_EXECUTOR_SECRET=${EXEC_SECRET}|" \
  -e "s|_APP_DB_PASS=.*|_APP_DB_PASS=${DB_PASS}|" \
  -e "s|_APP_DB_ROOT_PASS=.*|_APP_DB_ROOT_PASS=${DB_ROOT}|" \
  -e "s|_APP_OPTIONS_FORCE_HTTPS=.*|_APP_OPTIONS_FORCE_HTTPS=disabled|" \
  -e "s|_APP_OPTIONS_FUNCTIONS_FORCE_HTTPS=.*|_APP_OPTIONS_FUNCTIONS_FORCE_HTTPS=disabled|" \
  -e "s|_APP_OPTIONS_ROUTER_FORCE_HTTPS=.*|_APP_OPTIONS_ROUTER_FORCE_HTTPS=disabled|" \
  -e "s|_APP_DOMAIN=.*|_APP_DOMAIN=${REMOTE_IP}|" \
  -e "s|_APP_DOMAIN_TARGET=.*|_APP_DOMAIN_TARGET=${REMOTE_IP}|" \
  -e "s|_APP_CONSOLE_HOSTNAMES=.*|_APP_CONSOLE_HOSTNAMES=${REMOTE_IP},localhost|" \
  -e "s|_APP_STORAGE_LIMIT=.*|_APP_STORAGE_LIMIT=52428800|" \
  .env
# Если переменная отсутствует — дописываем явно (52428800 = 50 MB)
grep -q '_APP_STORAGE_LIMIT' .env || echo '_APP_STORAGE_LIMIT=52428800' >> .env

echo "[remote] Запуск контейнеров (может занять несколько минут)..."
if sudo docker compose version >/dev/null 2>&1; then
  sudo docker compose up -d --remove-orphans
elif sudo docker-compose version >/dev/null 2>&1; then
  sudo docker-compose up -d --remove-orphans
else
  echo "docker compose не найден"
  exit 1
fi
echo "[remote] Проверяю restart policy у всех контейнеров..."
CONTAINERS="$(sudo docker compose ps -q)"
if [[ -z "${CONTAINERS}" ]]; then
  echo "Не удалось получить список контейнеров compose"
  exit 1
fi
NO_RESTART_POLICY="$(sudo docker inspect ${CONTAINERS} --format '{{.Name}} {{.HostConfig.RestartPolicy.Name}}' | awk '$2 == "" || $2 == "no" { print }')"
if [[ -n "${NO_RESTART_POLICY}" ]]; then
  echo "Найдены контейнеры без restart policy:"
  echo "${NO_RESTART_POLICY}"
  exit 1
fi
echo "[remote] Restart policy OK у всех контейнеров."
echo "[remote] Готово. Консоль: http://${REMOTE_IP}/"
EOS
)
REMOTE_SCRIPT="${REMOTE_SCRIPT//__REMOTE_IP__/$REMOTE_IP}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__COMPOSE_URL__/$COMPOSE_URL}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__ENV_URL__/$ENV_URL}"

"${SSH_BASE[@]}" "$VPS_SSH" "bash -s" <<< "$REMOTE_SCRIPT"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1) Откройте в браузере: http://${REMOTE_IP}/"
echo "2) Создайте аккаунт администратора и проект."
echo "3) Создайте API Key (scope: databases.read/write, documents.*, storage.*)."
echo "4) Database + коллекции presets, user_generations + bucket user-photos"
echo "5) Впишите в .env приложения:"
echo "   APPWRITE_ENDPOINT=http://${REMOTE_IP}/v1"
echo "   APPWRITE_PROJECT_ID=..."
echo "   APPWRITE_DATABASE_ID=..."
echo "   APPWRITE_API_KEY=..."
echo "   USE_APPWRITE=true"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
