package com.mine2yourlingo.mine2yourlingo

import android.app.Instrumentation
import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel

/** Runs model inference only. No UI automation, app-data reset, microphone or permission grant. */
class TranslationSmokeInstrumentation : Instrumentation() {
    private var offlineTest = false
    override fun onCreate(arguments: Bundle?) { offlineTest = arguments?.getString("offline") == "true"; super.onCreate(arguments); start() }
    override fun onStart() {
        val report = Bundle()
        var failed: String? = null
        val voicesDone = CountDownLatch(1)
        var voices: Set<String> = emptySet()
        Handler(Looper.getMainLooper()).post {
            NativeAudio.initialize(targetContext)
            DeviceTranslation.initialize(targetContext)
            NativeAudio.capabilities(object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val caps = result as? Map<*, *>
                    voices = (caps?.get("voices") as? List<*>)?.mapNotNull {
                        (it as? Map<*, *>)?.get("language")?.toString()?.substringBefore('-')
                    }?.toSet().orEmpty()
                    voicesDone.countDown()
                }
                override fun error(code: String, message: String?, details: Any?) { voicesDone.countDown() }
                override fun notImplemented() { voicesDone.countDown() }
            })
        }
        if (!voicesDone.await(15, TimeUnit.SECONDS) || !voices.containsAll(setOf("ta", "en"))) {
            failed = "Tamil / English offline reading voice missing"
        }
        report.putString("reading-voices", if (failed == null) "Tamil and English installed" else failed)
        report.putString("sdk-language-codes", "ta=${DeviceTranslation.supported("ta")}; hi=${DeviceTranslation.supported("hi")}; ta-IN=${DeviceTranslation.supported("ta-IN")}")
        for ((source, target, text) in listOf(Triple("en", "ta", "Bring two bags"), Triple("ta", "en", "இரண்டு பைகளை கொண்டு வாருங்கள்"), Triple("ta", "hi", "வணக்கம், நீங்கள் எப்படி இருக்கிறீர்கள்?"), Triple("hi", "ta", "नमस्ते, आप कैसे हैं?"))) {
            val done = CountDownLatch(1)
            var output: String? = null
            var error: String? = null
            Handler(Looper.getMainLooper()).post {
                DeviceTranslation.translate(text, source, target, object : MethodChannel.Result {
                    override fun success(result: Any?) { output = result as? String; done.countDown() }
                    override fun error(code: String, message: String?, details: Any?) { error = code; done.countDown() }
                    override fun notImplemented() { error = "not_implemented"; done.countDown() }
                })
            }
            if (!done.await(105, TimeUnit.SECONDS)) error = "timeout"
            if (error != null || output.isNullOrBlank() || output == text) { failed = "$source->$target: ${error ?: "no translated output"}"; break }
            report.putString("$source-$target", output)
        }
        if (offlineTest && failed == null) {
            val checked = CountDownLatch(1)
            var installed: Set<String>? = null
            Handler(Looper.getMainLooper()).post {
                RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java)
                    .addOnSuccessListener { models -> installed = models.map { it.language }.toSet(); checked.countDown() }
                    .addOnFailureListener { checked.countDown() }
            }
            if (!checked.await(15, TimeUnit.SECONDS) || installed == null) failed = "Cannot inspect actual downloaded models"
            else {
                val missing = TranslateLanguage.getAllLanguages().firstOrNull { it != "en" && !installed!!.contains(it) }
                if (missing != null) {
                    val done = CountDownLatch(1)
                    var failure: String? = null
                    Handler(Looper.getMainLooper()).post {
                        DeviceTranslation.translate("Hello", "en", missing, object : MethodChannel.Result {
                            override fun success(result: Any?) { failure = "unexpected_success_without_model"; done.countDown() }
                            override fun error(code: String, message: String?, details: Any?) { failure = code; done.countDown() }
                            override fun notImplemented() { failure = "not_implemented"; done.countDown() }
                        })
                    }
                    if (!done.await(105, TimeUnit.SECONDS)) failure = "timeout"
                    report.putString("missing-model-offline", failure)
                    if (failure != "model_download_offline") failed = "Offline missing model returned $failure"
                } else failed = "No missing model available for offline failure check"
            }
        }
        report.putString("result", failed ?: "device translation model downloads and inference passed; linguistic quality needs human review")
        Handler(Looper.getMainLooper()).post { NativeAudio.release() }
        finish(if (failed == null) Activity.RESULT_OK else Activity.RESULT_CANCELED, report)
    }
}
