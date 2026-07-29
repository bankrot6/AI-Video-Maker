#!/usr/bin/env bash
# Диагностика SSH-подключения к VPS
# Использование: ./scripts/debug_ssh.sh

set -euo pipefail

VPS_SSH="${VPS_SSH:-ubuntu@158.160.254.66}"
SSH_KEY_ZIP="${SSH_KEY_ZIP:-$PWD/ssh-key-1775452628632.zip}"
REMOTE_IP="${REMOTE_IP:-${VPS_SSH##*@}}"

echo "==> Диагностика SSH-подключения"
echo "VPS: $VPS_SSH"
echo "SSH Key: $SSH_KEY_ZIP" 
echo "IP: $REMOTE_IP"
echo ""

# Проверка zip файла
if [[ ! -f "$SSH_KEY_ZIP" ]]; then
  echo "❌ SSH ключ не найден: $SSH_KEY_ZIP"
  exit 1
fi
echo "✅ SSH ключ найден: $(ls -lh "$SSH_KEY_ZIP")"

# Проверка содержимого zip
echo ""
echo "==> Содержимое SSH ключа:"
unzip -l "$SSH_KEY_ZIP" || {
  echo "❌ Ошибка чтения zip-архива"
  exit 1
}

# Извлечение и проверка ключа
TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo ""
echo "==> Извлечение ключа..."
unzip -q -o "$SSH_KEY_ZIP" -d "$TMP_DIR"
echo "Файлы в архиве:"
ls -la "$TMP_DIR"

# Поиск приватного ключа
PRIV_KEY=$(find "$TMP_DIR" -type f ! -name '*.pub' ! -name '*.txt' | head -1)
if [[ -z "$PRIV_KEY" || ! -f "$PRIV_KEY" ]]; then
  echo "❌ Приватный SSH ключ не найден в архиве"
  exit 1
fi

echo "✅ Найден приватный ключ: $PRIV_KEY"
chmod 600 "$PRIV_KEY"

# Проверка формата ключа
echo ""
echo "==> Проверка формата ключа:"
head -1 "$PRIV_KEY"
if head -1 "$PRIV_KEY" | grep -q "BEGIN.*PRIVATE KEY"; then
  echo "✅ Ключ имеет правильный формат"
else
  echo "❌ Ключ имеет неправильный формат"
  echo "Первые строки файла:"
  head -3 "$PRIV_KEY"
fi

# Проверка доступности сервера
echo ""
echo "==> Проверка доступности сервера..."
if timeout 10 ping -c 1 "$REMOTE_IP" > /dev/null 2>&1; then
  echo "✅ Сервер $REMOTE_IP доступен"
else
  echo "❌ Сервер $REMOTE_IP недоступен"
  echo "Проверьте сетевое подключение и IP адрес"
fi

# Проверка SSH порта
echo ""
echo "==> Проверка SSH порта..."
if timeout 10 nc -z "$REMOTE_IP" 22; then
  echo "✅ SSH порт 22 открыт на $REMOTE_IP"
else
  echo "❌ SSH порт 22 недоступен на $REMOTE_IP"
  echo "Возможно, SSH служба не запущена или порт закрыт firewall"
fi

# Попытка подключения
echo ""
echo "==> Попытка SSH подключения..."
ssh -i "$PRIV_KEY" -o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10 "$VPS_SSH" 'echo "SSH подключение успешно!" && whoami && uname -a' || {
  echo "❌ SSH подключение неудачно"
  echo ""
  echo "Возможные причины:"
  echo "1. Неправильный SSH ключ"
  echo "2. Ключ не добавлен в ~/.ssh/authorized_keys на сервере"
  echo "3. Неправильное имя пользователя (ubuntu vs root vs другое)"
  echo "4. SSH служба не настроена или отключена"
  echo "5. Firewall блокирует подключение"
  echo ""
  echo "Попробуйте:"
  echo "- Проверить, что ключ добавлен при создании VM в Яндекс.Облаке"
  echo "- Использовать веб-консоль VM для настройки SSH"
  echo "- Проверить пользователя: может быть root вместо ubuntu"
}