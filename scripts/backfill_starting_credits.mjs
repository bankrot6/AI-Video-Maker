#!/usr/bin/env node
import { Client, Databases, Query } from 'node-appwrite';
import { config } from 'dotenv';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));
config({ path: join(__dirname, '..', '.env') });
config({ path: join(__dirname, '..', '.env.local') });

const ENDPOINT = process.env.APPWRITE_ENDPOINT;
const PROJECT_ID = process.env.APPWRITE_PROJECT_ID;
const API_KEY = process.env.APPWRITE_API_KEY;
const DATABASE_ID = process.env.APPWRITE_DATABASE_ID || 'main';
const COLLECTION_ID = 'device_registry';
const FREE_STARTING_CREDITS = 10;

if (!ENDPOINT || !PROJECT_ID || !API_KEY) {
  console.error('Missing APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, or APPWRITE_API_KEY');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const db = new Databases(client);

async function run() {
  console.log('Backfilling currentBalance for devices with 0 balance and no purchases...');
  console.log('FREE_STARTING_CREDITS:', FREE_STARTING_CREDITS);
  
  let offset = 0;
  const limit = 100;
  let totalUpdated = 0;
  
  while (true) {
    const result = await db.listDocuments(DATABASE_ID, COLLECTION_ID, [
      Query.limit(limit),
      Query.offset(offset),
    ]);
    
    if (result.documents.length === 0) break;
    
    for (const doc of result.documents) {
      const balance = doc.currentBalance ?? 0;
      const purchased = doc.purchasedCredits ?? 0;
      const earned = doc.earnedCredits ?? 0;
      
      // Only update if: balance is less than starting credits AND no purchased/earned
      if (balance < FREE_STARTING_CREDITS && purchased === 0 && earned === 0) {
        const fp = doc.fingerprint?.slice(0, 8) || 'unknown';
        console.log(`Updating ${fp}... balance: ${balance} -> ${FREE_STARTING_CREDITS}`);
        
        await db.updateDocument(DATABASE_ID, COLLECTION_ID, doc.$id, {
          currentBalance: FREE_STARTING_CREDITS,
        });
        totalUpdated++;
      }
    }
    
    offset += limit;
    if (result.documents.length < limit) break;
  }
  
  console.log(`\nDone! Updated ${totalUpdated} devices.`);
}

run().catch(e => {
  console.error('Error:', e.message);
  process.exit(1);
});
