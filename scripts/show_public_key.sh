#!/usr/bin/env bash
# Показывает содержимое публичного SSH ключа для копирования

set -e

SSH_KEY_ZIP="${SSH_KEY_ZIP:-$PWD/ssh-key-1775452628632.zip}"

if [[ ! -f "$SSH_KEY_ZIP" ]]; then
  echo "Файл не найден: $SSH_KEY_ZIP"
  exit 1
fi

TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Извлекаю публичный ключ из $SSH_KEY_ZIP..."
unzip -q -o "$SSH_KEY_ZIP" -d "$TMP_DIR"

PUB_KEY=$(find "$TMP_DIR" -name "*.pub" | head -1)
if [[ -z "$PUB_KEY" ]]; then
  echo "Публичный ключ (.pub) не найден в архиве"
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "СКОПИРУЙТЕ ЭТУ СТРОКУ:"
echo "═══════════════════════════════════════════════"
cat "$PUB_KEY"
echo ""
echo "═══════════════════════════════════════════════"
echo ""
echo "Эту строку нужно добавить в ~/.ssh/authorized_keys на сервере"