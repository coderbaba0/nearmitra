package com.farmitra.nearby

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Application-context engine and channels; never keep a destroyed Activity's handlers. */
internal object NearbyEngineHost {
    private const val NETWORK_CHANNEL = "farmitra_nearby/network"
    private const val P2P_CHANNEL = "farmitra_nearby/wifi_p2p"
    private const val P2P_EVENTS = "farmitra_nearby/wifi_p2p_events"
    private const val RUNTIME_CHANNEL = "farmitra_nearby/runtime"
    private var store: RuntimeEngineStore<FlutterEngine>? = null
    var p2pEventSink: EventChannel.EventSink? = null
        private set
    var onP2pListen: (() -> Unit)? = null

    // The legacy shared_preferences API uses this Android file/key. Read the
    // same setting Dart writes, so an OFF choice also survives a process restart.
    fun backgroundEnabled(context: Context): Boolean = context.applicationContext
        .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        .getBoolean("flutter.background_service_enabled", true)

    fun forActivity(activity: MainActivity): FlutterEngine =
        engineStore(activity).acquireActivity(activity)

    fun forService(service: FarmitraForegroundService): FlutterEngine =
        engineStore(service).acquireService(service)

    fun activityAttached(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, RUNTIME_CHANNEL).invokeMethod("attachUi", null)
    }

    fun releaseActivity(activity: MainActivity, engine: FlutterEngine) {
        val owner = store ?: return
        if (!owner.ownsActivity(activity)) return
        onP2pListen = null
        installBackgroundChannels(activity.applicationContext, engine)
        // FlutterActivity still needs its engine while completing onDetach.
        // Destroy an unused engine only after that callback has returned.
        Handler(Looper.getMainLooper()).post { owner.releaseActivity(activity) }
    }

    fun releaseService(service: FarmitraForegroundService) {
        store?.releaseService(service)
    }

    private fun engineStore(context: Context): RuntimeEngineStore<FlutterEngine> {
        store?.let { return it }
        val app = context.applicationContext
        return RuntimeEngineStore<FlutterEngine>(create = { background ->
            // FlutterEngine auto-registers the generated plugins once, using
            // Application context. MainActivity later attaches Activity plugins.
            val engine = FlutterEngine(app)
            installBackgroundChannels(app, engine)
            PhoneAudioRelay.install(engine, app)
            MethodChannel(engine.dartExecutor.binaryMessenger, RUNTIME_CHANNEL)
                .setMethodCallHandler { call, result ->
                    if (call.method == "hasActivity") result.success(store?.hasActivity == true)
                    else result.notImplemented()
                }
            EventChannel(engine.dartExecutor.binaryMessenger, P2P_EVENTS)
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        p2pEventSink = events
                        onP2pListen?.invoke()
                    }
                    override fun onCancel(arguments: Any?) { p2pEventSink = null }
                })
            engine.navigationChannel.setInitialRoute("/")
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
                if (background) listOf("--background") else emptyList()
            )
            engine
        }, destroy = { engine ->
            PhoneAudioRelay.shutdown()
            onP2pListen = null
            p2pEventSink = null
            engine.destroy()
        }).also { store = it }
    }

    private fun installBackgroundChannels(app: Context, engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, NETWORK_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startForegroundService" -> {
                        if (!backgroundEnabled(app)) {
                            result.success(false)
                        } else {
                            val intent = Intent(app, FarmitraForegroundService::class.java).apply {
                                action = FarmitraForegroundService.ACTION_START_SERVICE
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) app.startForegroundService(intent)
                            else app.startService(intent)
                            result.success(true)
                        }
                    }
                    "stopForegroundService" -> {
                        app.stopService(Intent(app, FarmitraForegroundService::class.java))
                        result.success(true)
                    }
                    "stopWirelessAudioService", "stopMediaProjectionService" -> {
                        if (backgroundEnabled(app)) {
                            app.startService(Intent(app, FarmitraForegroundService::class.java).apply {
                                action = FarmitraForegroundService.ACTION_START_SERVICE
                            })
                        } else app.stopService(Intent(app, FarmitraForegroundService::class.java))
                        result.success(true)
                    }
                    "isForegroundServiceRunning", "acquireMulticastLock" ->
                        result.success(FarmitraForegroundService.isRunning)
                    // The service owns the background locks until it stops.
                    "releaseMulticastLock" -> result.success(true)
                    "getInitialSharedFiles" -> result.success(emptyList<String>())
                    "clearInitialSharedFiles", "getPendingCallEvent" -> result.success(null)
                    "moveTaskToBackground" -> result.success(false)
                    else -> result.error("ACTIVITY_UNAVAILABLE", "Open NearMitra to use this control", null)
                }
            } catch (error: Exception) {
                result.error("BACKGROUND_RUNTIME", error.message, null)
            }
        }
        MethodChannel(messenger, P2P_CHANNEL).setMethodCallHandler { _, result ->
            result.error("ACTIVITY_UNAVAILABLE", "Open NearMitra to manage Wi-Fi Direct", null)
        }
    }
}
