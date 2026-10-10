package com.mine2yourlingo.mine2yourlingo

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    private var visible = false
    private var refreshVoiceEngine = false
    private var modelPermission: Pair<String, String>? = null
    private var downloads: LanguageDownloads? = null
    private val picker by lazy { PersonnelPicker(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NativeAudio.initialize(applicationContext)
        DeviceTranslation.initialize(applicationContext)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.mine2yourlingo/audio")
        downloads = LanguageDownloads(applicationContext) { channel?.invokeMethod("languageDownload", it) }
        NativeAudio.events = { event, payload -> channel?.invokeMethod(event, payload) }
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openTranslationAttribution" -> {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://translate.google.com")))
                        result.success(true)
                    } catch (_: Exception) { result.error("browser_unavailable", "No browser is available.", null) }
                }
                "prepareTranslation" -> {
                    val code = call.argument<String>("language") ?: ""
                    DeviceTranslation.prepare(code, { channel?.invokeMethod("translationDownload", it) }, result)
                }
                "translateOnDevice" -> {
                    DeviceTranslation.translate(call.argument<String>("text") ?: "",
                        call.argument<String>("source") ?: "", call.argument<String>("target") ?: "", result)
                }
                "privateScreen" -> {
                    if (call.argument<Boolean>("enabled") == true) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "pickPersonnelImage" -> picker.pick(call.argument<String>("kind") ?: "document", result)
                "prepareLanguage" -> {
                    val language = call.argument<String>("language") ?: ""
                    val locale = call.argument<String>("locale") ?: ""
                    if (!language.matches(Regex("[a-z]{2,3}")) || !locale.matches(Regex("[a-z]{2,3}-[A-Z]{2}"))) {
                        result.error("invalid_language", "Choose a supported language.", null)
                    } else if (!visible) { result.error("foreground_required", "Open the app to download a language.", null) }
                    else if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                        if (modelPermission != null) { result.error("permission_pending", "Finish the microphone permission request first.", null) }
                        else {
                            modelPermission = language to locale
                            channel?.invokeMethod("languageDownload", mapOf("language" to language, "phase" to "permission"))
                            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4403)
                            result.success(mapOf("phase" to "permission"))
                        }
                    } else { downloads?.request(language, locale); result.success(mapOf("phase" to "queued")) }
                }
                "installVoiceData" -> {
                    try {
                        val installer = Intent(android.speech.tts.TextToSpeech.Engine.ACTION_INSTALL_TTS_DATA)
                        NativeAudio.enginePackage()?.let { installer.setPackage(it) }
                        try { startActivity(installer) } catch (_: Exception) { startActivity(Intent("com.android.settings.TTS_SETTINGS")) }
                        refreshVoiceEngine = true
                        result.success(true)
                    }
                    catch (_: Exception) { result.error("installer_unavailable", "Open Voice settings, select your speech engine, then install its voice data.", null) }
                }
                "getCapabilities" -> NativeAudio.capabilities(result)
                "openVoiceSettings" -> {
                    try {
                        startActivity(Intent("com.android.settings.TTS_SETTINGS"))
                        refreshVoiceEngine = true
                        result.success(true)
                    } catch (_: Exception) {
                        result.error("settings_unavailable", "Open Android Settings and search for text-to-speech.", null)
                    }
                }
                "openSpeechSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
                        result.success(true)
                    } catch (_: Exception) {
                        result.error("settings_unavailable", "Open Android Settings and search for voice input.", null)
                    }
                }
                "startReceiving" -> {
                    if (!visible) {
                        result.error("foreground_required", "Enable receiving while the app is visible.", null)
                    } else if (permissionResult != null) {
                        result.error("permission_pending", "Notification permission is being requested.", null)
                    } else if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        permissionResult = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4401)
                    } else {
                        startReceiving(result)
                    }
                }
                "stopReceiving" -> {
                    stopService(Intent(this, ReceivingAudioService::class.java))
                    NativeAudio.stop("receiving_disabled")
                    result.success(true)
                }
                "speak" -> {
                    val text = call.argument<String>("text")
                    val language = call.argument<String>("language")
                    val messageId = call.argument<String>("messageId")
                    if (text.isNullOrBlank() || language.isNullOrBlank() || messageId.isNullOrBlank() || text.length > 4000 || messageId.length > 200) {
                        result.error("invalid_arguments", "Provide messageId, language and 1–4000 characters of text.", null)
                    } else if (!visible && !ReceivingAudioService.active) {
                        result.error("foreground_required", "Open the app to play this message.", null)
                    } else {
                        withPlaybackRequest(call, result) { requestId ->
                            withPlaybackDeadline(call, result) { deadline ->
                                NativeAudio.speak(messageId, text, language, call.argument<Boolean>("headphonesOnly") ?: false, result, deadline, requestId)
                            }
                        }
                    }
                }
                "playAudio" -> {
                    val url = call.argument<String>("url")
                    val messageId = call.argument<String>("messageId")
                    if (url.isNullOrBlank() || url.length > 4096 || messageId.isNullOrBlank() || messageId.length > 200) {
                        result.error("invalid_arguments", "Provide messageId and an authorized audio URL.", null)
                    } else if (!visible && !ReceivingAudioService.active) {
                        result.error("foreground_required", "Open the app to play this message.", null)
                    } else {
                        withPlaybackRequest(call, result) { requestId ->
                            withPlaybackDeadline(call, result) { deadline ->
                                NativeAudio.playAudio(messageId, url, call.argument<Boolean>("headphonesOnly") ?: false,
                                    call.argument<Map<String, String>>("headers") ?: emptyMap(), result, deadline, requestId)
                            }
                        }
                    }
                }
                "stopPlayback" -> { NativeAudio.stop("user_stopped"); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }

    private fun withPlaybackRequest(call: MethodCall, result: MethodChannel.Result, action: (String?) -> Unit) {
        if (!call.hasArgument("playbackRequestId")) {
            action(null)
            return
        }
        val requestId = PlaybackRequestPolicy.parse(call.argument<Any?>("playbackRequestId"))
        if (requestId == null) {
            result.error("invalid_playback_request_id", "playbackRequestId must contain 1–128 ASCII letters, digits, underscores or hyphens.", null)
        } else action(requestId)
    }

    private fun withPlaybackDeadline(call: MethodCall, result: MethodChannel.Result, action: (Long?) -> Unit) {
        if (!call.hasArgument("stopAtEpochMillis")) {
            action(null)
            return
        }
        val deadline = PlaybackDeadlinePolicy.parse(call.argument<Any?>("stopAtEpochMillis"))
        if (deadline == null) {
            result.error("invalid_playback_deadline", "stopAtEpochMillis must be a future integer epoch timestamp within 48 hours.", null)
        } else action(deadline)
    }

    private fun startReceiving(result: MethodChannel.Result) {
        try {
            val intent = Intent(this, ReceivingAudioService::class.java)
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
            result.success(mapOf("enabled" to true, "backgroundReceive" to false, "backgroundPlayback" to true,
                "note" to "Playback session only. Realtime delivery currently requires the running Flutter app."))
        } catch (_: Exception) {
            result.error("service_unavailable", "Android could not start the playback session. Open the app and try again.", null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4403) {
            val language = modelPermission; modelPermission = null
            if (language != null) {
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                    downloads?.request(language.first, language.second)
                    channel?.invokeMethod("languagePermissionGranted", mapOf("language" to language.first))
                } else channel?.invokeMethod("languageDownload", mapOf("language" to language.first, "phase" to "error", "message" to "Your speech service requires microphone permission to download its model. No recording starts during a download."))
            }
        }
        if (requestCode == 4401) {
            val result = permissionResult
            permissionResult = null
            if (result != null) {
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && visible) startReceiving(result)
                else result.error("notification_permission_required", "Receiving needs a visible persistent notification. Permission was not granted.", null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 4402) picker.returned(resultCode, data)
    }

    override fun onResume() {
        super.onResume(); visible = true
        if (refreshVoiceEngine) { refreshVoiceEngine = false; NativeAudio.refreshVoices(applicationContext) }
    }
    override fun onPause() {
        visible = false
        if (!ReceivingAudioService.active) NativeAudio.stop("app_backgrounded")
        super.onPause()
    }
    override fun onDestroy() {
        downloads?.close(); downloads = null; picker.close()
        permissionResult?.error("activity_closed", "The app was closed during the permission request.", null)
        permissionResult = null
        channel?.setMethodCallHandler(null)
        NativeAudio.events = null
        if (!ReceivingAudioService.active) NativeAudio.release()
        super.onDestroy()
    }
}
