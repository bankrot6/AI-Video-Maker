#!/bin/bash

# Скрипт для тестирования интеграции RuStore
# Автор: AI Video Maker Team

echo "🏪 Тестирование интеграции RuStore"
echo "=================================="

# Проверка окружения
echo "1. Проверка окружения..."

if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter не найден. Установите Flutter SDK."
    exit 1
fi

if ! command -v adb &> /dev/null; then
    echo "❌ ADB не найден. Установите Android SDK."
    exit 1
fi

echo "✅ Flutter и ADB найдены"

# Проверка подключенных устройств
echo "2. Проверка подключенных устройств..."
DEVICES=$(adb devices | grep -v "List of devices" | grep -v "^$" | wc -l)

if [ $DEVICES -eq 0 ]; then
    echo "❌ Нет подключенных устройств. Подключите Android устройство."
    exit 1
fi

echo "✅ Найдено $DEVICES устройств"

# Сборка debug APK
echo "3. Сборка debug APK..."
flutter build apk --debug

if [ $? -ne 0 ]; then
    echo "❌ Ошибка при сборке APK"
    exit 1
fi

echo "✅ Debug APK собран успешно"

# Установка APK на устройство
echo "4. Установка APK на устройство..."
APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"

if [ ! -f "$APK_PATH" ]; then
    echo "❌ APK файл не найден: $APK_PATH"
    exit 1
fi

adb install -r "$APK_PATH"

if [ $? -ne 0 ]; then
    echo "❌ Ошибка при установке APK"
    exit 1
fi

echo "✅ APK установлен успешно"

# Запуск приложения
echo "5. Запуск приложения..."
PACKAGE_NAME="com.nomadvoice.app"
adb shell am start -n "$PACKAGE_NAME/com.nomadvoice.app.MainActivity"

if [ $? -ne 0 ]; then
    echo "❌ Ошибка при запуске приложения"
    exit 1
fi

echo "✅ Приложение запущено"

# Инструкции для тестирования
echo ""
echo "📋 Инструкции для тестирования:"
echo "1. Откройте Настройки в приложении"
echo "2. Найдите 'Диагностика платежей' (только в debug режиме)"
echo "3. Проверьте следующие параметры:"
echo "   - Источник установки должен быть 'Local Source' (для sideload)"
echo "   - Активный провайдер должен быть 'standard'"
echo "4. Нажмите 'Тест RuStore' для принудительного тестирования"
echo "5. Перейдите на экран подписки и попробуйте купить"
echo "6. Проверьте логи в консоли"

echo ""
echo "🔍 Для просмотра логов в реальном времени:"
echo "adb logcat | grep -E '(PAYWALL|PAYMENT_PROVIDER|RUSTORE_BILLING|STORE_DETECTION)'"

echo ""
echo "🏪 Тестирование завершено!" 