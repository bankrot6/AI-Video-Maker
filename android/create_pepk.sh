#!/bin/bash
# Автоматическое создание PEPK архива для RuStore
set -e

cd "$(dirname "$0")/.."

KEYSTORE="$PWD/upload-keystore.jks"
PEPK_JAR="$PWD/pepk.jar"
PEPK_OUT="$PWD/android/pepk_out.zip"
ENCRYPTION_KEY="000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0"

STORE_PASS="PhotoAI2026RuStoreSecureProd9xK8mL2n"
KEY_PASS="UploadKey2026PhotoAI7wQ5bN4pSecure"
ALIAS="upload"

echo "============================================"
echo "Создание PEPK архива для RuStore"
echo "============================================"
echo ""

# Проверка expect
if ! command -v expect &> /dev/null; then
    echo "⚠️  expect не установлен."
    echo ""
    echo "Вариант 1: Установить expect"
    echo "  brew install expect"
    echo ""
    echo "Вариант 2: Запустить вручную"
    echo ""
    echo "Выполните в Terminal.app:"
    echo ""
    echo "java -jar pepk.jar \\"
    echo "  --keystore upload-keystore.jks \\"
    echo "  --alias upload \\"
    echo "  --output android/pepk_out.zip \\"
    echo "  --encryptionkey=$ENCRYPTION_KEY \\"
    echo "  --include-cert"
    echo ""
    echo "Пароли:"
    echo "  Store: $STORE_PASS"
    echo "  Key:   $KEY_PASS"
    exit 1
fi

echo "Используем expect для автоматического ввода паролей..."
echo ""

expect <<EOF
set timeout 60
log_user 1

spawn java -jar "$PEPK_JAR" --keystore "$KEYSTORE" --alias "$ALIAS" --output "$PEPK_OUT" --encryptionkey="$ENCRYPTION_KEY" --include-cert

expect {
    -re "(Enter password for store|Keystore password):.*" {
        send "$STORE_PASS\r"
        exp_continue
    }
    -re "(Enter password for key|Key password):.*" {
        send "$KEY_PASS\r"
        exp_continue
    }
    timeout {
        puts "\nТаймаут ожидания ответа от pepk.jar"
        exit 1
    }
    eof
}

set wait_result [wait]
set exit_code [lindex \$wait_result 3]
exit \$exit_code
EOF

EXIT_CODE=$?

echo ""
if [[ $EXIT_CODE -eq 0 && -f "$PEPK_OUT" ]]; then
    echo "============================================"
    echo "✓ УСПЕШНО!"
    echo "============================================"
    echo ""
    echo "Созданные файлы:"
    ls -lh "$PEPK_OUT"
    ls -lh "$PWD/android/upload-cert.pem"
    echo ""
    echo "Загрузите в RuStore Console:"
    echo "  Шаг 3: android/pepk_out.zip"
    echo "  Шаг 4: android/upload-cert.pem"
    echo ""
else
    echo "============================================"
    echo "✗ ОШИБКА"
    echo "============================================"
    echo ""
    echo "Запустите команду вручную в Terminal.app:"
    echo ""
    echo "java -jar pepk.jar \\"
    echo "  --keystore upload-keystore.jks \\"
    echo "  --alias upload \\"
    echo "  --output android/pepk_out.zip \\"
    echo "  --encryptionkey=$ENCRYPTION_KEY \\"
    echo "  --include-cert"
    echo ""
    echo "Пароли: смотрите android/PRODUCTION_PASSWORDS.txt"
    exit 1
fi
