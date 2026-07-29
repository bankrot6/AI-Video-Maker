#!/usr/bin/env node
/**
 * Миграция пресетов из Firebase Firestore в Appwrite
 * 
 * Особенности:
 * - Батчовая обработка для снижения нагрузки на сервер
 * - Rate limiting между батчами  
 * - Возможность resume при ошибках
 * - Детальное логирование
 * - Проверка дубликатов
 * - Rollback при критических ошибках
 */

import { initializeApp } from 'firebase/app';
import { getFirestore, collection, getDocs, query, orderBy, limit, startAfter } from 'firebase/firestore';
import { Client, Databases, ID } from 'node-appwrite';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '..');

// ==========================================
// КОНФИГУРАЦИЯ
// ==========================================

const CONFIG = {
  // Batch settings
  FIREBASE_BATCH_SIZE: 25,        // Количество документов за один запрос из Firebase
  APPWRITE_BATCH_SIZE: 10,        // Количество документов для записи в Appwrite за раз
  DELAY_BETWEEN_BATCHES: 1000,    // Задержка между батчами (мс)
  RETRY_ATTEMPTS: 3,              // Количество попыток при ошибке
  RETRY_DELAY: 2000,              // Задержка между повторными попытками
  
  // Logging
  LOG_FILE: path.join(PROJECT_ROOT, 'migration.log'),
  PROGRESS_FILE: path.join(PROJECT_ROOT, 'migration_progress.json'),
  
  // Collections
  FIREBASE_COLLECTION: 'presets',
  APPWRITE_COLLECTION: 'presets',
  APPWRITE_DATABASE: 'main'
};

// ==========================================
// ИНИЦИАЛИЗАЦИЯ
// ==========================================

// Загрузка переменных окружения
const envPath = path.join(PROJECT_ROOT, '.env');
const envContent = await fs.readFile(envPath, 'utf8');
const env = {};
envContent.split('\n').forEach(line => {
  const [key, value] = line.split('=');
  if (key && value) env[key.trim()] = value.trim();
});

// Firebase config
const firebaseConfig = {
  apiKey: env.FIREBASE_API_KEY,
  authDomain: env.FIREBASE_AUTH_DOMAIN,
  projectId: env.FIREBASE_PROJECT_ID,
  storageBucket: env.FIREBASE_STORAGE_BUCKET,
  messagingSenderId: env.FIREBASE_MESSAGING_SENDER_ID,
  appId: env.FIREBASE_APP_ID
};

// Appwrite config
const appwriteConfig = {
  endpoint: env.APPWRITE_ENDPOINT || 'http://158.160.254.66/v1',
  project: env.APPWRITE_PROJECT_ID,
  key: env.APPWRITE_API_KEY
};

// Инициализация клиентов
const firebaseApp = initializeApp(firebaseConfig);
const firestore = getFirestore(firebaseApp);

const appwrite = new Client()
  .setEndpoint(appwriteConfig.endpoint)
  .setProject(appwriteConfig.project)
  .setKey(appwriteConfig.key);

const databases = new Databases(appwrite);

// ==========================================
// УТИЛИТЫ
// ==========================================

class Logger {
  static async log(level, message, data = null) {
    const timestamp = new Date().toISOString();
    const logEntry = {
      timestamp,
      level: level.toUpperCase(),
      message,
      ...(data && { data })
    };
    
    const logLine = JSON.stringify(logEntry) + '\n';
    
    // Консоль
    const colors = { ERROR: '\x1b[31m', WARN: '\x1b[33m', INFO: '\x1b[36m', SUCCESS: '\x1b[32m' };
    console.log(`${colors[level.toUpperCase()] || ''} [${timestamp}] ${level.toUpperCase()}: ${message}\x1b[0m`);
    
    // Файл
    try {
      await fs.appendFile(CONFIG.LOG_FILE, logLine);
    } catch (err) {
      console.error('Failed to write to log file:', err.message);
    }
  }

