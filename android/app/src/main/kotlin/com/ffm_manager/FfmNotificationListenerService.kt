package com.ffm_manager

import android.content.ComponentName
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * FfmNotificationListenerService
 *
 * Menangkap notifikasi dari aplikasi bank dan e-wallet Indonesia secara lokal.
 * Semua pemrosesan terjadi di dalam perangkat — tidak ada data dikirim ke cloud.
 * Hanya membaca notifikasi dari whitelist paket terpercaya.
 * Notifikasi OTP dan keamanan selalu diabaikan.
 */
class FfmNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val sbn = sbn ?: return
        val packageName = sbn.packageName ?: return

        // Whitelist: hanya proses notifikasi dari bank/e-wallet Indonesia resmi
        if (packageName !in TRUSTED_PACKAGES) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val title = extras.getCharSequence("android.title")?.toString()?.trim() ?: ""
        val content = extras.getCharSequence("android.text")?.toString()?.trim() ?: ""
        val bigContent = extras.getCharSequence("android.bigText")?.toString()?.trim() ?: ""
        val body = if (bigContent.isNotBlank()) bigContent else content

        // Filter: abaikan jika judul atau isi kosong
        if (title.isBlank() && body.isBlank()) return

        // Filter keamanan: abaikan notifikasi OTP dan verifikasi
        if (isSecurityNotification(title, body)) return

        sendToFlutter(
            packageName = packageName,
            title = title,
            body = body,
            postTime = sbn.postTime,
        )
    }

    /**
     * Deteksi notifikasi OTP / keamanan yang wajib diabaikan.
     * Regex ini dirancang ketat agar tidak memblokir notifikasi pembayaran biasa.
     */
    private fun isSecurityNotification(title: String, body: String): Boolean {
        val combined = "$title $body".lowercase()
        return SECURITY_PATTERNS.any { pattern -> pattern.containsMatchIn(combined) }
    }

    /**
     * Kirim data notifikasi mentah ke Flutter layer via MethodChannel.
     * Flutter akan memproses teks ini dengan PaymentNotificationParser (Dart/regex).
     * Jika engine Flutter tidak tersedia (app background), data akan di-drop karena
     * fitur ini menggunakan Catch-Up saat app dibuka kembali.
     */
    private fun sendToFlutter(
        packageName: String,
        title: String,
        body: String,
        postTime: Long,
    ) {
        try {
            val engine = FlutterEngineCache.getInstance().get(FLUTTER_ENGINE_ID)
            if (engine == null) {
                enqueuePendingNotification(packageName, title, body, postTime)
                return
            }
            val messenger = engine.dartExecutor.binaryMessenger
            val channel = MethodChannel(messenger, NOTIFICATION_CHANNEL)
            channel.invokeMethod(
                "onNotification",
                mapOf(
                    "packageName" to packageName,
                    "title" to title,
                    "body" to body,
                    "postTime" to postTime,
                ),
            )
        } catch (e: Exception) {
            Log.w(TAG, "Tidak dapat mengirim notifikasi ke Flutter: ${e.message}")
        }
    }

    private fun enqueuePendingNotification(
        packageName: String,
        title: String,
        body: String,
        postTime: Long,
    ) {
        val prefs = getSharedPreferences(PENDING_PREFS, MODE_PRIVATE)
        val queue = JSONArray(prefs.getString(PENDING_KEY, "[]"))
        queue.put(JSONObject().apply {
            put("packageName", packageName)
            put("title", title)
            put("body", body)
            put("postTime", postTime)
        })
        // Bound the queue so notification bursts cannot consume unbounded storage.
        while (queue.length() > MAX_PENDING) queue.remove(0)
        prefs.edit().putString(PENDING_KEY, queue.toString()).apply()
    }

    companion object {
        private const val TAG = "FfmNLS"
        private const val FLUTTER_ENGINE_ID = "ffm_flutter_engine"
        const val NOTIFICATION_CHANNEL = "ffm/notification_listener"
        private const val PENDING_PREFS = "ffm_notification_listener"
        private const val PENDING_KEY = "pending_notifications"
        private const val MAX_PENDING = 100

        fun consumePendingNotifications(context: Context): List<Map<String, Any>> {
            val prefs = context.getSharedPreferences(PENDING_PREFS, Context.MODE_PRIVATE)
            val queue = JSONArray(prefs.getString(PENDING_KEY, "[]"))
            val result = buildList {
                for (index in 0 until queue.length()) {
                    val item = queue.optJSONObject(index) ?: continue
                    add(
                        mapOf(
                            "packageName" to item.optString("packageName"),
                            "title" to item.optString("title"),
                            "body" to item.optString("body"),
                            "postTime" to item.optLong("postTime"),
                        ),
                    )
                }
            }
            prefs.edit().remove(PENDING_KEY).apply()
            return result
        }

        /** Paket bank, e-wallet, dan e-commerce resmi Indonesia yang dipercaya. */
        val TRUSTED_PACKAGES = setOf(
            // Bank Konvensional
            "com.bca",                      // BCA Mobile
            "com.bca.mybca",               // myBCA
            "com.bankmandiri.livin",        // Livin' by Mandiri
            "id.co.bri.brimo",             // BRImo
            "id.bni.mobile",               // BNI Mobile Banking
            "id.co.bni.wondr",             // Wondr by BNI

            // Bank Digital
            "com.seabank.id",              // SeaBank Indonesia
            "com.bnc.finance",             // Neobank (BNC)
            "id.krom.bank",                // Krom Bank
            "com.jago.digitalBanking",     // Bank Jago
            "id.co.bcadigital.blu",        // blu by BCA Digital
            "bcadigital.blubybcadigital",  // blu by BCA Digital (alt package)
            "com.btpn.dc",                 // Jenius BTPN
            "com.alloapp.yump",            // Allo Bank
            "id.co.banksaqu.mobile",       // Bank Saqu
            "id.co.banksaqu.app",          // Bank Saqu (alt package)
            "id.co.superbank.mobile",      // Superbank
            "id.co.superbank.app",         // Superbank (alt package)
            "com.uob.id.tmrw",             // TMRW by UOB
            "com.linecorp.linebankid",     // LINE Bank by Hana Bank
            "id.co.dbs.digibank",          // digibank by DBS

            // E-Wallet & Pembayaran Digital
            "com.gojek.app",               // GoPay (via Gojek)
            "com.gopay.wallet",            // GoPay standalone
            "ovo.id",                       // OVO
            "id.dana",                      // DANA
            "com.shopee.id",               // Shopee / ShopeePay
            "id.flip",                     // Flip
            "com.telkom.mwallet",          // LinkAja
            "com.astrapay",                // AstraPay
            "com.isaku.app",               // i.saku
            "com.spin.app.latest",         // MotionPay
            "com.paypal.android.p2pmobile", // PayPal
            "com.doku.wallet",             // DOKU Wallet
            "id.kaspro.app",               // KasPro
            "com.google.android.apps.walletnfcrel", // Google Wallet
            "com.transferwise.android",    // Wise
            "com.treni.paytren",           // Paytren
            "id.oy.app",                   // OY! Indonesia
            "com.pluang",                  // Pluang
            "com.bibit.bibitid",           // Bibit
            "com.ajaib.android",           // Ajaib

            // E-Commerce / Marketplace
            "com.tokopedia.tkpd",          // Tokopedia
            "com.lazada.android",          // Lazada
            "com.zhiliaoapp.musically",    // TikTok / TikTok Shop
            "com.ss.android.ugc.trill",    // TikTok / TikTok Shop (alt)
            "blibli.mobile.commerce",      // Blibli
            "com.blibli.mobile.android",   // Blibli (alt)
            "com.bukalapak.android",       // Bukalapak

            // Merchant, Bisnis & Pengiriman
            "id.dana.kasir",               // DANA Bisnis
            "com.honestbank.android",      // Honest
            "hk.easyvan.app.client",       // Lalamove
            "com.qmove.logistics.consignor", // Qmove
        )

        /** Pola regex untuk mendeteksi notifikasi keamanan / OTP — wajib diabaikan. */
        private val SECURITY_PATTERNS = listOf(
            Regex("\\botp\\b"),
            Regex("\\bkode verifikasi\\b"),
            Regex("\\bkode otorisasi\\b"),
            Regex("\\btap\\s+untuk\\s+verifikasi\\b"),
            Regex("\\bsandi\\s+sekali\\s+pakai\\b"),
            Regex("\\bjangan\\s+berikan\\b"),
            Regex("\\bjangan\\s+share\\b"),
            Regex("\\bdo not share\\b"),
            Regex("\\bone.?time\\s+password\\b"),
            Regex("\\bverification code\\b"),
            Regex("\\bautentikasi\\b"),
            Regex("\\bpercobaan\\s+login\\b"),
            Regex("\\bmasuk\\s+baru\\b"),
            Regex("\\bperangkat\\s+baru\\b"),
        )

        /**
         * Periksa apakah NotificationListenerService sudah diizinkan user.
         */
        fun isEnabled(context: Context): Boolean {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
            val componentName = ComponentName(context, FfmNotificationListenerService::class.java)
            return flat.contains(componentName.flattenToString())
        }

        /**
         * Buka halaman pengaturan Notification Access di Android.
         */
        fun openSettings(context: Context) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            context.startActivity(intent)
        }
    }
}
