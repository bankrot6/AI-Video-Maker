#!/bin/bash
# Простой прямой запуск pepk.jar без проверок
set -e

cd "$(dirname "$0")/.."

KEYSTORE="$PWD/upload-keystore-DEMO.jks"
PEPK_JAR="$PWD/pepk.jar"
OUT_ZIP="$PWD/android/pepk_out.zip"
ENCRYPTION_KEY="000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0"

STORE_PASS="Demo7RuStore9Photosession2026Key!Temp"
KEY_PASS="DemoKey8PhotoAI2026Upload!Secure"
ALIAS="upload"

echo "================================"
echo "DEMO: Экспорт ключа для RuStore"
echo "================================"
echo "Keystore: $KEYSTORE"
echo "Alias: $ALIAS"
echo "Output: $OUT_ZIP"
echo ""

printf '%s\n%s\n' "$STORE_PASS" "$KEY_PASS" | java -jar "$PEPK_JAR" \
  --keystore "$KEYSTORE" \
  --alias "$ALIAS" \
  --output "$OUT_ZIP" \
  --encryptionkey="$ENCRYPTION_KEY" \
  --include-cert

echo ""
echo "✓ Готово! Файл создан: $OUT_ZIP"
echo ""
echo "ВАЖНО: Это DEMO ключ, НЕ для production!"
echo "Для production используйте ваш РЕАЛЬНЫЙ keystore."
