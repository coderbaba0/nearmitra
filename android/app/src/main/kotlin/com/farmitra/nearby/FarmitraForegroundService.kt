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
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class FarmitraForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "farmitra_bg_service_channel"
        const val NOTIFICATION_ID = 43888
        const val ACTION_START_SERVICE = "ACTION_START_SERVICE"
        const val ACTION_STOP_SERVICE = "ACTION_STOP_SERVICE"
        const val ACTION_START_MEDIA_PROJECTION = "ACTION_START_MEDIA_PROJECTION"
        private const val TCP_PORT = 43889
        private const val TAG = "FarmitraService"

        var isRunning = false
            private set
    }

    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    // Native TCP socket listener for background/killed call reception
    private val tcpExecutor = Executors.newSingleThreadExecutor()
    private val isTcpRunning = AtomicBoolean(false)
    private var tcpServer: ServerSocket? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP_SERVICE) {
            stopForegroundService()
            return START_NOT_STICKY
        }
        startForegroundServiceNow()
        return START_STICKY
    }

    private fun startForegroundServiceNow() {
        createNotificationChannel()
        val notification = buildNotification()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    // Android 14+: add phoneCall + microphone types
                    serviceType = serviceType or
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                startForeground(NOTIFICATION_ID, notification, serviceType)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isRunning = true
            acquireLocks()
            startNativeTcpListener()
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service: ${e.message}", e)
        }
    }

    // ─── Native Kotlin TCP Listener ─────────────────────────────────────────────
    // Listens on port 43889 for call_invite packets and shows CallKit UI natively
    // Works even when Flutter Dart isolate is dead (app killed state)
    private fun startNativeTcpListener() {
        if (isTcpRunning.getAndSet(true)) return // Already running

        tcpExecutor.execute {
            try {
                // Reuse port so Dart ServerSocket can also bind if app is alive
                tcpServer = ServerSocket(TCP_PORT, 50, null).apply {
                    reuseAddress = true
                    soTimeout = 0 // Block indefinitely
                }
                Log.d(TAG, "[NativeTCP] Listening on port $TCP_PORT for incoming calls")

                while (isTcpRunning.get() && !tcpServer!!.isClosed) {
                    try {
                        val client: Socket = tcpServer!!.accept()
                        handleTcpClient(client)
                    } catch (e: Exception) {
                        if (isTcpRunning.get()) {
                            Log.w(TAG, "[NativeTCP] Accept error: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                // Port may already be bound by Dart — that's fine, Dart will handle it
                Log.w(TAG, "[NativeTCP] Could not bind port $TCP_PORT (Dart may own it): ${e.message}")
                isTcpRunning.set(false)
            }
        }
    }

    private fun handleTcpClient(socket: Socket) {
        Executors.newSingleThreadExecutor().execute {
            try {
                socket.soTimeout = 3000
                val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
                val line = reader.readLine() ?: return@execute

                val json = JSONObject(line)
                val type = json.optString("type")
                val sender = json.optString("sender", json.optString("name", "Nearby Device"))
                val senderId = json.optString("sender_id", json.optString("id", ""))
                val remoteIp = socket.inetAddress?.hostAddress ?: ""

                Log.d(TAG, "[NativeTCP] Received type=$type from $sender ($remoteIp)")

                if (type == "call_invite") {
                    val isVideo = json.optBoolean("is_video", false)
                    Log.d(TAG, "[NativeTCP] Incoming call from $sender — isVideo=$isVideo")
                    // Show CallKit incoming call notification natively from Kotlin
                    showNativeIncomingCall(
                        peerId = senderId.ifEmpty { remoteIp },
                        peerName = sender.ifEmpty { "Nearby Device" },
                        peerIp = remoteIp,
                        isVideo = isVideo
                    )
                }
                // All other packet types (chat, file, etc.) will be handled
                // by the Dart ServerSocket if app is alive, or ignored if not
            } catch (e: Exception) {
                Log.w(TAG, "[NativeTCP] Error handling client: ${e.message}")
            } finally {
                try { socket.close() } catch (_: Exception) {}
            }
        }
    }

    private fun showNativeIncomingCall(
        peerId: String,
        peerName: String,
        peerIp: String,
        isVideo: Boolean
    ) {
        try {
            // Send a broadcast that flutter_callkit_incoming plugin can intercept
            // Use the plugin's internal action to show the incoming call UI
            val callType = if (isVideo) 1 else 0
            val uuid = System.currentTimeMillis().toString()

            // Build the incoming call notification manually for background/killed state
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("call_incoming", true)
                putExtra("peer_id", peerId)
                putExtra("peer_name", peerName)
                putExtra("peer_ip", peerIp)
                putExtra("is_video", isVideo)
                putExtra("call_uuid", uuid)
            }

            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val fullScreenIntent = PendingIntent.getActivity(
                this, uuid.hashCode(), launchIntent ?: Intent(), pendingFlags
            )

            val callIcon = if (isVideo) android.R.drawable.ic_menu_camera
                           else android.R.drawable.sym_call_incoming

            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("Incoming ${if (isVideo) "Video" else "Audio"} Call")
                .setContentText("$peerName is calling via NearMitra")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setFullScreenIntent(fullScreenIntent, true)
                .setAutoCancel(true)
                .setOngoing(true)
                .setVibrate(longArrayOf(0, 500, 250, 500))
                .setLights(0xFF10B981.toInt(), 500, 500)
                .build()

            val manager = getSystemService(NotificationManager::class.java)
            val callNotifId = uuid.hashCode()
            manager?.notify(callNotifId, notification)

            Log.d(TAG, "[NativeTCP] Native call notification shown for $peerName")
        } catch (e: Exception) {
            Log.e(TAG, "[NativeTCP] Error showing native call: ${e.message}", e)
        }
    }

    private fun stopNativeTcpListener() {
        isTcpRunning.set(false)
        try {
            tcpServer?.close()
            tcpServer = null
        } catch (e: Exception) {
            Log.w(TAG, "Error closing TCP server: ${e.message}")
        }
    }
    // ─────────────────────────────────────────────────────────────────────────────

    private fun stopForegroundService() {
        stopNativeTcpListener()
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
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Keeps NearMitra active to receive calls, messages & streams"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)

            // Separate high-priority channel for incoming calls
            val callChannel = NotificationChannel(
                "farmitra_incoming_call",
                "NearMitra Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming call notifications from nearby peers"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 250, 500)
            }
            manager?.createNotificationChannel(callChannel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent ?: Intent(),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            else PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("NearMitra Active")
            .setContentText("P2P Transfers, Calls & Streams Active • Listening for calls")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .build()
    }

    override fun onDestroy() {
        stopNativeTcpListener()
        releaseLocks()
        isRunning = false
        super.onDestroy()
    }
}
