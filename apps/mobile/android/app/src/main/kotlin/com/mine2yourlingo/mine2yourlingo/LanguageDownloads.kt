package com.mine2yourlingo.mine2yourlingo

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.ModelDownloadListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.util.ArrayDeque

/** Own the recognizer until the real download callback; selecting never means installed. */
class LanguageDownloads(private val context: Context, private val event: (Map<String, Any>) -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<Pair<String, String>>()
    private var recognizer: SpeechRecognizer? = null
    private var active: String? = null
    private var serial = 0
    fun request(language: String, locale: String) {
        if (active == language || queue.any { it.first == language }) return
        queue.add(language to locale)
        emit(language, "queued")
        next()
    }
    private fun emit(language: String, phase: String, progress: Int? = null, message: String? = null) {
        val value = mutableMapOf<String, Any>("language" to language, "phase" to phase)
        progress?.let { value["progress"] = it.coerceIn(0, 100) }
        message?.let { value["message"] = it }
        event(value)
    }
    private fun finish(language: String, ticket: Int, phase: String, message: String? = null) {
        if (serial != ticket || active != language) return
        emit(language, phase, message = message)
        recognizer?.destroy(); recognizer = null; active = null
        handler.post { next() }
    }
    private fun next() {
        if (active != null || queue.isEmpty()) return
        val (language, locale) = queue.removeFirst()
        active = language
        val ticket = ++serial
        if (Build.VERSION.SDK_INT < 33 || !SpeechRecognizer.isRecognitionAvailable(context)) {
            finish(language, ticket, "manual", "This phone needs its speech service's language installer. Open Speech settings.")
            return
        }
        try {
            val engine = SpeechRecognizer.createSpeechRecognizer(context)
            recognizer = engine
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            emit(language, "checking")
            handler.postDelayed({ finish(language, ticket, "scheduled", "The speech service has not confirmed installation. Check again after its download completes.") }, 120_000)
            engine.checkRecognitionSupport(intent, context.mainExecutor, object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    if (serial != ticket || active != language) return
                    val installed = support.installedOnDeviceLanguages.any { it.replace('_', '-').equals(locale, true) || it.equals(language, true) }
                    if (installed) { finish(language, ticket, "installed"); return }
                    download(engine, intent, language, ticket)
                }
                override fun onError(error: Int) {
                    if (serial != ticket || active != language) return
                    // Some services do not expose support enumeration but implement downloads.
                    download(engine, intent, language, ticket)
                }
            })
        } catch (_: Exception) {
            finish(language, ticket, "manual", "Your speech service could not start the download. Open Speech settings or try again.")
        }
    }
    private fun download(engine: SpeechRecognizer, intent: Intent, language: String, ticket: Int) {
        if (Build.VERSION.SDK_INT < 33) return
        emit(language, "downloading")
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                engine.triggerModelDownload(intent, context.mainExecutor, object : ModelDownloadListener {
                    override fun onProgress(completedPercent: Int) {
                        if (serial == ticket && active == language) emit(language, "downloading", completedPercent)
                    }
                    override fun onSuccess() { finish(language, ticket, "installed") }
                    override fun onScheduled() { finish(language, ticket, "scheduled", "Download scheduled by your speech service. Check again when it finishes.") }
                    override fun onError(error: Int) {
                        val message = when(error) {
                            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "This speech service does not support this language. Try another speech service or type your message."
                            SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "The language download needs internet access. Reconnect and try again."
                            else -> "The speech service could not download this language (code $error). Open Speech settings or try again."
                        }
                        finish(language, ticket, "error", message)
                    }
                })
            } else {
                engine.triggerModelDownload(intent)
                // API 33 has no completion listener. Do not claim readiness.
                finish(language, ticket, "scheduled", "Download requested. Check again to confirm installation.")
            }
        } catch (_: Exception) {
            finish(language, ticket, "manual", "This speech service needs its own language installer. Open Speech settings.")
        }
    }
    fun close() { serial++; queue.clear(); active = null; recognizer?.destroy(); recognizer = null; handler.removeCallbacksAndMessages(null) }
}
