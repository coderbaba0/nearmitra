package com.farmitra.nearby

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.NetworkInfo
import android.net.wifi.WifiManager
import android.net.wifi.p2p.*
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface

class MainActivity : FlutterActivity() {
    private val networkChannelName = "farmitra_nearby/network"
    private val p2pMethodChannelName = "farmitra_nearby/wifi_p2p"
    private val p2pEventChannelName = "farmitra_nearby/wifi_p2p_events"

    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: android.os.PowerManager.WakeLock? = null
    private var p2pManager: WifiP2pManager? = null
    private var p2pChannel: WifiP2pManager.Channel? = null
    private var p2pReceiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null

    private var isP2pEnabled = false
    private var isConnected = false
    private var isGroupOwner = false
    private var groupOwnerIp: String? = null
    private var localP2pIp: String? = null

    private var initialSharedFiles = mutableListOf<String>()
    private var flutterEngineInstance: FlutterEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngineInstance = flutterEngine
        handleSendIntent(intent)

        // Multicast & Background Network Lock Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    try {
                        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                        if (multicastLock == null) {
                            multicastLock = wifi.createMulticastLock("farmitra-nearby-multicast").apply {
                                setReferenceCounted(true)
                            }
                        }
                        if (multicastLock?.isHeld != true) multicastLock?.acquire()

