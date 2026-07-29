#!/bin/bash

echo "🚀 Начало сборки IPA для AI Video Maker"

# Проверяем, что мы находимся в правильной директории
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Ошибка: pubspec.yaml не найден. Убедитесь, что вы находитесь в корне Flutter проекта."
    exit 1
fi

echo "📱 Очистка предыдущих сборок..."
flutter clean

echo "📦 Получение зависимостей..."
flutter pub get

echo "🔨 Сборка iOS приложения в релизном режиме..."

# Попытка 1: Используем стандартную команду flutter build ipa
echo "📱 Попытка 1: Стандартная сборка IPA..."
flutter build ipa --release --no-codesign

if [ $? -eq 0 ]; then
    echo "✅ Стандартная сборка IPA успешна"
    if [ -f "build/ios/ipa/AI Video Maker.ipa" ]; then
        cp build/ios/ipa/AI Video Maker.ipa ./AI Video Maker.ipa
        echo "✅ IPA файл скопирован: AI Video Maker.ipa"
        echo "📍 Расположение: $(pwd)/AI Video Maker.ipa"
        echo "📊 Размер файла: $(du -h AI Video Maker.ipa | cut -f1)"
        echo "🎉 Сборка завершена успешно!"
        exit 0
    fi
fi

echo "📱 Попытка 2: Сборка через iOS..."
flutter build ios --release --no-codesign

if [ $? -eq 0 ]; then
    echo "✅ iOS сборка успешна"
    
    # Проверяем, что .app файл создан
    if [ -d "build/ios/iphoneos/Runner.app" ]; then
        echo "📦 Создание IPA архива вручную..."
        
        # Создаем директорию для Payload
        rm -rf build/ios/ipa
        mkdir -p build/ios/ipa/Payload
        
        # Копируем .app файл в Payload
        cp -r build/ios/iphoneos/Runner.app build/ios/ipa/Payload/
        
        # Создаем zip архив и переименовываем в .ipa
        cd build/ios/ipa
        zip -r ../../../AI Video Maker.ipa Payload/
        cd ../../../
        
        echo "✅ IPA файл создан: AI Video Maker.ipa"
        echo "📍 Расположение: $(pwd)/AI Video Maker.ipa"
        
        # Показываем информацию о файле
        if [ -f "AI Video Maker.ipa" ]; then
            echo "📊 Размер файла: $(du -h AI Video Maker.ipa | cut -f1)"
            echo "🎉 Сборка завершена успешно!"
        else
            echo "❌ Ошибка: IPA файл не был создан"
            exit 1
        fi
    else
        echo "❌ Ошибка: Runner.app не найден в build/ios/iphoneos/"
        exit 1
    fi
else
    echo "❌ Ошибка сборки iOS"
    
    echo "📱 Попытка 3: Сборка через Xcode..."
    
    # Попытка использовать xcodebuild напрямую
    cd ios
    xcodebuild -workspace Runner.xcworkspace -scheme Runner -configuration Release -archivePath build/Runner.xcarchive archive
    
    if [ $? -eq 0 ]; then
        echo "✅ Xcode archive создан"
        
        # Экспортируем IPA из архива
        xcodebuild -exportArchive -archivePath build/Runner.xcarchive -exportPath build/ipa -exportOptionsPlist ../ios/exportOptions.plist
        
        if [ $? -eq 0 ] && [ -f "build/ipa/Runner.ipa" ]; then
            cp build/ipa/Runner.ipa ../AI Video Maker.ipa
            cd ..
            echo "✅ IPA файл создан через Xcode: AI Video Maker.ipa"
            echo "📍 Расположение: $(pwd)/AI Video Maker.ipa"
            echo "📊 Размер файла: $(du -h AI Video Maker.ipa | cut -f1)"
            echo "🎉 Сборка завершена успешно!"
        else
            cd ..
            echo "❌ Ошибка экспорта IPA из архива"
            exit 1
        fi
    else
        cd ..
        echo "❌ Все попытки сборки неудачны"
        echo "💡 Рекомендации:"
        echo "  1. Установите Xcode из App Store"
        echo "  2. Выполните: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
        echo "  3. Выполните: sudo xcodebuild -runFirstLaunch"
        exit 1
    fi
fi 