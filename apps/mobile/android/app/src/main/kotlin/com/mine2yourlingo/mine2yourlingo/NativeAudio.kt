package com.mine2yourlingo.mine2yourlingo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID
import java.io.File
import java.net.HttpURLConnection
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** On-device speech and bounded authenticated media fetch; never a microphone or network receiver. */
object NativeAudio {
    var events: ((String, Map<String, Any>) -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())
    private var context: Context? = null
    private var manager: AudioManager? = null
    private var tts: TextToSpeech? = null
    private var ready = false
    private var initializationFailed = false
    private var initializationGeneration = 0
    private var messageId: String? = null
    private var playbackRequestId: String? = null
    @Volatile private var utteranceToken: String? = null
    private var playbackDeadlineMillis: Long? = null
    private var deadlineTask: Runnable? = null
    private var player: MediaPlayer? = null
    private var mediaFile: File? = null
    private val downloads = Executors.newSingleThreadExecutor()
    private var downloadTask: Future<*>? = null
    @Volatile private var connection: HttpURLConnection? = null
    private var playbackStartedOnHeadphones = false
    private var headphonesRequired = false
    private var focusRequest: AudioFocusRequest? = null
    private val capabilityRequests = mutableListOf<MethodChannel.Result>()
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change != AudioManager.AUDIOFOCUS_GAIN) main.post { stop("audio_focus_lost") }
    }
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { stop("audio_route_changed") }
    }
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
            // Stop conservatively before any private speech can move to the speaker.
            if (playbackStartedOnHeadphones || headphonesRequired) stop("headphones_disconnected")
        }
    }

    fun initialize(appContext: Context) {
        if (tts != null) return
        context = appContext.applicationContext
        File(appContext.cacheDir, "voice-playback").listFiles()?.forEach { it.delete() }
        manager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        initializationFailed = false
        val generation = ++initializationGeneration
        if (Build.VERSION.SDK_INT >= 33) appContext.registerReceiver(noisyReceiver,
            IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), Context.RECEIVER_NOT_EXPORTED)
        else appContext.registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        manager?.registerAudioDeviceCallback(deviceCallback, main)
        tts = TextToSpeech(appContext) { status -> main.post {
            if (generation != initializationGeneration) return@post
            ready = status == TextToSpeech.SUCCESS
            initializationFailed = !ready
            if (ready) {
                tts?.setAudioAttributes(attributes)
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) { main.post {
                        if (utteranceToken == utteranceId && utteranceId != null && !stopIfDeadlineReached(utteranceId)) emit("playbackStarted", messageId, playbackRequestId)
                    } }
                    override fun onDone(utteranceId: String?) { main.post {
                        complete(utteranceId)
                    } }
                    @Deprecated("Android TTS compatibility callback")
                    override fun onError(utteranceId: String?) { main.post { fail(utteranceId, "tts_error") } }
                    override fun onError(utteranceId: String?, errorCode: Int) { main.post { fail(utteranceId, "tts_error_$errorCode") } }
                })
            }
            drainCapabilities()
        } }
        main.postDelayed({
            if (generation == initializationGeneration && !ready && !initializationFailed) { initializationFailed = true; drainCapabilities() }
        }, 8000)
    }

    private fun offlineVoices(): List<Voice> = if (ready) tts?.voices.orEmpty().filter {
        !it.isNetworkConnectionRequired && !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
    }.sortedBy { it.name } else emptyList()

    fun refreshVoices(appContext: Context) { release(); initialize(appContext) }

    fun enginePackage(): String? = tts?.defaultEngine

    fun capabilities(result: MethodChannel.Result) {
        if (!ready && !initializationFailed) capabilityRequests.add(result)
        else result.success(capabilityMap())
    }

    private fun drainCapabilities() {
        capabilityRequests.toList().forEach { it.success(capabilityMap()) }
        capabilityRequests.clear()
    }

    private fun capabilityMap(): Map<String, Any> = mapOf(
        "platform" to "android", "onDeviceTts" to ready,
        "remoteAudioPlayback" to true,
        "backgroundPlayback" to true, "backgroundReceive" to false,
        "receivingEnabled" to ReceivingAudioService.active,
        "headphonesConnected" to headphonesConnected(),
        "headphonesOnlySupported" to false,
        "voices" to offlineVoices().map { mapOf("identifier" to it.name, "language" to it.locale.toLanguageTag(), "offline" to true) },
        "note" to "An explicit playback session supports already-delivered speech; no native background network receiver is implemented."
    )

    fun headphonesConnected(): Boolean = manager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)?.any {
        it.type in setOf(AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_HEARING_AID,
            AudioDeviceInfo.TYPE_BLE_HEADSET)
    } ?: false

    fun speak(id: String, text: String, language: String, onlyHeadphones: Boolean, result: MethodChannel.Result, stopAtEpochMillis: Long? = null, requestId: String? = null) {
        if (rejectRequestId(requestId, result)) return
        if (rejectDeadline(stopAtEpochMillis, result)) return
        if (!ready) { result.error("tts_unavailable", "On-device speech is unavailable or still initializing.", null); return }
        val policy = policyError(onlyHeadphones)
        if (policy != null) { result.error(policy.first, policy.second, null); return }
        val locale = Locale.forLanguageTag(language)
        if (locale.language.isBlank() || locale.language == "und") {
            result.error("unsupported_language", "Use a valid BCP-47 language code.", null); return
        }
        val voice = offlineVoices().firstOrNull { it.locale.toLanguageTag().equals(locale.toLanguageTag(), true) }
            ?: offlineVoices().firstOrNull { it.locale.language == locale.language }
        if (voice == null) { result.error("voice_unavailable", "Install an offline voice for $language in Android speech settings.", null); return }
        stop("replaced_by_new_playback")
        if (!obtainFocus()) { result.error("audio_focus_denied", "Audio is busy. Replay when the current call or audio session ends.", null); return }
        if (tts?.setVoice(voice) != TextToSpeech.SUCCESS) {
            abandonFocus(); result.error("voice_unavailable", "Android could not select the installed offline voice.", null); return
        }
        messageId = id
        playbackRequestId = requestId
        val token = UUID.randomUUID().toString()
        utteranceToken = token
        if (!bindDeadline(token, stopAtEpochMillis)) {
            result.error("quiet_hours_started", "Playback stopped because quiet hours have started.", null); return
        }
        headphonesRequired = onlyHeadphones
        playbackStartedOnHeadphones = headphonesConnected()
        ReceivingAudioService.onPlaybackStarted()
        val params = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f) }
        if (tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, token) != TextToSpeech.SUCCESS) {
            fail(token, "tts_start_failed")
            result.error("tts_start_failed", "Android could not start speech playback.", null)
        } else result.success(true)
    }

    private fun policyError(onlyHeadphones: Boolean): Pair<String, String>? {
        if (manager?.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
            return "device_silent" to "The device is in silent or vibrate mode. Replay after changing audio settings."
        }
        val notifications = context?.getSystemService(NotificationManager::class.java)
        if (notifications?.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL) {
            return "do_not_disturb" to "Do not disturb is active. Replay after changing device audio settings."
        }
        if (onlyHeadphones) {
            // getDevices is output inventory, not the currently selected media route.
            return "private_route_unverified" to "The active private headphone route is unverified. Read the transcript; strict headphone playback requires device-tested routing support."
        }
        return null
    }

    private fun obtainFocus(): Boolean {
        val audioManager = manager ?: return false
        val focus = try { if (Build.VERSION.SDK_INT >= 26) {
            focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attributes).setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(focusListener, main).build()
            audioManager.requestAudioFocus(focusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        } } catch (_: Exception) { AudioManager.AUDIOFOCUS_REQUEST_FAILED }
        if (focus != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            abandonFocus(); return false
        }
        return true
    }

    fun playAudio(id: String, url: String, onlyHeadphones: Boolean, headers: Map<String, String>, result: MethodChannel.Result, stopAtEpochMillis: Long? = null, requestId: String? = null) {
        if (rejectRequestId(requestId, result)) return
        if (rejectDeadline(stopAtEpochMillis, result)) return
        val appContext = context ?: return result.error("audio_unavailable", "Audio service is unavailable.", null)
        val debug = appContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        val uri = runCatching { AudioDownloadPolicy.validateUrl(url, debug) }.getOrNull()
        if (uri == null) {
            result.error("insecure_audio_url", "Use an authorized HTTPS audio URL; HTTP is permitted only for a local Wi-Fi debug review.", null); return
        }
        val policy = policyError(onlyHeadphones)
        if (policy != null) { result.error(policy.first, policy.second, null); return }
        stop("replaced_by_new_playback")
        messageId = id
        playbackRequestId = requestId
        val token = UUID.randomUUID().toString()
        utteranceToken = token
        if (!bindDeadline(token, stopAtEpochMillis)) {
            result.error("quiet_hours_started", "Playback stopped because quiet hours have started.", null); return
        }
        headphonesRequired = onlyHeadphones
        playbackStartedOnHeadphones = headphonesConnected()
        ReceivingAudioService.onPlaybackStarted()
        val directory = File(appContext.cacheDir, "voice-playback").apply { mkdirs() }
        val file = try { File.createTempFile("audio-", ".bin", directory) } catch (_: Exception) {
            fail(token, "audio_storage_unavailable"); result.error("audio_storage_unavailable", "Temporary audio storage is unavailable.", null); return
        }
        mediaFile = file
        downloadTask = downloads.submit {
            var request: HttpURLConnection? = null
            try {
                if (utteranceToken != token || PlaybackDeadlinePolicy.expired(stopAtEpochMillis)) {
                    file.delete(); main.post { stopIfDeadlineReached(token) }; return@submit
                }
                request = AudioDownloadPolicy.open(uri, headers)
                connection = request
                if (request.responseCode != 200 || request.contentLengthLong > AudioDownloadPolicy.MAX_BYTES ||
                    !(request.contentType ?: "").lowercase().startsWith("audio/")) throw IllegalStateException("Invalid audio response")
                request.inputStream.use { input -> file.outputStream().use { output ->
                    AudioDownloadPolicy.copyBounded(input, output) {
                        utteranceToken != token || PlaybackDeadlinePolicy.expired(stopAtEpochMillis)
                    }
                } }
                main.post {
                    if (utteranceToken != token) { file.delete(); return@post }
                    if (stopIfDeadlineReached(token)) return@post
                    val changedPolicy = policyError(onlyHeadphones)
                    if (changedPolicy != null) { fail(token, changedPolicy.first); return@post }
                    if (!obtainFocus()) { fail(token, "audio_focus_denied"); return@post }
                    try {
                        val media = MediaPlayer()
                        player = media
                        media.setAudioAttributes(attributes)
                        media.setOnPreparedListener {
                            if (utteranceToken == token && !stopIfDeadlineReached(token)) {
                                try { it.start(); emit("playbackStarted", id, requestId) }
                                catch (_: Exception) { fail(token, "audio_start_failed") }
                            }
                        }
                        media.setOnCompletionListener { complete(token) }
                        media.setOnErrorListener { _, _, _ -> fail(token, "audio_decode_failed"); true }
                        media.setDataSource(file.absolutePath)
                        media.prepareAsync()
                    } catch (_: Exception) { fail(token, "audio_decode_failed") }
                }
            } catch (_: Exception) {
                file.delete()
                main.post { fail(token, "audio_download_failed") }
            } finally {
                request?.disconnect()
                if (connection === request) connection = null
            }
        }
        result.success(true)
    }

    private fun rejectRequestId(requestId: String?, result: MethodChannel.Result): Boolean {
        if (requestId == null || PlaybackRequestPolicy.valid(requestId)) return false
        result.error("invalid_playback_request_id", "playbackRequestId must contain 1–128 ASCII letters, digits, underscores or hyphens.", null)
        return true
    }

    private fun rejectDeadline(deadline: Long?, result: MethodChannel.Result): Boolean {
        val error = PlaybackDeadlinePolicy.error(deadline) ?: return false
        val explanation = if (error == "quiet_hours_started") "Playback was rejected because quiet hours have started."
            else "stopAtEpochMillis must be a future integer epoch timestamp within 48 hours."
        result.error(error, explanation, null)
        return true
    }

    private fun bindDeadline(token: String, deadline: Long?): Boolean {
        cancelDeadline()
        playbackDeadlineMillis = deadline
        if (deadline == null) return true
        if (stopIfDeadlineReached(token)) return false
        val task = object : Runnable {
            override fun run() {
                // A replaced/replayed message may have the same ID; only its unique token owns this timer.
                if (utteranceToken != token || deadlineTask !== this) return
                if (stopIfDeadlineReached(token)) return
                val remaining = deadline - System.currentTimeMillis()
                main.postDelayed(this, remaining.coerceAtLeast(1).coerceAtMost(PlaybackDeadlinePolicy.MAX_AHEAD_MILLIS))
            }
        }
        deadlineTask = task
        main.postDelayed(task, (deadline - System.currentTimeMillis()).coerceAtLeast(1))
        return true
    }

    private fun stopIfDeadlineReached(token: String?): Boolean {
        if (token == null || utteranceToken != token || !PlaybackDeadlinePolicy.expired(playbackDeadlineMillis)) return false
        stop("quiet_hours_started")
        return true
    }

    private fun cancelDeadline() {
        deadlineTask?.let { main.removeCallbacks(it) }
        deadlineTask = null
        playbackDeadlineMillis = null
    }

    private fun cleanupMedia() {
        downloadTask?.cancel(true); downloadTask = null
        connection?.disconnect(); connection = null
        player?.release(); player = null
        mediaFile?.delete(); mediaFile = null
    }

    private fun complete(token: String?) {
        if (token != null && token == utteranceToken) {
            if (stopIfDeadlineReached(token)) return
            cancelDeadline()
            val id = messageId
            val requestId = playbackRequestId
            messageId = null; playbackRequestId = null; utteranceToken = null
            cleanupMedia(); abandonFocus()
            emit("playbackCompleted", id, requestId); ReceivingAudioService.onPlaybackEnded()
        }
    }

    private fun fail(token: String?, reason: String) {
        if (token != null && token == utteranceToken) {
            if (stopIfDeadlineReached(token)) return
            cancelDeadline()
            val id = messageId
            val requestId = playbackRequestId
            messageId = null; playbackRequestId = null; utteranceToken = null
            cleanupMedia(); abandonFocus(); emit("playbackError", id, requestId, reason); ReceivingAudioService.onPlaybackEnded()
        }
    }

    fun stop(reason: String) {
        cancelDeadline()
        val id = messageId
        val requestId = playbackRequestId
        messageId = null
        playbackRequestId = null
        utteranceToken = null
        tts?.stop()
        cleanupMedia()
        abandonFocus()
        headphonesRequired = false
        playbackStartedOnHeadphones = false
        if (id != null) emit("playbackError", id, requestId, reason)
        ReceivingAudioService.onPlaybackEnded()
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= 26) focusRequest?.let { manager?.abandonAudioFocusRequest(it) }
        else { @Suppress("DEPRECATION") manager?.abandonAudioFocus(focusListener) }
        focusRequest = null
    }

    private fun emit(event: String, id: String?, requestId: String?, reason: String? = null) {
        if (id == null) return
        val payload = mutableMapOf<String, Any>("messageId" to id)
        if (requestId != null) payload["playbackRequestId"] = requestId
        if (reason != null) payload["reason"] = reason
        events?.invoke(event, payload)
    }

    fun release() {
        stop("audio_session_closed")
        initializationGeneration++
        tts?.shutdown(); tts = null; ready = false; initializationFailed = true
        drainCapabilities()
        manager?.unregisterAudioDeviceCallback(deviceCallback)
        context?.let { runCatching { it.unregisterReceiver(noisyReceiver) } }
        context = null; manager = null
    }
}
