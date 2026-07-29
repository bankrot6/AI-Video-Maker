#!/bin/bash
set -e

echo "=========================================="
echo "ВНИМАНИЕ: ДЕМОНСТРАЦИОННЫЙ СКРИПТ"
echo "=========================================="
echo ""
echo "ЭТОТ СКРИПТ СОЗДАЁТ ТЕСТОВЫЙ KEYSTORE"
echo "НЕ ИСПОЛЬЗУЙТЕ ЕГО ДЛЯ PRODUCTION ПРИЛОЖЕНИЙ!"
echo ""
echo "Если у вас уже есть keystore для приложения"
echo "в production, НЕ ЗАМЕНЯЙТЕ его этим тестовым."
echo ""
read -p "Продолжить создание DEMO keystore? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Отменено."
    exit 0
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/.."

echo ""
echo "1. Генерация случайных паролей..."
STORE_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)
KEY_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)

echo "2. Создание key.properties..."
cat > "$SCRIPT_DIR/key.properties" <<EOF
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=upload
storeFile=../upload-keystore-DEMO.jks
EOF

echo "3. Создание .pepk_encryption_key (RuStore encryption key)..."
cat > "$SCRIPT_DIR/.pepk_encryption_key" <<'EOF'
000087b97df54de973a38193a23d61553c6f52cfe12bc4703b424aa514157443618a9b8c148176f7916f261dae02efd3a3250fc7ee92a482423674af00dbac25df9575c0
EOF

echo "4. Генерация DEMO keystore (это может занять минуту)..."
keytool -genkeypair -v \
  -keystore "upload-keystore-DEMO.jks" \
  -storetype JKS \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=Demo AI Video Maker, OU=Mobile Development, O=AI Video Maker Demo, L=Moscow, ST=Moscow, C=RU"

echo ""
echo "=========================================="
echo "ГОТОВО! Созданные файлы:"
echo "=========================================="
echo "✓ android/key.properties"
echo "✓ android/.pepk_encryption_key"
echo "✓ upload-keystore-DEMO.jks"
echo ""
echo "Теперь можно запустить:"
echo "  cd android && ./export_pepk_for_store.sh"
echo ""
echo "=========================================="
echo "ДЛЯ PRODUCTION:"
echo "=========================================="
echo "1. Найдите ваш НАСТОЯЩИЙ keystore"
echo "   (тот который использовался для сборки app-release.aab)"
echo ""
echo "2. Обновите android/key.properties с реальными данными:"
echo "   - storePassword (настоящий пароль keystore)"
echo "   - keyPassword (настоящий пароль ключа)"
echo "   - keyAlias (имя ключа в keystore)"
echo "   - storeFile (путь к РЕАЛЬНОМУ keystore)"
echo ""
echo "3. Только ПОТОМ запускайте export_pepk_for_store.sh"
echo "=========================================="
