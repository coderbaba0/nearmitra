package com.farmitra.nearby

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class CallActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_ACCEPT = "com.farmitra.nearby.ACTION_CALL_ACCEPT"
        const val ACTION_DECLINE = "com.farmitra.nearby.ACTION_CALL_DECLINE"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        val notifId = intent.getIntExtra("notif_id", 0)
        val peerId = intent.getStringExtra("peer_id") ?: ""
        val peerName = intent.getStringExtra("peer_name") ?: "Peer Device"
        val peerIp = intent.getStringExtra("peer_ip") ?: ""
        val isVideo = intent.getBooleanExtra("is_video", false)

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        if (notifId != 0) {
            manager?.cancel(notifId)
        }

        if (intent.action == ACTION_ACCEPT) {
            Log.d("CallActionReceiver", "Call ACCEPTED by user for $peerName ($peerIp)")
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("call_incoming", true)
                putExtra("call_action", "accept")
                putExtra("peer_id", peerId)
                putExtra("peer_name", peerName)
                putExtra("peer_ip", peerIp)
                putExtra("is_video", isVideo)
            }
            if (launchIntent != null) {
                context.startActivity(launchIntent)
            }
        }
    }
}
