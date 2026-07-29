#!/bin/bash
# Автоматический экспорт DEMO ключа для RuStore с использованием expect
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

if ! command -v expect &> /dev/null; then
    echo "ОШИБКА: expect не установлен."
    echo "Установите: brew install expect"
    echo ""
    echo "ИЛИ запустите вручную:"
    echo "java -jar pepk.jar \\"
    echo "  --keystore \"$KEYSTORE\" \\"
    echo "  --alias \"$ALIAS\" \\"
    echo "  --output \"$OUT_ZIP\" \\"
    echo "  --encryptionkey=\"$ENCRYPTION_KEY\" \\"
    echo "  --include-cert"
    echo ""
    echo "Пароли:"
    echo "  Store password: $STORE_PASS"
    echo "  Key password: $KEY_PASS"
    exit 1
fi

expect <<EOF
set timeout 60
spawn java -jar "$PEPK_JAR" --keystore "$KEYSTORE" --alias "$ALIAS" --output "$OUT_ZIP" --encryptionkey="$ENCRYPTION_KEY" --include-cert

expect {
    "Enter password for store*" {
        send "$STORE_PASS\r"
        exp_continue
    }
    "Enter password for key*" {
        send "$KEY_PASS\r"
        exp_continue
    }
    eof
}

wait
EOF

if [[ -f "$OUT_ZIP" ]]; then
    echo ""
    echo "✓ Успешно создан: $OUT_ZIP"
    ls -lh "$OUT_ZIP"
else
    echo ""
    echo "ОШИБКА: Файл не создан"
    exit 1
fi

echo ""
echo "=========================================="
echo "ВАЖНО: Это DEMO ключ!"
echo "=========================================="
echo "Для production используйте ваш РЕАЛЬНЫЙ keystore"
echo "из которого собирался app-release.aab"
