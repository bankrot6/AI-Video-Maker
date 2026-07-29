#!/usr/bin/env node
/**
 * Автоматическое создание ресурсов в Appwrite
 * Читает API ключ из .env файла
 */

import { Client, Databases, Storage } from 'node-appwrite';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

// Загрузка .env
async function loadEnv() {
    const envPath = path.join(PROJECT_ROOT, '.env');
    const envContent = await fs.readFile(envPath, 'utf8');
    const env = {};
    
    envContent.split('\n').forEach(line => {
        const [key, ...valueParts] = line.split('=');
        if (key && valueParts.length > 0) {
            env[key.trim()] = valueParts.join('=').trim();
        }
    });
    
    return env;
}

async function main() {
    console.log('🚀 Автоматическое создание ресурсов Appwrite');
    console.log('=============================================');
    console.log('');

    try {
        // Загрузка переменных
        const env = await loadEnv();
        
        const APPWRITE_ENDPOINT = env.APPWRITE_ENDPOINT || 'http://158.160.254.66/v1';
        const APPWRITE_PROJECT_ID = env.APPWRITE_PROJECT_ID || 'project-default-6a66f25200139fc454e7';
        const APPWRITE_API_KEY = env.APPWRITE_API_KEY;
        
        if (!APPWRITE_API_KEY) {
            console.log('❌ APPWRITE_API_KEY не найден в .env файле!');
            console.log('');
            console.log('Пожалуйста:');
            console.log('1. Создайте API ключ в Appwrite Console');
            console.log('2. Добавьте его в .env файл как APPWRITE_API_KEY=your_key');
            console.log('');
            console.log('📋 Инструкции: cat QUICK_SETUP.md');
            process.exit(1);
        }
        
        console.log('✅ Конфигурация загружена');
        console.log(`   • Endpoint: ${APPWRITE_ENDPOINT}`);
        console.log(`   • Project: ${APPWRITE_PROJECT_ID}`);
        console.log(`   • API Key: ${APPWRITE_API_KEY.substring(0, 10)}...`);
        console.log('');
        
        // Инициализация клиентов
        const client = new Client()
            .setEndpoint(APPWRITE_ENDPOINT)
            .setProject(APPWRITE_PROJECT_ID)
            .setKey(APPWRITE_API_KEY);
        
        const databases = new Databases(client);
        const storage = new Storage(client);
        
        // Проверка подключения
        console.log('🔗 Проверка подключения к Appwrite...');
        await databases.list();
        console.log('✅ Подключение успешно');
        console.log('');
        
        // Создание базы данных
        console.log('📊 Создание базы данных "main"...');
        try {
            await databases.create('main', 'Main Database', true);
            console.log('✅ База данных создана');
        } catch (error) {
            if (error.code === 409) {
                console.log('⚠️  База данных уже существует');
            } else {
                throw error;
            }
        }
        
        // Небольшая пауза для обработки
        await new Promise(resolve => setTimeout(resolve, 1000));
        
        // Создание коллекции presets
        console.log('');
        console.log('📁 Создание коллекции "presets"...');
        try {
            await databases.createCollection(
                'main',
                'presets',
                'Presets Collection',
                ['read("any")', 'write("any")'],
                false
            );
            console.log('✅ Коллекция "presets" создана');
            
            console.log('  ⚙️ Добавление атрибутов...');
            
            // Атрибуты для presets
            await databases.createStringAttribute('main', 'presets', 'name', 255, true);
            await new Promise(resolve => setTimeout(resolve, 500));
            
            await databases.createStringAttribute('main', 'presets', 'prompt', 2000, true);
            await new Promise(resolve => setTimeout(resolve, 500));
            
            await databases.createStringAttribute('main', 'presets', 'tags', 1000, false, null, true);
            await new Promise(resolve => setTimeout(resolve, 500));
            
            console.log('  ✅ Атрибуты добавлены');
            
        } catch (error) {
            if (error.code === 409) {
                console.log('⚠️  Коллекция "presets" уже существует');
            } else {
                throw error;
            }
        }
        
        // Создание коллекции user_generations
        console.log('');
        console.log('📁 Создание коллекции "user_generations"...');
        try {
            await databases.createCollection(
                'main',
                'user_generations',
                'User Generations Collection',
                ['read("any")', 'write("any")'],
                false
            );
            console.log('✅ Коллекция "user_generations" создана');
            
            console.log('  ⚙️ Добавление атрибутов...');
            
            // Атрибуты для user_generations
            await databases.createStringAttribute('main', 'user_generations', 'userId', 255, true);
            await new Promise(resolve => setTimeout(resolve, 500));
            
            await databases.createStringAttribute('main', 'user_generations', 'prompt', 2000, true);
            await new Promise(resolve => setTimeout(resolve, 500));
            
            await databases.createStringAttribute('main', 'user_generations', 'imageUrl', 500, true);
            await new Promise(resolve => setTimeout(resolve, 500));
            
            await databases.createDatetimeAttribute('main', 'user_generations', 'createdAt', true);
            await new Promise(resolve => setTimeout(resolve, 500));
            
            console.log('  ✅ Атрибуты добавлены');
            
        } catch (error) {
            if (error.code === 409) {
                console.log('⚠️  Коллекция "user_generations" уже существует');
            } else {
                throw error;
            }
        }
        
        // Создание storage bucket
        console.log('');
        console.log('💾 Создание Storage bucket "user-photos"...');
        try {
            await storage.createBucket(
                'user-photos',
                'User Photos Bucket',
                ['read("any")', 'write("any")'],
                false,
                true,
                10485760, // 10MB
                ['jpg', 'jpeg', 'png', 'webp'],
                'gzip',
                false,
                false
            );
            console.log('✅ Storage bucket создан');
        } catch (error) {
            if (error.code === 409) {
                console.log('⚠️  Storage bucket уже существует');
            } else {
                throw error;
            }
        }
        
        console.log('');
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log('🎉 ВСЕ РЕСУРСЫ СОЗДАНЫ УСПЕШНО!');
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log('');
        console.log('📋 Созданные ресурсы:');
        console.log('   ✅ Database: main');
        console.log('   ✅ Collection: presets (name, prompt, tags[])');
        console.log('   ✅ Collection: user_generations (userId, prompt, imageUrl, createdAt)');
        console.log('   ✅ Storage: user-photos (10MB max, jpg/png/webp)');
        console.log('');
        console.log('🚀 ГОТОВ К МИГРАЦИИ!');
        console.log('');
        console.log('Запустите миграцию:');
        console.log('   ./scripts/migrate_presets.sh migrate');
        console.log('');
        
    } catch (error) {
        console.error('');
        console.error('💥 ОШИБКА:', error.message);
        
        if (error.code === 401) {
            console.error('');
            console.error('🔑 Проблема с API ключом:');
            console.error('   • Проверьте правильность APPWRITE_API_KEY в .env');
            console.error('   • Убедитесь что у ключа есть все необходимые права');
            console.error('   • Создайте новый ключ если нужно');
        }
        
        process.exit(1);
    }
}

main().catch(console.error);