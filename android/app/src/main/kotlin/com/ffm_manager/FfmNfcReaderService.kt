package com.ffm_manager

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.nfc.tech.Ndef
import android.nfc.tech.NdefFormatable
import android.nfc.tech.NfcA
import android.util.Log
import java.io.IOException

/**
 * FfmNfcReaderService
 *
 * Layanan pemindaian NFC 100% lokal untuk membaca kartu e-Money Indonesia
 * (Mandiri e-Money, BCA Flazz, BNI TapCash, BRI Brizzi) serta memprogram
 * stiker koin NFC Pintar (NFC Smart Tag Writer).
 */
class FfmNfcReaderService(private val activity: Activity) : NfcAdapter.ReaderCallback {

    private var nfcAdapter: NfcAdapter? = NfcAdapter.getDefaultAdapter(activity)
    private var onResultListener: ((Map<String, Any?>) -> Unit)? = null
    private var writePayloadUri: String? = null
    private var onWriteResultListener: ((Map<String, Any?>) -> Unit)? = null

    /**
     * Mulai mendengarkan pemindaian NFC saat aktivitas di depan (foreground).
     */
    fun startScanning(listener: (Map<String, Any?>) -> Unit): Boolean {
        val adapter = nfcAdapter ?: return false
        if (!adapter.isEnabled) return false

        writePayloadUri = null
        onWriteResultListener = null
        onResultListener = listener
        val flags = NfcAdapter.FLAG_READER_NFC_A or
                NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK

        adapter.enableReaderMode(activity, this, flags, null)
        return true
    }

    /**
     * Memprogram stiker/koin NFC fisik dengan format NDEF Deep Link URI.
     */
    fun startWritingTag(uriString: String, listener: (Map<String, Any?>) -> Unit): Boolean {
        val adapter = nfcAdapter ?: return false
        if (!adapter.isEnabled) return false

        writePayloadUri = uriString
        onWriteResultListener = listener
        onResultListener = null

        val flags = NfcAdapter.FLAG_READER_NFC_A or
                NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_NFC_F or
                NfcAdapter.FLAG_READER_NFC_V

        adapter.enableReaderMode(activity, this, flags, null)
        return true
    }

    fun cancelWriting() {
        writePayloadUri = null
        onWriteResultListener = null
        stopScanning()
    }

    /**
     * Hentikan mode pemindaian NFC.
     */
    fun stopScanning() {
        nfcAdapter?.disableReaderMode(activity)
        onResultListener = null
        writePayloadUri = null
        onWriteResultListener = null
    }

