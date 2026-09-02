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
import androidx.core.app.NotificationCompat

class FarmitraForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "farmitra_bg_service_channel"
        const val NOTIFICATION_ID = 43888
        const val ACTION_START_SERVICE = "ACTION_START_SERVICE"
        const val ACTION_STOP_SERVICE = "ACTION_STOP_SERVICE"
        const val ACTION_START_MEDIA_PROJECTION = "ACTION_START_MEDIA_PROJECTION"

        var isRunning = false
            private set
    }

    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP_SERVICE) {
            stopForegroundService()
            return START_NOT_STICKY
        }

        startForegroundService(withMediaProjection = true)
        return START_STICKY
    }

    private fun startForegroundService(withMediaProjection: Boolean = true) {
        createNotificationChannel()

        val notification = buildNotification()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                if (withMediaProjection && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                }
                startForeground(NOTIFICATION_ID, notification, serviceType)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isRunning = true
            acquireLocks()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun stopForegroundService() {
        releaseLocks()
        isRunning = false
        @Suppress("DEPRECATION")
        stopForeground(true)
        stopSelf()
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
            e.printStackTrace()
        }
    }

    private fun releaseLocks() {
        try {
            if (multicastLock?.isHeld == true) multicastLock?.release()
            if (wifiLock?.isHeld == true) wifiLock?.release()
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Farmitra Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Farmitra Nearby active to receive files, messages, and screen streams"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Farmitra Nearby Active")
            .setContentText("P2P Transfers, Calls & Screen Sharing Active")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }

    override fun onDestroy() {
        releaseLocks()
        isRunning = false
        super.onDestroy()
    }
}