                        if (wifiLock == null) {
                            @Suppress("DEPRECATION")
                            wifiLock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "farmitra-nearby-wifilock")
                        }
                        if (wifiLock?.isHeld != true) wifiLock?.acquire()

                        if (wakeLock == null) {
                            val pm = applicationContext.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                            wakeLock = pm.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "farmitra-nearby:wakelock")
                        }
                        if (wakeLock?.isHeld != true) wakeLock?.acquire()

                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MULTICAST_LOCK", e.message, null)
                    }
                }
                "releaseMulticastLock" -> {
                    try {
                        if (multicastLock?.isHeld == true) multicastLock?.release()
                        if (wifiLock?.isHeld == true) wifiLock?.release()
                        if (wakeLock?.isHeld == true) wakeLock?.release()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("MULTICAST_UNLOCK", e.message, null)
                    }
                }
                "startForegroundService" -> {
                    try {
                        val intent = Intent(applicationContext, FarmitraForegroundService::class.java).apply {
                            action = FarmitraForegroundService.ACTION_START_SERVICE
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            applicationContext.startForegroundService(intent)
                        } else {
                            applicationContext.startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_START_ERR", e.message, null)
                    }
                }
                "startMediaProjectionService" -> {
                    try {
                        val intent = Intent(applicationContext, FarmitraForegroundService::class.java).apply {
                            action = FarmitraForegroundService.ACTION_START_MEDIA_PROJECTION
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            applicationContext.startForegroundService(intent)
                        } else {
                            applicationContext.startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_START_ERR", e.message, null)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        val intent = Intent(applicationContext, FarmitraForegroundService::class.java).apply {
                            action = FarmitraForegroundService.ACTION_STOP_SERVICE
                        }
                        applicationContext.startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_STOP_ERR", e.message, null)
                    }
                }
                "isForegroundServiceRunning" -> {
                    result.success(FarmitraForegroundService.isRunning)
                }
                "enterPipMode" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val aspectRatio = android.util.Rational(9, 16)
                            val params = android.app.PictureInPictureParams.Builder()
                                .setAspectRatio(aspectRatio)
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "isPipSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    result.success(supported)
                }
                "minimizeApp" -> {
                    try {
                        moveTaskToBack(true)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getInitialSharedFiles" -> {
                    val list = ArrayList(initialSharedFiles)
                    initialSharedFiles.clear()
                    result.success(list)
                }
                "clearSharedFiles" -> {
                    initialSharedFiles.clear()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Wi-Fi Direct MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, p2pMethodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "initP2p" -> {
                    initWifiP2p()
                    result.success(true)
                }
                "discoverPeers" -> {
                    if (p2pManager != null && p2pChannel != null) {
                        try {
                            p2pManager?.stopPeerDiscovery(p2pChannel, null)
                            p2pManager?.discoverPeers(p2pChannel, object : WifiP2pManager.ActionListener {
                                override fun onSuccess() {
                                    Log.d("FarmitraP2P", "[P2P DEBUG] discovery started successfully")
                                    result.success(true)
                                }
                                override fun onFailure(reason: Int) {
                                    Log.d("FarmitraP2P", "[P2P DEBUG] discovery failed code: $reason. Retrying...")
                                    result.success(false)
                                }
                            })
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        initWifiP2p()
                        result.success(false)
                    }
                }
                "stopPeerDiscovery" -> {
                    try {
                        p2pManager?.stopPeerDiscovery(p2pChannel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() { result.success(true) }
                            override fun onFailure(reason: Int) { result.success(false) }
                        })
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "connectP2p" -> {
                    val address = call.argument<String>("deviceAddress")
                    if (address != null && p2pManager != null && p2pChannel != null) {
                        val config = WifiP2pConfig().apply {
                            deviceAddress = address
                        }
                        Log.d("FarmitraP2P", "[P2P DEBUG] connection requested to $address")
                        try {
                            p2pManager?.connect(p2pChannel, config, object : WifiP2pManager.ActionListener {
                                override fun onSuccess() {
                                    result.success(true)
                                }
                                override fun onFailure(reason: Int) {
                                    Log.d("FarmitraP2P", "[P2P DEBUG] connect failed: $reason")
                                    result.success(false)
                                }
                            })
                        } catch (e: Exception) {
                            result.error("CONNECT_ERR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ADDR", "Device address missing or P2P uninitialized", null)
                    }
                }
                "disconnectP2p" -> {
                    try {
                        p2pManager?.removeGroup(p2pChannel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() {
                                isConnected = false
                                result.success(true)
                            }
                            override fun onFailure(reason: Int) { result.success(false) }
                        })
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "requestConnectionInfo" -> {
                    val infoMap = mapOf(
                        "connected" to isConnected,
                        "isGroupOwner" to isGroupOwner,
                        "groupOwnerIp" to (groupOwnerIp ?: ""),
                        "localIp" to (findLocalP2pIp() ?: "")
                    )
                    result.success(infoMap)
                }
                "getLocalP2pIp" -> {
                    result.success(findLocalP2pIp() ?: "")
                }
                "isWifiEnabled" -> {
                    result.success(checkIsWifiEnabled())
                }
                "isLocationEnabled" -> {
                    try {
                        val locationManager = getSystemService(Context.LOCATION_SERVICE) as? android.location.LocationManager
                        val isGpsEnabled = locationManager?.isProviderEnabled(android.location.LocationManager.GPS_PROVIDER) == true ||
                                           locationManager?.isProviderEnabled(android.location.LocationManager.NETWORK_PROVIDER) == true
                        result.success(isGpsEnabled)
                    } catch (e: Exception) {
                        result.success(true)
                    }
                }
                "openWifiSettings" -> {
                    try {
                        val intent = Intent(android.provider.Settings.ACTION_WIFI_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                            @Suppress("DEPRECATION")
                            wifi?.isWifiEnabled = true
                            result.success(true)
                        } catch (ex: Exception) {
                            result.success(false)
                        }
                    }
                }
                "openLocationSettings" -> {
                    try {
                        val intent = Intent(android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "openFolder" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        result.success(openFolderNative(path))
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()

            }
        }


        // Wi-Fi Direct EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, p2pEventChannelName).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                initWifiP2p()
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun checkIsWifiEnabled(): Boolean {
        return try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            wifi?.isWifiEnabled == true
        } catch (_: Exception) {
            isP2pEnabled
        }
    }

    private fun initWifiP2p() {
        if (p2pManager == null) {
            p2pManager = getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
            p2pChannel = p2pManager?.initialize(this, mainLooper, null)
        }

        isP2pEnabled = checkIsWifiEnabled()
        sendEvent(mapOf("event" to "state_changed", "enabled" to isP2pEnabled))


        if (p2pReceiver == null && p2pManager != null) {
            val intentFilter = IntentFilter().apply {
                addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
                addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
            }

            p2pReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    when (intent?.action) {
                        WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                            val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                            isP2pEnabled = (state == WifiP2pManager.WIFI_P2P_STATE_ENABLED)
                            Log.d("FarmitraP2P", "[P2P DEBUG] P2P enabled: $isP2pEnabled")
                            sendEvent(mapOf("event" to "state_changed", "enabled" to isP2pEnabled))
                        }
                        WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                            try {
                                p2pManager?.requestPeers(p2pChannel) { peerList ->
                                    val peersList = peerList.deviceList.map { device ->
                                        mapOf(
                                            "name" to device.deviceName,
                                            "address" to device.deviceAddress,
                                            "status" to device.status,
                                            "primaryDeviceType" to (device.primaryDeviceType ?: "")
                                        )
                                    }
                                    Log.d("FarmitraP2P", "[P2P DEBUG] peer found count: ${peersList.size}")
                                    sendEvent(mapOf("event" to "peers_changed", "peers" to peersList))
                                }
                            } catch (e: Exception) {
                                Log.e("FarmitraP2P", "Error requesting peers", e)
                            }
                        }
                        WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                            @Suppress("DEPRECATION")
                            val networkInfo = intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                            if (networkInfo?.isConnected == true) {
                                isConnected = true
                                try {
                                    p2pManager?.requestConnectionInfo(p2pChannel) { info ->
                                        isGroupOwner = info.isGroupOwner
                                        groupOwnerIp = info.groupOwnerAddress?.hostAddress
                                        localP2pIp = findLocalP2pIp()
                                        Log.d("FarmitraP2P", "[P2P DEBUG] connected. groupOwner: $isGroupOwner, GO IP: $groupOwnerIp, Local IP: $localP2pIp")
                                        sendEvent(mapOf(
                                            "event" to "connection_changed",
                                            "connected" to true,
                                            "isGroupOwner" to isGroupOwner,
                                            "groupOwnerIp" to (groupOwnerIp ?: ""),
                                            "localIp" to (localP2pIp ?: "")
                                        ))
                                    }
                                } catch (e: Exception) {
                                    Log.e("FarmitraP2P", "Error requesting connection info", e)
                                }
                            } else {
                                isConnected = false
                                groupOwnerIp = null
                                localP2pIp = null
                                Log.d("FarmitraP2P", "[P2P DEBUG] disconnected")
                                sendEvent(mapOf("event" to "connection_changed", "connected" to false))
                            }
                        }
                        WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                            @Suppress("DEPRECATION")
                            val device = intent.getParcelableExtra<WifiP2pDevice>(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                            if (device != null) {
                                sendEvent(mapOf(
                                    "event" to "this_device_changed",
                                    "name" to device.deviceName,
                                    "address" to device.deviceAddress
                                ))
                            }
                        }
                    }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(p2pReceiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(p2pReceiver, intentFilter)
            }
        }
    }

    private fun findLocalP2pIp(): String? {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val iface = interfaces.nextElement()
                if (iface.name.contains("p2p") || iface.name.contains("wlan")) {
                    val addrs = iface.inetAddresses
                    while (addrs.hasMoreElements()) {
                        val addr = addrs.nextElement()
                        if (!addr.isLoopbackAddress && addr is Inet4Address) {
                            val host = addr.hostAddress
                            if (host.startsWith("192.168.49.") || host.startsWith("192.168.")) {
                                return host
                            }
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    private fun sendEvent(data: Map<String, Any?>) {
        runOnUiThread {
            try {
                eventSink?.success(data)
            } catch (e: Exception) {
                Log.e("FarmitraP2P", "Error sending P2P event to Flutter", e)
            }
        }
    }

    private fun openFolderNative(folderPath: String): Boolean {
        try {
            val file = java.io.File(folderPath)
            if (file.exists()) {
                val uri = androidx.core.content.FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    file
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "resource/folder")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return true
            }
        } catch (_: Exception) {}

        try {
            val intent = Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return true
        } catch (_: Exception) {}

        try {
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                val file = java.io.File(folderPath)
                val uri = android.net.Uri.fromFile(file)
                setDataAndType(uri, "*/*")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return true
        } catch (_: Exception) {}

        return false
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSendIntent(intent)
    }

    private fun handleSendIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type ?: return

        val paths = mutableListOf<String>()

        if (Intent.ACTION_SEND == action) {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, android.net.Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            if (uri != null) {
                resolveUriToPath(uri)?.let { paths.add(it) }
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action) {
            val uris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, android.net.Uri::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
            uris?.forEach { uri ->
                resolveUriToPath(uri)?.let { paths.add(it) }
            }
        }

        if (paths.isNotEmpty()) {
            initialSharedFiles.addAll(paths)
            flutterEngineInstance?.dartExecutor?.binaryMessenger?.let { messenger ->
                runOnUiThread {
                    MethodChannel(messenger, networkChannelName).invokeMethod("onSharedFilesReceived", paths)
                }
            }
        }
    }

    private fun resolveUriToPath(uri: android.net.Uri): String? {
        if (uri.scheme == "file") {
            return uri.path
        }
        if (uri.scheme == "content") {
            try {
                val returnCursor = contentResolver.query(uri, null, null, null, null)
                val nameIndex = returnCursor?.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME) ?: -1
                var fileName = "shared_${System.currentTimeMillis()}"
                if (returnCursor != null && returnCursor.moveToFirst() && nameIndex != -1) {
                    fileName = returnCursor.getString(nameIndex) ?: fileName
                    returnCursor.close()
                }

                val cacheDir = java.io.File(cacheDir, "shared_incoming").apply { mkdirs() }
                val cacheFile = java.io.File(cacheDir, fileName)
                contentResolver.openInputStream(uri)?.use { input ->
                    java.io.FileOutputStream(cacheFile).use { output ->
                        input.copyTo(output)
                    }
                }
                return cacheFile.absolutePath
            } catch (e: Exception) {
                Log.e("FarmitraShare", "Error resolving shared URI: $e")
            }
        }
        return null
    }

    override fun onDestroy() {
        try {
            if (p2pReceiver != null) {
                unregisterReceiver(p2pReceiver)
                p2pReceiver = null
            }
            if (multicastLock?.isHeld == true) multicastLock?.release()
            if (wifiLock?.isHeld == true) wifiLock?.release()
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}

