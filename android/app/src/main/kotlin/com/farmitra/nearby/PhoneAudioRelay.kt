package com.farmitra.nearby

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.*
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.*
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.DataInputStream
import java.io.DataOutputStream
import java.lang.ref.WeakReference
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread
import kotlin.math.max

/** Android app playback capture. Audio bytes never pass through Flutter's UI isolate. */
internal object PhoneAudioRelay {
    private const val REQUEST_CAPTURE = 43891
    private val main = Handler(Looper.getMainLooper())
    private var activity = WeakReference<Activity>(null)
    private var events: EventChannel.EventSink? = null
    @Volatile private var current: State? = null
    private var pending: Pending? = null

    private class State(val id: String, val sending: Boolean, val peerIp: String = "") {
        val closed = AtomicBoolean(false)
        @Volatile var record: AudioRecord? = null
        @Volatile var projection: MediaProjection? = null
        @Volatile var track: AudioTrack? = null
        @Volatile var server: ServerSocket? = null
        @Volatile var socket: Socket? = null
        var volume = 1f
        var lastLevel = 0L
        @Volatile var lastProgress = 0L
        var watchdog: Runnable? = null
    }
    private class Pending(val state: State, val owner: Activity, val result: MethodChannel.Result)

    fun attachActivity(owner: Activity) { activity = WeakReference(owner) }
    fun detachActivity(owner: Activity) {
        if (activity.get() !== owner) return
        activity.clear()
        pending?.takeIf { it.owner === owner }?.let { finish(it.state, "Audio consent was interrupted") }
    }