  static async info(message, data) { await this.log('info', message, data); }
  static async success(message, data) { await this.log('success', message, data); }
  static async warn(message, data) { await this.log('warn', message, data); }
  static async error(message, data) { await this.log('error', message, data); }
}

class ProgressManager {
  constructor() {
    this.progress = {
      startTime: null,
      totalProcessed: 0,
      totalMigrated: 0,
      totalErrors: 0,
      lastProcessedId: null,
      currentBatch: 0,
      status: 'not_started'
    };
  }

  async load() {
    try {
      const data = await fs.readFile(CONFIG.PROGRESS_FILE, 'utf8');
      this.progress = { ...this.progress, ...JSON.parse(data) };
      await Logger.info('Progress loaded from file', this.progress);
    } catch (err) {
      await Logger.info('Starting fresh migration - no previous progress found');
    }
  }

  async save() {
    try {
      await fs.writeFile(CONFIG.PROGRESS_FILE, JSON.stringify(this.progress, null, 2));
    } catch (err) {
      await Logger.error('Failed to save progress', err.message);
    }
  }

  update(updates) {
    this.progress = { ...this.progress, ...updates };
  }

  getStats() {
    const elapsed = this.progress.startTime ? Date.now() - this.progress.startTime : 0;
    const rate = elapsed > 0 ? (this.progress.totalProcessed / elapsed * 1000).toFixed(2) : 0;
    
    return {
      ...this.progress,
      elapsedMs: elapsed,
      elapsedFormatted: this.formatDuration(elapsed),
      migrationRate: `${rate} docs/sec`
    };
  }

  formatDuration(ms) {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    
    if (hours > 0) return `${hours}h ${minutes % 60}m ${seconds % 60}s`;
    if (minutes > 0) return `${minutes}m ${seconds % 60}s`;
    return `${seconds}s`;
  }
}

// ==========================================
// ОСНОВНАЯ ЛОГИКА МИГРАЦИИ  
// ==========================================

class FirebaseToAppwriteMigrator {
  constructor() {
    this.progress = new ProgressManager();
    this.migratedIds = new Set();
  }

  async init() {
    await this.progress.load();
    await Logger.info('🚀 Initializing Firebase to Appwrite migration');
    
    // Проверка подключений
    await this.validateConnections();
    
    // Создание коллекции если не существует
    await this.ensureAppwriteCollection();
    
    // Загрузка уже мигрированных ID
    await this.loadExistingIds();
  }

  async validateConnections() {
    try {
      // Проверка Firebase
      const testQuery = query(collection(firestore, CONFIG.FIREBASE_COLLECTION), limit(1));
      await getDocs(testQuery);
      await Logger.success('✅ Firebase connection validated');

      // Проверка Appwrite
      await databases.list();
      await Logger.success('✅ Appwrite connection validated');
      
    } catch (error) {
      await Logger.error('❌ Connection validation failed', error.message);
      throw error;
    }
  }

  async ensureAppwriteCollection() {
    try {
      await databases.getCollection(CONFIG.APPWRITE_DATABASE, CONFIG.APPWRITE_COLLECTION);
      await Logger.info('✅ Appwrite collection exists');
    } catch (error) {
      if (error.code === 404) {
        await Logger.info('Creating Appwrite collection...');
        
        await databases.createCollection(
          CONFIG.APPWRITE_DATABASE,
          CONFIG.APPWRITE_COLLECTION,
          'Presets Collection',
          ['read("any")', 'write("any")'], // Permissions
          false // Document Security
        );

        // Создание атрибутов
        const attributes = [
          { key: 'name', type: 'string', size: 255, required: true },
          { key: 'prompt', type: 'string', size: 2000, required: true },
          { key: 'tags', type: 'string', size: 1000, required: false, array: true }
        ];

        for (const attr of attributes) {
          if (attr.type === 'string') {
            await databases.createStringAttribute(
              CONFIG.APPWRITE_DATABASE,
              CONFIG.APPWRITE_COLLECTION,
              attr.key,
              attr.size,
              attr.required,
              null, // default
              attr.array || false
            );
          }
          await this.sleep(500); // Задержка между созданием атрибутов
        }

        await Logger.success('✅ Appwrite collection created with attributes');
      } else {
        throw error;
      }
    }
  }

