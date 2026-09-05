package com.ffm_manager

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.nfc.NfcAdapter
import java.util.Locale
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingWidgetAction: String? = null
    private var pendingNfcTagTrigger: String? = null
    private var widgetChannel: MethodChannel? = null
    private var nfcChannel: MethodChannel? = null
    private var textToSpeech: TextToSpeech? = null
    private var speechSegments: List<String> = emptyList()
    private var nextSpeechSegment = 0
    private var activeUtteranceId: String? = null
    private var activeSpeechSessionId: String? = null
    private var speechPaused = false
    private var speechChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put("ffm_flutter_engine", flutterEngine)
        pendingNfcTagTrigger = if (intent?.action == NfcAdapter.ACTION_NDEF_DISCOVERED || intent?.data?.scheme == "ffm") {
            intent?.data?.toString()
        } else {
            null
        }
        textToSpeech = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                textToSpeech?.language = Locale("id", "ID")
                restoreSelectedVoice()
                textToSpeech?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        if (utteranceId == activeUtteranceId) emitSpeechState("started")
                    }

                    override fun onDone(utteranceId: String?) {
                        if (utteranceId != activeUtteranceId) return
                        if (speechPaused) return
                        runOnUiThread { speakNextSegment() }
                    }

                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) {
                        if (utteranceId == activeUtteranceId) clearSpeechQueue("error")
                    }
                })
            }
        }
        pendingWidgetAction = intent?.getStringExtra(WIDGET_ACTION_EXTRA)
        intent?.removeExtra(WIDGET_ACTION_EXTRA)
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingAction" -> {
                        result.success(pendingWidgetAction)
                        pendingWidgetAction = null
                    }
                    "updateWidgetState" -> {
                        val title = call.argument<String>("title").orEmpty().trim()
                        val subtitle = call.argument<String>("subtitle").orEmpty().trim()
                        if (title.isBlank() || subtitle.isBlank()) {
                            result.success(false)
                        } else {
                            FfmWidgetProvider.updateState(this, title, subtitle)
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SOUND_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "pick") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            pendingResult = result
            val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                putExtra(
                    RingtoneManager.EXTRA_RINGTONE_TYPE,
                    RingtoneManager.TYPE_NOTIFICATION,
                )
                putExtra(
                    RingtoneManager.EXTRA_RINGTONE_TITLE,
                    "Pilih nada pengingat",
                )
                putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                call.argument<String>("currentUri")?.takeIf { it.isNotBlank() }?.let {
                    putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(it))
                }
            }
            startActivityForResult(intent, REQUEST_CODE)
        }

        speechChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SPEECH_CHANNEL,
        )
        speechChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    val text = call.argument<String>("text").orEmpty().trim()
                    if (text.isBlank()) {
                        result.success(false)
                    } else {
                        speechSegments = splitSpeechSegments(text)
                        nextSpeechSegment = 0
                        activeSpeechSessionId = call.argument<String>("sessionId")
                        speechPaused = false
                        textToSpeech?.stop()
                        result.success(speakNextSegment())
                    }
                }
                "stop" -> {
                    val expectedSessionId = call.argument<String>("sessionId")
                    if (expectedSessionId == null || expectedSessionId == activeSpeechSessionId) {
                        textToSpeech?.stop()
                        speechPaused = true
                        emitSpeechState("stopped")
                    }
                    result.success(true)
                }
                "cancel" -> {
                    textToSpeech?.stop()
                    clearSpeechQueue("stopped")
                    result.success(true)
                }
                "resume" -> {
                    val canResume = speechPaused && textToSpeech?.isSpeaking != true
                    if (canResume) speechPaused = false
                    result.success(canResume && speakNextSegment())
                }
                "isSpeaking" -> result.success(textToSpeech?.isSpeaking == true)
                "voices" -> result.success(
                    offlineVoices().map { voice ->
                        mapOf(
                            "name" to voice.name,
                            "locale" to voice.locale.toLanguageTag(),
                            "quality" to voiceQualityLabel(voice),
                        )
                    },
                )
                "selectedVoice" -> result.success(selectedVoiceName())
                "selectVoice" -> {
                    val name = call.argument<String>("name").orEmpty()
                    val voice = offlineVoices().firstOrNull { it.name == name }
                    if (voice == null) {
                        result.success(false)
                    } else {
                        val tts = textToSpeech
                        if (tts == null) {
                            result.success(false)
                        } else {
                            tts.voice = voice
                            getSharedPreferences(TTS_PREFERENCES, MODE_PRIVATE)
                                .edit()
                                .putString(TTS_VOICE_KEY, voice.name)
                                .apply()
                            result.success(true)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PRIVACY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermissions" -> result.success(checkPermissions())
                "openAppSettings" -> {
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Notification Access Bridge — Fitur 02 (Pendeteksi QRIS & Bank)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_ACCESS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(
                    FfmNotificationListenerService.isEnabled(this)
                )
                "openSettings" -> {
                    FfmNotificationListenerService.openSettings(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // NFC e-Money Reader Bridge — Fitur #1
        val nfcService = FfmNfcReaderService(this)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NFC_CHANNEL,
        )
        nfcChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(FfmNfcReaderService.isAvailable(this))
                "isEnabled" -> result.success(FfmNfcReaderService.isEnabled(this))
                "startSession" -> {
                    val started = nfcService.startScanning { data ->
                        runOnUiThread {
                            channel.invokeMethod("onCardScanned", data)
                        }
                    }
                    result.success(started)
                }
                "stopSession" -> {
                    nfcService.stopScanning()
                    result.success(true)
                }
                "writeTag" -> {
                    val uri = call.argument<String>("uri").orEmpty()
                    val started = nfcService.startWritingTag(uri) { res ->
                        runOnUiThread {
                            result.success(res)
                        }
                    }
                    if (!started) {
                        result.success(mapOf("success" to false, "error" to "NFC tidak aktif atau tidak tersedia."))
                    }
                }
                "cancelWrite" -> {
                    nfcService.cancelWriting()
                    result.success(true)
                }
                "consumePendingTagTrigger" -> {
                    result.success(pendingNfcTagTrigger)
                    pendingNfcTagTrigger = null
                }
                else -> result.notImplemented()
            }
        }

        // Calendar Service Bridge — Fitur #2
        val calendarService = FfmCalendarService(this)
        val calendarChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALENDAR_CHANNEL,
        )
        calendarChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(FfmCalendarService.isAvailable(this))
                "requestCalendarPermissions" -> result.success(true) // Assume permissions granted for now
                "getDefaultCalendarId" -> result.success(FfmCalendarService.getDefaultCalendarId(this))
                "createBillReminder" -> {
                    val title = call.argument<String>("title").orEmpty()
                    val description = call.argument<String>("description").orEmpty()
                    val dueDate = call.argument<Long>("dueDate") ?: System.currentTimeMillis()
                    val amount = call.argument<Double>("amount") ?: 0.0
                    val category = call.argument<String>("category").orEmpty()

                    val response = calendarService.createBillReminderEvent(
                        title, description, dueDate, amount, category
                    )
                    result.success(response)
                }
                "updateBillReminder" -> {
                    val eventId = call.argument<Long>("eventId") ?: 0L
                    val title = call.argument<String>("title").orEmpty()
                    val description = call.argument<String>("description").orEmpty()
                    val dueDate = call.argument<Long>("dueDate") ?: System.currentTimeMillis()
                    val amount = call.argument<Double>("amount") ?: 0.0
                    val category = call.argument<String>("category").orEmpty()

                    val response = calendarService.updateBillReminderEvent(
                        eventId, title, description, dueDate, amount, category
                    )
                    result.success(response)
                }
                "deleteBillReminder" -> {
                    val eventId = call.argument<Long>("eventId") ?: 0L
                    val response = calendarService.deleteBillReminderEvent(eventId)
                    result.success(response)
                }
                "getBillReminders" -> {
                    val startDate = call.argument<Long>("startDate") ?: System.currentTimeMillis()
                    val endDate = call.argument<Long>("endDate") ?: (System.currentTimeMillis() + 30L * 24 * 60 * 60 * 1000)
                    val reminders = calendarService.getBillReminders(startDate, endDate)
                    result.success(reminders)
                }
                else -> result.notImplemented()
            }
        }
    }


    private fun checkPermissions(): Map<String, String> {
        val camera = if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            "diizinkan"
        } else {
            "belum diizinkan"
        }
        val microphone = if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            "diizinkan"
        } else {
            "belum diizinkan"
        }
        return mapOf(
            "kamera" to camera,
            "mikrofon" to microphone,
            "penyimpanan" to "dikelola aplikasi",
        )
    }

    private fun splitSpeechSegments(text: String): List<String> =
        text
            .split(Regex("(?<=[.!?])\\s+|\\n+"))
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .ifEmpty { listOf(text) }

    private fun speakNextSegment(): Boolean {
        val tts = textToSpeech ?: return false
        if (nextSpeechSegment >= speechSegments.size) {
            clearSpeechQueue("completed")
            return false
        }
        val utteranceId = "ffm-assistant-${System.nanoTime()}"
        activeUtteranceId = utteranceId
        val segment = speechSegments[nextSpeechSegment]
        nextSpeechSegment += 1
        val code = tts.speak(segment, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
        if (code != TextToSpeech.SUCCESS) clearSpeechQueue("error")
        return code == TextToSpeech.SUCCESS
    }

    private fun emitSpeechState(status: String, sessionId: String? = activeSpeechSessionId) {
        if (sessionId.isNullOrBlank()) return
        runOnUiThread {
            speechChannel?.invokeMethod(
                "ttsState",
                mapOf("sessionId" to sessionId, "status" to status),
            )
        }
    }

    private fun clearSpeechQueue(status: String? = null) {
        val sessionId = activeSpeechSessionId
        speechSegments = emptyList()
        nextSpeechSegment = 0
        activeUtteranceId = null
        activeSpeechSessionId = null
        speechPaused = false
        if (status != null) emitSpeechState(status, sessionId)
    }

    private fun offlineVoices(): List<Voice> = textToSpeech
        ?.voices
        ?.filter { voice ->
            !voice.isNetworkConnectionRequired && voice.locale.language == "id"
        }
        ?.sortedWith(
            compareByDescending<Voice> { it.quality }
                .thenBy { it.name.lowercase(Locale.ROOT) },
        )
        .orEmpty()

    private fun voiceQualityLabel(voice: Voice): String = when {
        voice.quality >= Voice.QUALITY_HIGH -> "kualitas tinggi"
        voice.quality >= Voice.QUALITY_NORMAL -> "standar"
        else -> "dasar"
    }

    private fun selectedVoiceName(): String? = textToSpeech?.voice?.name

    private fun restoreSelectedVoice() {
        val savedName = getSharedPreferences(TTS_PREFERENCES, MODE_PRIVATE)
            .getString(TTS_VOICE_KEY, null)
            ?: return
        offlineVoices().firstOrNull { it.name == savedName }?.let { voice ->
            textToSpeech?.voice = voice
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra(WIDGET_ACTION_EXTRA)?.let { action ->
            intent.removeExtra(WIDGET_ACTION_EXTRA)
            if (widgetChannel == null) {
                pendingWidgetAction = action
            } else {
                widgetChannel?.invokeMethod("openAction", action)
            }
        }
        if (intent.action == NfcAdapter.ACTION_NDEF_DISCOVERED || intent.data?.scheme == "ffm") {
            val tagUri = intent.data?.toString()
            if (nfcChannel == null) {
                pendingNfcTagTrigger = tagUri
            } else {
                nfcChannel?.invokeMethod("onTagTriggered", tagUri)
            }
        }
    }

    override fun onDestroy() {
        textToSpeech?.stop()
        clearSpeechQueue("stopped")
        textToSpeech?.shutdown()
        textToSpeech = null
        FlutterEngineCache.getInstance().remove("ffm_flutter_engine")
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CODE) return

        val result = pendingResult ?: return
        pendingResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (uri == null) {
            result.success(null)
            return
        }
        val name = runCatching {
            RingtoneManager.getRingtone(this, uri)?.getTitle(this)
        }.getOrNull().orEmpty()
        result.success(
            mapOf(
                "uri" to uri.toString(),
                "name" to if (name.isBlank()) "Nada pilihan" else name,
            ),
        )
    }

    companion object {
        private const val WIDGET_CHANNEL = "ffm/widget"
        private const val WIDGET_ACTION_EXTRA = "ffm_widget_action"
        private const val SOUND_CHANNEL = "ffm/reminder_sound"
        private const val PRIVACY_CHANNEL = "ffm/privacy"
        private const val SPEECH_CHANNEL = "ffm/activity_speech"
        private const val NOTIFICATION_ACCESS_CHANNEL = "ffm/notification_access"
        private const val NFC_CHANNEL = "ffm/nfc_reader"
        private const val CALENDAR_CHANNEL = "ffm/calendar_service"
        private const val TTS_PREFERENCES = "ffm_tts_preferences"
        private const val TTS_VOICE_KEY = "selected_voice_name"
        private const val REQUEST_CODE = 7201
    }
}
