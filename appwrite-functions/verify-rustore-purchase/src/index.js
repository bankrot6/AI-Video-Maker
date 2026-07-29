import { Client, Databases, ID, Query } from 'node-appwrite';
import { createSign } from 'node:crypto';

const DATABASE_ID = process.env.APPWRITE_DATABASE_ID ?? 'main';
const DEVICE_COLLECTION = 'device_registry';
const LEDGER_COLLECTION = 'rustore_purchase_ledger';
const TRIAL_COLLECTION = 'trial_registry';

const RUSTORE_APP_ID = String(process.env.RUSTORE_APP_ID ?? '').trim();
const RUSTORE_KEY_ID = String(process.env.RUSTORE_KEY_ID ?? '').trim();
const RUSTORE_PRIVATE_KEY = String(process.env.RUSTORE_PRIVATE_KEY ?? '').replace(/\\n/g, '\n').trim();
const RUSTORE_PUBLIC_API = 'https://public-api.rustore.ru';
const RUSTORE_PACKAGE_NAME = 'com.aivideomaker.app';

// MyTracker S2S: передача дохода RuStore как «Универсальный доход».
const MYTRACKER_S2S_TOKEN = String(process.env.MYTRACKER_S2S_TOKEN ?? '').trim();
const MYTRACKER_S2S_APP_ID = String(process.env.MYTRACKER_S2S_APP_ID ?? '1055317').trim();
const MYTRACKER_S2S_BASE = 'https://tracker-s2s.my.com/v1';

const PRODUCT_CREDITS = new Map([
  ['aivideomaker.credits.50.rustore', 40],
  ['aivideomaker.credits.200.rustore', 150],
  ['aivideomaker.credits.600.rustore', 400],
]);

// Подписки RuStore начисляют кредиты так же, как разовые пакеты, но при
// верификации помечают устройство платным и не увеличивают purchasedCredits
// (тот счётчик зарезервирован под consumable-пакеты).
const SUBSCRIPTION_CREDITS = new Map([
  ['aivideomaker.weekly.rustore', 40],
  ['aivideomaker.monthly.rustore', 140],
  ['aivideomaker.yearly.rustore', 500],
]);

/** Сколько дней даём по productId при dual-SDK sync с BillingClient (до конца периода). */
const SUBSCRIPTION_PERIOD_DAYS = new Map([
  ['aivideomaker.weekly.rustore', 7],
  ['aivideomaker.monthly.rustore', 30],
  ['aivideomaker.yearly.rustore', 365],
]);

let cachedToken = null;

function buildClient() {
  return new Client()
    .setEndpoint(process.env.APPWRITE_ENDPOINT)
    .setProject(process.env.APPWRITE_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);
}

function json(res, body, status = 200) {
  return res.json(body, status);
}

function nowIso() {
  return new Date().toISOString();
}

function intVal(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(0, Math.trunc(parsed));
}

function normalizeInvoiceStatus(status) {
  return String(status ?? '').trim().toUpperCase();
}

function normalizeAckState(value) {
  return String(value ?? '').trim().toUpperCase();
}

function requireRustoreConfig() {
  return Boolean(RUSTORE_APP_ID && RUSTORE_KEY_ID && RUSTORE_PRIVATE_KEY);
}

function buildAuthPayload() {
  const timestamp = new Date().toISOString();
  const signer = createSign('RSA-SHA512');
  signer.update(`${RUSTORE_KEY_ID}${timestamp}`);
  signer.end();
  const signature = signer.sign(RUSTORE_PRIVATE_KEY, 'base64');
  return {
    keyId: RUSTORE_KEY_ID,
    timestamp,
    signature,
  };
}

async function getRustoreToken() {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 30_000) {
    return cachedToken.value;
  }

  const response = await fetch(`${RUSTORE_PUBLIC_API}/public/auth`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(buildAuthPayload()),
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload?.body?.jwe) {
    throw new Error(`rustore_auth_failed:${payload?.message ?? response.status}`);
  }

  cachedToken = {
    value: payload.body.jwe,
    expiresAt: now + (intVal(payload.body.ttl, 900) * 1000),
  };
  return cachedToken.value;
}