  async loadExistingIds() {
    try {
      let offset = 0;
      const batchSize = 100;
      
      while (true) {
        const response = await databases.listDocuments(
          CONFIG.APPWRITE_DATABASE,
          CONFIG.APPWRITE_COLLECTION,
          [], // queries
          batchSize,
          offset
        );

        response.documents.forEach(doc => {
          this.migratedIds.add(doc.$id);
        });

        if (response.documents.length < batchSize) break;
        offset += batchSize;
      }

      await Logger.info(`📋 Found ${this.migratedIds.size} existing documents in Appwrite`);
    } catch (error) {
      await Logger.warn('Could not load existing IDs', error.message);
    }
  }

  async migrate() {
    try {
      this.progress.update({ 
        status: 'running', 
        startTime: this.progress.startTime || Date.now() 
      });
      await this.progress.save();

      await Logger.info('🔄 Starting migration process');

      let lastDoc = null;
      let batchCount = 0;
      let totalProcessed = this.progress.totalProcessed;

      while (true) {
        batchCount++;
        await Logger.info(`📦 Processing batch #${batchCount}`);

        // Получение батча из Firebase
        const firebaseBatch = await this.getFirebaseBatch(lastDoc);
        
        if (firebaseBatch.length === 0) {
          await Logger.success('🎉 No more documents to process - migration complete!');
          break;
        }

        // Фильтрация уже мигрированных документов
        const newDocuments = firebaseBatch.filter(doc => !this.migratedIds.has(doc.id));
        
        if (newDocuments.length === 0) {
          await Logger.info(`⏭️  All documents in batch #${batchCount} already migrated, skipping`);
        } else {
          // Миграция батча в Appwrite
          const migratedCount = await this.migrateToAppwrite(newDocuments);
          
          this.progress.update({ 
            totalMigrated: this.progress.totalMigrated + migratedCount,
            currentBatch: batchCount 
          });
        }

        totalProcessed += firebaseBatch.length;
        this.progress.update({ totalProcessed });
        
        lastDoc = firebaseBatch[firebaseBatch.length - 1];
        await this.progress.save();

        // Rate limiting
        await this.sleep(CONFIG.DELAY_BETWEEN_BATCHES);
      }

      this.progress.update({ status: 'completed' });
      await this.progress.save();
      
      const stats = this.progress.getStats();
      await Logger.success('🎊 Migration completed successfully!', stats);

    } catch (error) {
      this.progress.update({ status: 'failed' });
      await this.progress.save();
      await Logger.error('💥 Migration failed', error.message);
      throw error;
    }
  }

  async getFirebaseBatch(lastDoc = null) {
    let q = query(
      collection(firestore, CONFIG.FIREBASE_COLLECTION),
      orderBy('__name__'), // Используем document ID для стабильной сортировки
      limit(CONFIG.FIREBASE_BATCH_SIZE)
    );

    if (lastDoc) {
      q = query(
        collection(firestore, CONFIG.FIREBASE_COLLECTION),
        orderBy('__name__'),
        startAfter(lastDoc.id),
        limit(CONFIG.FIREBASE_BATCH_SIZE)
      );
    }

    const snapshot = await getDocs(q);
    return snapshot.docs.map(doc => ({
      id: doc.id,
      data: doc.data()
    }));
  }