    fun install(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        EventChannel(engine.dartExecutor.binaryMessenger, "farmitra_nearby/phone_audio_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { events = sink }
                override fun onCancel(arguments: Any?) { events = null }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "farmitra_nearby/phone_audio")
            .setMethodCallHandler { call, result ->
                try {
                    val id = call.argument<String>("id") ?: ""
                    when (call.method) {
                        "canCapture" -> result.success(Build.VERSION.SDK_INT >= 29)
                        "prepareCapture" -> prepare(app, id, result)
                        "receive" -> receive(app, id, call.argument<String>("peerIp") ?: "", result)
                        "send" -> {
                            val s = requireState(id)
                            check(s.sending && s.record != null && s.socket == null) { "Audio capture is not ready" }
                            val ip = call.argument<String>("peerIp") ?: ""
                            val port = call.argument<Int>("port") ?: 0
                            val token = call.argument<String>("token") ?: ""
                            require(validIp(ip) && port in 1..65535 && token.matches(Regex("[a-f0-9]{64}"))) { "Invalid audio endpoint" }
                            send(s, ip, port, token)
                            result.success(null)
                        }
                        "stop" -> { current?.takeIf { it.id == id }?.let { finish(it, "Wireless audio stopped") }; result.success(null) }
                        "volume" -> {
                            val s = requireState(id)
                            s.volume = (call.argument<Number>("value")?.toFloat() ?: 1f).coerceIn(0f, 1f)
                            s.track?.setVolume(s.volume)
                            result.success(null)
                        }
                        "speaker" -> {
                            val s = requireState(id)
                            val speaker = call.argument<Boolean>("value") ?: true
                            val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            val type = if (speaker) AudioDeviceInfo.TYPE_BUILTIN_SPEAKER else AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                            val device = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.type == type }
                            check(device != null && s.track?.setPreferredDevice(device) == true) { "This audio output is unavailable" }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) { result.error("PHONE_AUDIO", error.message, null) }
            }
    }

    private fun validIp(ip: String): Boolean = ip.split('.').let { parts ->
        parts.size == 4 && parts.all { part -> part.toIntOrNull()?.let { it in 0..255 } == true }
    }
    private fun requireState(id: String): State = current?.takeIf { it.id == id && !it.closed.get() }
        ?: error("Audio session ended")
    private fun newState(id: String, sending: Boolean, ip: String = ""): State {
        require(id.matches(Regex("wa-[A-Za-z0-9-]{8,80}"))) { "Invalid audio session" }
        check(current == null) { "Another phone audio session is active" }
        return State(id, sending, ip).also { current = it }
    }

    private fun prepare(app: Context, id: String, result: MethodChannel.Result) {
        check(Build.VERSION.SDK_INT >= 29) { "App audio sharing requires Android 10 or newer" }
        val owner = activity.get()?.takeUnless { it.isFinishing || it.isDestroyed }
            ?: error("Open NearMitra to approve phone audio capture")
        val s = newState(id, true)
        pending = Pending(s, owner, result)
        try {
            val manager = app.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            owner.startActivityForResult(manager.createScreenCaptureIntent(), REQUEST_CAPTURE)
        } catch (error: Exception) { finish(s, error.message ?: "Could not request audio consent") }
    }

    fun onActivityResult(owner: Activity, request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST_CAPTURE) return false
        val p = pending?.takeIf { it.owner === owner } ?: return true
        if (code != Activity.RESULT_OK || data == null) { finish(p.state, "Phone audio capture was declined"); return true }
        startService(owner.applicationContext, FarmitraForegroundService.ACTION_PHONE_AUDIO, p.state.id) { ready ->
            if (pending !== p || p.state.closed.get()) return@startService
            if (!ready) { finish(p.state, "Audio capture service did not start"); return@startService }
            thread(name = "nearmitra-audio-prepare") {
                try {
                    val manager = owner.applicationContext.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    val projection = manager.getMediaProjection(code, data)
                        ?: error("Android did not grant audio capture")
                    p.state.projection = projection
                    projection.registerCallback(object : MediaProjection.Callback() {
                        override fun onStop() { finish(p.state, "Android stopped phone audio sharing") }
                    }, main)
                    if (p.state.closed.get()) { release(p.state); return@thread }
                    val config = AudioPlaybackCaptureConfiguration.Builder(projection)
                        .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                        .addMatchingUsage(AudioAttributes.USAGE_GAME)
                        .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN).build()
                    val minimum = AudioRecord.getMinBufferSize(PhoneAudioPcm.RATE, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT)
                    check(minimum > 0) { "Phone does not support the audio capture format" }
                    val record = AudioRecord.Builder().setAudioPlaybackCaptureConfig(config)
                        .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(PhoneAudioPcm.RATE).setChannelMask(AudioFormat.CHANNEL_IN_STEREO).build())
                        .setBufferSizeInBytes(max(minimum, PhoneAudioPcm.BLOCK_BYTES * 4)).build()
                    p.state.record = record
                    check(record.state == AudioRecord.STATE_INITIALIZED) { "Phone audio capture could not initialize" }
                    check(record.sampleRate == PhoneAudioPcm.RATE && record.channelCount == PhoneAudioPcm.CHANNELS) {
                        "Phone returned an unsupported audio format"
                    }
                    main.post {
                        if (pending === p && !p.state.closed.get()) {
                            pending = null
                            p.result.success(null)
                        } else thread(name = "nearmitra-audio-cleanup") { release(p.state) }
                    }
                } catch (error: Exception) {
                    finish(p.state, error.message ?: "Phone audio capture failed")
                    release(p.state)
                }
            }
        }
        return true
    }

    fun acceptsServiceStart(id: String): Boolean = current?.let { it.id == id && !it.closed.get() } == true

    private fun startService(app: Context, action: String, id: String, done: (Boolean) -> Unit) {
        var completed = false
        val expired = Runnable { if (!completed) { completed = true; done(false) } }
        val receiver = object : ResultReceiver(main) {
            override fun onReceiveResult(code: Int, data: Bundle?) {
                if (completed) return
                completed = true
                main.removeCallbacks(expired)
                done(code == 1)
            }
        }
        try {
            val intent = Intent(app, FarmitraForegroundService::class.java).apply {
                this.action = action
                putExtra("phone_audio_session", id)
                putExtra("projectionReady", receiver)
            }
            main.postDelayed(expired, 5000)
            if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(intent) else app.startService(intent)
        } catch (_: Exception) { main.removeCallbacks(expired); completed = true; done(false) }
    }

    private fun receive(app: Context, id: String, ip: String, result: MethodChannel.Result) {
        require(validIp(ip)) { "A direct Nearby address is required" }
        val s = newState(id, false, ip)
        startService(app, FarmitraForegroundService.ACTION_WIRELESS_AUDIO, s.id) { ready ->
            if (!ready || s.closed.get()) {
                result.error("PHONE_AUDIO", "Audio playback service did not start", null)
                finish(s, "Could not start playback")
                return@startService
            }
            thread(name = "nearmitra-audio-receive") {
                var replied = false
                try {
                    val server = ServerSocket(0).also { it.soTimeout = 1000; s.server = it }
                    val token = ByteArray(32).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it.toInt() and 255) }
                    main.post { result.success(mapOf("port" to server.localPort, "token" to token)) }
                    replied = true
                    val deadline = SystemClock.elapsedRealtime() + 35000
                    var input: DataInputStream? = null
                    while (!s.closed.get() && SystemClock.elapsedRealtime() < deadline && input == null) {
                        val socket = try { server.accept() } catch (_: java.net.SocketTimeoutException) { continue }
                        if (socket.inetAddress.hostAddress != ip) { socket.close(); continue }
                        s.socket = socket
                        socket.soTimeout = 3000
                        val stream = DataInputStream(socket.getInputStream())
                        if (try { stream.readUTF() == "NEARMITRA-PCM1:$token" } catch (_: Exception) { false }) input = stream
                        else { socket.close(); s.socket = null }
                    }
                    check(input != null && !s.closed.get()) { "Other phone did not connect" }
                    server.close()
                    val socket = s.socket!!
                    socket.soTimeout = 10000
                    socket.tcpNoDelay = true
                    socket.receiveBufferSize = PhoneAudioPcm.BLOCK_BYTES * 8
                    val minBuffer = AudioTrack.getMinBufferSize(PhoneAudioPcm.RATE, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
                    check(minBuffer > 0) { "Phone does not support this playback format" }
                    val track = AudioTrack.Builder().setAudioAttributes(AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build())
                        .setAudioFormat(AudioFormat.Builder().setSampleRate(PhoneAudioPcm.RATE)
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build())
                        .setBufferSizeInBytes(max(minBuffer, PhoneAudioPcm.BLOCK_BYTES * 4))
                        .setTransferMode(AudioTrack.MODE_STREAM).build().also { s.track = it }
                    check(track.state == AudioTrack.STATE_INITIALIZED) { "Audio playback could not initialize" }
                    track.setVolume(s.volume)
                    track.play()
                    watchProgress(s)
                    event(s, "connected")
                    val frame = PhoneAudioFrames()
                    val buffer = ByteArray(PhoneAudioPcm.BLOCK_BYTES)
                    while (!s.closed.get()) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        s.lastProgress = SystemClock.elapsedRealtime()
                        val pcm = frame.consume(buffer, count)
                        var offset = 0
                        while (offset < pcm.size && !s.closed.get()) {
                            val written = track.write(pcm, offset, pcm.size - offset, AudioTrack.WRITE_BLOCKING)
                            check(written > 0) { "Audio output stopped" }
                            offset += written
                        }
                        level(s, pcm, pcm.size)
                    }
                    finish(s, "Other phone stopped sharing audio")
                } catch (error: Exception) {
                    if (!replied) main.post { result.error("PHONE_AUDIO", error.message, null) }
                    finish(s, error.message ?: "Phone audio connection ended")
                } finally { release(s) }
            }
        }
    }

    private fun send(s: State, ip: String, port: Int, token: String) {
        thread(name = "nearmitra-audio-send") {
            try {
                val socket = Socket().also { s.socket = it }
                socket.connect(InetSocketAddress(ip, port), 8000)
                check(!s.closed.get()) { "Audio session ended" }
                socket.tcpNoDelay = true
                socket.sendBufferSize = PhoneAudioPcm.BLOCK_BYTES * 8
                val output = DataOutputStream(socket.getOutputStream())
                output.writeUTF("NEARMITRA-PCM1:$token")
                val record = s.record ?: error("Audio capture ended")
                record.startRecording()
                check(record.recordingState == AudioRecord.RECORDSTATE_RECORDING) { "Audio capture did not start" }
                watchProgress(s)
                event(s, "connected")
                val buffer = ByteArray(PhoneAudioPcm.BLOCK_BYTES)
                while (!s.closed.get()) {
                    val count = record.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                    check(count > 0) { "Audio capture stopped" }
                    output.write(buffer, 0, count) // TCP backpressure, bounded native buffers.
                    s.lastProgress = SystemClock.elapsedRealtime()
                    level(s, buffer, count)
                }
            } catch (error: Exception) { finish(s, error.message ?: "Phone audio sharing ended") }
            finally { release(s) }
        }
    }

    private fun level(s: State, buffer: ByteArray, count: Int) {
        val now = SystemClock.elapsedRealtime()
        if (now - s.lastLevel < 500) return
        s.lastLevel = now
        event(s, "level", mapOf("level" to PhoneAudioPcm.level(buffer, count)))
    }
    private fun watchProgress(s: State) {
        s.lastProgress = SystemClock.elapsedRealtime()
        val watchdog = object : Runnable {
            override fun run() {
                if (s.closed.get()) return
                if (SystemClock.elapsedRealtime() - s.lastProgress > 10000) {
                    finish(s, "Phone audio connection stalled. Check Wi-Fi and retry.")
                } else main.postDelayed(this, 2000)
            }
        }
        s.watchdog = watchdog
        main.postDelayed(watchdog, 2000)
    }
    private fun event(s: State, type: String, extra: Map<String, Any> = emptyMap()) {
        main.post { if (current === s && !s.closed.get()) events?.success(mapOf("id" to s.id, "type" to type) + extra) }
    }
    private fun finish(s: State, reason: String) {
        if (!s.closed.compareAndSet(false, true)) return
        s.watchdog?.let { main.removeCallbacks(it) }
        main.post {
            pending?.takeIf { it.state === s }?.let { pending = null; it.result.error("PHONE_AUDIO", reason, null) }
            if (current === s) { current = null; events?.success(mapOf("id" to s.id, "type" to "stopped", "reason" to reason)) }
        }
        runCatching { s.socket?.close() }
        runCatching { s.server?.close() }
        thread(name = "nearmitra-audio-cleanup") { release(s) }
    }
    private fun release(s: State) = synchronized(s) {
        runCatching { s.record?.stop() }
        runCatching { s.record?.release() }
        s.record = null
        runCatching { s.track?.pause() }
        runCatching { s.track?.flush() }
        runCatching { s.track?.release() }
        s.track = null
        runCatching { s.projection?.stop() }
        s.projection = null
        runCatching { s.socket?.close() }
        runCatching { s.server?.close() }
    }
    fun stopForService() { current?.let { finish(it, "Phone audio service stopped") } }
    fun shutdown() { stopForService(); events = null; activity.clear() }
}