async function rustoreRequest(path, { method = 'GET' } = {}) {
  const token = await getRustoreToken();
  const response = await fetch(`${RUSTORE_PUBLIC_API}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'Public-Token': token,
      'API-key': token,
    },
  });
  const payload = await response.json().catch(() => ({}));
  return {
    ok: response.ok && payload?.code === 'OK',
    status: response.status,
    payload,
  };
}

async function fetchInvoice(invoiceId, sandbox = false) {
  const sandboxPrefix = sandbox ? '/public/sandbox' : '/public';
  const result = await rustoreRequest(`${sandboxPrefix}/v2/purchase/${encodeURIComponent(String(invoiceId).trim())}`);
  if (!result.ok || !result.payload?.body) {
    throw new Error(`rustore_invoice_failed:${result.payload?.message ?? result.status}`);
  }
  return result.payload.body;
}

/**
 * Pay SDK: валидация подписки по purchaseId (Public API v4).
 * BillingClient invoice API (v2) для consumable по-прежнему через fetchInvoice.
 */
async function fetchPaySubscription(productId, purchaseId, sandbox = false) {
  const sandboxPrefix = sandbox ? '/public/sandbox' : '/public';
  const result = await rustoreRequest(
    `${sandboxPrefix}/v4/subscription/${encodeURIComponent(RUSTORE_PACKAGE_NAME)}/${encodeURIComponent(productId)}/${encodeURIComponent(purchaseId)}`,
  );
  if (!result.ok || !result.payload?.body) {
    throw new Error(`rustore_subscription_v4_failed:${result.payload?.message ?? result.status}`);
  }
  return result.payload.body;
}

async function confirmPurchaseServer(purchaseId, sandbox = false) {
  const sandboxPrefix = sandbox ? '/public/sandbox' : '/public';
  const result = await rustoreRequest(
    `${sandboxPrefix}/applications/${encodeURIComponent(RUSTORE_APP_ID)}/purchases/${encodeURIComponent(String(purchaseId).trim())}:confirm`,
    { method: 'PUT' },
  );
  if (!result.ok) {
    throw new Error(`rustore_confirm_failed:${result.payload?.message ?? result.status}`);
  }
}

// Сумма фактического платежа из invoice (в рублях). Для триалов и льготных
// периодов RuStore возвращает amountCurrent = 0 — такой доход не учитываем.
function resolveInvoiceRevenue(invoice) {
  const order = invoice?.order ?? {};
  const kopecks = intVal(order.amountCurrent, intVal(order.amountCreate, 0));
  const currency = String(order.currency ?? 'RUB').trim().toUpperCase() || 'RUB';
  return { total: kopecks / 100, currency };
}

// Отправка дохода в MyTracker через S2S customRevenue. Идемпотентность
// обеспечивается на стороне MyTracker дедупликацией по idTransaction
// (используем purchaseId), а на нашей — отправкой только при первичной
// обработке покупки. Ошибки не влияют на основной поток верификации.
async function sendMyTrackerRevenue({ instanceId, idTransaction, total, currency, log }) {
  if (!MYTRACKER_S2S_TOKEN) {
    log?.('mytracker revenue skipped: token not configured');
    return false;
  }
  if (!instanceId || String(instanceId).length < 8) {
    log?.('mytracker revenue skipped: instanceId missing');
    return false;
  }
  if (!(total > 0)) {
    log?.(`mytracker revenue skipped: non-positive total (${total})`);
    return false;
  }

  const response = await fetch(
    `${MYTRACKER_S2S_BASE}/customRevenue/?idApp=${encodeURIComponent(MYTRACKER_S2S_APP_ID)}`,
    {
      method: 'POST',
      headers: {
        Authorization: MYTRACKER_S2S_TOKEN,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        instanceId: String(instanceId),
        idTransaction: String(idTransaction).slice(0, 255),
        currency,
        total,
        eventTimestamp: String(Math.floor(Date.now() / 1000)),
      }),
    },
  );
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    log?.(`mytracker revenue failed ${response.status}: ${JSON.stringify(payload)}`);
    return false;
  }
  log?.(`mytracker revenue sent idTransaction=${idTransaction} total=${total} ${currency}`);
  return true;
}

/** Платная/legacy-подписка ⇒ триал больше недоступен на этом fingerprint. */
async function ensureTrialBlocked(db, fingerprint, platform, log) {
  try {
    const existing = await db.listDocuments(DATABASE_ID, TRIAL_COLLECTION, [
      Query.equal('fingerprint', fingerprint),
      Query.limit(1),
    ]);
    if (existing.total > 0) return;
    const base = {
      fingerprint,
      platform,
      claimedAt: nowIso(),
    };
    try {
      await db.createDocument(DATABASE_ID, TRIAL_COLLECTION, ID.unique(), {
        ...base,
        source: 'paid_subscription_block',
      });
    } catch (_) {
      // Атрибут source может отсутствовать в старой схеме Appwrite
      await db.createDocument(DATABASE_ID, TRIAL_COLLECTION, ID.unique(), base);
    }
    log?.(`trial blocked after paid sub — fp=${String(fingerprint).slice(0, 8)}…`);
  } catch (e) {
    log?.(`ensureTrialBlocked ignored: ${e.message}`);
  }
}

async function getLedgerByPurchaseId(db, purchaseId) {
  const docs = await db.listDocuments(DATABASE_ID, LEDGER_COLLECTION, [
    Query.equal('purchaseId', purchaseId),
    Query.limit(1),
  ]);
  return docs.total > 0 ? docs.documents[0] : null;
}

async function getOrCreateDevice(db, fingerprint, platform = 'android') {
  const docs = await db.listDocuments(DATABASE_ID, DEVICE_COLLECTION, [
    Query.equal('fingerprint', fingerprint),
    Query.limit(1),
  ]);

  if (docs.total > 0) {
    return docs.documents[0];
  }

  const createdAt = nowIso();
  return db.createDocument(DATABASE_ID, DEVICE_COLLECTION, ID.unique(), {
    fingerprint,
    platform,
    firstSeenAt: createdAt,
    freeCreditsUsed: 0,
    freeGenerationsUsed: 0,
    purchasedCredits: 0,
    earnedCredits: 0,
    currentBalance: 0,
    subscriptionType: 'free',
  });
}

function mapLedgerStatus(invoiceStatus, ackState) {
  if (ackState === 'ACKNOWLEDGED' || invoiceStatus === 'CONFIRMED') {
    return 'confirmed';
  }
  if (invoiceStatus === 'PAID') {
    return 'confirm_pending';
  }
  return 'rejected';
}

function isSubscriptionProduct(productId) {
  return SUBSCRIPTION_CREDITS.has(productId);
}

function resolveCredits(productId) {
  return PRODUCT_CREDITS.get(productId) ?? SUBSCRIPTION_CREDITS.get(productId) ?? 0;
}

function buildSnapshot(deviceDoc) {
  return {
    purchasedCredits: intVal(deviceDoc?.purchasedCredits),
    currentBalance: intVal(deviceDoc?.currentBalance),
    earnedCredits: intVal(deviceDoc?.earnedCredits),
  };
}

async function verifyAndGrant({
  db,
  fingerprint,
  platform = 'android',
  purchaseId,
  invoiceId,
  productId,
  orderId,
  sandbox = false,
  autoConfirm = false,
  mytrackerInstanceId,
  log,
}) {
  if (!fingerprint || String(fingerprint).length < 16) {
    return { success: false, reason: 'invalid_fingerprint', status: 400 };
  }
  if (!purchaseId || !invoiceId) {
    return { success: false, reason: 'purchase_id_and_invoice_id_required', status: 400 };
  }

  const invoice = await fetchInvoice(invoiceId, sandbox);
  const invoiceStatus = normalizeInvoiceStatus(invoice.invoiceStatus);
  const ackState = normalizeAckState(invoice.acknowledgementState);
  const effectiveProductId = String(invoice?.order?.itemCode ?? productId ?? '').trim();
  const effectivePurchaseId = String(invoice.purchaseId ?? purchaseId).trim();
  const effectiveOrderId = String(invoice?.order?.orderId ?? orderId ?? '').trim();
  const creditsGranted = resolveCredits(effectiveProductId);

  if (String(invoice.appId) !== RUSTORE_APP_ID) {
    return { success: false, reason: 'app_id_mismatch', status: 409 };
  }
  if (!creditsGranted) {
    return { success: false, reason: 'unsupported_product', status: 409 };
  }
  if (effectiveProductId && productId && effectiveProductId !== productId) {
    return { success: false, reason: 'product_mismatch', status: 409 };
  }
  if (effectiveOrderId && orderId && effectiveOrderId !== orderId) {
    return { success: false, reason: 'order_mismatch', status: 409 };
  }
  if (!['PAID', 'CONFIRMED'].includes(invoiceStatus)) {
    return {
      success: false,
      reason: `invoice_not_ready:${invoiceStatus || 'UNKNOWN'}`,
      invoiceStatus,
      acknowledgementState: ackState,
      status: 409,
    };
  }

  const existingLedger = await getLedgerByPurchaseId(db, effectivePurchaseId);
  const device = await getOrCreateDevice(db, fingerprint, platform);

  if (existingLedger) {
    const snapshot = buildSnapshot(device);
    return {
      success: true,
      alreadyProcessed: true,
      purchaseId: effectivePurchaseId,
      invoiceId: String(invoiceId),
      productId: effectiveProductId,
      orderId: effectiveOrderId,
      creditsGranted: intVal(existingLedger.creditsGranted, creditsGranted),
      ledgerStatus: existingLedger.status ?? mapLedgerStatus(invoiceStatus, ackState),
      invoiceStatus,
      acknowledgementState: ackState,
      autoConfirmed: false,
      ...snapshot,
      status: 200,
    };
  }

  const isSubscription = isSubscriptionProduct(effectiveProductId);
  const nextBalance = intVal(device.currentBalance) + creditsGranted;
  // purchasedCredits растёт только для разовых пакетов; подписки его не трогают.
  const nextPurchasedCredits = isSubscription
    ? intVal(device.purchasedCredits)
    : intVal(device.purchasedCredits) + creditsGranted;
  const ledgerStatus = mapLedgerStatus(invoiceStatus, ackState);
  const createdAt = nowIso();

  // Важно: классический invoice-путь (старые BillingClient-клиенты) НЕ пишет
  // новые атрибуты (sdkSource и т.п.) — иначе createDocument падает, если
  // атрибут ещё не добавлен в Appwrite-схему.
  await db.createDocument(DATABASE_ID, LEDGER_COLLECTION, ID.unique(), {
    purchaseId: effectivePurchaseId,
    invoiceId: String(invoiceId),
    orderId: effectiveOrderId,
    fingerprint,
    productId: effectiveProductId,
    creditsGranted,
    store: 'rustore',
    status: ledgerStatus,
    platform,
    purchaseState: invoiceStatus,
    acknowledgementState: ackState || 'UNKNOWN',
    createdAt,
    updatedAt: createdAt,
  });

  const devicePatch = { currentBalance: nextBalance };
  if (isSubscription) {
    devicePatch.subscriptionType = 'paid';
  } else {
    devicePatch.purchasedCredits = nextPurchasedCredits;
  }
  await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, device.$id, devicePatch);

  // Платная подписка ⇒ триал больше недоступен на этом fingerprint
  if (isSubscription) {
    await ensureTrialBlocked(db, fingerprint, platform, log);
  }

  // Доход отправляем только при первичной обработке покупки (мы здесь, значит
  // existingLedger отсутствовал) и по фактической сумме платежа. Триал/льготный
  // период (amountCurrent = 0) и отсутствие instanceId — пропускаются внутри.
  try {
    const { total, currency } = resolveInvoiceRevenue(invoice);
    await sendMyTrackerRevenue({
      instanceId: mytrackerInstanceId,
      idTransaction: effectivePurchaseId,
      total,
      currency,
      log,
    });
  } catch (e) {
    log?.(`mytracker revenue error purchaseId=${effectivePurchaseId}: ${e.message}`);
  }

  let autoConfirmed = false;
  if (autoConfirm && ledgerStatus === 'confirm_pending') {
    try {
      await confirmPurchaseServer(effectivePurchaseId, sandbox);
      autoConfirmed = true;
      const docs = await db.listDocuments(DATABASE_ID, LEDGER_COLLECTION, [
        Query.equal('purchaseId', effectivePurchaseId),
        Query.limit(1),
      ]);
      if (docs.total > 0) {
        await db.updateDocument(DATABASE_ID, LEDGER_COLLECTION, docs.documents[0].$id, {
          status: 'confirmed',
          acknowledgementState: 'ACKNOWLEDGED',
          updatedAt: nowIso(),
        });
      }
    } catch (e) {
      log?.(`autoConfirm failed purchaseId=${effectivePurchaseId}: ${e.message}`);
    }
  }

  return {
    success: true,
    alreadyProcessed: false,
    purchaseId: effectivePurchaseId,
    invoiceId: String(invoiceId),
    productId: effectiveProductId,
    orderId: effectiveOrderId,
    creditsGranted,
    purchasedCredits: nextPurchasedCredits,
    currentBalance: nextBalance,
    invoiceStatus,
    acknowledgementState: autoConfirmed ? 'ACKNOWLEDGED' : ackState,
    ledgerStatus: autoConfirmed ? 'confirmed' : ledgerStatus,
    autoConfirmed,
    status: 200,
  };
}

export default async ({ req, res, log, error }) => {
  let body;
  try {
    body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body ?? {});
  } catch {
    return json(res, { error: 'invalid_json' }, 400);
  }

  if (!requireRustoreConfig()) {
    return json(res, { error: 'rustore_config_missing' }, 500);
  }

  const {
    action,
    fingerprint,
    platform = 'android',
    purchaseId,
    invoiceId,
    productId,
    orderId,
    sandbox = false,
    autoConfirm = false,
    purchases = [],
    mytrackerInstanceId,
    sdkSource,
    purchaseState,
    expirationDate,
  } = body;

  const db = new Databases(buildClient());

  try {
    if (action === 'verify_purchase') {
      // Pay v4 только для нового клиента (явный sdkSource) — старые BillingClient
      // приложения шлют invoiceId без sdkSource и должны идти в invoice v2.
      const isSubProduct = isSubscriptionProduct(productId);
      const usePaySubscriptionApi =
        sdkSource === 'pay_subscription' ||
        (sdkSource === 'pay' && !invoiceId);
      if (
        isSubProduct &&
        purchaseId &&
        productId &&
        usePaySubscriptionApi
      ) {
        try {
          const sub = await fetchPaySubscription(productId, purchaseId, sandbox);
          const paymentState = String(sub.paymentState ?? sub.status ?? '').toUpperCase();
          const active =
            paymentState === 'ACTIVE' ||
            paymentState === '1' ||
            Boolean(sub.autoRenewing) ||
            Boolean(sub.expiryTimeMillis);
          if (!active && paymentState && !['0', 'ACTIVE', '1'].includes(paymentState)) {
            return json(
              res,
              {
                success: false,
                reason: `subscription_not_active:${paymentState}`,
                status: 409,
              },
              409,
            );
          }

          const device = await getOrCreateDevice(db, fingerprint, platform);
          const creditsGranted = resolveCredits(productId);
          const expiry =
            expirationDate ||
            (sub.expiryTimeMillis
              ? new Date(Number(sub.expiryTimeMillis)).toISOString()
              : '');

          const existingLedger = await getLedgerByPurchaseId(db, String(purchaseId));
          let nextBalance = intVal(device.currentBalance);
          if (!existingLedger) {
            nextBalance += creditsGranted;
            const createdAt = nowIso();
            const ledgerBase = {
              purchaseId: String(purchaseId),
              invoiceId: String(invoiceId ?? ''),
              orderId: String(orderId ?? ''),
              fingerprint,
              productId: String(productId),
              creditsGranted,
              store: 'rustore',
              status: 'confirmed',
              platform,
              purchaseState: paymentState || 'ACTIVE',
              acknowledgementState: 'ACKNOWLEDGED',
              createdAt,
              updatedAt: createdAt,
            };
            try {
              await db.createDocument(DATABASE_ID, LEDGER_COLLECTION, ID.unique(), {
                ...ledgerBase,
                sdkSource: 'pay_subscription',
              });
            } catch (_) {
              await db.createDocument(DATABASE_ID, LEDGER_COLLECTION, ID.unique(), ledgerBase);
            }
          }

          const deviceCore = {
            subscriptionType: 'paid',
            subscriptionEndDate: expiry,
            currentBalance: nextBalance,
          };
          try {
            await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, device.$id, {
              ...deviceCore,
              rustorePurchaseId: String(purchaseId),
              rustoreSdk: 'pay',
            });
          } catch (_) {
            await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, device.$id, deviceCore);
          }
          await ensureTrialBlocked(db, fingerprint, platform, log);

          return json(
            res,
            {
              success: true,
              alreadyProcessed: Boolean(existingLedger),
              purchaseId: String(purchaseId),
              invoiceId: String(invoiceId ?? ''),
              productId: String(productId),
              creditsGranted: existingLedger ? 0 : creditsGranted,
              purchasedCredits: intVal(device.purchasedCredits),
              currentBalance: nextBalance,
              earnedCredits: intVal(device.earnedCredits),
              ledgerStatus: 'confirmed',
              invoiceStatus: paymentState || 'ACTIVE',
              acknowledgementState: 'ACKNOWLEDGED',
              status: 200,
            },
            200,
          );
        } catch (e) {
          // Fallback на invoice v2, если v4 недоступен / старая покупка
          log(`pay_subscription v4 failed, fallback invoice: ${e.message}`);
        }
      }

      const result = await verifyAndGrant({
        db,
        fingerprint,
        platform,
        purchaseId,
        invoiceId,
        productId,
        orderId,
        sandbox,
        autoConfirm,
        mytrackerInstanceId,
        log,
      });
      return json(res, result, result.status ?? 200);
    }

    /**
     * Dual-SDK: клиент нашёл ACTIVE/CONFIRMED подписку в BillingClient.
     * Привязываем entitlement к fingerprint на сервере без Pay invoice.
     * До 01.08.2026 это официальный способ не потерять старых подписчиков.
     * Кредиты не начисляются повторно — они уже были выданы при исходной
     * покупке до миграции на Pay SDK.
     */
    if (action === 'link_legacy_subscription') {
      if (!fingerprint || String(fingerprint).length < 16) {
        return json(res, { error: 'invalid_fingerprint' }, 400);
      }
      if (!isSubscriptionProduct(productId)) {
        return json(res, { error: 'unsupported_product' }, 409);
      }
      if (!purchaseId) {
        return json(res, { error: 'purchase_id_required' }, 400);
      }

      const state = String(purchaseState ?? 'CONFIRMED').toUpperCase();
      if (state !== 'CONFIRMED' && state !== 'ACTIVE') {
        return json(
          res,
          { success: false, reason: `legacy_not_active:${state}` },
          409,
        );
      }

      const device = await getOrCreateDevice(db, fingerprint, platform);
      const days = SUBSCRIPTION_PERIOD_DAYS.get(productId) ?? 30;
      const endDate =
        expirationDate ||
        new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();

      try {
        await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, device.$id, {
          subscriptionType: 'paid',
          subscriptionEndDate: endDate,
          rustorePurchaseId: String(purchaseId),
          rustoreSdk: 'billingclient',
        });
      } catch (_) {
        await db.updateDocument(DATABASE_ID, DEVICE_COLLECTION, device.$id, {
          subscriptionType: 'paid',
          subscriptionEndDate: endDate,
        });
      }
      await ensureTrialBlocked(db, fingerprint, platform, log);

      const existingLedger = await getLedgerByPurchaseId(db, String(purchaseId));
      if (!existingLedger) {
        const createdAt = nowIso();
        const ledgerBase = {
          purchaseId: String(purchaseId),
          invoiceId: String(invoiceId ?? ''),
          orderId: '',
          fingerprint,
          productId: String(productId),
          creditsGranted: 0,
          store: 'rustore',
          status: 'confirmed',
          platform,
          purchaseState: state,
          acknowledgementState: 'ACKNOWLEDGED',
          createdAt,
          updatedAt: createdAt,
        };
        try {
          await db.createDocument(DATABASE_ID, LEDGER_COLLECTION, ID.unique(), {
            ...ledgerBase,
            sdkSource: 'billingclient',
          });
        } catch (e) {
          try {
            await db.createDocument(DATABASE_ID, LEDGER_COLLECTION, ID.unique(), ledgerBase);
          } catch (e2) {
            log(`legacy ledger create ignored: ${e2.message} purchaseId=${purchaseId}`);
          }
        }
      }

      return json(
        res,
        {
          success: true,
          subscriptionEndDate: endDate,
          purchaseId: String(purchaseId),
          sdkSource: 'billingclient',
          trialBlocked: true,
        },
        200,
      );
    }

    if (action === 'reconcile_purchases') {
      if (!Array.isArray(purchases)) {
        return json(res, { error: 'invalid_purchases' }, 400);
      }
      const items = [];
      for (const purchase of purchases) {
        try {
          const result = await verifyAndGrant({
            db,
            fingerprint,
            platform,
            purchaseId: purchase?.purchaseId,
            invoiceId: purchase?.invoiceId,
            productId: purchase?.productId,
            orderId: purchase?.orderId,
            sandbox: Boolean(purchase?.sandbox ?? sandbox),
            autoConfirm: Boolean(purchase?.autoConfirm ?? autoConfirm),
            mytrackerInstanceId: purchase?.mytrackerInstanceId ?? mytrackerInstanceId,
            log,
          });
          items.push(result);
        } catch (e) {
          items.push({
            success: false,
            purchaseId: purchase?.purchaseId ?? '',
            invoiceId: purchase?.invoiceId ?? '',
            reason: e.message,
          });
        }
      }
      return json(res, { success: true, items }, 200);
    }

    if (action === 'mark_confirmed') {
      if (!purchaseId) {
        return json(res, { error: 'purchase_id_required' }, 400);
      }
      const docs = await db.listDocuments(DATABASE_ID, LEDGER_COLLECTION, [
        Query.equal('purchaseId', String(purchaseId)),
        Query.limit(1),
      ]);
      if (docs.total === 0) {
        return json(res, { error: 'purchase_not_found' }, 404);
      }
      await db.updateDocument(DATABASE_ID, LEDGER_COLLECTION, docs.documents[0].$id, {
        status: 'confirmed',
        acknowledgementState: 'ACKNOWLEDGED',
        updatedAt: nowIso(),
      });
      return json(res, { success: true }, 200);
    }

    return json(res, { error: 'unknown_action' }, 400);
  } catch (e) {
    error(`verify-rustore-purchase error: ${e.message}`);
    return json(res, { error: e.message }, 500);
  }
};
