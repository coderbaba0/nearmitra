package com.farmitra.nearby.reply

import android.app.NotificationManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors

/** A small native inbox shared by the notification callback and networking engines. */
class NotificationReplyPlugin : FlutterPlugin {
    companion object {
        private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "nearmitra-reply-inbox").apply { isDaemon = true } }
        private val main = Handler(Looper.getMainLooper())
        private val sinks = CopyOnWriteArraySet<EventChannel.EventSink>()
        private var store: ReplyStore? = null
        private fun database(context: Context): ReplyStore = store ?: ReplyStore(context.applicationContext).also { store = it }
    }
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val app = binding.applicationContext
        events = EventChannel(binding.binaryMessenger, "farmitra_nearby/notification_reply_events").also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink?.let { sinks.remove(it) }
                    sink = events
                    sinks.add(events)
                    events.success(null) // Recover events queued before the runtime attached.
                }
                override fun onCancel(arguments: Any?) { sink?.let { sinks.remove(it) }; sink = null }
            })
        }
        methods = MethodChannel(binding.binaryMessenger, "farmitra_nearby/notification_replies").also { channel ->
            channel.setMethodCallHandler { call, result ->
                worker.execute {
                    try {
                        val db = database(app)
                        when (call.method) {
                            "registerNotification" -> {
                                db.register(call.argument<Int>("id") ?: error("Missing notification id"),
                                    call.argument<String>("nonce") ?: error("Missing notification nonce"))
                                main.post { result.success(null) }
                            }
                            "save" -> {
                                val peer = call.argument<String>("peerId")?.trim().orEmpty()
                                val text = call.argument<String>("text")?.trim().orEmpty()
                                val nonce = call.argument<String>("nonce")
                                require(peer.isNotEmpty() && text.isNotEmpty()) { "Reply and recipient are required" }
                                val pending = db.save(peer, text, nonce)
                                // Persist first. Do not dismiss a newer notification for this peer.
                                val notificationId = call.argument<Int>("notificationId")
                                if (notificationId != null && nonce != null && db.isCurrent(notificationId, nonce)) {
                                    (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(notificationId)
                                }
                                if (pending) {
                                    main.post { sinks.forEach { runCatching { it.success(null) } } }
                                    try {
                                        val wake = Intent("com.farmitra.nearby.NOTIFICATION_REPLY").apply {
                                            component = ComponentName(app.packageName, "com.farmitra.nearby.FarmitraForegroundService")
                                        }
                                        if (Build.VERSION.SDK_INT >= 26) app.startForegroundService(wake) else app.startService(wake)
                                    } catch (_: Exception) {
                                        // A platform background-start restriction must not discard the
                                        // reply. Runtime startup/resume and its retry timer drain the DB.
                                    }
                                }
                                main.post { result.success(null) }
                            }
                            "pending" -> {
                                val replies = db.pending()
                                main.post { result.success(replies) }
                            }
                            "acknowledge" -> {
                                db.acknowledge(call.argument<String>("id") ?: error("Missing reply id"))
                                main.post { result.success(null) }
                            }
                            else -> main.post { result.notImplemented() }
                        }
                    } catch (error: Exception) { main.post { result.error("REPLY_INBOX", error.message, null) } }
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        sink?.let { sinks.remove(it) }
        sink = null
    }
}

private class ReplyStore(context: Context) : SQLiteOpenHelper(context, "notification_replies_v1.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE replies (id TEXT PRIMARY KEY, peer TEXT NOT NULL, body TEXT, created INTEGER NOT NULL, imported INTEGER NOT NULL DEFAULT 0)")
        db.execSQL("CREATE INDEX pending_replies ON replies (imported, created, id)")
        db.execSQL("CREATE TABLE slots (notification INTEGER PRIMARY KEY, nonce TEXT NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    fun register(id: Int, nonce: String) {
        writableDatabase.insertWithOnConflict("slots", null, ContentValues().apply {
            put("notification", id); put("nonce", nonce)
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    fun isCurrent(id: Int, nonce: String): Boolean = readableDatabase.rawQuery(
        "SELECT nonce FROM slots WHERE notification=?", arrayOf(id.toString())).use {
        it.moveToFirst() && it.getString(0) == nonce
    }
    fun save(peer: String, text: String, nonce: String?): Boolean {
        val id = ReplyIdentity.create(peer, text, nonce)
        writableDatabase.insertWithOnConflict("replies", null, ContentValues().apply {
            put("id", id); put("peer", peer); put("body", text); put("created", System.currentTimeMillis()); put("imported", 0)
        }, SQLiteDatabase.CONFLICT_IGNORE)
        return readableDatabase.rawQuery("SELECT imported FROM replies WHERE id=?", arrayOf(id)).use { it.moveToFirst() && it.getInt(0) == 0 }
    }
    fun pending(): List<Map<String, Any>> = readableDatabase.rawQuery(
        "SELECT id, peer, body, created FROM replies WHERE imported=0 ORDER BY created, id LIMIT 100", null).use { cursor ->
        buildList { while (cursor.moveToNext()) add(mapOf("id" to cursor.getString(0), "peerId" to cursor.getString(1),
            "text" to cursor.getString(2), "createdAt" to cursor.getLong(3))) }
    }
    fun acknowledge(id: String) {
        // Keep the receipt ID so a repeated callback cannot re-send the reply.
        writableDatabase.update("replies", ContentValues().apply { put("imported", 1); putNull("body"); put("peer", "") }, "id=?", arrayOf(id))
    }
}