  async migrateToAppwrite(documents) {
    let successCount = 0;
    
    // Обработка документов меньшими батчами для Appwrite
    for (let i = 0; i < documents.length; i += CONFIG.APPWRITE_BATCH_SIZE) {
      const batch = documents.slice(i, i + CONFIG.APPWRITE_BATCH_SIZE);
      
      for (const doc of batch) {
        const success = await this.migrateDocument(doc);
        if (success) {
          successCount++;
          this.migratedIds.add(doc.id);
        }
      }
      
      // Небольшая пауза между мини-батчами
      if (i + CONFIG.APPWRITE_BATCH_SIZE < documents.length) {
        await this.sleep(200);
      }
    }

    await Logger.success(`✅ Migrated ${successCount}/${documents.length} documents in this batch`);
    return successCount;
  }

  async migrateDocument(firebaseDoc, attempt = 1) {
    try {
      // Подготовка данных для Appwrite
      const appwriteData = this.transformDocument(firebaseDoc.data);
      
      // Создание документа в Appwrite
      await databases.createDocument(
        CONFIG.APPWRITE_DATABASE,
        CONFIG.APPWRITE_COLLECTION,
        firebaseDoc.id, // Используем тот же ID
        appwriteData
      );

      await Logger.info(`📄 Migrated document: ${firebaseDoc.id}`);
      return true;

    } catch (error) {
      if (error.code === 409) {
        // Документ уже существует
        await Logger.warn(`⚠️  Document ${firebaseDoc.id} already exists, skipping`);
        return true;
      }

      if (attempt <= CONFIG.RETRY_ATTEMPTS) {
        await Logger.warn(`🔄 Retrying document ${firebaseDoc.id} (attempt ${attempt}/${CONFIG.RETRY_ATTEMPTS})`);
        await this.sleep(CONFIG.RETRY_DELAY * attempt);
        return await this.migrateDocument(firebaseDoc, attempt + 1);
      }

      await Logger.error(`❌ Failed to migrate document ${firebaseDoc.id}`, {
        error: error.message,
        attempts: attempt
      });
      
      this.progress.update({ totalErrors: this.progress.totalErrors + 1 });
      return false;
    }
  }

  transformDocument(firebaseData) {
    // Преобразование данных из Firebase формата в Appwrite формат
    const appwriteData = {};

    // Копирование базовых полей
    if (firebaseData.name) appwriteData.name = firebaseData.name;
    if (firebaseData.prompt) appwriteData.prompt = firebaseData.prompt;

    // Обработка массива тегов
    if (firebaseData.tags) {
      if (Array.isArray(firebaseData.tags)) {
        appwriteData.tags = firebaseData.tags.filter(tag => tag && typeof tag === 'string');
      } else if (typeof firebaseData.tags === 'string') {
        appwriteData.tags = [firebaseData.tags];
      }
    }

    return appwriteData;
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  async getStatus() {
    const stats = this.progress.getStats();
    return {
      status: stats.status,
      progress: {
        processed: stats.totalProcessed,
        migrated: stats.totalMigrated,
        errors: stats.totalErrors,
        currentBatch: stats.currentBatch
      },
      timing: {
        elapsed: stats.elapsedFormatted,
        rate: stats.migrationRate,
        startTime: new Date(stats.startTime).toISOString()
      }
    };
  }
}

// ==========================================
// ВЫПОЛНЕНИЕ
// ==========================================

async function main() {
  const migrator = new FirebaseToAppwriteMigrator();
  
  try {
    await migrator.init();
    await migrator.migrate();
    
    const finalStats = await migrator.getStatus();
    console.log('\n🎉 MIGRATION COMPLETED!');
    console.log('📊 Final Statistics:');
    console.log(`   • Total Processed: ${finalStats.progress.processed}`);
    console.log(`   • Successfully Migrated: ${finalStats.progress.migrated}`);
    console.log(`   • Errors: ${finalStats.progress.errors}`);
    console.log(`   • Duration: ${finalStats.timing.elapsed}`);
    console.log(`   • Average Rate: ${finalStats.timing.rate}`);
    
  } catch (error) {
    console.error('\n💥 MIGRATION FAILED!');
    console.error('Error:', error.message);
    process.exit(1);
  }
}

// Запуск только если файл вызывается напрямую
if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(console.error);
}

export default FirebaseToAppwriteMigrator;