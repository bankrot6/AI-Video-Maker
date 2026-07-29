#!/usr/bin/env bash
# Очистка Docker кеша и повторная установка Appwrite

set -euo pipefail

VPS_SSH="${VPS_SSH:-bankr0t@158.160.254.66}"
SSH_KEY_ZIP="${SSH_KEY_ZIP:-$PWD/ssh-key-1775452628632.zip}"
REMOTE_IP="${REMOTE_IP:-${VPS_SSH##*@}}"

if [[ ! -f "$SSH_KEY_ZIP" ]]; then
  echo "SSH ключ не найден: $SSH_KEY_ZIP"
  exit 1
fi

TMP_KEYS="$(mktemp -d)"
cleanup() { rm -rf "$TMP_KEYS"; }
trap cleanup EXIT

unzip -q -o "$SSH_KEY_ZIP" -d "$TMP_KEYS"
PRIV="$(find "$TMP_KEYS" -type f ! -name '*.pub' ! -name '*.txt' | head -1)"
chmod 600 "$PRIV"

SSH_BASE=(ssh -i "$PRIV" -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=20)

echo "==> Подключение к серверу и очистка Docker кеша..."

"${SSH_BASE[@]}" "$VPS_SSH" "REMOTE_IP=$REMOTE_IP bash -s" <<'EOF'
set -euo pipefail

echo "[remote] Проверяем место на диске ПЕРЕД очисткой:"
df -h / | head -2

echo "[remote] Останавливаем все Docker контейнеры..."
if sudo docker ps -q | wc -l | grep -q '^0$'; then
  echo "[remote] Контейнеры не запущены"
else
  sudo docker stop $(sudo docker ps -q) || true
fi

echo "[remote] Удаляем все контейнеры, образы и тома..."
sudo docker system prune -af --volumes || true
sudo docker builder prune -af || true
sudo docker volume prune -f || true

# Дополнительная очистка containerd snapshots
echo "[remote] Очистка containerd snapshots..."
sudo systemctl stop containerd || true
sudo rm -rf /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/* || true
sudo systemctl start containerd || true

echo "[remote] Очистка системных логов и кеша..."
sudo journalctl --vacuum-time=1d || true
sudo apt-get clean || true
sudo rm -rf /tmp/* /var/tmp/* || true

echo "[remote] Место на диске ПОСЛЕ очистки:"
df -h / | head -2

echo "[remote] Переустановка Appwrite..."
cd "$HOME"
rm -rf appwrite || true
mkdir -p appwrite
cd appwrite

COMPOSE_URL="https://appwrite.io/install/compose"
ENV_URL="https://appwrite.io/install/env"

echo "[remote] Скачиваю продакшен compose..."
curl -fsSL "$COMPOSE_URL" -o docker-compose.yml
curl -fsSL "$ENV_URL" -o .env.raw

# Обработка markdown обертки в .env файле
if head -1 .env.raw | grep -q '^```'; then
  tail -n +2 .env.raw | sed '$d' > .env
  rm -f .env.raw
else
  mv .env.raw .env
fi

# Генерация секретных ключей
OPENSSL_KEY="$(openssl rand -hex 32)"
EXEC_SECRET="$(openssl rand -hex 32)"
DB_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
DB_ROOT="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"

# Настройка .env файла
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
  .env

echo "[remote] Запуск Appwrite (осторожно, может занять время)..."
if sudo docker compose version >/dev/null 2>&1; then
  sudo docker compose up -d --remove-orphans
elif sudo docker-compose version >/dev/null 2>&1; then
  sudo docker-compose up -d --remove-orphans
else
  echo "Docker compose не найден!"
  exit 1
fi

echo "[remote] Проверяем статус контейнеров..."
sleep 10
sudo docker compose ps

echo "[remote] ✅ Готово! Консоль: http://${REMOTE_IP}/"
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Appwrite успешно переустановлен!"
echo ""
echo "Далее:"
echo "1) Откройте: http://${REMOTE_IP}/"
echo "2) Создайте аккаунт администратора и проект"
echo "3) Создайте API Key (scope: databases.*, documents.*, storage.*)"
echo "4) Database + коллекции presets, user_generations + bucket user-photos"
echo "5) Обновите .env приложения:"
echo "   APPWRITE_ENDPOINT=http://${REMOTE_IP}/v1"
echo "   APPWRITE_PROJECT_ID=..."
echo "   APPWRITE_DATABASE_ID=..."
echo "   APPWRITE_API_KEY=..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"