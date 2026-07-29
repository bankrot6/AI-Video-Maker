#!/bin/bash
# Создание файлов для загрузки подписи в RuStore
set -e

cd "$(dirname "$0")/.."

KEYSTORE="$PWD/upload-keystore.jks"
PEPK_JAR="$PWD/pepk.jar"
PEPK_OUT="$PWD/android/pepk_out.zip"
CERT_OUT="$PWD/android/upload-cert.pem"
ENCRYPTION_KEY="000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0"

STORE_PASS="PhotoAI2026RuStoreSecureProd9xK8mL2n"
ALIAS="upload"

echo "============================================"
echo "Создание файлов для RuStore"
echo "============================================"
echo ""
echo "1/2: Экспорт сертификата (PEM формат)..."
echo ""

keytool -exportcert \
  -alias "$ALIAS" \
  -keystore "$KEYSTORE" \
  -storepass "$STORE_PASS" \
  -rfc \
  -file "$CERT_OUT"

if [[ -f "$CERT_OUT" ]]; then
    echo "✓ Сертификат создан: $CERT_OUT"
    ls -lh "$CERT_OUT"
else
    echo "✗ Ошибка создания сертификата"
    exit 1
fi

echo ""
echo "2/2: Экспорт ключа (PEPK архив)..."
echo ""
echo "ВАЖНО: Команда запросит пароли интерактивно."
echo "Используйте пароли из android/PRODUCTION_PASSWORDS.txt"
echo ""
echo "Store password: $STORE_PASS"
echo "Key password: PhotoAI2026PhotoAI7wQ5bN4pSecure"
echo ""
read -p "Нажмите Enter для продолжения..." -r

java -jar "$PEPK_JAR" \
  --keystore "$KEYSTORE" \
  --alias "$ALIAS" \
  --output "$PEPK_OUT" \
  --encryptionkey="$ENCRYPTION_KEY" \
  --include-cert

echo ""
echo "============================================"
echo "✓ ГОТОВО!"
echo "============================================"
echo ""
echo "Созданные файлы:"
echo "  1. ZIP архив: $PEPK_OUT"
echo "  2. Сертификат: $CERT_OUT"
echo ""
echo "Загрузите их в RuStore Console:"
echo "  - Шаг 3: Загрузите ZIP ($PEPK_OUT)"
echo "  - Шаг 4: Загрузите PEM ($CERT_OUT)"
echo ""
echo "============================================"