    override fun onTagDiscovered(tag: Tag?) {
        if (tag == null) return

        if (writePayloadUri != null) {
            handleTagWrite(tag)
            return
        }

        val tagIdHex = bytesToHex(tag.id)
        val isoDep = IsoDep.get(tag)

        if (isoDep == null) {
            // Fallback jika IsoDep tidak tersedia tetapi tag NFC-A terdeteksi
            val result = mapOf(
                "cardId" to tagIdHex,
                "balance" to 0.0,
                "balanceAvailable" to false,
                "cardType" to "unknown_nfc",
                "history" to emptyList<Map<String, Any>>(),
                "success" to true,
            )
            activity.runOnUiThread { onResultListener?.invoke(result) }
            return
        }

        try {
            isoDep.connect()
            isoDep.timeout = 3000

            val cardData = readCardData(isoDep, tagIdHex)
            isoDep.close()

            activity.runOnUiThread {
                onResultListener?.invoke(cardData)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Gagal membaca kartu NFC: ${e.message}")
            try { isoDep.close() } catch (_: Exception) {}

            val errorResult = mapOf<String, Any?>(
                "cardId" to tagIdHex,
                "balance" to 0.0,
                "cardType" to "unknown",
                "history" to emptyList<Map<String, Any>>(),
                "success" to false,
                "error" to (e.message ?: "Gagal membaca tag NFC"),
            )
            activity.runOnUiThread { onResultListener?.invoke(errorResult) }
        }
    }

    private fun handleTagWrite(tag: Tag) {
        val uriStr = writePayloadUri ?: return
        val listener = onWriteResultListener
        writePayloadUri = null
        onWriteResultListener = null
        stopScanning()

        try {
            val record = NdefRecord.createUri(Uri.parse(uriStr))
            val message = NdefMessage(arrayOf(record))

            val ndef = Ndef.get(tag)
            if (ndef != null) {
                ndef.connect()
                if (!ndef.isWritable) {
                    activity.runOnUiThread {
                        listener?.invoke(mapOf("success" to false, "error" to "Tag NFC terkunci / tidak dapat ditulis."))
                    }
                    try { ndef.close() } catch (_: Exception) {}
                    return
                }
                if (ndef.maxSize < message.byteArrayLength) {
                    activity.runOnUiThread {
                        listener?.invoke(mapOf("success" to false, "error" to "Kapasitas memori tag NFC tidak mencukupi."))
                    }
                    try { ndef.close() } catch (_: Exception) {}
                    return
                }
                ndef.writeNdefMessage(message)
                ndef.close()
                activity.runOnUiThread {
                    listener?.invoke(mapOf("success" to true, "message" to "Tag NFC berhasil diprogram."))
                }
                return
            }

            val formatable = NdefFormatable.get(tag)
            if (formatable != null) {
                formatable.connect()
                formatable.format(message)
                formatable.close()
                activity.runOnUiThread {
                    listener?.invoke(mapOf("success" to true, "message" to "Tag NFC berhasil diformat dan diprogram."))
                }
                return
            }

            activity.runOnUiThread {
                listener?.invoke(mapOf("success" to false, "error" to "Tag ini tidak mendukung format NDEF."))
            }
        } catch (e: Exception) {
            activity.runOnUiThread {
                listener?.invoke(mapOf("success" to false, "error" to (e.message ?: "Gagal menulis ke tag NFC")))
            }
        }
    }

    /**
     * Membaca riwayat transaksi (cyclic records) dari kartu e-Money jika didukung.
     */
    private fun readTransactionHistory(isoDep: IsoDep, cardType: String): List<Map<String, Any>> {
        val history = mutableListOf<Map<String, Any>>()
        try {
            for (recNo in 1..3) {
                val apdu = if (cardType == "flazz_bca") {
                    byteArrayOf(0x00.toByte(), 0xB2.toByte(), recNo.toByte(), 0xC4.toByte(), 0x00.toByte())
                } else {
                    byteArrayOf(0x00.toByte(), 0xB2.toByte(), recNo.toByte(), 0x0C.toByte(), 0x00.toByte())
                }
                val resp = isoDep.transceive(apdu)
                if (isSuccessApdu(resp) && resp.size >= 16) {
                    val amount = parseBalanceFromBuffer(resp)
                    if (amount > 0) {
                        history.add(
                            mapOf(
                                "recordIndex" to recNo,
                                "amount" to amount,
                                "rawHex" to bytesToHex(resp),
                            )
                        )
                    }
                }
            }
        } catch (_: Exception) {
            // Graceful fallback jika chip tidak mengizinkan read records
        }
        return history
    }

    /**
     * Mengirim perintah APDU ke kartu e-Money dan mengekstrak nomor ID & saldo.
     */
    private fun readCardData(isoDep: IsoDep, tagIdHex: String): Map<String, Any?> {
        // 1. Coba baca Mandiri e-Money / TapCash APDU
        // APDU Select Applet: 00 A4 04 00 07 F0 00 00 00 18 00 01
        val selectMandiri = hexToBytes("00A4040007F0000000180001")
        val resMandiri = isoDep.transceive(selectMandiri)

        if (isSuccessApdu(resMandiri)) {
            // Read Balance File APDU: 00 B0 81 00 00
            val readBalance = hexToBytes("00B0810000")
            val balanceRes = isoDep.transceive(readBalance)
            val balance = parseBalanceFromBuffer(balanceRes)
            val history = readTransactionHistory(isoDep, "mandiri_emoney")
            return mapOf(
                "cardId" to (extractCardNumber(balanceRes) ?: "MANDIRI-$tagIdHex"),
                "balance" to balance,
                "cardType" to "mandiri_emoney",
                "balanceAvailable" to true,
                "history" to history,
                "success" to true,
            )
        }

        // 2. Coba baca BCA Flazz APDU
        // APDU Select BCA Flazz Applet
        val selectFlazz = hexToBytes("00A4040008A000000018000001")
        val resFlazz = isoDep.transceive(selectFlazz)

        if (isSuccessApdu(resFlazz)) {
            val readFlazz = hexToBytes("00B0810010")
            val balanceRes = isoDep.transceive(readFlazz)
            val balance = parseBalanceFromBuffer(balanceRes)
            val history = readTransactionHistory(isoDep, "flazz_bca")
            return mapOf(
                "cardId" to "FLAZZ-$tagIdHex",
                "balance" to balance,
                "cardType" to "flazz_bca",
                "balanceAvailable" to true,
                "history" to history,
                "success" to true,
            )
        }

        // 3. Fallback APDU Generik (BNI TapCash / BRI Brizzi / Generic IsoDep)
        val readGeneric = hexToBytes("00B0820000")
        val genericRes = try { isoDep.transceive(readGeneric) } catch (_: Exception) { byteArrayOf() }
        val balance = parseBalanceFromBuffer(genericRes)

        return mapOf(
            "cardId" to "NFC-$tagIdHex",
            "balance" to balance,
            "balanceAvailable" to (balance > 0.0),
            "cardType" to "emoney_generic",
            "history" to emptyList<Map<String, Any>>(),
            "success" to true,
        )
    }

    private fun isSuccessApdu(response: ByteArray?): Boolean {
        if (response == null || response.size < 2) return false
        val sw1 = response[response.size - 2].toInt() and 0xFF
        val sw2 = response[response.size - 1].toInt() and 0xFF
        return sw1 == 0x90 && sw2 == 0x00
    }

    private fun parseBalanceFromBuffer(buffer: ByteArray?): Double {
        if (buffer == null || buffer.size < 4) return 0.0
        // Ekstrak 4-byte integer (Big-Endian)
        for (i in 0..(buffer.size - 4)) {
            val valBig = ((buffer[i].toInt() and 0xFF) shl 24) or
                    ((buffer[i + 1].toInt() and 0xFF) shl 16) or
                    ((buffer[i + 2].toInt() and 0xFF) shl 8) or
                    (buffer[i + 3].toInt() and 0xFF)

            // Saldo e-money logis berkisar antara Rp 1.000 s.d. Rp 20.000.000
            if (valBig in 500..20000000) {
                return valBig.toDouble()
            }

            // Ekstrak Little-Endian
            val valLittle = ((buffer[i + 3].toInt() and 0xFF) shl 24) or
                    ((buffer[i + 2].toInt() and 0xFF) shl 16) or
                    ((buffer[i + 1].toInt() and 0xFF) shl 8) or
                    (buffer[i].toInt() and 0xFF)

            if (valLittle in 500..20000000) {
                return valLittle.toDouble()
            }
        }
        return 0.0
    }

    private fun extractCardNumber(buffer: ByteArray?): String? {
        if (buffer == null || buffer.size < 16) return null
        val hex = bytesToHex(buffer)
        return if (hex.length >= 16) hex.substring(0, 16) else null
    }

    companion object {
        private const val TAG = "FfmNfcReader"

        fun isAvailable(context: Context): Boolean {
            return NfcAdapter.getDefaultAdapter(context) != null
        }

        fun isEnabled(context: Context): Boolean {
            val adapter = NfcAdapter.getDefaultAdapter(context)
            return adapter != null && adapter.isEnabled
        }

        private fun bytesToHex(bytes: ByteArray?): String {
            if (bytes == null) return ""
            val sb = StringBuilder()
            for (b in bytes) {
                sb.append(String.format("%02X", b))
            }
            return sb.toString()
        }

        private fun hexToBytes(s: String): ByteArray {
            val len = s.length
            val data = ByteArray(len / 2)
            for (i in 0 until len step 2) {
                data[i / 2] = ((Character.digit(s[i], 16) shl 4) +
                        Character.digit(s[i + 1], 16)).toByte()
            }
            return data
        }
    }
}
