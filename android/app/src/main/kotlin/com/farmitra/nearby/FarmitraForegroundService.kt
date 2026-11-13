package com.farmitra.nearby

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine

class FarmitraForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "farmitra_bg_service_channel"
        const val NOTIFICATION_ID = 43888
        const val ACTION_START_SERVICE = "ACTION_START_SERVICE"
        const val ACTION_STOP_SERVICE = "ACTION_STOP_SERVICE"
        const val ACTION_WIRELESS_AUDIO = "ACTION_WIRELESS_AUDIO"
        const val ACTION_START_MEDIA_PROJECTION = "ACTION_START_MEDIA_PROJECTION"
        const val ACTION_PHONE_AUDIO = "ACTION_PHONE_AUDIO"
        const val ACTION_NOTIFICATION_REPLY = "com.farmitra.nearby.NOTIFICATION_REPLY"
        private const val TAG = "FarmitraService"

        var isRunning = false
            private set
    }

    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var networkingEngine: FlutterEngine? = null
    private val replyHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var replyExpiry: Runnable? = null
    private var replyOnly = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP_SERVICE) {
            stopForegroundService()
            return START_NOT_STICKY
        }
        // Reject cancelled audio starts before touching a temporary reply lease.
        val phoneAudioSession = intent?.getStringExtra("phone_audio_session")
        if (phoneAudioSession != null && !PhoneAudioRelay.acceptsServiceStart(phoneAudioSession)) {
            @Suppress("DEPRECATION")
            val receiver = intent.getParcelableExtra<android.os.ResultReceiver>("projectionReady")
            receiver?.send(0, null)
            if (!isRunning) stopSelf()
            return if (isRunning && NearbyEngineHost.backgroundEnabled(this)) START_STICKY else START_NOT_STICKY
        }
        if (action == ACTION_NOTIFICATION_REPLY && isRunning) {
            // Inbox events already wake the retained runtime. Do not change an
            // ongoing call/cast/audio service's notification or foreground type.
            if (replyOnly) armReplyExpiry()
            return if (NearbyEngineHost.backgroundEnabled(this)) START_STICKY else START_NOT_STICKY
        }
        if (action == ACTION_NOTIFICATION_REPLY && !NearbyEngineHost.backgroundEnabled(this)) {
            replyOnly = true
            armReplyExpiry()
        } else {
            replyExpiry?.let { replyHandler.removeCallbacks(it) }
            replyExpiry = null
            replyOnly = false
        }
        // A sticky restart may arrive without an Activity or Intent. Never
        // revive networking if the owner explicitly turned background mode OFF.
        if ((action == null || action == ACTION_START_SERVICE) &&
            !NearbyEngineHost.backgroundEnabled(this)) {
            stopForegroundService()
            return START_NOT_STICKY
        }
        val isMediaProjection = action == ACTION_START_MEDIA_PROJECTION || action == ACTION_PHONE_AUDIO
        val wirelessMode = if (action == ACTION_PHONE_AUDIO) "system" else if (action == ACTION_WIRELESS_AUDIO) {
            if (intent.getBooleanExtra("microphone", false)) "microphone" else "speaker"
        } else null
        var ready = startForegroundServiceNow(isMediaProjection, wirelessMode)
        if (ready) {
            try {
                // Reuse the visible engine, or bootstrap the same Dart runtime
                // after process death. Task removal never creates a second one.
                networkingEngine = NearbyEngineHost.forService(this)
            } catch (error: Exception) {
                Log.e(TAG, "Could not start networking runtime", error)
                ready = false
                stopForegroundService()
            }
        } else {
            stopSelf()
        }
        @Suppress("DEPRECATION")
        val receiver = intent?.getParcelableExtra<android.os.ResultReceiver>("projectionReady")
        receiver?.send(if (ready) 1 else 0, null)
        return if (ready && NearbyEngineHost.backgroundEnabled(this)) START_STICKY else START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Android may destroy FlutterActivity on a Recents swipe. The service
        // retains the engine, socket listeners and Dart timers independently.
        if (!NearbyEngineHost.backgroundEnabled(this) && !replyOnly) stopForegroundService()
        super.onTaskRemoved(rootIntent)
    }

    private fun startForegroundServiceNow(isMediaProjection: Boolean = false, wirelessMode: String? = null): Boolean {
        createNotificationChannel()
        val notification = buildNotification(isMediaProjection, wirelessMode)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val serviceType = if (isMediaProjection) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                } else if (wirelessMode == "microphone") {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                } else if (wirelessMode == "speaker") {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                } else {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                }
                startForeground(NOTIFICATION_ID, notification, serviceType)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isRunning = true
            acquireLocks()
            Log.d(TAG, "NearMitra background service started (mediaProjection=$isMediaProjection)")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service: ${e.message}", e)
            return false
        }
    }

    private fun stopForegroundService() {
        replyExpiry?.let { replyHandler.removeCallbacks(it) }
        replyExpiry = null
        replyOnly = false
        releaseLocks()
        isRunning = false
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
    }

    private fun armReplyExpiry() {
        replyExpiry?.let { replyHandler.removeCallbacks(it) }
        val expiry = Runnable {
            if (replyOnly && !NearbyEngineHost.backgroundEnabled(this)) stopForegroundService()
        }
        replyExpiry = expiry
        // A user-triggered reply may temporarily run with Background OFF, but
        // must not silently turn that preference into an indefinite service.
        replyHandler.postDelayed(expiry, 120000)
    }

    private fun acquireLocks() {
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            if (multicastLock == null && wifi != null) {
                multicastLock = wifi.createMulticastLock("farmitra-bg-multicast").apply {
                    setReferenceCounted(false)
                }
            }
            if (multicastLock?.isHeld != true) multicastLock?.acquire()

            if (wifiLock == null && wifi != null) {
                @Suppress("DEPRECATION")
                wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "farmitra-bg-wifilock")
            }
            if (wifiLock?.isHeld != true) wifiLock?.acquire()

            if (wakeLock == null) {
                val pm = applicationContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
                wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "farmitra-nearby:bgwakelock")
            }
            if (wakeLock?.isHeld != true) wakeLock?.acquire()
        } catch (e: Exception) {
            Log.e(TAG, "Error acquiring locks: ${e.message}", e)
        }
    }

    private fun releaseLocks() {
        try {
            if (multicastLock?.isHeld == true) multicastLock?.release()
            if (wifiLock?.isHeld == true) wifiLock?.release()
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing locks: ${e.message}", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "NearMitra Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps NearMitra active to receive calls, messages & streams"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(isMediaProjection: Boolean = false, wirelessMode: String? = null): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent ?: Intent(),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val title = when {
            wirelessMode == "system" -> "NearMitra Phone Audio Sharing"
            wirelessMode == "microphone" -> "NearMitra Wireless Microphone"
            wirelessMode == "speaker" -> "NearMitra Wireless Speaker"
            isMediaProjection -> "NearMitra Screen Casting Active"
            else -> if (replyOnly) "NearMitra Sending Reply" else "NearMitra Active"
        }
        val text = when (wirelessMode) {
            "system" -> "Sharing app audio only • Tap to open audio controls"
            "microphone" -> "Sharing microphone audio • Tap to open streaming controls"
            "speaker" -> "Receiving device audio • Tap to open streaming controls"
            else -> if (replyOnly) "Sending saved reply • Tap to open NearMitra" else if (isMediaProjection) "Broadcasting your phone screen to peer" else "P2P Transfers, Calls & Streams Active"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }

    override fun onDestroy() {
        replyExpiry?.let { replyHandler.removeCallbacks(it) }
        PhoneAudioRelay.stopForService()
        releaseLocks()
        isRunning = false
        networkingEngine = null
        NearbyEngineHost.releaseService(this)
        super.onDestroy()
    }
}
