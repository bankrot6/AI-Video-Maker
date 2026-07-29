import { Client, Databases, Query, ID } from 'node-appwrite';
import { createHash } from 'node:crypto';

const DATABASE_ID       = process.env.APPWRITE_DATABASE_ID ?? 'main';
const TRIAL_COLLECTION  = 'trial_registry';
const DEVICE_COLLECTION = 'device_registry';
const RUSTORE_LEDGER_COLLECTION = 'rustore_purchase_ledger';
const REVIEW_BONUS_CREDITS = 10;
const FREE_STARTING_CREDITS = 10;

function buildClient() {
  return new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);
}

function deviceFallbackBalance(doc) {
  return (doc.purchasedCredits ?? 0) + (doc.earnedCredits ?? 0);
}

function buildDeviceState(doc) {
  return {
    firstSeenAt:         doc.firstSeenAt,
    isNewDevice:         false,
    freeCreditsUsed:     doc.freeCreditsUsed     ?? 0,
    freeGenerationsUsed: doc.freeGenerationsUsed ?? 0,
    purchasedCredits:    doc.purchasedCredits    ?? 0,
    earnedCredits:       doc.earnedCredits       ?? 0,
    currentBalance:      doc.currentBalance      ?? deviceFallbackBalance(doc),
    subscriptionType:    doc.subscriptionType    ?? '',
  };
}

/**
 * POST /
 *
 * Поддерживаемые действия (action):
 *
 *   check           { fingerprint }
 *     → { eligible: bool, reason: string }
 *       Проверяет, может ли устройство активировать триал.
 *
 *   claim           { fingerprint, platform? }
 *     → { success: bool, alreadyClaimed?: bool, trialId?: string }
 *       Регистрирует начало триала; идемпотентно.
 *
 *   register_device { fingerprint, platform? }
 *     → { firstSeenAt: ISO-string, isNewDevice: bool }
 *       Создаёт запись об устройстве при первой установке или возвращает
 *       исходную дату первой установки при переустановке. Используется для
 *       восстановления прогрессии бесплатных квот (3→2→1) после переустановки.
 */
