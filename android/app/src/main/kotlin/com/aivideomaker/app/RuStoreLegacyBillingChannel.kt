package com.aivideomaker.app

import android.app.Application
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import ru.rustore.sdk.billingclient.RuStoreBillingClient
import ru.rustore.sdk.billingclient.RuStoreBillingClientFactory
import ru.rustore.sdk.billingclient.model.product.ProductType
import ru.rustore.sdk.billingclient.model.purchase.PurchaseState

/**
 * Нативный мост к BillingClient SDK для dual-SDK миграции на Pay.
 * Flutter-плагин billing НЕ используется (DEX FlutterError с Pay).
 */
class RuStoreLegacyBillingChannel(
    private val application: Application,
    messenger: BinaryMessenger,
) {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private var client: RuStoreBillingClient? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    val appId = call.argument<String>("consoleApplicationId")
                        ?: DEFAULT_CONSOLE_APP_ID
                    val scheme = call.argument<String>("deeplinkScheme")
                        ?: DEFAULT_DEEPLINK_SCHEME
                    initialize(appId, scheme, result)
                }
                "getLegacySubscriptions" -> getLegacySubscriptions(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun initialize(
        consoleApplicationId: String,
        deeplinkScheme: String,
        result: MethodChannel.Result,
    ) {
        try {
            if (client != null) {
                result.success(true)
                return
            }
            client = RuStoreBillingClientFactory.create(
                context = application,
                consoleApplicationId = consoleApplicationId,
                deeplinkScheme = deeplinkScheme,
                debugLogs = false,
            )
            Log.i(TAG, "BillingClient initialized for legacy subscriptions")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "BillingClient init failed", e)
            result.error("INIT_FAILED", e.message, null)
        }
    }

    private fun getLegacySubscriptions(result: MethodChannel.Result) {
        val billingClient = client
        if (billingClient == null) {
            result.error("NOT_INITIALIZED", "Call initialize first", null)
            return
        }

        billingClient.purchases.getPurchases()
            .addOnSuccessListener { purchases ->
                val subscriptions = purchases
                    .filter { it.productType == ProductType.SUBSCRIPTION }
                    .filter {
                        it.purchaseState == PurchaseState.CONFIRMED ||
                            it.purchaseState == PurchaseState.PAUSED
                    }
                    .map { purchase ->
                        mapOf(
                            "purchaseId" to (purchase.purchaseId ?: ""),
                            "productId" to (purchase.productId ?: ""),
                            "invoiceId" to purchase.invoiceId,
                            "purchaseState" to (purchase.purchaseState?.name ?: "UNKNOWN"),
                            "subscriptionToken" to purchase.subscriptionToken,
                        )
                    }
                Log.i(TAG, "Legacy subscriptions: ${subscriptions.size}")
                result.success(subscriptions)
            }
            .addOnFailureListener { error ->
                Log.e(TAG, "getPurchases failed", error)
                // Не валим Pay SDK-флоу: пустой список = нет legacy-подписок
                result.success(emptyList<Map<String, Any?>>())
            }
    }

    companion object {
        private const val TAG = "RuStoreLegacyBilling"
        const val CHANNEL_NAME = "com.aivideomaker.app/rustore_legacy_billing"
        private const val DEFAULT_CONSOLE_APP_ID = "2063737207"
        private const val DEFAULT_DEEPLINK_SCHEME = "aivideomaker"
    }
}
