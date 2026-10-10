package com.mine2yourlingo.mine2yourlingo

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.plugin.common.MethodChannel

/** Models download over internet; inference stays on-device. Never invokes cloud AI. */
object DeviceTranslation {
    private val handler = Handler(Looper.getMainLooper())
    private var context: Context? = null
    fun initialize(value: Context) { context = value.applicationContext }
    fun supported(code: String): String? = try {
        TranslateLanguage.fromLanguageTag(code.trim().lowercase().replace('_', '-'))
    } catch (_: IllegalArgumentException) { null }
    private fun offline(): Boolean {
        val manager = context?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        val network = manager.activeNetwork ?: return true
        return manager.getNetworkCapabilities(network)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) != true
    }
    private fun downloadError(): Pair<String, String> = if (offline())
        "model_download_offline" to "A translation model is missing and this device is offline. Connect to the internet once to download it, then retry."
    else "model_download_failed" to "The translation model could not download. Check internet access and free storage, then retry."
    fun prepare(code: String, emit: (Map<String, Any>) -> Unit, result: MethodChannel.Result) {
        val language = supported(code)
        if (language == null) {
            emit(mapOf("language" to code, "translationPhase" to "unsupported", "translationCode" to "device_language_unsupported"))
            result.success(false)
            return
        }
        if (language == "en") {
            emit(mapOf("language" to code, "translationPhase" to "ready"))
            result.success(true)
            return
        }
        try {
            val manager = RemoteModelManager.getInstance()
            val model = TranslateRemoteModel.Builder(language).build()
            manager.isModelDownloaded(model).addOnSuccessListener { installed ->
                if (installed) emit(mapOf("language" to code, "translationPhase" to "ready"))
                else {
                    emit(mapOf("language" to code, "translationPhase" to "downloading"))
                    manager.download(model, DownloadConditions.Builder().build())
                        .addOnSuccessListener { emit(mapOf("language" to code, "translationPhase" to "ready")) }
                        .addOnFailureListener {
                            val (error, message) = downloadError()
                            emit(mapOf("language" to code, "translationPhase" to "error", "translationCode" to error, "translationMessage" to message))
                        }
                }
            }.addOnFailureListener {
                emit(mapOf("language" to code, "translationPhase" to "error", "translationCode" to "model_status_failed",
                    "translationMessage" to "Could not check the installed translation model. Restart the app and retry."))
            }
            result.success(true) // Readiness is emitted only by actual SDK callbacks.
        } catch (_: Exception) {
            result.error("translation_initialization_failed", "Could not initialize device translation. Restart the app and retry.", null)
        }
    }
    fun translate(text: String, source: String, target: String, result: MethodChannel.Result) {
        if (text.isBlank() || text.length > 4000) {
            result.error("invalid_text", "Provide 1–4000 characters.", null)
            return
        }
        val from = supported(source)
        val to = supported(target)
        if (from == null || to == null) {
            result.error("device_language_unsupported", "This language is unavailable in ML Kit device translation. Cloud AI requires an eligible plan, consent and configured billing.", null)
            return
        }
        if (from == to) { result.success(text); return }
        val translator = try { Translation.getClient(TranslatorOptions.Builder()
            .setSourceLanguage(from).setTargetLanguage(to).build()) }
        catch (_: Exception) {
            result.error("translation_initialization_failed", "Could not initialize device translation. Restart the app and retry.", null)
            return
        }
        var completed = false
        var phase = "download"
        fun finish(value: String? = null, code: String? = null, message: String? = null) {
            if (completed) return
            completed = true
            translator.close()
            if (code != null) result.error(code, message, null)
            else if (value.isNullOrBlank()) result.error("device_translation_empty", "No translation was produced.", null)
            else result.success(value)
        }
        val deadline = Runnable {
            if (phase == "download") finish(code = "model_download_pending", message = "Translation models are still downloading. Keep internet connected and retry.")
            else finish(code = "translation_timeout", message = "Device translation timed out. Retry this message.")
        }
        handler.postDelayed(deadline, 90000)
        fun fail(code: String, message: String) { handler.removeCallbacks(deadline); finish(code = code, message = message) }
        try {
            RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java)
                .addOnSuccessListener { models ->
                    if (!completed) {
                        val installed = models.map { it.language }.toSet()
                        val missing = listOf(from, to).any { it != "en" && !installed.contains(it) }
                        if (missing && offline()) {
                            val (code, message) = downloadError(); fail(code, message)
                        } else {
                            translator.downloadModelIfNeeded(DownloadConditions.Builder().build())
                                .addOnSuccessListener {
                                    if (!completed) {
                                        phase = "translation"
                                        translator.translate(text)
                                            .addOnSuccessListener { handler.removeCallbacks(deadline); finish(value = it) }
                                            .addOnFailureListener { fail("device_translation_failed", "The installed model could not translate this message. Retry or re-download the language model.") }
                                    }
                                }.addOnFailureListener { val (code, message) = downloadError(); fail(code, message) }
                        }
                    }
                }.addOnFailureListener { fail("model_status_failed", "Could not inspect the installed translation models. Restart the app and retry.") }
        } catch (_: Exception) { fail("translation_initialization_failed", "Device translation could not start. Restart the app and retry.") }
    }
}