export default async ({ req, res, log, error }) => {
  let body;
  try {
    body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body ?? {});
  } catch {
    return res.json({ error: 'invalid_json' }, 400);
  }

  const { action, fingerprint, platform = 'unknown' } = body;

  if (!fingerprint || typeof fingerprint !== 'string' || fingerprint.length < 16) {
    return res.json({ error: 'invalid_fingerprint' }, 400);
  }

  const db = new Databases(buildClient());

  // ── CHECK ─────────────────────────────────────────────────────────────────
  if (action === 'check') {
    try {
      const results = await db.listDocuments(DATABASE_ID, TRIAL_COLLECTION, [
        Query.equal('fingerprint', fingerprint),
        Query.limit(1),
      ]);

      if (results.total > 0) {
        log(`check: already claimed — fp=${fingerprint.slice(0, 8)}…`);
        return res.json({ eligible: false, reason: 'trial_already_used' });
      }

      // Платные (в т.ч. dual-SDK legacy) подписчики тоже не должны видеть
      // триал как доступный, даже если trial_registry ещё не записан.
      const devices = await db.listDocuments(DATABASE_ID, DEVICE_COLLECTION, [
        Query.equal('fingerprint', fingerprint),
        Query.limit(1),
      ]);
      if (devices.total > 0) {
        const subType = String(devices.documents[0].subscriptionType ?? '');
        if (subType === 'paid') {
          log(`check: blocked by prior subscriptionType=${subType}`);
          return res.json({ eligible: false, reason: `prior_subscription_${subType}` });
        }
      }

      log(`check: eligible — fp=${fingerprint.slice(0, 8)}…`);
      return res.json({ eligible: true, reason: 'trial_available' });
    } catch (e) {
      error(`check error: ${e.message}`);
      return res.json({ eligible: true, reason: 'server_error_allow' });
    }
  }

  // ── CLAIM ─────────────────────────────────────────────────────────────────
  if (action === 'claim') {
    try {
      const existing = await db.listDocuments(DATABASE_ID, TRIAL_COLLECTION, [
        Query.equal('fingerprint', fingerprint),
        Query.limit(1),
      ]);

      if (existing.total > 0) {
        log(`claim: already claimed (idempotent) — fp=${fingerprint.slice(0, 8)}…`);
        return res.json({ success: true, alreadyClaimed: true });
      }

      // Доп. защита: если на устройстве уже платная подписка — триал нельзя
      const devices = await db.listDocuments(DATABASE_ID, DEVICE_COLLECTION, [
        Query.equal('fingerprint', fingerprint),
        Query.limit(1),
      ]);
      if (devices.total > 0) {
        const subType = String(devices.documents[0].subscriptionType ?? '');
        if (subType === 'paid') {
          await db.createDocument(DATABASE_ID, TRIAL_COLLECTION, ID.unique(), {
            fingerprint,
            platform,
            claimedAt: new Date().toISOString(),
            source: `block_from_subscription_${subType}`,
          });
          log(`claim: blocked by prior subscriptionType=${subType}`);
          return res.json({ success: true, alreadyClaimed: true, reason: 'prior_subscription' });
        }
      }

      const doc = await db.createDocument(DATABASE_ID, TRIAL_COLLECTION, ID.unique(), {
        fingerprint,
        platform,
        claimedAt: new Date().toISOString(),
      });

      log(`claim: registered — fp=${fingerprint.slice(0, 8)}… id=${doc.$id}`);
      return res.json({ success: true, trialId: doc.$id });
    } catch (e) {
      error(`claim error: ${e.message}`);
      return res.json({ success: true, reason: 'server_error_allow' });
    }
  }

  // ── REGISTER_DEVICE ───────────────────────────────────────────────────────
  //
  // Логика: одно устройство — одна запись. При переустановке возвращается
  // оригинальная firstSeenAt и накопленное использование кредитов/генераций,
  // чтобы пользователь не мог сбросить счётчики удалением и переустановкой.
  if (action === 'register_device') {
    try {
      const existing = await db.listDocuments(DATABASE_ID, DEVICE_COLLECTION, [
        Query.equal('fingerprint', fingerprint),
        Query.limit(1),
      ]);

      if (existing.total > 0) {
        const doc = existing.documents[0];
        log(`register_device: known — fp=${fingerprint.slice(0, 8)}… purchased=${doc.purchasedCredits ?? 0} earned=${doc.earnedCredits ?? 0}`);
        return res.json(buildDeviceState(doc));
      }

      const now = new Date().toISOString();
      const doc = await db.createDocument(DATABASE_ID, DEVICE_COLLECTION, ID.unique(), {
        fingerprint, platform, firstSeenAt: now,
        freeCreditsUsed: 0, freeGenerationsUsed: 0,
        purchasedCredits: 0, earnedCredits: 0,
        currentBalance: FREE_STARTING_CREDITS,
        subscriptionType: 'free',
      });

      log(`register_device: new device — fp=${fingerprint.slice(0, 8)}… id=${doc.$id} startingCredits=${FREE_STARTING_CREDITS}`);
      return res.json({
        firstSeenAt: now, isNewDevice: true,
        freeCreditsUsed: 0, freeGenerationsUsed: 0,
        purchasedCredits: 0, earnedCredits: 0,
        currentBalance: FREE_STARTING_CREDITS,
        subscriptionType: 'free',
      });
    } catch (e) {
      error(`register_device error: ${e.message}`);
      return res.json({
        firstSeenAt: new Date().toISOString(), isNewDevice: false,
        freeCreditsUsed: 0, freeGenerationsUsed: 0,
        purchasedCredits: 0, earnedCredits: 0, currentBalance: 0, subscriptionType: '',
        reason: 'server_error_allow',
      });
    }
  }

  // ── RESERVE_CREDITS ────────────────────────────────────────────────────────
  if (action === 'reserve_credits') {
    const amount = Math.max(0, parseInt(body.amount ?? 0, 10));
    const countAsFreeGeneration = Boolean(body.countAsFreeGeneration);

    if (amount <= 0) {
      return res.json({ error: 'invalid_amount' }, 400);
    }

    try {
      const existing = await db.listDocuments(DATABASE_ID, DEVICE_COLLECTION, [
        Query.equal('fingerprint', fingerprint),
        Query.limit(1),
      ]);

      if (existing.total === 0) {
        return res.json({ error: 'device_not_registered' }, 404);
      }

      const doc = existing.documents[0];
      const balance = Math.max(0, parseInt(doc.currentBalance ?? deviceFallbackBalance(doc), 10));
      if (balance < amount) {
        return res.json({
          error: `Недостаточно кредитов: ${balance} из ${amount} необходимых`,
          currentBalance: balance,
        }, 402);
      }

      const patch = {
        currentBalance: balance - amount,
      };

      if ((doc.subscriptionType ?? '') === 'free') {
        patch.freeCreditsUsed = Math.max(0, parseInt(doc.freeCreditsUsed ?? 0, 10)) + amount;
        if (countAsFreeGeneration) {
          patch.freeGenerationsUsed =
            Math.max(0, parseInt(doc.freeGenerationsUsed ?? 0, 10)) + 1;
        }
      }

      const updated = await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, doc.$id, patch);
      log(
        `reserve_credits: fp=${fingerprint.slice(0, 8)}… `
        + `amount=${amount} balance=${balance}->${updated.currentBalance}`,
      );
      return res.json(buildDeviceState(updated));
    } catch (e) {
      error(`reserve_credits error: ${e.message}`);
      return res.json({ error: 'reserve_failed' }, 500);
    }
  }

  // ── ROLLBACK_CREDITS ───────────────────────────────────────────────────────
  if (action === 'rollback_credits') {
    const amount = Math.max(0, parseInt(body.amount ?? 0, 10));
    const countAsFreeGeneration = Boolean(body.countAsFreeGeneration);

    if (amount <= 0) {
      return res.json({ error: 'invalid_amount' }, 400);
    }

    try {
      const existing = await db.listDocuments(DATABASE_ID, DEVICE_COLLECTION, [
        Query.equal('fingerprint', fingerprint),
        Query.limit(1),
      ]);

      if (existing.total === 0) {
        return res.json({ error: 'device_not_registered' }, 404);
      }

      const doc = existing.documents[0];
      const balance = Math.max(0, parseInt(doc.currentBalance ?? deviceFallbackBalance(doc), 10));
      const patch = {
        currentBalance: balance + amount,
      };

      if ((doc.subscriptionType ?? '') === 'free') {
        patch.freeCreditsUsed = Math.max(
          0,
          Math.max(0, parseInt(doc.freeCreditsUsed ?? 0, 10)) - amount,
        );
        if (countAsFreeGeneration) {
          patch.freeGenerationsUsed = Math.max(
            0,
            Math.max(0, parseInt(doc.freeGenerationsUsed ?? 0, 10)) - 1,
          );
        }
      }

      const updated = await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, doc.$id, patch);
      log(
        `rollback_credits: fp=${fingerprint.slice(0, 8)}… `
        + `amount=${amount} balance=${balance}->${updated.currentBalance}`,
      );
      return res.json(buildDeviceState(updated));
    } catch (e) {
      error(`rollback_credits error: ${e.message}`);
      return res.json({ error: 'rollback_failed' }, 500);
    }
  }

  // ── CLAIM_REVIEW_BONUS ────────────────────────────────────────────────────
  if (action === 'claim_review_bonus') {
    const store = (body.store ?? '').toString().toLowerCase().trim();
    const appVersion = (body.appVersion ?? '').toString().trim().slice(0, 32);
    const reviewOutcome = (body.reviewOutcome ?? '').toString().trim().slice(0, 32);

    if (store !== 'rustore') {
      return res.json({
        awardedCredits: 0,
        totalEarnedCredits: 0,
        reason: 'unsupported_store',
      });
    }

    const allowedOutcomes = new Set(['completed', 'alreadyReviewed']);
    if (!allowedOutcomes.has(reviewOutcome)) {
      return res.json({
        awardedCredits: 0,
        totalEarnedCredits: 0,
        reason: 'invalid_outcome',
      });
    }

    const claimFingerprint = `${fingerprint}::review_bonus::${store}`;
    const claimDocId = `rvw_${createHash('sha256').update(claimFingerprint).digest('hex').slice(0, 32)}`;

    try {
      await db.createDocument(DATABASE_ID, TRIAL_COLLECTION, claimDocId, {
        fingerprint: claimFingerprint,
        platform: `review_${platform}`.slice(0, 32),
        claimedAt: new Date().toISOString(),
      });
    } catch (e) {
      const message = (e?.message ?? '').toLowerCase();
      if (message.includes('already exists') || e?.code === 409) {
        return res.json({
          awardedCredits: 0,
          totalEarnedCredits: 0,
          reason: 'already_claimed',
        });
      }
      error(`claim_review_bonus lock error: ${e.message}`);
      return res.json({
        awardedCredits: 0,
        totalEarnedCredits: 0,
        reason: 'server_error',
      });
    }

    try {
      const existing = await db.listDocuments(DATABASE_ID, DEVICE_COLLECTION, [
        Query.equal('fingerprint', fingerprint),
        Query.limit(1),
      ]);

      let docId = null;
      let currentEarned = 0;

      if (existing.total === 0) {
        const now = new Date().toISOString();
        const created = await db.createDocument(DATABASE_ID, DEVICE_COLLECTION, ID.unique(), {
          fingerprint,
          platform,
          firstSeenAt: now,
          freeCreditsUsed: 0,
          freeGenerationsUsed: 0,
          purchasedCredits: 0,
          earnedCredits: REVIEW_BONUS_CREDITS,
          currentBalance: REVIEW_BONUS_CREDITS,
          subscriptionType: '',
        });
        docId = created.$id;
        currentEarned = REVIEW_BONUS_CREDITS;
      } else {
        const doc = existing.documents[0];
        docId = doc.$id;
        currentEarned = (doc.earnedCredits ?? 0) + REVIEW_BONUS_CREDITS;
        const currentBalance = Math.max(
          0,
          parseInt(doc.currentBalance ?? (doc.purchasedCredits ?? 0) + (doc.earnedCredits ?? 0), 10),
        ) + REVIEW_BONUS_CREDITS;
        await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, docId, {
          earnedCredits: currentEarned,
          currentBalance,
        });
      }

      log(`claim_review_bonus: awarded=${REVIEW_BONUS_CREDITS} fp=${fingerprint.slice(0, 8)}… store=${store} outcome=${reviewOutcome} appVersion=${appVersion} doc=${docId}`);
      return res.json({
        awardedCredits: REVIEW_BONUS_CREDITS,
        totalEarnedCredits: currentEarned,
        reason: 'awarded',
      });
    } catch (e) {
      error(`claim_review_bonus update error: ${e.message}`);
      try {
        await db.deleteDocument(DATABASE_ID, TRIAL_COLLECTION, claimDocId);
      } catch (_) {}
      return res.json({
        awardedCredits: 0,
        totalEarnedCredits: 0,
        reason: 'server_error',
      });
    }
  }

  // ── SYNC_CREDITS ──────────────────────────────────────────────────────────
  //
  // Синхронизирует кредиты устройства для ВСЕХ типов пользователей.
  //
  // Поля с prefix free* (freeCreditsUsed, freeGenerationsUsed) — только для
  // free-пользователей. purchasedCredits и earnedCredits — для всех.
  //
  // Применяет MAX(current, incoming) — значения только растут.
  // Возвращает итоговые значения после обновления.
  //
  // Обратная совместимость: принимает action="sync_free_usage" тоже.
  if (action === 'sync_credits' || action === 'sync_free_usage') {
    const incomingFreeCredits  = Math.max(0, parseInt(body.freeCreditsUsed      ?? 0, 10));
    const incomingFreeGens     = Math.max(0, parseInt(body.freeGenerationsUsed  ?? 0, 10));
    const incomingPurchased    = Math.max(0, parseInt(body.purchasedCredits      ?? 0, 10));
    const incomingEarned       = Math.max(0, parseInt(body.earnedCredits         ?? 0, 10));
    const incomingBalance      = Math.max(0, parseInt(body.currentBalance        ?? 0, 10));
    const incomingSubType      = (body.subscriptionType ?? '').toString().slice(0, 16);

    try {
      const existing = await db.listDocuments(DATABASE_ID, DEVICE_COLLECTION, [
        Query.equal('fingerprint', fingerprint),
        Query.limit(1),
      ]);

      const rustoreLedger = await db.listDocuments(
        DATABASE_ID,
        RUSTORE_LEDGER_COLLECTION,
        [
          Query.equal('fingerprint', fingerprint),
          Query.limit(100),
        ],
      ).catch(() => ({ total: 0, documents: [] }));
      const verifiedRustoreCredits = (rustoreLedger.documents ?? []).reduce(
        (sum, doc) => {
          const status = (doc.status ?? '').toString().toLowerCase();
          if (status !== 'confirm_pending' && status !== 'confirmed') return sum;
          return sum + Math.max(0, parseInt(doc.creditsGranted ?? 0, 10));
        },
        0,
      );

      if (existing.total === 0) {
        const now = new Date().toISOString();
        const data = {
          fingerprint, platform, firstSeenAt: now,
          freeCreditsUsed: incomingFreeCredits,
          freeGenerationsUsed: incomingFreeGens,
          purchasedCredits: verifiedRustoreCredits > 0
            ? verifiedRustoreCredits
            : incomingPurchased,
          earnedCredits: incomingEarned,
          currentBalance: verifiedRustoreCredits > 0
            ? verifiedRustoreCredits + incomingEarned
            : incomingBalance,
        };
        if (incomingSubType) data.subscriptionType = incomingSubType;
        await db.createDocument(DATABASE_ID, DEVICE_COLLECTION, ID.unique(), data);
        log(`sync_credits: created — fp=${fingerprint.slice(0, 8)}… purchased=${incomingPurchased} earned=${incomingEarned}`);
        return res.json({
          freeCreditsUsed: data.freeCreditsUsed,
          freeGenerationsUsed: data.freeGenerationsUsed,
          purchasedCredits: data.purchasedCredits,
          earnedCredits: data.earnedCredits,
          currentBalance: data.currentBalance,
          subscriptionType: data.subscriptionType ?? '',
        });
      }

      const doc = existing.documents[0];
      const newFreeCredits = Math.max(doc.freeCreditsUsed      ?? 0, incomingFreeCredits);
      const newFreeGens    = Math.max(doc.freeGenerationsUsed  ?? 0, incomingFreeGens);
      const newPurchased   = verifiedRustoreCredits > 0
        ? Math.max(doc.purchasedCredits ?? 0, verifiedRustoreCredits)
        : Math.max(doc.purchasedCredits ?? 0, incomingPurchased);
      const newEarned      = Math.max(doc.earnedCredits        ?? 0, incomingEarned);
      const existingBalance = Math.max(
        0,
        parseInt(doc.currentBalance ?? deviceFallbackBalance(doc), 10),
      );
      const purchasedDelta = Math.max(0, newPurchased - (doc.purchasedCredits ?? 0));
      const earnedDelta = Math.max(0, newEarned - (doc.earnedCredits ?? 0));
      const balanceFromNewCredits = existingBalance + purchasedDelta + earnedDelta;
      let newBalance = Math.max(existingBalance, balanceFromNewCredits);

      const prevSubType = (doc.subscriptionType ?? '').toString();
      const subscriptionChanged =
        incomingSubType &&
        incomingSubType !== prevSubType &&
        incomingSubType !== 'free';

      // Списание через apibost-proxy / reserve_credits — только на сервере.
      // Клиент для ApiBost не уменьшает локальный остаток, поэтому incomingBalance
      // после генерации часто завышен — нельзя делать MAX с ним без новых кредитов.
      if (purchasedDelta > 0 || earnedDelta > 0) {
        newBalance = Math.max(newBalance, incomingBalance);
      } else if (subscriptionChanged && incomingBalance > newBalance) {
        newBalance = incomingBalance;
      }

      const patch = {};
      if (newFreeCredits !== (doc.freeCreditsUsed     ?? 0)) patch.freeCreditsUsed     = newFreeCredits;
      if (newFreeGens    !== (doc.freeGenerationsUsed ?? 0)) patch.freeGenerationsUsed = newFreeGens;
      if (newPurchased   !== (doc.purchasedCredits    ?? 0)) patch.purchasedCredits    = newPurchased;
      if (newEarned      !== (doc.earnedCredits       ?? 0)) patch.earnedCredits       = newEarned;
      if (newBalance     !== (doc.currentBalance      ?? 0)) patch.currentBalance      = newBalance;
      if (incomingSubType && incomingSubType !== doc.subscriptionType) patch.subscriptionType = incomingSubType;

      if (Object.keys(patch).length > 0) {
        await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, doc.$id, patch);
        log(`sync_credits: updated — fp=${fingerprint.slice(0, 8)}… patch=${JSON.stringify(patch)}`);
      }

      return res.json({
        freeCreditsUsed: newFreeCredits, freeGenerationsUsed: newFreeGens,
        purchasedCredits: newPurchased,  earnedCredits: newEarned, currentBalance: newBalance,
        subscriptionType: incomingSubType || doc.subscriptionType || '',
      });
    } catch (e) {
      error(`sync_credits error: ${e.message}`);
      return res.json({
        freeCreditsUsed: incomingFreeCredits, freeGenerationsUsed: incomingFreeGens,
        purchasedCredits: incomingPurchased,  earnedCredits: incomingEarned, currentBalance: incomingBalance,
        reason: 'server_error_allow',
      });
    }
  }

  return res.json({ error: 'unknown_action' }, 400);
};
