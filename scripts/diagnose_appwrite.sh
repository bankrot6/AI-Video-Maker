#!/usr/bin/env bash
# Диагностика проблем с Appwrite

set -euo pipefail

VPS_SSH="${VPS_SSH:-bankr0t@158.160.254.66}"
SSH_KEY_ZIP="${SSH_KEY_ZIP:-$PWD/ssh-key-1775452628632.zip}"
AUTO_RESTART="${AUTO_RESTART:-0}"

TMP_KEYS="$(mktemp -d)"
cleanup() { rm -rf "$TMP_KEYS"; }
trap cleanup EXIT

unzip -q -o "$SSH_KEY_ZIP" -d "$TMP_KEYS"
PRIV="$(find "$TMP_KEYS" -type f ! -name '*.pub' ! -name '*.txt' | head -1)"
chmod 600 "$PRIV"

SSH_BASE=(ssh -i "$PRIV" -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=20)

echo "==> Диагностика Appwrite на сервере..."

"${SSH_BASE[@]}" "$VPS_SSH" "AUTO_RESTART=$AUTO_RESTART bash -s" <<'EOF'
echo "[remote] 1. Статус контейнеров:"
cd ~/appwrite
sudo docker compose ps

echo -e "\n[remote] 2. Статус Docker-сервиса (автозапуск/активность):"
if command -v systemctl >/dev/null 2>&1; then
  echo -n "enabled: "
  sudo systemctl is-enabled docker || true
  echo -n "active: "
  sudo systemctl is-active docker || true
else
  echo "systemd не найден, проверка пропущена"
fi

echo -e "\n[remote] 3. Проверка restart policy контейнеров:"
CONTAINERS="$(sudo docker compose ps -q)"
if [[ -z "$CONTAINERS" ]]; then
  echo "Контейнеры compose не найдены"
else
  sudo docker inspect $CONTAINERS --format '{{.Name}} -> {{.HostConfig.RestartPolicy.Name}}'
fi

echo -e "\n[remote] 4. Логи Traefik (reverse proxy):"
sudo docker compose logs --tail=10 appwrite-traefik || echo "Traefik не запущен"

echo -e "\n[remote] 5. Логи основного Appwrite:"
sudo docker compose logs --tail=10 appwrite || echo "Appwrite не запущен"

echo -e "\n[remote] 6. Проверка портов:"
sudo netstat -tlnp | grep :80 || echo "Порт 80 не слушается"

echo -e "\n[remote] 7. Проверка firewall (ufw):"
sudo ufw status || echo "ufw не установлен/не активен"

echo -e "\n[remote] 8. Использование ресурсов:"
df -h / | head -2
free -h

echo -e "\n[remote] 9. Управляемый перезапуск (опционально):"
if [[ "${AUTO_RESTART}" == "1" ]]; then
  sudo docker compose restart appwrite-traefik appwrite
  sudo docker compose ps | grep -E "(traefik|appwrite[^-])"
else
  echo "Пропущено. Для принудительного рестарта: AUTO_RESTART=1 ./scripts/diagnose_appwrite.sh"
fi
EOF

echo ""
echo "Попробуйте открыть: http://158.160.254.66/ через несколько минут"