#!/bin/bash

# Скрипт для создания нового Flutter проекта на основе AI Video Maker

if [ $# -eq 0 ]; then
    echo "Использование: ./create_new_project.sh <имя_нового_проекта>"
    echo "Пример: ./create_new_project.sh MyNewApp"
    exit 1
fi

NEW_PROJECT_NAME=$1
OLD_PROJECT_NAME="AI Video Maker"
TEMPLATE_DIR="/Volumes/External_Storage/Projects/AI Video Maker-template"
NEW_PROJECT_DIR="/Volumes/External_Storage/Projects/$NEW_PROJECT_NAME"

echo "🚀 Создаю новый проект: $NEW_PROJECT_NAME"

# Проверяем существование шаблона
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "❌ Шаблон не найден: $TEMPLATE_DIR"
    echo "Сначала создайте шаблон следуя инструкциям"
    exit 1
fi

# Проверяем, что проект с таким именем не существует
if [ -d "$NEW_PROJECT_DIR" ]; then
    echo "❌ Проект с именем $NEW_PROJECT_NAME уже существует"
    exit 1
fi

# Копируем шаблон
echo "📁 Копирую файлы..."
cp -r "$TEMPLATE_DIR" "$NEW_PROJECT_DIR"

cd "$NEW_PROJECT_DIR"

echo "🔧 Обновляю конфигурацию проекта..."

# Обновляем pubspec.yaml
sed -i '' "s/name: $OLD_PROJECT_NAME/name: $NEW_PROJECT_NAME/g" pubspec.yaml
sed -i '' "s/description: \"A new Flutter project.\"/description: \"$NEW_PROJECT_NAME - Flutter project\"/g" pubspec.yaml
sed -i '' "s/version: [0-9.+]*/version: 1.0.0+1/g" pubspec.yaml

# Обновляем Android
if [ -d "android" ]; then
    # Обновляем package name в android/app/build.gradle
    sed -i '' "s/applicationId \".*\"/applicationId \"com.example.${NEW_PROJECT_NAME,,}\"/g" android/app/build.gradle
    
    # Обновляем AndroidManifest.xml
    find android -name "AndroidManifest.xml" -exec sed -i '' "s/package=\".*\"/package=\"com.example.${NEW_PROJECT_NAME,,}\"/g" {} \;
fi

# Обновляем iOS
if [ -d "ios" ]; then
    # Обновляем Bundle Identifier
    sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = .*;/PRODUCT_BUNDLE_IDENTIFIER = com.example.${NEW_PROJECT_NAME};/g" ios/Runner.xcodeproj/project.pbxproj
    
    # Обновляем Info.plist
    if [ -f "ios/Runner/Info.plist" ]; then
        sed -i '' "s/<string>AI Video Maker<\/string>/<string>$NEW_PROJECT_NAME<\/string>/g" ios/Runner/Info.plist
    fi
fi

# Инициализируем новый Git репозиторий
echo "🔄 Инициализирую Git..."
git init
git add .
git commit -m "Initial commit: Created $NEW_PROJECT_NAME from AI Video Maker template"

# Устанавливаем зависимости
echo "📦 Устанавливаю зависимости..."
flutter pub get

echo "✅ Проект $NEW_PROJECT_NAME успешно создан!"
echo "📂 Расположение: $NEW_PROJECT_DIR"
echo ""
echo "Следующие шаги:"
echo "1. cd $NEW_PROJECT_DIR"
echo "2. code . (или откройте в Cursor)"
echo "3. Обновите иконку приложения в assets/images/app_icon.png"
echo "4. Запустите: flutter pub run flutter_launcher_icons"
echo "5. Протестируйте: flutter run" 