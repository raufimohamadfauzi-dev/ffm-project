package com.ffm_manager

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingWidgetAction: String? = null
    private var widgetChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingWidgetAction = intent?.getStringExtra(WIDGET_ACTION_EXTRA)
        intent?.removeExtra(WIDGET_ACTION_EXTRA)
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            WIDGET_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "consumePendingAction") {
                    result.success(pendingWidgetAction)
                    pendingWidgetAction = null
                } else {
                    result.notImplemented()
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
        private const val REQUEST_CODE = 7201
    }
}
