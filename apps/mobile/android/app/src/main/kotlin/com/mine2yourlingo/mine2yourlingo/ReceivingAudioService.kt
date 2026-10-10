package com.mine2yourlingo.mine2yourlingo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/** Explicit, bounded playback session. Not a keep-alive or continuous network receiver. */
class ReceivingAudioService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val idleTimeout = Runnable { stopSelf() }
    private val sessionTimeout = Runnable { NativeAudio.stop("session_expired"); stopSelf() }

    companion object {
        private const val CHANNEL = "receiving_playback"
        private const val NOTIFICATION = 4402
        private const val STOP = "com.mine2yourlingo.STOP_RECEIVING"
        @Volatile var active = false
            private set
        private var instance: ReceivingAudioService? = null
        fun onPlaybackStarted() { instance?.main?.removeCallbacks(instance!!.idleTimeout) }
        fun onPlaybackEnded() { instance?.scheduleIdleTimeout() }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Voice playback session", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Visible controls for an explicitly enabled voice playback session"
                setSound(null, null)
            })
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, ReceivingAudioService::class.java).setAction(STOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Mine2YourLingo voice playback")
            .setContentText("Session enabled • open the app for incoming messages")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        else startForeground(NOTIFICATION, notification)
        active = true
        NativeAudio.initialize(applicationContext)
        scheduleIdleTimeout()
        main.postDelayed(sessionTimeout, 15 * 60 * 1000L)
    }

    private fun scheduleIdleTimeout() {
        main.removeCallbacks(idleTimeout)
        // Do not keep a mediaPlayback foreground service alive indefinitely without media.
        main.postDelayed(idleTimeout, 60 * 1000L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) { NativeAudio.stop("user_stopped_session"); stopSelf() }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        main.removeCallbacksAndMessages(null)
        instance = null; active = false
        NativeAudio.stop("receiving_session_ended")
        NativeAudio.events?.invoke("receivingStopped", mapOf("reason" to "session_ended"))
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (NativeAudio.events == null) NativeAudio.release()
        super.onDestroy()
    }
}
