import { Client, Databases } from 'node-appwrite';
import { Query } from 'node-appwrite';

const ENDPOINT      = process.env.APPWRITE_ENDPOINT              ?? '';
const PROJECT_ID    = process.env.APPWRITE_PROJECT_ID            ?? '';
const API_KEY       = process.env.APPWRITE_API_KEY               ?? '';
const DATABASE_ID   = process.env.APPWRITE_DATABASE_ID           ?? 'main';
const PRESETS_COLL  = process.env.APPWRITE_PRESETS_COLLECTION_ID ?? 'presets';
const EARNINGS_COLL = process.env.APPWRITE_EARNINGS_COLLECTION_ID ?? 'preset_earnings';

const MIN_LIKES_THRESHOLD  = 3;
const MAX_CREDITS_PER_PRESET = 50;
const CREDITS_PER_LIKE     = 1;

function makeClient() {
  return new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
}

export default async ({ req, res, log, error }) => {
  let doc;
  try {
    doc = req.bodyJson ?? (typeof req.body === 'string' ? JSON.parse(req.body) : req.body);
  } catch {
    error('Invalid JSON body');
    return res.json({ ok: false, message: 'Invalid JSON body' }, 400);
  }

  const presetId = doc?.$id;
  const ownerId  = doc?.ownerId;
  const isPublic = doc?.isPublic;
  const newLikes = Number(doc?.likesCount ?? 0);

  if (!presetId || !ownerId || !isPublic) {
    log(`Skipping ${presetId}: not a public preset with owner`);
    return res.json({ ok: false, message: 'No ownerId or not public' });
  }

  if (newLikes < MIN_LIKES_THRESHOLD) {
    log(`Skipping ${presetId}: ${newLikes} likes < ${MIN_LIKES_THRESHOLD} minimum`);
    return res.json({ ok: false, message: 'Below minimum likes threshold' });
  }

  const client    = makeClient();
  const databases = new Databases(client);

  let creditsEarned    = 0;
  let lastProcessedLikes = 0;
  let earningsExists   = false;
  let createdAt        = new Date().toISOString();

  try {
    const earningsDoc = await databases.getDocument(DATABASE_ID, EARNINGS_COLL, presetId);
    creditsEarned      = Number(earningsDoc.creditsEarned    ?? 0);
    lastProcessedLikes = Number(earningsDoc.lastProcessedLikes ?? 0);
    createdAt          = earningsDoc.createdAt ?? createdAt;
    earningsExists     = true;
  } catch {
    earningsExists = false;
  }

  if (creditsEarned >= MAX_CREDITS_PER_PRESET) {
    log(`Skipping ${presetId}: max credits reached (${creditsEarned})`);
    return res.json({ ok: false, message: 'Max credits reached' });
  }

  const delta = newLikes - lastProcessedLikes;
  if (delta <= 0) {
    log(`Skipping ${presetId}: no new likes (delta=${delta})`);
    return res.json({ ok: false, message: 'No new likes' });
  }

  let newCredits = delta * CREDITS_PER_LIKE;
  if (creditsEarned + newCredits > MAX_CREDITS_PER_PRESET) {
    newCredits = Math.max(0, MAX_CREDITS_PER_PRESET - creditsEarned);
  }
  if (newCredits === 0) {
    return res.json({ ok: false, message: 'No credits to award' });
  }

  const earningsData = {
    presetId,
    ownerId,
    totalLikes:         newLikes,
    creditsEarned:      creditsEarned + newCredits,
    lastProcessedLikes: newLikes,
    lastProcessedAt:    new Date().toISOString(),
    createdAt,
  };

  try {
    if (earningsExists) {
      await databases.updateDocument(DATABASE_ID, EARNINGS_COLL, presetId, earningsData);
    } else {
      await databases.createDocument(DATABASE_ID, EARNINGS_COLL, presetId, earningsData, ['read("any")']);
    }
    log(`Rewarded: preset ${presetId} +${newCredits} credits (total ${creditsEarned + newCredits}, likes ${newLikes})`);
    return res.json({ ok: true, creditsAwarded: newCredits });
  } catch (err) {
    error(`Failed to write earnings for ${presetId}: ${err.message}`);
    return res.json({ ok: false, error: err.message }, 500);
  }
};
