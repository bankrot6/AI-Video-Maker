#!/bin/bash

# Скрипт для сборки Android App Bundle (AAB) с использованием Flutter
# Автоматически собирает релизную версию для Google Play

echo "====== Начало сборки Android App Bundle (AAB) ======"

# Очистка предыдущих сборок
echo "🧹 Очистка предыдущих сборок..."
flutter clean

# Получение зависимостей
echo "📦 Получение зависимостей..."
flutter pub get

# Сборка AAB файла
echo "🔨 Сборка AAB файла..."
flutter build appbundle --release

if [ $? -eq 0 ]; then
    AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
    
    echo "✅ Сборка успешно завершена!"
    echo "📱 AAB файл создан: $AAB_PATH"
    echo "📋 Информация о размере:"
    ls -lh $AAB_PATH
    
    # Открываем директорию с собранным файлом
    echo "🔍 Открытие директории с файлом..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        open build/app/outputs/bundle/release/
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        xdg-open build/app/outputs/bundle/release/
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        # Windows
        start build/app/outputs/bundle/release/
    fi
    
    echo "====== Сборка завершена ======"
else
    echo "❌ Ошибка при сборке AAB файла"
    echo "====== Сборка не удалась ======"
    exit 1
fi 