package com.ffm_manager

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FfmLocalModelBridgePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var bridge: FfmLocalModelBridge? = null
    private var bridgeLoadError: Throwable? = null
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        appContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ffm_local_model_bridge")
        channel.setMethodCallHandler(this)
    }

    private fun postSuccess(result: Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun postError(result: Result, code: String, message: String, details: Any? = null) {
        mainHandler.post { result.error(code, message, details) }
    }

    /**
     * Native SLM is optional. Loading it in the plugin constructor caused an
     * unsupported x86_64 emulator or device to crash before Flutter could show
     * the fallback rule-based assistant. Load lazily on the first real model
     * request and convert LinkageError into a normal MethodChannel error.
     */
    private fun nativeBridge(): FfmLocalModelBridge? {
        bridge?.let { return it }
        bridgeLoadError?.let { return null }
        return try {
            FfmLocalModelBridge().also { bridge = it }
        } catch (error: Throwable) {
            bridgeLoadError = error
            null
        }
    }

    private fun nativeUnavailableMessage(): String {
        val error = bridgeLoadError
        return if (error == null) {
            "Library AI lokal belum tersedia di perangkat ini"
        } else {
            "Library AI lokal tidak tersedia untuk ABI perangkat ini"
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initNative" -> {
                val modelPath = call.argument<String>("modelPath")
                val mmprojPath = call.argument<String>("mmprojPath")
                if (modelPath.isNullOrBlank() || mmprojPath.isNullOrBlank()) {
                    result.error("ARG_ERROR", "modelPath/mmprojPath tidak valid", null)
                    return
                }
                executor.execute {
                    val native = nativeBridge()
                    if (native == null) {
                        postError(result, "NATIVE_UNAVAILABLE", nativeUnavailableMessage(), null)
                        return@execute
                    }
                    try {
                        postSuccess(result, native.initNative(modelPath, mmprojPath))
                    } catch (error: Throwable) {
                        postError(result, "NATIVE_INIT_ERROR", error.message ?: "Gagal memuat model", null)
                    }
                }
            }
            "destroyNative" -> {
                executor.execute {
                    val native = bridge
                    if (native == null) {
                        postSuccess(result, null)
                        return@execute
                    }
                    try {
                        native.destroyNative()
                        postSuccess(result, null)
                    } catch (error: Throwable) {
                        postError(result, "NATIVE_DESTROY_ERROR", error.message ?: "Gagal membebaskan model", null)
                    }
                }
            }
            "startBackgroundBundleDownload" -> startBackgroundBundleDownload(call, result)
            "backgroundBundleStatus" -> postSuccess(result, backgroundBundleStatus())
            "cancelBackgroundBundleDownload" -> cancelBackgroundBundleDownload(result)
            "generateSingleShotNative" -> {
                val systemPrompt = call.argument<String>("systemPrompt")
                val userPrompt = call.argument<String>("userPrompt")
                if (systemPrompt == null || userPrompt == null) {
                    result.error("ARG_ERROR", "Prompt tidak valid", null)
                    return
                }
                val imagePath = call.argument<String>("imagePath")
                // Exactly one blocking JNI call. The single-thread executor is
                // the ownership boundary for the native model session.
                executor.execute {
                    val native = nativeBridge()
                    if (native == null) {
                        postError(result, "NATIVE_UNAVAILABLE", nativeUnavailableMessage(), null)
                        return@execute
                    }
                    try {
                        val response = native.generateSingleShotNative(systemPrompt, userPrompt, imagePath)
                        postSuccess(result, response)
                    } catch (error: Throwable) {
                        postError(result, "NATIVE_GENERATE_ERROR", error.message ?: "Gagal menjalankan model", null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun downloadManager(): DownloadManager =
        appContext.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private fun startBackgroundBundleDownload(call: MethodCall, result: Result) {
        val prefs = appContext.getSharedPreferences("ffm_slm_background_downloads", Context.MODE_PRIVATE)
        val manager = downloadManager()
        val requests = listOf(
            DownloadSpec("language_model", "https://github.com/raufimohamadfauzi-dev/ffm-project/releases/download/v1.0.0/Qwen2-VL-2B-Instruct-IQ4_NL.gguf", "Qwen2-VL-2B-Instruct-IQ4_NL.gguf", 936329984L),
            DownloadSpec("multimodal_projector", "https://github.com/raufimohamadfauzi-dev/ffm-project/releases/download/v1.0.0/mmproj-Qwen2-VL-2B-Instruct-f16.gguf", "mmproj-Qwen2-VL-2B-Instruct-f16.gguf", 1331656192L),
        )
        val requestedRoles = call.argument<List<String>>("roles")?.toSet()
            ?: requests.map { it.role }.toSet()
        requests.filter { it.role in requestedRoles }.forEach { spec ->
            if (backgroundFilePath(spec.fileName) == null) {
                postError(
                    result,
                    "STORAGE_UNAVAILABLE",
                    "Storage aplikasi untuk download SLM belum tersedia. Periksa storage perangkat lalu coba lagi.",
                )
                return
            }
            val key = "${spec.role}_id"
            val existingId = prefs.getLong(key, -1L)
            if (existingId != -1L && isDownloadActive(manager, existingId)) return@forEach
            if (existingId != -1L && isDownloadCompleteAndReadable(manager, existingId, spec)) return@forEach
            if (existingId != -1L) manager.remove(existingId)
            cleanupIncompleteDestination(spec)
            val request = DownloadManager.Request(Uri.parse(spec.url))
                .setTitle("FFM: ${spec.fileName}")
                .setDescription("Download SLM Qwen2-VL berjalan di latar belakang")
                .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                .setAllowedOverMetered(true)
                .setAllowedOverRoaming(false)
                .setDestinationInExternalFilesDir(appContext, Environment.DIRECTORY_DOWNLOADS, "ffm_models/qwen2-vl/${spec.fileName}")
            val id = manager.enqueue(request)
            prefs.edit().putLong(key, id).putString("${spec.role}_file", spec.fileName).apply()
        }
        postSuccess(result, backgroundBundleStatus())
    }

    private fun isDownloadActive(manager: DownloadManager, id: Long): Boolean {
        val cursor = manager.query(DownloadManager.Query().setFilterById(id)) ?: return false
        return cursor.use {
            it.moveToFirst() && when (it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                DownloadManager.STATUS_PENDING,
                DownloadManager.STATUS_RUNNING,
                DownloadManager.STATUS_PAUSED -> true
                else -> false
            }
        }
    }

    private fun isDownloadCompleteAndReadable(
        manager: DownloadManager,
        id: Long,
        spec: DownloadSpec,
    ): Boolean {
        val cursor = manager.query(DownloadManager.Query().setFilterById(id)) ?: return false
        return cursor.use {
            if (!it.moveToFirst()) return@use false
            if (it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) != DownloadManager.STATUS_SUCCESSFUL) {
                return@use false
            }
            val localUri = it.getString(it.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
            val file = fileFromDownloadManagerUri(localUri) ?: backgroundFile(spec.fileName)
            file?.isFile == true && file.length() == spec.expectedBytes
        }
    }

    private fun cleanupIncompleteDestination(spec: DownloadSpec) {
        val file = backgroundFile(spec.fileName) ?: return
        if (file.isFile && file.length() != spec.expectedBytes) {
            file.delete()
        }
    }

    private fun backgroundFilePath(fileName: String): String? =
        appContext.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?.let { java.io.File(it, "ffm_models/qwen2-vl/$fileName").absolutePath }

    private fun backgroundFile(fileName: String): File? =
        backgroundFilePath(fileName)?.let(::File)

    private fun fileFromDownloadManagerUri(rawUri: String?): File? {
        if (rawUri.isNullOrBlank()) return null
        return try {
            val uri = Uri.parse(rawUri)
            if (uri.scheme.equals("file", ignoreCase = true)) {
                uri.path?.let(::File)
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun backgroundBundleStatus(): List<Map<String, Any?>> {
        val prefs = appContext.getSharedPreferences("ffm_slm_background_downloads", Context.MODE_PRIVATE)
        val manager = downloadManager()
        return listOf("language_model", "multimodal_projector").mapNotNull { role ->
            val id = prefs.getLong("${role}_id", -1L)
            val fileName = prefs.getString("${role}_file", role) ?: role
            if (id == -1L) return@mapNotNull null
            val cursor = manager.query(DownloadManager.Query().setFilterById(id))
            if (cursor == null || !cursor.moveToFirst()) {
                cursor?.close()
                return@mapNotNull mapOf("role" to role, "fileName" to fileName, "state" to "unknown")
            }
            cursor.use {
                val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val reason = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                val received = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val total = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                val state = when (status) {
                    DownloadManager.STATUS_PENDING,
                    DownloadManager.STATUS_RUNNING,
                    DownloadManager.STATUS_PAUSED -> "downloading"
                    DownloadManager.STATUS_SUCCESSFUL -> "complete"
                    DownloadManager.STATUS_FAILED -> "failed"
                    else -> "unknown"
                }
                // DownloadManager adalah sumber kebenaran untuk lokasi hasil
                // unduhan. Path tujuan manual hanya fallback bila Android tidak
                // dapat mengembalikan URI file yang dapat dibuka sebagai File.
                val localUri = it.getString(it.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                val uriFile = fileFromDownloadManagerUri(localUri)
                val fallbackFile = backgroundFile(fileName)
                val pathMismatch = uriFile != null && fallbackFile != null &&
                    uriFile.absolutePath != fallbackFile.absolutePath
                if (pathMismatch) {
                    Log.w(
                        "FFMModelDownload",
                        "DownloadManager URI berbeda dari fallback untuk $fileName: ${uriFile.absolutePath} != ${fallbackFile.absolutePath}",
                    )
                }
                val file = uriFile ?: fallbackFile
                val pathSource = when {
                    uriFile != null -> "download_manager_local_uri"
                    fallbackFile != null -> "manual_destination_fallback"
                    else -> "unavailable"
                }
                val diskBytes = if (file?.isFile == true) file.length() else null
                val parentExists = file?.parentFile?.isDirectory
                mapOf(
                    "role" to role,
                    "fileName" to fileName,
                    "state" to state,
                    "receivedBytes" to received,
                    "totalBytes" to total,
                    "localPath" to file?.absolutePath,
                    "downloadManagerUri" to localUri,
                    "pathSource" to pathSource,
                    "pathMismatch" to pathMismatch,
                    "diskBytes" to diskBytes,
                    "parentExists" to parentExists,
                    "reason" to if (state == "failed") "Kode DownloadManager $reason" else null,
                )
            }
        }
    }

    private fun cancelBackgroundBundleDownload(result: Result) {
        val prefs = appContext.getSharedPreferences("ffm_slm_background_downloads", Context.MODE_PRIVATE)
        val manager = downloadManager()
        listOf("language_model", "multimodal_projector").forEach { role ->
            val id = prefs.getLong("${role}_id", -1L)
            if (id != -1L) manager.remove(id)
        }
        prefs.edit().clear().apply()
        postSuccess(result, null)
    }

    private data class DownloadSpec(
        val role: String,
        val url: String,
        val fileName: String,
        val expectedBytes: Long,
    )

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.execute {
            try {
                bridge?.destroyNative()
            } finally {
                executor.shutdown()
            }
        }
    }
}
