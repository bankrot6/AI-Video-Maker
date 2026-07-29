package com.aivideomaker.app

import android.content.Intent
import android.media.AudioManager
import com.my.tracker.MyTracker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity: FlutterActivity() {
    private val audioVolumeChannel = "com.aivideomaker.app/audio_volume"
    private val myTrackerPurchaseChannel = "com.aivideomaker.app/mytracker_purchase"
    private var legacyBillingChannel: RuStoreLegacyBillingChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        legacyBillingChannel = RuStoreLegacyBillingChannel(
            application = application,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioVolumeChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getMediaVolume") {
                    val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
                    val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                    val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val volume = if (maxVolume == 0) 0.0
                    else currentVolume.toDouble() / maxVolume.toDouble()
                    val isMuted = currentVolume == 0
                    val payload = hashMapOf(
                        "volume" to volume,
                        "muted" to isMuted
                    )
                    result.success(payload)
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, myTrackerPurchaseChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAutotrackingPurchaseEnabled" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        MyTracker.getTrackerConfig().setAutotrackingPurchaseEnabled(enabled)
                        result.success(null)
                    }
                    "trackPurchase" -> {
                        handleTrackPurchase(call, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleTrackPurchase(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            val productId = call.argument<String>("productId") ?: ""
            val type = call.argument<String>("type") ?: "inapp"
            val priceMicros = (call.argument<Number>("priceMicros") ?: 0L).toLong()
            val currency = call.argument<String>("currency") ?: "RUB"
            val title = call.argument<String>("title") ?: productId
            val orderId = call.argument<String>("orderId") ?: ""
            val purchaseToken = call.argument<String>("purchaseToken") ?: ""
            val purchaseTime = (call.argument<Number>("purchaseTime") ?: System.currentTimeMillis()).toLong()
            val eventParams = call.argument<Map<String, String>>("eventParams")

            val skuDetails = JSONObject().apply {
                put("productId", productId)
                put("type", type)
                put("price_amount_micros", priceMicros)
                put("price_currency_code", currency)
                put("price", (priceMicros / 1_000_000.0).toString())
                put("title", title)
            }

            val purchaseData = JSONObject().apply {
                put("orderId", orderId)
                put("packageName", packageName)
                put("productId", productId)
                put("purchaseTime", purchaseTime)
                put("purchaseState", 0)
                put("purchaseToken", purchaseToken)
                put("acknowledged", true)
            }

            if (eventParams != null) {
                MyTracker.trackPurchaseEvent(skuDetails, purchaseData, "", eventParams)
            } else {
                MyTracker.trackPurchaseEvent(skuDetails, purchaseData, "")
            }
            MyTracker.flush()
            result.success(true)
        } catch (e: Exception) {
            result.error("MYTRACKER_PURCHASE_ERROR", e.message, null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
